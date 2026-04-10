"""
DeviceChannel — ESP32 WebSocket 通信通道

职责:
1. 管理 WebSocket 连接 (/ws/device) + 心跳保活
2. 接收设备 JSON 文本帧，按 type 分发处理
3. 接收二进制帧，累积到音频 buffer（含溢出保护）
4. 音频接收完毕 → ASR 语音识别 → 发送到 AgentLoop
5. AI 回复 → TTS 语音合成 → 流式发送音频给设备
6. 维护设备状态机，状态变化时同步给设备
7. 处理触摸/摇一摇/设备状态事件
8. 断线检测 + 重连自动恢复会话

音频格式约定:
- ESP32 → 服务端: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- 服务端 → ESP32: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
"""
from __future__ import annotations

import asyncio
import hmac
import json
import time
import uuid
from datetime import datetime
from typing import Any, Optional

import aiohttp
from aiohttp import web
from loguru import logger

from models.protocol import DeviceMessageType, ServerMessageType, make_server_message
from models.device_state import DeviceState, VALID_TRANSITIONS, STATE_DISPLAY_HINTS
from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from services.asr import ASRService
from services.tts import TTSService


# 设备在 MessageBus 中的 channel / chat_id 标识
DEVICE_CHANNEL = "device"
DEVICE_CHAT_ID = "esp32"

# 音频流式发送的 chunk 大小 (4KB = 约 128ms @ 16kHz 16bit)
AUDIO_CHUNK_SIZE = 4096

# 最小有效音频长度 (太短可能是噪声, 0.5s @ 16kHz 16bit = 16000 bytes)
MIN_AUDIO_BYTES = 16000

# 最大音频 buffer 长度 (30s @ 16kHz 16bit = 960000 bytes)
MAX_AUDIO_BYTES = 960000

# 屏幕显示参数 (1.54寸 ST7789, 240×240)
DISPLAY_MAX_CHARS = 120  # 中文约每行10字 × 12行

# WebSocket 心跳间隔 (秒)
HEARTBEAT_INTERVAL = 30

# 设备无任何上行活动超过该时长后，主动判定连接已陈旧
DEVICE_ACTIVITY_STALE_TIMEOUT = 20

# 陈旧连接巡检频率 (秒)
CONNECTION_WATCHDOG_INTERVAL = 1

# 进入 LISTENING 后迟迟没有音频的超时 (秒)
LISTENING_START_TIMEOUT = 10

# 收到音频后，等待 audio_end 的空闲超时 (秒)
RECORDING_IDLE_TIMEOUT = 3

# 状态栏时间推送间隔 (秒)
TIME_PUSH_INTERVAL = 60

# 天气推送间隔 (秒) — 每 30 分钟
WEATHER_PUSH_INTERVAL = 1800

# App 设备命令等待结果超时 (秒)
COMMAND_RESULT_TIMEOUT = 5.0

# ACTIVE 状态判定：最近对话时间窗口 (秒)
ACTIVE_WINDOW = 30

# DeviceState → 表情状态映射
_STATE_TO_FACE: dict[DeviceState, str] = {
    DeviceState.IDLE: "IDLE",
    DeviceState.LISTENING: "LISTENING",
    DeviceState.PROCESSING: "PROCESSING",
    DeviceState.SPEAKING: "SPEAKING",
    DeviceState.ERROR: "IDLE",  # 错误状态显示默认表情
}

_SUPPORTED_APP_COMMANDS = {
    "mute",
    "toggle_led",
    "restart",
    "wake",
    "sleep",
    "set_volume",
    "set_led_color",
    "set_led_brightness",
}

_DEFAULT_CONTROL_STATE: dict[str, Any] = {
    "volume": 70,
    "muted": False,
    "sleeping": False,
    "led_enabled": True,
    "led_brightness": 50,
    "led_color": "#2563eb",
}

_DEFAULT_STATUS_BAR_STATE: dict[str, Any] = {
    "time": None,
    "weather": None,
    "weather_status": "idle",
    "updated_at": None,
}

_DEFAULT_LAST_COMMAND_STATE: dict[str, Any] = {
    "command_id": None,
    "client_command_id": None,
    "command": None,
    "status": "idle",
    "ok": None,
    "error": None,
    "updated_at": None,
}


