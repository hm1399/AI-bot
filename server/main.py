"""
AI-Bot 服务端入口
Phase 1-4: aiohttp 服务 + AgentLoop + DeviceChannel WebSocket + 语音交互
Demo: 集成 WhatsApp Channel，AI 回复同时发送到设备屏幕和 WhatsApp
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from aiohttp import web
from loguru import logger

from config import (
    load_yaml_config,
    generate_nanobot_config,
    get_server_config,
    WORKSPACE_DIR,
    NANOBOT_CONFIG_JSON,
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


# ── aiohttp 路由 ──────────────────────────────────────────────

async def health_handler(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


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
    # 加载配置
    cfg = load_yaml_config()
    generate_nanobot_config(cfg)
    server_cfg = get_server_config(cfg)

    # 检查 API Key
    api_key = cfg.get("nanobot", {}).get("api_key", "")
    if not api_key:
        provider = cfg.get("nanobot", {}).get("provider", "anthropic")
        logger.error("API Key 未设置！请在 config.yaml 的 nanobot.api_key 或对应环境变量中配置（provider: {}）。", provider)
        sys.exit(1)

    # 创建 Agent
    bus, agent = create_agent(cfg)

    # CLI 测试模式
    if "--test" in sys.argv:
        await run_cli_test(agent)
        return

    # 启动 aiohttp 服务
    app = web.Application()
    app.router.add_get("/api/health", health_handler)

    # 初始化 ASR / TTS 服务 (Phase 4)
    asr_cfg = cfg.get("asr", {})
    tts_cfg = cfg.get("tts", {})
    asr_service = ASRService(
        model=asr_cfg.get("model", "base"),
        language=asr_cfg.get("language", "zh"),
    )
    tts_service = TTSService(
        voice=tts_cfg.get("voice", "zh-CN-XiaoxiaoNeural"),
    )

    # 初始化 DeviceChannel (Phase 3 + 4)
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

    # 启动 AgentLoop 后台任务
    agent_task = asyncio.create_task(agent.run())

    # 启动统一 outbound 消费者（替代 DeviceChannel 单独的消费者）
    outbound_task = asyncio.create_task(
        unified_outbound_consumer(bus, device_channel, whatsapp_channel)
    )

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, server_cfg["host"], server_cfg["port"])
    await site.start()
    logger.info("服务已启动: http://{}:{}", server_cfg["host"], server_cfg["port"])
    logger.info("健康检查: http://localhost:{}/api/health", server_cfg["port"])
    logger.info("WebSocket: ws://localhost:{}/ws/device", server_cfg["port"])

    try:
        await asyncio.Event().wait()  # 永远运行
    except (KeyboardInterrupt, asyncio.CancelledError):
        logger.info("正在关闭服务...")
    finally:
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
        await device_channel.stop()
        await agent.close_mcp()
        await runner.cleanup()
        logger.info("服务已关闭")


if __name__ == "__main__":
    asyncio.run(main())
