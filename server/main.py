"""
AI-Bot 服务端入口
Phase 1-6: aiohttp 服务 + AgentLoop + DeviceChannel + 语音交互 + 状态机 + 稳定性
Demo: 集成 WhatsApp Channel，AI 回复同时发送到设备屏幕和 WhatsApp
"""
from __future__ import annotations

import asyncio
import signal
import sys
import time
from pathlib import Path

from aiohttp import web
from loguru import logger

from config import (
    load_yaml_config,
    generate_nanobot_config,
    get_server_config,
    validate_config,
    WORKSPACE_DIR,
    NANOBOT_CONFIG_JSON,
    SERVER_DIR,
)
from channels.device_channel import DeviceChannel, DEVICE_CHANNEL
from services.asr import ASRService
from services.tts import TTSService
from nanobot.bus.queue import MessageBus
from nanobot.bus.events import OutboundMessage
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from nanobot.agent.loop import AgentLoop
from nanobot.channels.whatsapp import WhatsAppChannel
from nanobot.config.schema import WhatsAppConfig

VERSION = "0.6.0"
_start_time: float = 0


# ── 日志配置 (Phase 6.3) ──────────────────────────────────────

def setup_logging() -> None:
    """配置 loguru: 控制台 INFO + 文件 DEBUG。"""
    # 移除默认 handler
    logger.remove()
    # 控制台: INFO 级别，简洁格式
    logger.add(
        sys.stderr,
        level="INFO",
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>",
    )
    # 文件: DEBUG 级别，详细格式，按天轮转，保留 7 天
    log_dir = SERVER_DIR / "logs"
    log_dir.mkdir(exist_ok=True)
    logger.add(
        str(log_dir / "server_{time:YYYY-MM-DD}.log"),
        level="DEBUG",
        format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {level: <8} | {name}:{function}:{line} - {message}",
        rotation="00:00",
        retention="7 days",
        encoding="utf-8",
    )


# ── aiohttp 路由 ──────────────────────────────────────────────

async def health_handler(request: web.Request) -> web.Response:
    """增强版健康检查: 返回版本、模型、ASR/TTS 状态、设备在线状态。"""
    dc: DeviceChannel = request.app["device_channel"]
    cfg: dict = request.app["config"]
    nanobot_cfg = cfg.get("nanobot", {})

    uptime = time.monotonic() - _start_time
    return web.json_response({
        "status": "ok",
        "version": VERSION,
        "uptime_s": round(uptime),
        "model": nanobot_cfg.get("model", "unknown"),
        "provider": nanobot_cfg.get("provider", "unknown"),
        "asr_model": cfg.get("asr", {}).get("model", "base"),
        "tts_voice": cfg.get("tts", {}).get("voice", "zh-CN-XiaoxiaoNeural"),
        "device_connected": dc.connected,
        "device_state": dc.state.value,
    })


async def device_info_handler(request: web.Request) -> web.Response:
    """查询设备状态: 连接状态 + 电量 + WiFi + 当前状态 + 重连次数。"""
    dc: DeviceChannel = request.app["device_channel"]
    return web.json_response({
        "connected": dc.connected,
        "state": dc.state.value,
        "battery": dc.device_info["battery"],
        "wifi_rssi": dc.device_info["wifi_rssi"],
        "charging": dc.device_info["charging"],
        "reconnect_count": dc._reconnect_count,
    })


# ── 初始化 ────────────────────────────────────────────────────

def create_agent(cfg: dict) -> tuple[MessageBus, AgentLoop]:
    """根据配置创建 MessageBus 和 AgentLoop。"""
    nanobot_cfg = cfg.get("nanobot", {})
    api_key = nanobot_cfg.get("api_key", "")
    model = nanobot_cfg.get("model", "claude-sonnet-4-6")
    provider_name = nanobot_cfg.get("provider", "anthropic")

    bus = MessageBus()
    provider = LiteLLMProvider(
        api_key=api_key,
        default_model=model,
        provider_name=provider_name,
    )
    session_manager = SessionManager(WORKSPACE_DIR)

    agent = AgentLoop(
        bus=bus,
        provider=provider,
        workspace=WORKSPACE_DIR,
        model=model,
        max_iterations=nanobot_cfg.get("max_tool_iterations", 20),
        temperature=nanobot_cfg.get("temperature", 0.1),
        max_tokens=nanobot_cfg.get("max_tokens", 8192),
        memory_window=nanobot_cfg.get("memory_window", 50),
        session_manager=session_manager,
    )
    return bus, agent


