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
import json
import time
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

# 屏幕显示参数 (1.69寸 ST7789, 240×280)
DISPLAY_MAX_CHARS = 120  # 中文约每行10字 × 12行

# WebSocket 心跳间隔 (秒)
HEARTBEAT_INTERVAL = 30


class DeviceChannel:
    """ESP32 WebSocket 通信通道，集成 ASR + TTS + 状态机。"""

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
        self._heartbeat_task: asyncio.Task | None = None

        # ── 状态机 (Phase 5) ────────────────────────────
        self.state = DeviceState.IDLE

        # ── 设备信息 (Phase 5) ───────────────────────────
        self.device_info: dict[str, Any] = {
            "battery": -1,      # 电量百分比, -1 = 未知
            "wifi_rssi": 0,     # WiFi 信号强度 (dBm)
            "charging": False,  # 是否充电中
        }

        # ── 连接统计 (Phase 6) ───────────────────────────
        self._connect_time: float = 0
        self._reconnect_count: int = 0

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

        # 通知设备状态变化
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": new_state.value}
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
        # 停止心跳
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

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

    async def _handle_ws(self, request: web.Request) -> web.WebSocketResponse:
        """处理 WebSocket 连接（含心跳保活和重连计数）。"""
        ws = web.WebSocketResponse(heartbeat=HEARTBEAT_INTERVAL)
        await ws.prepare(request)

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

        self.ws = ws
        self.connected = True
        self.audio_buffer.clear()
        self.state = DeviceState.IDLE
        self._connect_time = time.monotonic()

        # 启动心跳
        self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())

        # 发送初始状态（重连后设备恢复到 IDLE）
        await self.send_json(make_server_message(
            ServerMessageType.STATE_CHANGE, {"state": DeviceState.IDLE.value}
        ))

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
            # 断线清理
            self.connected = False
            self.ws = None
            self.audio_buffer.clear()
            self.state = DeviceState.IDLE
            if self._heartbeat_task and not self._heartbeat_task.done():
                self._heartbeat_task.cancel()
            uptime = time.monotonic() - self._connect_time
            logger.info("设备已断开 (在线 {:.0f}s)", uptime)

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
            await self._on_touch_event(data)

        elif msg_type == DeviceMessageType.SHAKE_EVENT:
            await self._on_shake_event(data)

        elif msg_type == DeviceMessageType.DEVICE_STATUS:
            self._on_device_status(data)

        else:
            logger.warning("未知消息类型: {}", msg_type)

    async def _on_binary(self, data: bytes) -> None:
        """处理二进制帧（音频数据）。

        收到第一帧时切换到 LISTENING 状态。
        超过 MAX_AUDIO_BYTES 时自动截断。
        """
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

    async def _on_audio_end(self) -> None:
        """音频接收完毕，触发 ASR 识别 → 发送到 AgentLoop。"""
        audio_size = len(self.audio_buffer)
        logger.info("收到 audio_end, 音频 buffer: {} bytes", audio_size)

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

        # 切换到 PROCESSING 状态
        await self._set_state(DeviceState.PROCESSING)

        # ASR 识别
        t0 = time.monotonic()
        try:
            text = await self.asr.transcribe(pcm_data)
        except Exception:
            logger.exception("ASR 识别失败")
            await self._send_display_update("语音识别失败，请重试")
            await self._set_state(DeviceState.IDLE)
            return

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

        # 发送到 AgentLoop
        await self.bus.publish_inbound(InboundMessage(
            channel=DEVICE_CHANNEL,
            sender_id="esp32",
            chat_id=DEVICE_CHAT_ID,
            content=text,
            metadata={"source": "voice", "asr_ms": asr_ms},
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
            elif self.state == DeviceState.LISTENING:
                # 结束录音：触发 audio_end 处理
                await self._on_audio_end()
            elif self.state == DeviceState.SPEAKING:
                # 播放中单击 → 打断，回到 IDLE
                await self._set_state(DeviceState.IDLE)

        elif action == "double":
            # 双击：无论当前状态，打断并回到 IDLE
            if self.state != DeviceState.IDLE:
                self.audio_buffer.clear()
                await self._set_state(DeviceState.IDLE)
                await self._send_display_update("已取消")

        elif action == "long_press":
            # 长按开始：进入 LISTENING
            if self.state == DeviceState.IDLE:
                await self._set_state(DeviceState.LISTENING)

        elif action == "long_release":
            # 长按松开：结束录音
            if self.state == DeviceState.LISTENING:
                await self._on_audio_end()

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

    def _on_device_status(self, data: dict) -> None:
        """记录设备状态（电量/WiFi/充电）。"""
        if "battery" in data:
            self.device_info["battery"] = data["battery"]
        if "wifi_rssi" in data:
            self.device_info["wifi_rssi"] = data["wifi_rssi"]
        if "charging" in data:
            self.device_info["charging"] = data["charging"]
        logger.info(
            "设备状态更新: 电量={}%, WiFi={}dBm, 充电={}",
            self.device_info["battery"],
            self.device_info["wifi_rssi"],
            self.device_info["charging"],
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

        # 1. 屏幕显示文字（带截断）
        await self._send_display_update(text)

        # 2. 切换到 SPEAKING 状态
        await self._set_state(DeviceState.SPEAKING)

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
                "[TTS {:.1f}s] {} chunks, {} bytes ({:.1f}s 音频)",
                tts_ms / 1000, chunk_count, total_bytes, duration_s,
            )

        except Exception:
            logger.exception("TTS 合成/发送失败，降级为文字回复")
            # TTS 失败降级: 发送文字回复 (Phase 6.2)
            await self.send_text_reply(text)

        # 4. 恢复 IDLE 状态
        await self._set_state(DeviceState.IDLE)

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