class DeviceChannel:
    """ESP32 WebSocket 通信通道，集成 ASR + TTS + 状态机。"""

    def __init__(
        self,
        bus: MessageBus,
        asr: Optional[ASRService] = None,
        tts: Optional[TTSService] = None,
        auth_token: str = "",
        command_result_timeout_s: float = COMMAND_RESULT_TIMEOUT,
    ):
        self.bus = bus
        self.asr = asr
        self.tts = tts
        self.auth_token = auth_token.strip()
        self.ws: web.WebSocketResponse | None = None
        self.connected = False
        self.audio_buffer = bytearray()
        self._outbound_task: asyncio.Task | None = None
        self._heartbeat_task: asyncio.Task | None = None
        self._connection_watchdog_task: asyncio.Task | None = None
        self._recording_timeout_task: asyncio.Task | None = None
        self._asr_task: asyncio.Task | None = None
        self._tts_task: asyncio.Task | None = None
        self._audio_finalize_lock = asyncio.Lock()
        self._connection_seq: int = 0

        # ── 状态机 (Phase 5) ────────────────────────────
        self.state = DeviceState.IDLE

        # ── 设备信息 (Phase 5) ───────────────────────────
        self.device_info: dict[str, Any] = {
            "battery": -1,      # 电量百分比, -1 = 未知
            "wifi_rssi": 0,     # WiFi 信号强度 (dBm)
            "charging": False,  # 是否充电中
        }
        self._control_state: dict[str, Any] = dict(_DEFAULT_CONTROL_STATE)
        self._status_bar_state: dict[str, Any] = dict(_DEFAULT_STATUS_BAR_STATE)
        self._last_command_state: dict[str, Any] = dict(_DEFAULT_LAST_COMMAND_STATE)
        self._pending_app_commands: dict[str, dict[str, Any]] = {}
        self._command_result_timeout_s = max(0.01, float(command_result_timeout_s))

        # ── 连接统计 (Phase 6) ───────────────────────────
        self._connect_time: float = 0
        self._reconnect_count: int = 0
        self._last_device_activity_monotonic: float = 0.0
        self._last_device_activity_at: str | None = None

        # ── 表情系统 (Phase 3) ────────────────────────────
        self._last_chat_time: float = 0  # 最后对话时间戳
        self._time_push_task: asyncio.Task | None = None

        # ── 天气推送 ────────────────────────────────────
        self._weather_task: asyncio.Task | None = None
        self._weather_config: dict[str, Any] = {}
        self._last_weather: str = ""  # 缓存最新天气字符串
        self._event_observer: Any | None = None
        self._desktop_voice_bridge: Any | None = None

    def set_weather_config(self, config: dict[str, Any]) -> None:
        """设置天气 API 配置（从 config.yaml 加载）。"""
        self._weather_config = config

    def set_event_observer(self, observer: Any) -> None:
        """注册设备事件观察器。"""
        self._event_observer = observer

    def set_desktop_voice_bridge(self, bridge: Any) -> None:
        """注册桌面麦克风桥接器。"""
        self._desktop_voice_bridge = bridge

    async def _notify_event_observer(self, method_name: str, **kwargs: Any) -> None:
        """安全通知设备事件观察器。"""
        if not self._event_observer:
            return
        callback = getattr(self._event_observer, method_name, None)
        if callback is None:
            return
        try:
            await callback(**kwargs)
        except Exception:
            logger.exception("Device event observer callback failed: {}", method_name)

    def get_snapshot(self) -> dict[str, Any]:
        """返回当前设备快照。"""
        return {
            "connected": self._is_effectively_connected(),
            "state": self.state.value,
            "battery": self.device_info["battery"],
            "wifi_rssi": self.device_info["wifi_rssi"],
            "charging": self.device_info["charging"],
            "reconnect_count": self._reconnect_count,
            "last_seen_at": self._last_device_activity_at,
            "controls": dict(self._control_state),
            "status_bar": dict(self._status_bar_state),
            "last_command": dict(self._last_command_state),
        }

    @staticmethod
    def _now_iso() -> str:
        return datetime.now().astimezone().isoformat(timespec="seconds")

    def _set_last_command_state(
        self,
        *,
        command_id: str | None,
        client_command_id: str | None,
        command: str | None,
        status: str,
        ok: bool | None,
        error: str | None,
    ) -> None:
        self._last_command_state = {
            "command_id": command_id,
            "client_command_id": client_command_id,
            "command": command,
            "status": status,
            "ok": ok,
            "error": error.strip() if isinstance(error, str) and error.strip() else None,
            "updated_at": self._now_iso(),
        }

    def _merge_control_state(self, payload: dict[str, Any]) -> None:
        if "volume" in payload:
            volume = payload.get("volume")
            if isinstance(volume, int):
                self._control_state["volume"] = max(0, min(100, volume))
        if "muted" in payload:
            self._control_state["muted"] = bool(payload.get("muted"))
        if "sleeping" in payload:
            self._control_state["sleeping"] = bool(payload.get("sleeping"))

        led_payload = payload.get("led")
        if isinstance(led_payload, dict):
            if "enabled" in led_payload:
                self._control_state["led_enabled"] = bool(led_payload.get("enabled"))
            if "brightness" in led_payload:
                brightness = led_payload.get("brightness")
                if isinstance(brightness, int):
                    self._control_state["led_brightness"] = max(0, min(100, brightness))
            if "color" in led_payload:
                color = led_payload.get("color")
                if isinstance(color, str) and color.strip():
                    self._control_state["led_color"] = color.strip()

        if "led_enabled" in payload:
            self._control_state["led_enabled"] = bool(payload.get("led_enabled"))
        if "led_brightness" in payload:
            brightness = payload.get("led_brightness")
            if isinstance(brightness, int):
                self._control_state["led_brightness"] = max(0, min(100, brightness))
        if "led_color" in payload:
            color = payload.get("led_color")
            if isinstance(color, str) and color.strip():
                self._control_state["led_color"] = color.strip()

    def _merge_status_bar_state(
        self,
        payload: dict[str, Any],
        *,
        weather_status: str | None = None,
    ) -> None:
        status_bar = payload.get("status_bar")
        if isinstance(status_bar, dict):
            payload = {
                key: status_bar.get(key)
                for key in ("time", "weather", "weather_status")
                if key in status_bar
            }

        changed = False
        if "time" in payload:
            time_value = payload.get("time")
            normalized_time = time_value.strip() if isinstance(time_value, str) and time_value.strip() else None
            if self._status_bar_state.get("time") != normalized_time:
                self._status_bar_state["time"] = normalized_time
                changed = True
        if "weather" in payload:
            weather_value = payload.get("weather")
            normalized_weather = weather_value.strip() if isinstance(weather_value, str) and weather_value.strip() else None
            if self._status_bar_state.get("weather") != normalized_weather:
                self._status_bar_state["weather"] = normalized_weather
                changed = True
        next_weather_status = weather_status
        if next_weather_status is None and isinstance(payload.get("weather_status"), str):
            next_weather_status = payload["weather_status"].strip() or None
        if next_weather_status is not None and self._status_bar_state.get("weather_status") != next_weather_status:
            self._status_bar_state["weather_status"] = next_weather_status
            changed = True
        if changed:
            self._status_bar_state["updated_at"] = self._now_iso()

    async def notify_external_voice_transcribing(self) -> None:
        """桌面麦克风链路进入转写阶段时，更新设备反馈。"""
        if not self._is_effectively_connected():
            return
        await self._set_state(DeviceState.PROCESSING)
        await self._send_display_update("录音结束，正在识别")

    async def notify_external_voice_responding(self) -> None:
        """桌面麦克风链路进入回复阶段时，更新设备反馈。"""
        if not self._is_effectively_connected():
            return
        if self.state != DeviceState.PROCESSING:
            await self._set_state(DeviceState.PROCESSING)
        await self._send_display_update("正在回复")

    async def deliver_external_text_response(self, text: str) -> None:
        """把桌面麦克风链路的回复回传到设备，优先走设备喇叭播放。"""
        if not self._is_effectively_connected():
            return
        if self.tts:
            await self._send_voice_reply(text)
            return
        if self.state != DeviceState.SPEAKING:
            await self._set_state(DeviceState.SPEAKING)
        await self._send_display_update(text)
        await self.send_text_reply(text)
        if self.state != DeviceState.IDLE:
            await self._set_state(DeviceState.IDLE)

    async def fail_external_voice_feedback(self, message: str) -> None:
        """桌面麦克风链路异常或取消时，恢复设备状态并提示。"""
        if not self._is_effectively_connected():
            return
        await self._send_display_update(message)
        if self.state != DeviceState.IDLE:
            await self._set_state(DeviceState.IDLE)

    # ── 状态机方法 ─────────────────────────────────────────

    async def _set_state(self, new_state: DeviceState) -> None:
        """切换设备状态，校验合法性，并通知设备。"""
        if new_state == self.state:
            return

        valid_targets = VALID_TRANSITIONS.get(self.state, set())
        if new_state not in valid_targets:
            logger.warning(
                "非法状态转换: {} → {}，强制恢复 IDLE",
                self.state.value, new_state.value,
            )
            new_state = DeviceState.IDLE

        old = self.state
        self.state = new_state
        logger.debug("状态转换: {} → {}", old.value, new_state.value)
        await self._notify_event_observer(
            "on_device_state_changed",
            old_state=old.value,
            new_state=new_state.value,
            snapshot=self.get_snapshot(),
        )

        # 通知设备状态变化
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": new_state.value}
        ))

        # 发送表情指令：状态 → 表情映射
        face_state = _STATE_TO_FACE.get(new_state, "IDLE")
        # IDLE 状态下判定是否为 ACTIVE（最近30秒内聊过天）
        if new_state == DeviceState.IDLE and self._last_chat_time > 0:
            if (time.time() - self._last_chat_time) < ACTIVE_WINDOW:
                face_state = "ACTIVE"
        await self.send_json(make_server_message(
            ServerMessageType.FACE_UPDATE, {"state": face_state}
        ))

        # 状态切换时发送屏幕提示
        hint = STATE_DISPLAY_HINTS.get(new_state, "")
        if hint:
            await self._send_display_update(hint)

    async def _recover_to_idle(self) -> None:
        """从 ERROR 或任何异常状态恢复到 IDLE。"""
        self.state = DeviceState.ERROR
        await self._set_state(DeviceState.IDLE)

    # ── 公共方法 ─────────────────────────────────────────────

    def register_routes(self, app: web.Application) -> None:
        """注册 WebSocket 路由到 aiohttp app。"""
        app.router.add_get("/ws/device", self._handle_ws)

    async def start_outbound_consumer(self) -> None:
        """启动后台任务，从 MessageBus outbound 队列消费消息并发给设备。"""
        self._outbound_task = asyncio.create_task(self._consume_outbound())

    async def stop(self) -> None:
        """优雅关闭: 停止心跳 + outbound 消费 + WebSocket 连接。"""
        await self._cancel_runtime_tasks()

        # 停止 outbound 消费
        if self._outbound_task and not self._outbound_task.done():
            self._outbound_task.cancel()
            try:
                await self._outbound_task
            except asyncio.CancelledError:
                pass

        # 关闭 WebSocket
        if self.ws and not self.ws.closed:
            await self.ws.close()

        logger.info("DeviceChannel 已停止")

    async def _cancel_task(self, task: asyncio.Task | None) -> None:
        """取消后台任务并等待结束。"""
        if not task or task.done():
            return
        if task is asyncio.current_task():
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    async def _cancel_runtime_tasks(self) -> None:
        """取消与当前设备连接相关的后台任务。"""
        await self._cancel_task(self._recording_timeout_task)
        await self._cancel_task(self._asr_task)
        await self._cancel_task(self._tts_task)
        await self._cancel_task(self._heartbeat_task)
        await self._cancel_task(self._connection_watchdog_task)
        await self._cancel_task(self._time_push_task)
        await self._cancel_task(self._weather_task)
        pending = list(self._pending_app_commands.values())
        self._pending_app_commands.clear()
        for item in pending:
            timeout_task = item.get("timeout_task")
            if isinstance(timeout_task, asyncio.Task):
                await self._cancel_task(timeout_task)

    def _mark_device_activity(self) -> None:
        self._last_device_activity_monotonic = time.monotonic()
        self._last_device_activity_at = self._now_iso()

    def _is_connection_stale(self) -> bool:
        if not self.connected:
            return False
        if self._last_device_activity_monotonic <= 0:
            return False
        return (
            time.monotonic() - self._last_device_activity_monotonic
        ) > DEVICE_ACTIVITY_STALE_TIMEOUT

    def _is_effectively_connected(self) -> bool:
        return self.connected and not self._is_connection_stale()

    async def _connection_watchdog_loop(self, connection_id: int) -> None:
        while True:
            try:
                await asyncio.sleep(CONNECTION_WATCHDOG_INTERVAL)
                if connection_id != self._connection_seq or not self.connected:
                    break
                if not self._is_connection_stale():
                    continue
                idle_for = time.monotonic() - self._last_device_activity_monotonic
                logger.warning(
                    "设备连接超过 {:.1f}s 无活动，主动判定离线",
                    idle_for,
                )
                if self.ws and not self.ws.closed:
                    await self.ws.close(
                        code=1001,
                        message=b"device activity timeout",
                    )
                break
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("设备连接 watchdog 异常")
                break

    def _arm_recording_timeout(self, timeout_s: float) -> None:
        """启动或重置录音 watchdog。"""
        if self._recording_timeout_task and not self._recording_timeout_task.done():
            self._recording_timeout_task.cancel()
        self._recording_timeout_task = asyncio.create_task(
            self._recording_timeout_loop(timeout_s)
        )

    async def _recording_timeout_loop(self, timeout_s: float) -> None:
        """录音超时保护：无音频或无 audio_end 时自动恢复。"""
        try:
            await asyncio.sleep(timeout_s)
            if self.state != DeviceState.LISTENING:
                return

            if self.audio_buffer:
                logger.warning("录音空闲超时，自动结束并处理当前音频")
                await self._send_display_update("录音结束，正在处理")
                await self._on_audio_end(trigger="timeout")
                return

            logger.warning("进入 LISTENING 后长时间未收到音频，自动恢复 IDLE")
            await self._send_display_update("录音超时，已取消")
            await self._set_state(DeviceState.IDLE)
        except asyncio.CancelledError:
            pass

    async def interrupt_current_activity(self, notice: str = "已取消") -> None:
        """打断当前录音 / 识别 / 播放，并恢复到 IDLE。"""
        should_stop_agent = self.state == DeviceState.PROCESSING
        self.audio_buffer.clear()
        await self._cancel_task(self._recording_timeout_task)
        await self._cancel_task(self._asr_task)
        await self._cancel_task(self._tts_task)
        if should_stop_agent:
            await self.bus.publish_inbound(InboundMessage(
                channel=DEVICE_CHANNEL,
                sender_id="esp32",
                chat_id=DEVICE_CHAT_ID,
                content="/stop",
                metadata={"source": "device_interrupt"},
            ))
        if self.state != DeviceState.IDLE:
            await self._set_state(DeviceState.IDLE)
        if notice:
            await self._send_display_update(notice)

    # ── WebSocket 心跳保活 (Phase 6.1) ────────────────────

    async def _heartbeat_loop(self) -> None:
        """定时发送 ping，检测设备是否在线。"""
        while True:
            try:
                await asyncio.sleep(HEARTBEAT_INTERVAL)
                if self.ws and not self.ws.closed:
                    await self.ws.ping()
                    logger.debug("WebSocket ping 已发送")
                else:
                    break
            except asyncio.CancelledError:
                break
            except Exception:
                logger.warning("WebSocket ping 失败，设备可能已断线")
                break

    # ── WebSocket 连接处理 ───────────────────────────────────

    async def _handle_ws(self, request: web.Request) -> web.StreamResponse:
        """处理 WebSocket 连接（含心跳保活和重连计数）。"""
        if not self._is_authorized(request):
            logger.warning("拒绝未授权设备连接 ({})", request.remote)
            return web.json_response({"error": "unauthorized"}, status=401)

        ws = web.WebSocketResponse(heartbeat=HEARTBEAT_INTERVAL)
        await ws.prepare(request)
        connection_id = self._connection_seq + 1

        # 如果已有连接，关闭旧的（单设备模式）
        if self.ws and not self.ws.closed:
            logger.warning("新设备连接，关闭旧连接")
            await self.ws.close()
            # 停止旧心跳
            if self._heartbeat_task and not self._heartbeat_task.done():
                self._heartbeat_task.cancel()

        # 判断是否重连
        is_reconnect = self._connect_time > 0
        if is_reconnect:
            self._reconnect_count += 1
            logger.info(
                "设备重连 (第{}次, {})",
                self._reconnect_count, request.remote,
            )
        else:
            logger.info("设备首次连接 ({})", request.remote)

        self._connection_seq = connection_id
        self.ws = ws
        self.connected = True
        self._mark_device_activity()
        self.audio_buffer.clear()
        self.state = DeviceState.IDLE
        self._connect_time = time.monotonic()
        await self._notify_event_observer(
            "on_device_connection_changed",
            connected=True,
            snapshot=self.get_snapshot(),
        )

        # 启动心跳
        self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())
        self._connection_watchdog_task = asyncio.create_task(
            self._connection_watchdog_loop(connection_id)
        )

        # 启动时间推送
        if self._time_push_task and not self._time_push_task.done():
            self._time_push_task.cancel()
        self._time_push_task = asyncio.create_task(self._time_push_loop())

        # 启动天气推送
        if self._weather_task and not self._weather_task.done():
            self._weather_task.cancel()
        self._weather_task = asyncio.create_task(self._weather_push_loop())

        # 发送初始状态（重连后设备恢复到 IDLE）
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": DeviceState.IDLE.value}
        ))

        # 发送初始时间
        import datetime
        now = datetime.datetime.now()
        await self._send_status_bar_update(time=now.strftime("%H:%M"))

        try:
            async for msg in ws:
                self._mark_device_activity()
                if msg.type == aiohttp.WSMsgType.TEXT:
                    await self._on_text(msg.data)
                elif msg.type == aiohttp.WSMsgType.BINARY:
                    await self._on_binary(msg.data)
                elif msg.type == aiohttp.WSMsgType.ERROR:
                    logger.error("WebSocket 错误: {}", ws.exception())
        except Exception:
            logger.exception("WebSocket 处理异常")
        finally:
            if connection_id != self._connection_seq:
                logger.info("旧设备连接已关闭，跳过当前实例清理")
                return ws

            # 断线清理
            self.connected = False
            self.ws = None
            self.audio_buffer.clear()
            await self._cancel_runtime_tasks()
            old_state = self.state
            self.state = DeviceState.IDLE
            if old_state != DeviceState.IDLE:
                await self._notify_event_observer(
                    "on_device_state_changed",
                    old_state=old_state.value,
                    new_state=DeviceState.IDLE.value,
                    snapshot=self.get_snapshot(),
                )
            await self._notify_event_observer(
                "on_device_connection_changed",
                connected=False,
                snapshot=self.get_snapshot(),
            )
            uptime = time.monotonic() - self._connect_time
            logger.info("设备已断开 (在线 {:.0f}s)", uptime)

        return ws

    def _is_authorized(self, request: web.Request) -> bool:
        """校验设备接入 token；未配置 token 时默认放行。"""
        if not self.auth_token:
            return True

        candidate = self._extract_auth_token(request)
        if not candidate:
            return False
        return hmac.compare_digest(candidate, self.auth_token)

    @staticmethod
    def _extract_auth_token(request: web.Request) -> str:
        """从 Header 或 Query 中提取设备 token。"""
        auth_header = request.headers.get("Authorization", "").strip()
        if auth_header.startswith("Bearer "):
            return auth_header[7:].strip()

        header_token = request.headers.get("X-Device-Token", "").strip()
        if header_token:
            return header_token

        return request.query.get("token", "").strip()

    # ── 接收处理 ─────────────────────────────────────────────

    async def _on_text(self, raw: str) -> None:
        """处理 JSON 文本帧。"""
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("收到无效 JSON: {}", raw[:100])
            return

        msg_type = payload.get("type", "")
        data = payload.get("data", {})

        if msg_type == DeviceMessageType.TEXT_INPUT:
            text = data.get("text", "").strip()
            if not text:
                return
            logger.info("收到文字输入: '{}'", text[:50])
            self._last_chat_time = time.time()
            await self.bus.publish_inbound(InboundMessage(
                channel=DEVICE_CHANNEL,
                sender_id="esp32",
                chat_id=DEVICE_CHAT_ID,
                content=text,
            ))

        elif msg_type == DeviceMessageType.AUDIO_END:
            await self._on_audio_end()

        elif msg_type == DeviceMessageType.TOUCH_EVENT:
            await self._on_touch_event(data)

        elif msg_type == DeviceMessageType.SHAKE_EVENT:
            await self._on_shake_event(data)

        elif msg_type == DeviceMessageType.DEVICE_STATUS:
            await self._on_device_status(data)

        elif msg_type == DeviceMessageType.DEVICE_COMMAND_RESULT:
            await self._on_device_command_result(data)

        else:
            logger.warning("未知消息类型: {}", msg_type)

    async def _on_binary(self, data: bytes) -> None:
        """处理二进制帧（音频数据）。

        收到第一帧时切换到 LISTENING 状态。
        超过 MAX_AUDIO_BYTES 时自动截断。
        """
        if self.state in {DeviceState.PROCESSING, DeviceState.SPEAKING}:
            logger.debug("当前状态为 {}，忽略音频帧", self.state.value)
            return

        if self.state == DeviceState.IDLE:
            await self._set_state(DeviceState.LISTENING)

        # 音频 buffer 溢出保护 (Phase 6.2)
        if len(self.audio_buffer) + len(data) > MAX_AUDIO_BYTES:
            logger.warning(
                "音频 buffer 溢出 ({} bytes > {}), 自动截断",
                len(self.audio_buffer) + len(data), MAX_AUDIO_BYTES,
            )
            await self._send_display_update("录音太长，已自动截断")
            # 触发处理当前已有的音频
            await self._on_audio_end()
            return

        self.audio_buffer.extend(data)
        self._arm_recording_timeout(RECORDING_IDLE_TIMEOUT)

    async def _on_audio_end(self, trigger: str = "device") -> None:
        """音频接收完毕，触发 ASR 识别 → 发送到 AgentLoop。"""
        async with self._audio_finalize_lock:
            await self._cancel_task(self._recording_timeout_task)
            audio_size = len(self.audio_buffer)
            logger.info("收到 audio_end(trigger={}), 音频 buffer: {} bytes", trigger, audio_size)

            pcm_data = bytes(self.audio_buffer)
            self.audio_buffer.clear()

            if audio_size < MIN_AUDIO_BYTES:
                logger.warning("音频太短 ({} bytes < {}), 忽略", audio_size, MIN_AUDIO_BYTES)
                await self._set_state(DeviceState.IDLE)
                return

            if not self.asr:
                logger.warning("ASR 服务未初始化，无法识别音频")
                await self._set_state(DeviceState.IDLE)
                return

            if self._asr_task and not self._asr_task.done():
                logger.warning("已有 ASR 任务在处理中，忽略重复 audio_end")
                await self._set_state(DeviceState.IDLE)
                return

            # 切换到 PROCESSING 状态
            await self._set_state(DeviceState.PROCESSING)
            self._asr_task = asyncio.create_task(
                self._run_asr_and_publish(pcm_data, audio_size)
            )

    async def _run_asr_and_publish(self, pcm_data: bytes, audio_size: int) -> None:
        """后台执行 ASR，并将识别文本投递给 AgentLoop。"""
        t0 = time.monotonic()
        try:
            text = await self.asr.transcribe(pcm_data)
        except asyncio.CancelledError:
            logger.info("ASR 任务已取消")
            await self._send_display_update("已取消")
            if self.state == DeviceState.PROCESSING:
                await self._set_state(DeviceState.IDLE)
            return
        except Exception:
            logger.exception("ASR 识别失败")
            await self._send_display_update("语音识别失败，请重试")
            await self._set_state(DeviceState.IDLE)
            return
        finally:
            if self._asr_task is asyncio.current_task():
                self._asr_task = None

        asr_ms = (time.monotonic() - t0) * 1000
        audio_duration = audio_size / (16000 * 2)
        logger.info(
            "[ASR {:.1f}s] 识别: '{}' (音频 {:.1f}s)",
            asr_ms / 1000, text[:50] if text else "", audio_duration,
        )

        if not text.strip():
            logger.warning("ASR 识别结果为空，忽略")
            await self._send_display_update("没听清，请再说一次")
            await self._set_state(DeviceState.IDLE)
            return

        self._last_chat_time = time.time()

        meta = {
            "source": "voice",
            "source_channel": DEVICE_CHANNEL,
            "voice_path": "device_mic",
            "interaction_surface": "device_press",
            "capture_source": "device_mic",
            "asr_ms": asr_ms,
        }
        if self.asr.last_emotion:
            meta["emotion"] = self.asr.last_emotion

        await self.bus.publish_inbound(InboundMessage(
            channel=DEVICE_CHANNEL,
            sender_id="esp32",
            chat_id=DEVICE_CHAT_ID,
            content=text,
            metadata=meta,
        ))

    # ── 触摸事件处理 (Phase 5.4) ─────────────────────────────

    async def _on_touch_event(self, data: dict) -> None:
        """处理触摸事件。

        动作:
        - single: 单击 — 开始/结束录音（toggle）
        - double: 双击 — 打断当前播放，回到 IDLE
        - long:   长按 — 持续录音模式（按住说话，松开结束）
        """
        action = data.get("action", "unknown")
        logger.info("收到触摸事件: {}", action)

        if action == "single":
            if self.state == DeviceState.IDLE:
                # 开始录音：通知设备进入 LISTENING
                await self._set_state(DeviceState.LISTENING)
                self._arm_recording_timeout(LISTENING_START_TIMEOUT)
            elif self.state == DeviceState.LISTENING:
                # 结束录音：触发 audio_end 处理
                await self._on_audio_end()
            elif self.state == DeviceState.SPEAKING:
                # 播放中单击 → 打断，回到 IDLE
                await self.interrupt_current_activity()

        elif action == "double":
            # 双击：无论当前状态，打断并回到 IDLE
            if self.state != DeviceState.IDLE:
                await self.interrupt_current_activity()

        elif action == "long_press":
            # 长按开始：进入 LISTENING
            if self.state == DeviceState.IDLE:
                bridge = self._desktop_voice_bridge
                if bridge is None:
                    await self._set_state(DeviceState.LISTENING)
                    self._arm_recording_timeout(LISTENING_START_TIMEOUT)
                elif getattr(bridge, "is_ready", lambda: False)():
                    started = await bridge.start_device_push_to_talk()
                    if started:
                        await self._set_state(DeviceState.LISTENING)
                    else:
                        await self._send_display_update("桌面麦克风不可用")
                        if self.state != DeviceState.IDLE:
                            await self._set_state(DeviceState.IDLE)
                else:
                    await self._send_display_update("桌面麦克风未连接")

        elif action == "long_release":
            # 长按松开：结束录音
            if self.state == DeviceState.LISTENING:
                bridge = self._desktop_voice_bridge
                if bridge is None:
                    await self._on_audio_end()
                else:
                    stopped = await bridge.stop_device_push_to_talk()
                    if not stopped:
                        await self._set_state(DeviceState.IDLE)

        else:
            logger.warning("未知触摸动作: {}", action)

    # ── 摇一摇事件处理 (Phase 5.4) ───────────────────────────

    async def _on_shake_event(self, data: dict) -> None:
        """处理摇一摇事件 — 触发 AI 讲一个笑话/随机互动。"""
        logger.info("收到摇一摇事件")

        if self.state != DeviceState.IDLE:
            logger.debug("设备非空闲状态，忽略摇一摇")
            return

        # 发送预设提示给 AgentLoop
        await self.bus.publish_inbound(InboundMessage(
            channel=DEVICE_CHANNEL,
            sender_id="esp32",
            chat_id=DEVICE_CHAT_ID,
            content="讲一个有趣的笑话或者冷知识",
            metadata={"source": "shake"},
        ))

    # ── 设备状态上报 (Phase 5.4) ──────────────────────────────

    async def _on_device_status(self, data: dict) -> None:
        """记录设备状态（电量/WiFi/充电）。"""
        self._mark_device_activity()
        if "battery" in data:
            self.device_info["battery"] = data["battery"]
        if "wifi_rssi" in data:
            self.device_info["wifi_rssi"] = data["wifi_rssi"]
        if "charging" in data:
            self.device_info["charging"] = data["charging"]
        self._merge_control_state(data)
        self._merge_status_bar_state(data)
        logger.info(
            "设备状态更新: 电量={}%, WiFi={}dBm, 充电={}",
            self.device_info["battery"],
            self.device_info["wifi_rssi"],
            self.device_info["charging"],
        )
        await self._notify_event_observer(
            "on_device_status_updated",
            snapshot=self.get_snapshot(),
        )

    async def _on_device_command_result(self, data: dict[str, Any]) -> None:
        self._mark_device_activity()
        command_id = str(data.get("command_id") or "").strip() or None
        pending = self._pending_app_commands.pop(command_id, None) if command_id else None
        timeout_task = pending.get("timeout_task") if isinstance(pending, dict) else None
        if isinstance(timeout_task, asyncio.Task):
            await self._cancel_task(timeout_task)
        client_command_id = str(data.get("client_command_id") or "").strip() or None
        if not client_command_id and pending:
            client_command_id = pending.get("client_command_id")
        command = str(data.get("command") or "").strip() or None
        if not command and pending:
            command = pending.get("command")
        ok = data.get("ok")
        ok_bool = ok if isinstance(ok, bool) else False
        error = str(data.get("error") or "").strip() or None

        applied_state = data.get("applied_state", {})
        if isinstance(applied_state, dict):
            self._merge_control_state(applied_state)
            self._merge_status_bar_state(applied_state)

        self._set_last_command_state(
            command_id=command_id,
            client_command_id=client_command_id,
            command=command,
            status="succeeded" if ok_bool else "failed",
            ok=ok_bool,
            error=error,
        )

        result_payload = {
            "command_id": command_id,
            "client_command_id": client_command_id,
            "command": command,
            "ok": ok_bool,
            "error": error,
            "applied_state": applied_state if isinstance(applied_state, dict) else {},
            "status": self._last_command_state["status"],
        }
        logger.info(
            "设备命令结果: command={} ok={} error={}",
            command or "unknown",
            ok_bool,
            error or "",
        )
        await self._notify_event_observer(
            "on_device_command_updated",
            result=result_payload,
            snapshot=self.get_snapshot(),
        )

    # ── 状态栏定时推送 (Phase 3) ─────────────────────────────

    async def _time_push_loop(self) -> None:
        """每分钟推送一次当前时间到设备状态栏。"""
        import datetime
        while True:
            try:
                await asyncio.sleep(TIME_PUSH_INTERVAL)
                if not self._is_effectively_connected():
                    continue
                now = datetime.datetime.now()
                time_str = now.strftime("%H:%M")
                await self._send_status_bar_update(time=time_str)
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("时间推送异常")

    async def _weather_push_loop(self) -> None:
        """每 30 分钟从 OpenWeatherMap 获取天气并推送到设备。"""
        while True:
            try:
                weather_str, weather_status = await self._fetch_weather()
                self._merge_status_bar_state({}, weather_status=weather_status)
                await self._notify_event_observer(
                    "on_device_status_updated",
                    snapshot=self.get_snapshot(),
                )
                if weather_str:
                    self._last_weather = weather_str
                    await self._send_status_bar_update(weather=weather_str)
                    logger.info("天气推送: {}", weather_str)
                await asyncio.sleep(WEATHER_PUSH_INTERVAL)
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("天气推送异常")
                self._merge_status_bar_state({}, weather_status="fetch_failed")
                await self._notify_event_observer(
                    "on_device_status_updated",
                    snapshot=self.get_snapshot(),
                )
                await asyncio.sleep(60)  # 出错后 1 分钟重试

    async def _fetch_weather(self) -> tuple[str, str]:
        """从 OpenWeatherMap API 获取当前温度。"""
        api_key = self._weather_config.get("api_key", "")
        city = self._weather_config.get("city", "Hong Kong")
        units = self._weather_config.get("units", "metric")
        if not api_key:
            logger.debug("天气 API Key 未配置，改用 fallback provider")
            return await self._fetch_weather_fallback(city=city, units=units)

        return await self._fetch_weather_openweather(
            api_key=api_key,
            city=city,
            units=units,
        )

    async def _fetch_weather_openweather(
        self,
        *,
        api_key: str,
        city: str,
        units: str,
    ) -> tuple[str, str]:
        url = (
            f"https://api.openweathermap.org/data/2.5/weather"
            f"?q={city}&units={units}&appid={api_key}"
        )

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                    if resp.status != 200:
                        logger.warning("天气 API 返回 {}: {}", resp.status, await resp.text())
                        return "", "fetch_failed"
                    data = await resp.json()
                    temp = data.get("main", {}).get("temp")
                    if temp is not None:
                        return f"{int(round(temp))}°C", "ready"
                    return "", "fetch_failed"
        except Exception:
            logger.exception("天气 API 请求失败")
            return "", "fetch_failed"

    async def _fetch_weather_fallback(
        self,
        *,
        city: str,
        units: str,
    ) -> tuple[str, str]:
        temperature_unit = "fahrenheit" if units == "imperial" else "celsius"
        suffix = "°F" if temperature_unit == "fahrenheit" else "°C"
        geocode_url = (
            "https://geocoding-api.open-meteo.com/v1/search"
            f"?name={city}&count=1&language=en&format=json"
        )

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    geocode_url,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(
                            "天气 fallback geocoding 返回 {}: {}",
                            resp.status,
                            await resp.text(),
                        )
                        return "", "fetch_failed"
                    geocode = await resp.json()
                results = geocode.get("results") or []
                if not results:
                    logger.warning("天气 fallback geocoding 未找到城市: {}", city)
                    return "", "fetch_failed"
                first = results[0]
                latitude = first.get("latitude")
                longitude = first.get("longitude")
                if latitude is None or longitude is None:
                    return "", "fetch_failed"

                forecast_url = (
                    "https://api.open-meteo.com/v1/forecast"
                    f"?latitude={latitude}&longitude={longitude}"
                    f"&current=temperature_2m&temperature_unit={temperature_unit}"
                )
                async with session.get(
                    forecast_url,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(
                            "天气 fallback forecast 返回 {}: {}",
                            resp.status,
                            await resp.text(),
                        )
                        return "", "fetch_failed"
                    data = await resp.json()
                temp = data.get("current", {}).get("temperature_2m")
                if temp is None:
                    return "", "fetch_failed"
                return f"{int(round(float(temp)))}{suffix}", "ready"
        except Exception:
            logger.exception("天气 fallback 请求失败")
            return "", "fetch_failed"

    async def _send_status_bar_update(
        self,
        time: str | None = None,
        battery: int | None = None,
        weather: str | None = None,
    ) -> None:
        """发送状态栏更新到设备。"""
        data: dict[str, Any] = {}
        if time is not None:
            data["time"] = time
        if battery is not None:
            data["battery"] = battery
        if weather is not None:
            data["weather"] = weather
        if data:
            next_weather_status = "ready" if weather is not None and weather else None
            self._merge_status_bar_state(data, weather_status=next_weather_status)
            await self.send_json(make_server_message(
                ServerMessageType.STATUS_BAR_UPDATE, data
            ))
            await self._notify_event_observer(
                "on_device_status_updated",
                snapshot=self.get_snapshot(),
            )

    # ── 屏幕显示控制 (Phase 5.3) ─────────────────────────────

    async def _send_display_update(self, text: str, truncate: bool = True) -> None:
        """发送屏幕显示更新。

        Args:
            text: 显示文字
            truncate: 是否截断超长文本（默认 True）
        """
        if truncate and len(text) > DISPLAY_MAX_CHARS:
            text = text[:DISPLAY_MAX_CHARS - 3] + "..."
        await self.send_json(make_server_message(
            ServerMessageType.DISPLAY_UPDATE, {"text": text}
        ))

    # ── 发送方法 ─────────────────────────────────────────────

    async def send_json(self, msg: dict) -> None:
        """发送 JSON 消息给设备。"""
        if not self.ws or self.ws.closed:
            logger.warning("无法发送: 设备未连接")
            return
        await self.ws.send_json(msg)

    async def send_bytes(self, data: bytes) -> None:
        """发送二进制数据给设备。"""
        if not self.ws or self.ws.closed:
            logger.warning("无法发送二进制: 设备未连接")
            return
        await self.ws.send_bytes(data)

    async def send_text_reply(self, text: str) -> None:
        """发送文字回复给设备。"""
        msg = make_server_message(ServerMessageType.TEXT_REPLY, {"text": text})
        await self.send_json(msg)

    async def execute_app_command(
        self,
        command: str,
        params: dict[str, Any],
        *,
        client_command_id: str | None = None,
    ) -> dict[str, Any]:
        """执行来自 Flutter App 的设备控制命令。"""
        if not self._is_effectively_connected():
            raise RuntimeError("DEVICE_OFFLINE")
        if command not in _SUPPORTED_APP_COMMANDS:
            raise ValueError("COMMAND_NOT_SUPPORTED")

        normalized_params = self._normalize_app_command_params(command, params)
        command_id = f"cmd_{uuid.uuid4().hex[:12]}"
        timeout_task = asyncio.create_task(self._expire_pending_command(command_id))
        self._pending_app_commands[command_id] = {
            "command": command,
            "client_command_id": client_command_id,
            "timeout_task": timeout_task,
        }
        self._set_last_command_state(
            command_id=command_id,
            client_command_id=client_command_id,
            command=command,
            status="pending",
            ok=None,
            error=None,
        )
        await self.send_json(make_server_message(
            ServerMessageType.DEVICE_COMMAND,
            {
                "command_id": command_id,
                "client_command_id": client_command_id,
                "command": command,
                "params": normalized_params,
            },
        ))
        return {
            "accepted": True,
            "command_id": command_id,
            "client_command_id": client_command_id,
            "command": command,
            "status": "pending",
            "device": self.get_snapshot(),
        }

    async def _expire_pending_command(self, command_id: str) -> None:
        try:
            await asyncio.sleep(self._command_result_timeout_s)
            pending = self._pending_app_commands.pop(command_id, None)
            if not pending:
                return
            command = pending.get("command")
            client_command_id = pending.get("client_command_id")
            self._set_last_command_state(
                command_id=command_id,
                client_command_id=client_command_id,
                command=command,
                status="failed",
                ok=False,
                error="command_timeout",
            )
            await self._notify_event_observer(
                "on_device_command_updated",
                result={
                    "command_id": command_id,
                    "client_command_id": client_command_id,
                    "command": command,
                    "ok": False,
                    "error": "command_timeout",
                    "applied_state": {},
                    "status": "failed",
                },
                snapshot=self.get_snapshot(),
            )
        except asyncio.CancelledError:
            pass

    @staticmethod
    def _normalize_app_command_params(command: str, params: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(params, dict):
            raise ValueError("INVALID_ARGUMENT")

        normalized = dict(params)
        if command == "set_volume":
            level = normalized.get("level")
            if not isinstance(level, int) or level < 0 or level > 100:
                raise ValueError("INVALID_ARGUMENT")
        elif command == "set_led_brightness":
            level = normalized.get("level")
            if not isinstance(level, int) or level < 0 or level > 100:
                raise ValueError("INVALID_ARGUMENT")
        elif command == "set_led_color":
            color = normalized.get("color")
            if not isinstance(color, str) or not color.strip():
                raise ValueError("INVALID_ARGUMENT")
            normalized["color"] = color.strip()
        return normalized

    async def send_outbound(self, out_msg: OutboundMessage) -> None:
        """按设备规则发送一条 outbound 消息。"""
        if out_msg.channel != DEVICE_CHANNEL:
            logger.debug("忽略非 device 消息 (channel={})", out_msg.channel)
            return

        if out_msg.metadata.get("_progress"):
            return

        if not out_msg.content:
            return

        logger.info("发送回复给设备: '{}'", out_msg.content[:50])

        source = out_msg.metadata.get("source", "")
        if self.tts and source == "voice":
            await self._send_voice_reply(out_msg.content)
        else:
            await self.send_text_reply(out_msg.content)

    async def _send_voice_reply(self, text: str) -> None:
        """TTS 合成并流式发送语音回复给设备。

        流程:
        1. 发送 display_update (屏幕显示文字)
        2. 发送 state_change → SPEAKING
        3. 发送 audio_play 开始信号
        4. TTS 合成 → 流式发送 PCM 二进制帧
        5. 发送 audio_play_end 结束信号
        6. 发送 state_change → IDLE
        """
        if not self.tts:
            logger.warning("TTS 服务未初始化，仅发送文字回复")
            await self.send_text_reply(text)
            return
        playback_task = asyncio.create_task(self._stream_voice_reply(text))
        try:
            self._tts_task = playback_task
            await playback_task
        except asyncio.CancelledError:
            logger.info("语音播放已取消")
            await self.send_json(make_server_message(
                ServerMessageType.AUDIO_PLAY_END, {}
            ))
        except Exception:
            logger.exception("TTS 合成/发送失败，降级为文字回复")
            # TTS 失败降级: 发送文字回复 (Phase 6.2)
            await self.send_text_reply(text)
        finally:
            if self._tts_task is playback_task and playback_task.done():
                self._tts_task = None
            if self.state != DeviceState.IDLE:
                await self._set_state(DeviceState.IDLE)

    async def _stream_voice_reply(self, text: str) -> None:
        """执行实际的 TTS 合成与音频流发送。"""
        await self._send_display_update(text)
        await self._set_state(DeviceState.SPEAKING)
        logger.info(
            "开始向设备发送 TTS 音频: voice={}, text='{}'",
            self.tts.voice if self.tts else "unknown",
            text[:50],
        )

        t0 = time.monotonic()
        await self.send_json(make_server_message(
            ServerMessageType.AUDIO_PLAY, {}
        ))

        chunk_count = 0
        total_bytes = 0
        async for chunk in self.tts.synthesize_stream(text, chunk_size=AUDIO_CHUNK_SIZE):
            await self.send_bytes(chunk)
            chunk_count += 1
            total_bytes += len(chunk)

        await self.send_json(make_server_message(
            ServerMessageType.AUDIO_PLAY_END, {}
        ))

        if total_bytes == 0:
            logger.warning("设备 TTS 播放结束，但未发送任何 PCM 字节")

        tts_ms = (time.monotonic() - t0) * 1000
        duration_s = total_bytes / (16000 * 2)
        logger.info(
            "[TTS {:.1f}s] {} chunks, {} bytes ({:.1f}s 音频)",
            tts_ms / 1000, chunk_count, total_bytes, duration_s,
        )

    # ── Outbound 消费 ────────────────────────────────────────

    async def _consume_outbound(self) -> None:
        """从 MessageBus outbound 队列消费消息，转发给设备。"""
        logger.info("DeviceChannel outbound 消费者已启动")
        while True:
            try:
                out_msg: OutboundMessage = await self.bus.consume_outbound()
                await self.send_outbound(out_msg)

            except asyncio.CancelledError:
                logger.info("DeviceChannel outbound 消费者已停止")
                break
            except Exception:
                logger.exception("Outbound 消费异常")
                await asyncio.sleep(1)
