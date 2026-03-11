"""
DeviceChannel — ESP32 WebSocket 通信通道

职责:
1. 管理 WebSocket 连接 (/ws/device)
2. 接收设备 JSON 文本帧，按 type 分发处理
3. 接收二进制帧，累积到音频 buffer
4. 音频接收完毕 → ASR 语音识别 → 发送到 AgentLoop
5. AI 回复 → TTS 语音合成 → 流式发送音频给设备
6. 消费 MessageBus outbound 队列，将回复转发给设备

音频格式约定:
- ESP32 → 服务端: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- 服务端 → ESP32: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
"""
from __future__ import annotations

import asyncio
import json
import time
from typing import Any, Optional

import aiohttp
from aiohttp import web
from loguru import logger

from models.protocol import DeviceMessageType, ServerMessageType, make_server_message
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


class DeviceChannel:
    """ESP32 WebSocket 通信通道，集成 ASR + TTS。"""

    def __init__(
        self,
        bus: MessageBus,
        asr: Optional[ASRService] = None,
        tts: Optional[TTSService] = None,
    ):
        self.bus = bus
        self.asr = asr
        self.tts = tts
        self.ws: web.WebSocketResponse | None = None
        self.connected = False
        self.audio_buffer = bytearray()
        self._outbound_task: asyncio.Task | None = None

    # ── 公共方法 ─────────────────────────────────────────────

    def register_routes(self, app: web.Application) -> None:
        """注册 WebSocket 路由到 aiohttp app。"""
        app.router.add_get("/ws/device", self._handle_ws)

    async def start_outbound_consumer(self) -> None:
        """启动后台任务，从 MessageBus outbound 队列消费消息并发给设备。"""
        self._outbound_task = asyncio.create_task(self._consume_outbound())

    async def stop(self) -> None:
        """停止 outbound 消费任务并关闭连接。"""
        if self._outbound_task and not self._outbound_task.done():
            self._outbound_task.cancel()
            try:
                await self._outbound_task
            except asyncio.CancelledError:
                pass
        if self.ws and not self.ws.closed:
            await self.ws.close()

    # ── WebSocket 连接处理 ───────────────────────────────────

    async def _handle_ws(self, request: web.Request) -> web.WebSocketResponse:
        """处理 WebSocket 连接。"""
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        # 如果已有连接，关闭旧的（单设备模式）
        if self.ws and not self.ws.closed:
            logger.warning("新设备连接，关闭旧连接")
            await self.ws.close()

        self.ws = ws
        self.connected = True
        self.audio_buffer.clear()
        logger.info("设备已连接 ({})", request.remote)

        try:
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    await self._on_text(msg.data)
                elif msg.type == aiohttp.WSMsgType.BINARY:
                    await self._on_binary(msg.data)
                elif msg.type == aiohttp.WSMsgType.ERROR:
                    logger.error("WebSocket 错误: {}", ws.exception())
        except Exception:
            logger.exception("WebSocket 处理异常")
        finally:
            self.connected = False
            self.ws = None
            self.audio_buffer.clear()
            logger.info("设备已断开")

        return ws

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
            await self.bus.publish_inbound(InboundMessage(
                channel=DEVICE_CHANNEL,
                sender_id="esp32",
                chat_id=DEVICE_CHAT_ID,
                content=text,
            ))

        elif msg_type == DeviceMessageType.AUDIO_END:
            await self._on_audio_end()

        elif msg_type == DeviceMessageType.TOUCH_EVENT:
            action = data.get("action", "unknown")
            logger.info("收到触摸事件: {}", action)
            # TODO Phase 5: 触摸事件处理

        elif msg_type == DeviceMessageType.SHAKE_EVENT:
            logger.info("收到摇一摇事件")
            # TODO Phase 5: 摇一摇处理

        elif msg_type == DeviceMessageType.DEVICE_STATUS:
            logger.debug("设备状态: {}", data)
            # TODO Phase 5: 记录电量/WiFi

        else:
            logger.warning("未知消息类型: {}", msg_type)

    async def _on_binary(self, data: bytes) -> None:
        """处理二进制帧（音频数据）。"""
        self.audio_buffer.extend(data)

    async def _on_audio_end(self) -> None:
        """音频接收完毕，触发 ASR 识别 → 发送到 AgentLoop。"""
        audio_size = len(self.audio_buffer)
        logger.info("收到 audio_end, 音频 buffer: {} bytes", audio_size)

        pcm_data = bytes(self.audio_buffer)
        self.audio_buffer.clear()

        if audio_size < MIN_AUDIO_BYTES:
            logger.warning("音频太短 ({} bytes < {}), 忽略", audio_size, MIN_AUDIO_BYTES)
            return

        if not self.asr:
            logger.warning("ASR 服务未初始化，无法识别音频")
            return

        # 通知设备进入 PROCESSING 状态
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": "PROCESSING"}
        ))

        # ASR 识别
        t0 = time.monotonic()
        try:
            text = await self.asr.transcribe(pcm_data)
        except Exception:
            logger.exception("ASR 识别失败")
            await self.send_json(make_server_message(
                ServerMessageType.STATE_CHANGE, {"state": "IDLE"}
            ))
            return

        asr_ms = (time.monotonic() - t0) * 1000
        logger.info("ASR 耗时: {:.0f}ms, 识别结果: '{}'", asr_ms, text[:50] if text else "")

        if not text.strip():
            logger.warning("ASR 识别结果为空，忽略")
            await self.send_json(make_server_message(
                ServerMessageType.STATE_CHANGE, {"state": "IDLE"}
            ))
            return

        # 发送到 AgentLoop
        await self.bus.publish_inbound(InboundMessage(
            channel=DEVICE_CHANNEL,
            sender_id="esp32",
            chat_id=DEVICE_CHAT_ID,
            content=text,
            metadata={"source": "voice", "asr_ms": asr_ms},
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

        # 1. 屏幕显示文字
        await self.send_json(make_server_message(
            ServerMessageType.DISPLAY_UPDATE, {"text": text}
        ))

        # 2. 切换到 SPEAKING 状态
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": "SPEAKING"}
        ))

        # 3. TTS 合成并流式发送
        t0 = time.monotonic()
        try:
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

            tts_ms = (time.monotonic() - t0) * 1000
            duration_s = total_bytes / (16000 * 2)
            logger.info(
                "TTS 发送完成: {:.0f}ms, {} chunks, {} bytes ({:.1f}s 音频)",
                tts_ms, chunk_count, total_bytes, duration_s,
            )

        except Exception:
            logger.exception("TTS 合成/发送失败")

        # 4. 恢复 IDLE 状态
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": "IDLE"}
        ))

    # ── Outbound 消费 ────────────────────────────────────────

    async def _consume_outbound(self) -> None:
        """从 MessageBus outbound 队列消费消息，转发给设备。"""
        logger.info("DeviceChannel outbound 消费者已启动")
        while True:
            try:
                out_msg: OutboundMessage = await self.bus.consume_outbound()

                # 只处理发给 device channel 的消息
                if out_msg.channel != DEVICE_CHANNEL:
                    logger.debug("忽略非 device 消息 (channel={})", out_msg.channel)
                    continue

                # 跳过 progress 消息（工具调用中间状态）
                if out_msg.metadata.get("_progress"):
                    continue

                if not out_msg.content:
                    continue

                logger.info("发送回复给设备: '{}'", out_msg.content[:50])

                # 判断是否需要语音回复
                # 如果原始消息来自语音输入，或者 TTS 可用，则发语音
                source = out_msg.metadata.get("source", "")
                if self.tts and source == "voice":
                    await self._send_voice_reply(out_msg.content)
                else:
                    # 纯文字回复 (来自 test_client 文字输入)
                    await self.send_text_reply(out_msg.content)

            except asyncio.CancelledError:
                logger.info("DeviceChannel outbound 消费者已停止")
                break
            except Exception:
                logger.exception("Outbound 消费异常")
                await asyncio.sleep(1)
