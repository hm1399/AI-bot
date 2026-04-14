from __future__ import annotations

import asyncio
import hmac
import json
import re
import time
from datetime import datetime
from typing import TYPE_CHECKING, Any, Callable

from aiohttp import WSMsgType, web
from loguru import logger

from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from services.asr import ASRService

if TYPE_CHECKING:
    from channels.device_channel import DeviceChannel


DESKTOP_VOICE_CHANNEL = "desktop_voice"
DESKTOP_VOICE_CHAT_ID = "desktop"

PCM_SAMPLE_RATE = 16000
PCM_CHANNELS = 1
PCM_SAMPLE_WIDTH_BYTES = 2
MIN_AUDIO_BYTES = PCM_SAMPLE_RATE * PCM_SAMPLE_WIDTH_BYTES // 2
MAX_AUDIO_BYTES = PCM_SAMPLE_RATE * PCM_SAMPLE_WIDTH_BYTES * 60

STATUS_IDLE = "idle"
STATUS_LISTENING = "listening"
STATUS_TRANSCRIBING = "transcribing"
STATUS_RESPONDING = "responding"
STATUS_ERROR = "error"

_CJK_PATTERN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
_EXPLICIT_CHINESE_REPLY_PATTERN = re.compile(
    r"(用中文|说中文|中文回答|中文回复|汉语回答|普通话回答|reply in chinese|answer in chinese|speak chinese|mandarin|chinese)"
)
_EXPLICIT_ENGLISH_REPLY_PATTERN = re.compile(
    r"(用英文|说英文|英文回答|英文回复|英语回答|reply in english|answer in english|speak english|english)"
)