async def run_cli_test(agent: AgentLoop) -> None:
    """发送一条测试消息验证 AgentLoop 能调用 Claude API。"""
    logger.info("CLI 测试: 发送 '你好' ...")
    reply = await agent.process_direct("你好", session_key="test:cli")
    logger.info("AI 回复: {}", reply)


async def unified_outbound_consumer(
    bus: MessageBus,
    device_channel: DeviceChannel,
    whatsapp_channel: WhatsAppChannel | None,
) -> None:
    """统一的 outbound 消费者：路由回复到设备和 WhatsApp。

    解决 DeviceChannel 和 WhatsApp Channel 竞争同一个 outbound 队列的问题。
    所有来自设备的消息回复同时发送到设备屏幕和 WhatsApp。
    """
    # WhatsApp 默认发送目标（demo 模式发给最近一个联系人）
    whatsapp_last_chat_id: str | None = None

    # 监听 WhatsApp 来源消息以记录 chat_id
    if whatsapp_channel:
        _orig_handle = whatsapp_channel._handle_bridge_message

        async def _track_chat_id(raw: str):
            nonlocal whatsapp_last_chat_id
            import json as _json
            try:
                data = _json.loads(raw)
                if data.get("type") == "message":
                    sender = data.get("sender", "")
                    if sender:
                        whatsapp_last_chat_id = sender
            except Exception:
                pass
            await _orig_handle(raw)

        whatsapp_channel._handle_bridge_message = _track_chat_id

    logger.info("统一 outbound 消费者已启动")
    while True:
        try:
            out_msg: OutboundMessage = await bus.consume_outbound()

            # 跳过 progress 消息
            if out_msg.metadata.get("_progress"):
                continue
            if not out_msg.content:
                continue

            # 发送到设备（如果是 device channel 的消息）
            if out_msg.channel == DEVICE_CHANNEL:
                logger.info("发送回复给设备: '{}'", out_msg.content[:50])
                source = out_msg.metadata.get("source", "")
                if device_channel.tts and source == "voice":
                    await device_channel._send_voice_reply(out_msg.content)
                else:
                    await device_channel.send_text_reply(out_msg.content)

                # 同时转发到 WhatsApp（demo 模式）
                if whatsapp_channel and whatsapp_last_chat_id:
                    wa_msg = OutboundMessage(
                        channel="whatsapp",
                        chat_id=whatsapp_last_chat_id,
                        content=out_msg.content,
                    )
                    await whatsapp_channel.send(wa_msg)
                    logger.info("回复已转发到 WhatsApp")

            # 发送到 WhatsApp（来自 WhatsApp 的消息）
            elif out_msg.channel == "whatsapp":
                if whatsapp_channel:
                    await whatsapp_channel.send(out_msg)
                    logger.info("发送 WhatsApp 回复: '{}'", out_msg.content[:50])

            else:
                logger.debug("忽略未知 channel 消息: {}", out_msg.channel)

        except asyncio.CancelledError:
            logger.info("统一 outbound 消费者已停止")
            break
        except Exception:
            logger.exception("Outbound 消费异常")
            await asyncio.sleep(1)