class DesktopVoiceService:
    """Desktop microphone bridge with its own WebSocket/HTTP ingress."""

    def __init__(
        self,
        *,
        bus: MessageBus,
        asr: ASRService | None,
        device_channel: DeviceChannel,
        auth_token: str = "",
        default_app_session_id: str = "app:main",
        enable_local_microphone: bool = True,
    ) -> None:
        self.bus = bus
        self.asr = asr
        self.device_channel = device_channel
        self.auth_token = auth_token.strip()
        self.default_app_session_id = default_app_session_id
        self.enable_local_microphone = enable_local_microphone
        self._event_observer: Any | None = None
        self._active_app_session_resolver: Callable[[], str | None] | None = None
        self._clients: set[web.WebSocketResponse] = set()
        self._client_order: dict[web.WebSocketResponse, int] = {}
        self._client_seq = 0
        self._primary_ws: web.WebSocketResponse | None = None
        self._lock = asyncio.Lock()
        self._audio_finalize_lock = asyncio.Lock()
        self._capture: dict[str, Any] | None = None
        self._pending_device_capture = False
        self._audio_buffer = bytearray()
        self._asr_task: asyncio.Task | None = None
        self._local_audio_queue: asyncio.Queue[bytes | None] | None = None
        self._local_audio_task: asyncio.Task | None = None
        self._local_stream: Any | None = None
        self._local_loop: asyncio.AbstractEventLoop | None = None
        self._local_microphone_error: str | None = None
        self._state: dict[str, Any] = {
            "connected": False,
            "ready": False,
            "client_count": 0,
            "status": STATUS_IDLE,
            "capture_active": False,
            "interaction_surface": None,
            "capture_source": "desktop_mic",
            "format": {
                "sample_rate_hz": PCM_SAMPLE_RATE,
                "channels": PCM_CHANNELS,
                "sample_width_bytes": PCM_SAMPLE_WIDTH_BYTES,
            },
            "last_error": None,
            "last_transcript": None,
            "last_response": None,
            "last_capture_started_at": None,
            "last_capture_stopped_at": None,
        }

    def register_routes(self, app: web.Application) -> None:
        app.router.add_get("/api/desktop-voice/v1/state", self.handle_state)
        app.router.add_get("/ws/desktop-voice", self.handle_ws)

    def set_event_observer(self, observer: Any) -> None:
        self._event_observer = observer

    def set_active_app_session_resolver(
        self,
        resolver: Callable[[], str | None],
    ) -> None:
        self._active_app_session_resolver = resolver

    def _resolve_app_session_id(self, candidate: str | None = None) -> str:
        cleaned = str(candidate or "").strip()
        if cleaned.startswith("app:"):
            return cleaned
        if self._active_app_session_resolver is not None:
            try:
                resolved = str(self._active_app_session_resolver() or "").strip()
            except Exception:
                logger.exception("Failed to resolve active app session")
            else:
                if resolved.startswith("app:"):
                    return resolved
        return self.default_app_session_id

    def get_snapshot(self) -> dict[str, Any]:
        local_available = self._local_microphone_available()
        snapshot = dict(self._state)
        snapshot["format"] = dict(self._state["format"])
        snapshot["client_count"] = len(self._clients)
        snapshot["connected"] = bool(self._clients) or local_available
        snapshot["ready"] = bool(self._primary_ws and not self._primary_ws.closed) or local_available
        snapshot["capture_active"] = self._capture is not None or self._pending_device_capture
        snapshot["device_feedback_available"] = bool(self.device_channel.connected)
        snapshot["asr_available"] = bool(self.asr)
        snapshot["local_microphone_enabled"] = self.enable_local_microphone
        snapshot["local_microphone_available"] = local_available
        snapshot["local_microphone_error"] = self._local_microphone_error
        snapshot["wake_word_active"] = False
        snapshot["auto_listen_active"] = False
        return snapshot

    def is_ready(self) -> bool:
        return bool(self._primary_ws and not self._primary_ws.closed) or self._local_microphone_available()

    @staticmethod
    def _preferred_reply_language_from_transcript(transcript: str) -> str | None:
        normalized = transcript.strip()
        if not normalized:
            return None

        lowered = normalized.casefold()
        if _EXPLICIT_ENGLISH_REPLY_PATTERN.search(lowered):
            return "English"
        if _EXPLICIT_CHINESE_REPLY_PATTERN.search(lowered):
            return "Chinese"

        contains_cjk = bool(_CJK_PATTERN.search(normalized))
        contains_latin = bool(re.search(r"[A-Za-z]", normalized))
        if contains_cjk and not contains_latin:
            return "Chinese"
        if contains_latin and not contains_cjk:
            return "English"
        return None

    async def start_device_push_to_talk(self) -> bool:
        use_external_client = False
        async with self._lock:
            if self._capture is not None or self._pending_device_capture or self._asr_in_flight():
                await self._send_primary_json(
                    {
                        "type": "capture.reject",
                        "data": {"reason": "voice_busy"},
                    }
                )
                return False

            if self._primary_ws and not self._primary_ws.closed:
                use_external_client = True
                self._pending_device_capture = True
                await self._set_status_unlocked(
                    STATUS_LISTENING,
                    interaction_surface="device_press",
                    capture_source="desktop_mic",
                    last_error=None,
                    last_capture_started_at=self._now_iso(),
                )
            elif not self._local_microphone_available():
                await self._set_status_unlocked(
                    STATUS_ERROR,
                    interaction_surface="device_press",
                    last_error=self._local_microphone_error or "desktop_mic_client_unavailable",
                )
                return False

        if use_external_client:
            await self._send_primary_json(
                {
                    "type": "capture.start",
                    "data": {
                        "interaction_surface": "device_press",
                        "capture_source": "desktop_mic",
                        "sample_rate_hz": PCM_SAMPLE_RATE,
                        "channels": PCM_CHANNELS,
                        "sample_width_bytes": PCM_SAMPLE_WIDTH_BYTES,
                    },
                }
            )
            return True

        try:
            await self._start_embedded_capture(
                interaction_surface="device_press",
                app_session_id=self._resolve_app_session_id(),
            )
            return True
        except Exception:
            logger.exception("Failed to start embedded desktop microphone capture")
            async with self._lock:
                self._capture = None
                self._pending_device_capture = False
                self._audio_buffer.clear()
                await self._set_status_unlocked(
                    STATUS_ERROR,
                    interaction_surface="device_press",
                    last_error="embedded_desktop_mic_start_failed",
                )
            return False

    async def stop_device_push_to_talk(self) -> bool:
        use_external_client = False
        use_embedded_microphone = False
        async with self._lock:
            if self._primary_ws and not self._primary_ws.closed:
                use_external_client = True
            elif self._capture and self._capture.get("mode") == "embedded_local":
                use_embedded_microphone = True
            else:
                return False

            if use_external_client:
                pending_only = self._pending_device_capture and self._capture is None
                self._pending_device_capture = False
                if pending_only:
                    await self._set_status_unlocked(
                        STATUS_IDLE,
                        interaction_surface=None,
                        last_capture_stopped_at=self._now_iso(),
                    )

        if use_external_client:
            await self._send_primary_json(
                {
                    "type": "capture.stop",
                    "data": {"interaction_surface": "device_press"},
                }
            )
            return True

        if use_embedded_microphone:
            await self._stop_embedded_capture()
            return True

        return False

    async def cancel_device_push_to_talk(self, *, reason: str) -> None:
        if self._capture and self._capture.get("mode") == "embedded_local":
            await self._cancel_embedded_capture(reason)
            return

        async with self._lock:
            self._pending_device_capture = False
            self._capture = None
            self._audio_buffer.clear()
            await self._set_status_unlocked(
                STATUS_IDLE,
                interaction_surface=None,
                last_error=reason,
                last_capture_stopped_at=self._now_iso(),
            )

        await self._send_primary_json(
            {
                "type": "capture.cancel",
                "data": {"reason": reason},
            }
        )

    async def handle_state(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        return web.json_response({"data": self.get_snapshot()})

    async def handle_ws(self, request: web.Request) -> web.StreamResponse:
        if not self._is_authorized(request):
            logger.warning("拒绝未授权桌面语音连接 ({})", request.remote)
            return web.json_response({"error": "unauthorized"}, status=401)

        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)

        async with self._lock:
            self._client_seq += 1
            self._clients.add(ws)
            self._client_order[ws] = self._client_seq
            self._primary_ws = ws
            await self._set_status_unlocked(self._state["status"])

        await ws.send_json({"type": "hello", "data": self.get_snapshot()})

        try:
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    await self._on_text(ws, msg.data)
                elif msg.type == WSMsgType.BINARY:
                    await self._on_binary(msg.data)
                elif msg.type == WSMsgType.ERROR:
                    logger.warning("Desktop voice websocket error: {}", ws.exception())
        finally:
            await self._detach_client(ws)

        return ws

    async def stop(self) -> None:
        await self._shutdown_embedded_microphone()

        async with self._lock:
            clients = tuple(self._clients)
            self._clients.clear()
            self._client_order.clear()
            self._primary_ws = None
            self._pending_device_capture = False
            self._capture = None
            self._audio_buffer.clear()
            await self._set_status_unlocked(
                STATUS_IDLE,
                interaction_surface=None,
                last_error="service_stopped",
            )

        if self._asr_task and not self._asr_task.done():
            self._asr_task.cancel()
            try:
                await self._asr_task
            except asyncio.CancelledError:
                pass

        for ws in clients:
            if not ws.closed:
                await ws.close()

    async def _start_embedded_capture(
        self,
        *,
        interaction_surface: str,
        app_session_id: str,
    ) -> None:
        if not self._local_microphone_available():
            raise RuntimeError(self._local_microphone_error or "sounddevice unavailable")
        if not app_session_id.startswith("app:"):
            raise RuntimeError("app_session_id must start with app:")

        async with self._lock:
            if self._capture is not None or self._pending_device_capture or self._asr_in_flight():
                raise RuntimeError("voice pipeline is busy")
            started_at = self._now_iso()
            self._capture = {
                "client": None,
                "mode": "embedded_local",
                "interaction_surface": interaction_surface,
                "capture_source": "desktop_mic",
                "app_session_id": app_session_id,
                "started_at": started_at,
            }
            self._audio_buffer.clear()
            await self._set_status_unlocked(
                STATUS_LISTENING,
                interaction_surface=interaction_surface,
                capture_source="desktop_mic",
                last_error=None,
                last_capture_started_at=started_at,
            )

        self._local_audio_queue = asyncio.Queue()
        self._local_loop = asyncio.get_running_loop()
        self._local_audio_task = asyncio.create_task(self._embedded_audio_loop())

        try:
            import sounddevice as sd

            def _callback(indata, frames, time_info, status) -> None:
                if status:
                    logger.warning("Embedded desktop microphone warning: {}", status)
                if self._local_loop is None or self._local_audio_queue is None:
                    return
                try:
                    self._local_loop.call_soon_threadsafe(
                        self._local_audio_queue.put_nowait,
                        bytes(indata),
                    )
                except RuntimeError:
                    return

            self._local_stream = sd.RawInputStream(
                samplerate=PCM_SAMPLE_RATE,
                channels=PCM_CHANNELS,
                dtype="int16",
                blocksize=1024,
                callback=_callback,
            )
            self._local_stream.start()
        except Exception:
            await self._shutdown_embedded_microphone()
            raise

    async def _stop_embedded_capture(self) -> None:
        await self._shutdown_embedded_microphone()
        await self._handle_stop({})

    async def _cancel_embedded_capture(self, reason: str) -> None:
        await self._shutdown_embedded_microphone()
        await self._handle_cancel({"reason": reason})

    async def _shutdown_embedded_microphone(self) -> None:
        stream = self._local_stream
        self._local_stream = None
        if stream is not None:
            try:
                stream.stop()
            except Exception:
                logger.exception("Failed to stop embedded desktop microphone stream")
            try:
                stream.close()
            except Exception:
                logger.exception("Failed to close embedded desktop microphone stream")

        queue = self._local_audio_queue
        self._local_audio_queue = None
        if queue is not None:
            await queue.put(None)

        task = self._local_audio_task
        self._local_audio_task = None
        if task is not None:
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._local_loop = None

    async def _embedded_audio_loop(self) -> None:
        queue = self._local_audio_queue
        if queue is None:
            return

        while True:
            chunk = await queue.get()
            if chunk is None:
                return
            await self._on_binary(chunk)

    async def send_outbound(self, out_msg: OutboundMessage) -> None:
        if out_msg.channel != DESKTOP_VOICE_CHANNEL or not out_msg.content:
            return

        response_text = out_msg.content
        interaction_surface = str(out_msg.metadata.get("interaction_surface") or "").strip()
        capture_source = str(out_msg.metadata.get("capture_source") or "").strip()

        if interaction_surface == "device_press":
            await self.device_channel.notify_external_voice_responding()
            await self.device_channel.deliver_external_text_response(response_text)

        await self._broadcast_json(
            {
                "type": "response",
                "data": {
                    "text": response_text,
                    "interaction_surface": interaction_surface or None,
                    "capture_source": capture_source or None,
                },
            }
        )

        async with self._lock:
            await self._set_status_unlocked(
                STATUS_IDLE,
                interaction_surface=None,
                last_response=response_text,
                last_error=None,
            )

        await self._notify_event_observer(
            "on_desktop_voice_response",
            text=response_text,
            snapshot=self.get_snapshot(),
            metadata=dict(out_msg.metadata or {}),
        )

    async def _detach_client(self, ws: web.WebSocketResponse) -> None:
        disconnected_capture: dict[str, Any] | None = None
        async with self._lock:
            self._clients.discard(ws)
            self._client_order.pop(ws, None)
            if self._primary_ws is ws:
                self._primary_ws = self._pick_primary_ws()
            if self._capture and self._capture.get("client") is ws:
                disconnected_capture = dict(self._capture)
                self._capture = None
                self._pending_device_capture = False
                self._audio_buffer.clear()
                await self._set_status_unlocked(
                    STATUS_IDLE,
                    interaction_surface=None,
                    last_error="desktop_mic_client_disconnected",
                    last_capture_stopped_at=self._now_iso(),
                )
            else:
                await self._set_status_unlocked(self._state["status"])

        if disconnected_capture and disconnected_capture.get("interaction_surface") == "device_press":
            await self.device_channel.fail_external_voice_feedback("桌面麦克风已断开")

    async def _on_text(self, ws: web.WebSocketResponse, raw: str) -> None:
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            await self._send_error("invalid_json", "invalid json payload")
            return

        msg_type = str(payload.get("type") or "").strip()
        data = payload.get("data", {})
        if not isinstance(data, dict):
            await self._send_error("invalid_payload", "data must be an object")
            return

        if msg_type == "start":
            await self._handle_start(ws, data)
            return
        if msg_type == "stop":
            await self._handle_stop(data)
            return
        if msg_type == "cancel":
            await self._handle_cancel(data)
            return
        if msg_type == "ping":
            await ws.send_json({"type": "pong", "data": self.get_snapshot()})
            return
        if msg_type == "status":
            await ws.send_json({"type": "status", "data": self.get_snapshot()})
            return

        await self._send_error("unknown_type", f"unknown message type: {msg_type}")

    async def _handle_start(self, ws: web.WebSocketResponse, data: dict[str, Any]) -> None:
        if self._asr_in_flight():
            await self._send_error("voice_busy", "voice pipeline is busy")
            return

        interaction_surface = str(data.get("interaction_surface") or "desktop_manual").strip()
        capture_source = str(data.get("capture_source") or "desktop_mic").strip()
        app_session_id = self._resolve_app_session_id(data.get("app_session_id"))
        if capture_source != "desktop_mic":
            await self._send_error("invalid_capture_source", "capture_source must be desktop_mic")
            return
        if not app_session_id.startswith("app:"):
            await self._send_error("invalid_app_session", "app_session_id must start with app:")
            return

        sample_rate = self._read_int(data, "sample_rate_hz", "sample_rate", default=PCM_SAMPLE_RATE)
        channels = self._read_int(data, "channels", default=PCM_CHANNELS)
        sample_width = self._read_int(
            data,
            "sample_width_bytes",
            "sample_width",
            default=PCM_SAMPLE_WIDTH_BYTES,
        )
        bits_per_sample = self._read_int(data, "bits_per_sample", default=sample_width * 8)
        if (
            sample_rate != PCM_SAMPLE_RATE
            or channels != PCM_CHANNELS
            or sample_width != PCM_SAMPLE_WIDTH_BYTES
            or bits_per_sample != PCM_SAMPLE_WIDTH_BYTES * 8
        ):
            await self._send_error(
                "unsupported_audio_format",
                "desktop voice expects 16kHz/16bit/mono PCM",
            )
            return

        async with self._lock:
            if self._capture is not None or self._pending_device_capture and interaction_surface != "device_press":
                await self._send_error("capture_already_active", "capture already active")
                return
            self._pending_device_capture = False
            self._capture = {
                "client": ws,
                "interaction_surface": interaction_surface,
                "capture_source": capture_source,
                "app_session_id": app_session_id,
                "started_at": self._now_iso(),
            }
            self._audio_buffer.clear()
            await self._set_status_unlocked(
                STATUS_LISTENING,
                interaction_surface=interaction_surface,
                capture_source=capture_source,
                last_error=None,
                last_capture_started_at=self._capture["started_at"],
            )

        await self._broadcast_json(
            {
                "type": "capture.started",
                "data": {
                    "interaction_surface": interaction_surface,
                    "capture_source": capture_source,
                },
            }
        )

    async def _handle_stop(self, data: dict[str, Any]) -> None:
        capture: dict[str, Any] | None
        pcm_data: bytes
        async with self._audio_finalize_lock:
            async with self._lock:
                capture = dict(self._capture) if self._capture else None
                self._capture = None
                self._pending_device_capture = False
                pcm_data = bytes(self._audio_buffer)
                self._audio_buffer.clear()
                if capture is None:
                    await self._set_status_unlocked(
                        STATUS_IDLE,
                        interaction_surface=None,
                        last_capture_stopped_at=self._now_iso(),
                    )
                else:
                    await self._set_status_unlocked(
                        STATUS_TRANSCRIBING,
                        interaction_surface=capture["interaction_surface"],
                        capture_source=capture["capture_source"],
                        last_capture_stopped_at=self._now_iso(),
                    )

        if capture is None:
            return

        await self._broadcast_json(
            {
                "type": "capture.stopped",
                "data": {
                    "interaction_surface": capture["interaction_surface"],
                    "bytes": len(pcm_data),
                },
            }
        )

        if self._asr_in_flight():
            await self._send_error("voice_busy", "voice pipeline is busy")
            return

        self._asr_task = asyncio.create_task(self._run_asr_and_publish(capture, pcm_data))

    async def _handle_cancel(self, data: dict[str, Any]) -> None:
        reason = str(data.get("reason") or "cancelled").strip()
        interaction_surface: str | None = None
        async with self._lock:
            if self._capture:
                interaction_surface = str(self._capture.get("interaction_surface") or "").strip() or None
            self._capture = None
            self._pending_device_capture = False
            self._audio_buffer.clear()
            await self._set_status_unlocked(
                STATUS_IDLE,
                interaction_surface=None,
                last_error=reason,
                last_capture_stopped_at=self._now_iso(),
            )

        await self._broadcast_json(
            {
                "type": "capture.cancelled",
                "data": {"reason": reason},
            }
        )
        if interaction_surface == "device_press":
            await self.device_channel.fail_external_voice_feedback("已取消")

    async def _on_binary(self, data: bytes) -> None:
        async with self._lock:
            if self._capture is None:
                return
            if len(self._audio_buffer) + len(data) > MAX_AUDIO_BYTES:
                overflow_capture = dict(self._capture)
                self._capture = None
                self._audio_buffer.clear()
                await self._set_status_unlocked(
                    STATUS_IDLE,
                    interaction_surface=None,
                    last_error="audio_too_long",
                    last_capture_stopped_at=self._now_iso(),
                )
            else:
                self._audio_buffer.extend(data)
                return

        await self._broadcast_json(
            {
                "type": "error",
                "data": {
                    "code": "audio_too_long",
                    "message": "recording exceeded desktop voice buffer limit",
                },
            }
        )
        if overflow_capture.get("interaction_surface") == "device_press":
            await self.device_channel.fail_external_voice_feedback("录音太长，请重试")

    async def _run_asr_and_publish(self, capture: dict[str, Any], pcm_data: bytes) -> None:
        interaction_surface = str(capture.get("interaction_surface") or "").strip()
        capture_source = str(capture.get("capture_source") or "desktop_mic").strip()
        app_session_id = self._resolve_app_session_id(capture.get("app_session_id"))

        try:
            if len(pcm_data) < MIN_AUDIO_BYTES:
                await self._handle_capture_failure(
                    code="audio_too_short",
                    message="没听清，请再说一次",
                    interaction_surface=interaction_surface,
                )
                return
            if not self.asr:
                await self._handle_capture_failure(
                    code="asr_unavailable",
                    message="语音识别服务未启用",
                    interaction_surface=interaction_surface,
                )
                return

            if interaction_surface == "device_press":
                await self.device_channel.notify_external_voice_transcribing()

            started = time.monotonic()
            try:
                transcript = await self.asr.transcribe(pcm_data)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Desktop voice ASR failed")
                await self._handle_capture_failure(
                    code="asr_failed",
                    message="语音识别失败，请重试",
                    interaction_surface=interaction_surface,
                )
                return

            asr_ms = (time.monotonic() - started) * 1000
            transcript = transcript.strip()
            if not transcript:
                await self._handle_capture_failure(
                    code="empty_transcript",
                    message="没听清，请再说一次",
                    interaction_surface=interaction_surface,
                )
                return

            await self._broadcast_json(
                {
                    "type": "transcript",
                    "data": {
                        "text": transcript,
                        "interaction_surface": interaction_surface,
                        "capture_source": capture_source,
                    },
                }
            )

            async with self._lock:
                await self._set_status_unlocked(
                    STATUS_RESPONDING,
                    interaction_surface=interaction_surface,
                    capture_source=capture_source,
                    last_transcript=transcript,
                    last_error=None,
                )

            if interaction_surface == "device_press":
                await self.device_channel.notify_external_voice_responding()

            metadata: dict[str, Any] = {
                "source": "voice",
                "source_channel": DESKTOP_VOICE_CHANNEL,
                "voice_path": "desktop_mic",
                "interaction_surface": interaction_surface or "desktop_manual",
                "capture_source": capture_source,
                "app_session_id": app_session_id,
                "asr_ms": asr_ms,
            }
            reply_language = self._preferred_reply_language_from_transcript(transcript)
            if reply_language:
                metadata["reply_language"] = reply_language
            if self.asr.last_emotion:
                metadata["emotion"] = self.asr.last_emotion

            observer_result = await self._notify_event_observer(
                "on_desktop_voice_transcript",
                transcript=transcript,
                metadata=dict(metadata),
                snapshot=self.get_snapshot(),
            )
            if isinstance(observer_result, dict) and observer_result.get("handled"):
                response_text = str(observer_result.get("response_text") or "").strip()
                outbound_metadata = observer_result.get("outbound_metadata")
                if not isinstance(outbound_metadata, dict):
                    outbound_metadata = dict(metadata)
                if response_text:
                    await self.send_outbound(
                        OutboundMessage(
                            channel=DESKTOP_VOICE_CHANNEL,
                            chat_id=DESKTOP_VOICE_CHAT_ID,
                            content=response_text,
                            metadata=dict(outbound_metadata),
                        )
                    )
                else:
                    async with self._lock:
                        await self._set_status_unlocked(
                            STATUS_IDLE,
                            interaction_surface=None,
                            last_error=None,
                        )
                return
            await self.bus.publish_inbound(
                InboundMessage(
                    channel=DESKTOP_VOICE_CHANNEL,
                    sender_id="desktop_mic",
                    chat_id=DESKTOP_VOICE_CHAT_ID,
                    content=transcript,
                    metadata=metadata,
                    session_key_override=app_session_id,
                )
            )
        finally:
            if self._asr_task is asyncio.current_task():
                self._asr_task = None

    async def _handle_capture_failure(
        self,
        *,
        code: str,
        message: str,
        interaction_surface: str,
    ) -> None:
        async with self._lock:
            await self._set_status_unlocked(
                STATUS_IDLE,
                interaction_surface=None,
                last_error=code,
            )
        await self._broadcast_json(
            {
                "type": "error",
                "data": {
                    "code": code,
                    "message": message,
                    "interaction_surface": interaction_surface or None,
                },
            }
        )
        await self._notify_event_observer(
            "on_desktop_voice_error",
            code=code,
            message=message,
            snapshot=self.get_snapshot(),
        )
        if interaction_surface == "device_press":
            await self.device_channel.fail_external_voice_feedback(message)

    async def _set_status_unlocked(self, status: str, **updates: Any) -> None:
        self._state["status"] = status
        for key, value in updates.items():
            self._state[key] = value
        snapshot = self.get_snapshot()
        await self._notify_event_observer(
            "on_desktop_voice_state_changed",
            snapshot=snapshot,
        )
        await self._broadcast_json({"type": "state", "data": snapshot})

    def _pick_primary_ws(self) -> web.WebSocketResponse | None:
        if not self._clients:
            return None
        return max(self._clients, key=lambda client: self._client_order.get(client, 0))

    def _local_microphone_available(self) -> bool:
        if not self.enable_local_microphone:
            self._local_microphone_error = None
            return False
        try:
            import sounddevice  # noqa: F401
        except Exception as exc:
            self._local_microphone_error = str(exc)
            return False
        self._local_microphone_error = None
        return True

    def _is_authorized(self, request: web.Request) -> bool:
        if not self.auth_token:
            return True
        token = self._extract_auth_token(request)
        if not token:
            return False
        return hmac.compare_digest(token, self.auth_token)

    @staticmethod
    def _extract_auth_token(request: web.Request) -> str:
        auth_header = request.headers.get("Authorization", "").strip()
        if auth_header.startswith("Bearer "):
            return auth_header[7:].strip()
        return request.query.get("token", "").strip()

    def _asr_in_flight(self) -> bool:
        return bool(self._asr_task and not self._asr_task.done())

    async def _send_primary_json(self, payload: dict[str, Any]) -> None:
        ws = self._primary_ws
        if not ws or ws.closed:
            return
        try:
            await ws.send_json(payload)
        except Exception:
            logger.exception("Failed to send desktop voice control message")

    async def _broadcast_json(self, payload: dict[str, Any]) -> None:
        if not self._clients:
            return
        dead: list[web.WebSocketResponse] = []
        for ws in tuple(self._clients):
            if ws.closed:
                dead.append(ws)
                continue
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._clients.discard(ws)
            self._client_order.pop(ws, None)
            if self._primary_ws is ws:
                self._primary_ws = self._pick_primary_ws()

    async def _send_error(self, code: str, message: str) -> None:
        await self._broadcast_json(
            {
                "type": "error",
                "data": {"code": code, "message": message},
            }
        )

    async def _notify_event_observer(self, method_name: str, **kwargs: Any) -> Any:
        if not self._event_observer:
            return None
        callback = getattr(self._event_observer, method_name, None)
        if callback is None:
            return None
        try:
            return await callback(**kwargs)
        except Exception:
            logger.exception("Desktop voice event observer callback failed: {}", method_name)
            return None

    @staticmethod
    def _read_int(payload: dict[str, Any], *keys: str, default: int) -> int:
        for key in keys:
            if key not in payload:
                continue
            value = payload.get(key)
            if isinstance(value, int):
                return value
            if isinstance(value, str) and value.strip().isdigit():
                return int(value.strip())
        return default

    @staticmethod
    def _now_iso() -> str:
        return datetime.now().astimezone().isoformat(timespec="seconds")