async def main() -> None:
    global _start_time
    _start_time = time.monotonic()

    # 配置日志 (Phase 6.3)
    setup_logging()
    logger.info("AI-Bot 服务端 v{}", VERSION)

    # 加载配置
    cfg = load_yaml_config()

    # 配置验证 (Phase 6.4)
    errors = validate_config(cfg)
    if errors:
        for err in errors:
            logger.error("配置错误: {}", err)
        sys.exit(1)

    generate_nanobot_config(cfg)
    server_cfg = get_server_config(cfg)

    # 创建 Agent
    bus, agent = create_agent(cfg)

    # CLI 测试模式
    if "--test" in sys.argv:
        await run_cli_test(agent)
        return

    # 启动 aiohttp 服务
    app = web.Application()
    app.router.add_get("/api/health", health_handler)
    app.router.add_get("/api/device", device_info_handler)

    # 初始化 ASR / TTS 服务
    asr_cfg = cfg.get("asr", {})
    tts_cfg = cfg.get("tts", {})
    asr_service = ASRService(
        model=asr_cfg.get("model", "base"),
        language=asr_cfg.get("language", "zh"),
    )
    tts_service = TTSService(
        voice=tts_cfg.get("voice", "zh-CN-XiaoxiaoNeural"),
    )

    # 初始化 DeviceChannel
    device_channel = DeviceChannel(bus, asr=asr_service, tts=tts_service)
    device_channel.register_routes(app)

    # 初始化 WhatsApp Channel
    wa_cfg = cfg.get("whatsapp", {})
    whatsapp_channel: WhatsAppChannel | None = None
    whatsapp_task: asyncio.Task | None = None

    if wa_cfg.get("enabled", False):
        whatsapp_config = WhatsAppConfig(
            enabled=True,
            bridge_url=wa_cfg.get("bridge_url", "ws://localhost:3001"),
            bridge_token=wa_cfg.get("bridge_token", ""),
            allow_from=wa_cfg.get("allow_from", ["*"]),
        )
        whatsapp_channel = WhatsAppChannel(whatsapp_config, bus)
        whatsapp_task = asyncio.create_task(whatsapp_channel.start())
        logger.info("WhatsApp channel 已启用，bridge: {}", wa_cfg.get("bridge_url"))

    # 在 app 上下文中保存引用
    app["bus"] = bus
    app["agent"] = agent
    app["device_channel"] = device_channel
    app["config"] = cfg

    # 启动 AgentLoop 后台任务
    agent_task = asyncio.create_task(agent.run())

    # 启动统一 outbound 消费者
    outbound_task = asyncio.create_task(
        unified_outbound_consumer(bus, device_channel, whatsapp_channel)
    )

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, server_cfg["host"], server_cfg["port"])
    await site.start()

    nanobot_cfg = cfg.get("nanobot", {})
    logger.info("服务已启动: http://{}:{}", server_cfg["host"], server_cfg["port"])
    logger.info("  模型: {} ({})", nanobot_cfg.get("model"), nanobot_cfg.get("provider"))
    logger.info("  ASR: {} | TTS: {}", asr_cfg.get("model", "base"), tts_cfg.get("voice"))
    logger.info("  健康检查: http://localhost:{}/api/health", server_cfg["port"])
    logger.info("  WebSocket: ws://localhost:{}/ws/device", server_cfg["port"])

    # 优雅关闭 (Phase 6.1)
    shutdown_event = asyncio.Event()

    def _signal_handler():
        logger.info("收到关闭信号，正在优雅关闭...")
        shutdown_event.set()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _signal_handler)

    await shutdown_event.wait()

    # 关闭顺序: WebSocket → outbound → agent → WhatsApp → HTTP
    logger.info("正在关闭服务...")
    await device_channel.stop()

    agent_task.cancel()
    outbound_task.cancel()
    try:
        await agent_task
    except asyncio.CancelledError:
        pass
    try:
        await outbound_task
    except asyncio.CancelledError:
        pass
    if whatsapp_channel:
        await whatsapp_channel.stop()
        if whatsapp_task:
            whatsapp_task.cancel()
            try:
                await whatsapp_task
            except asyncio.CancelledError:
                pass
    await agent.close_mcp()
    await runner.cleanup()

    uptime = time.monotonic() - _start_time
    logger.info("服务已关闭 (运行 {:.0f}s)", uptime)


if __name__ == "__main__":
    asyncio.run(main())
