"""
AI-Bot 服务端入口
Phase 1-4: aiohttp 服务 + AgentLoop + DeviceChannel WebSocket + 语音交互
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
)
from channels.device_channel import DeviceChannel
from services.asr import ASRService
from services.tts import TTSService
from nanobot.bus.queue import MessageBus
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from nanobot.agent.loop import AgentLoop


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

    # 在 app 上下文中保存引用
    app["bus"] = bus
    app["agent"] = agent
    app["device_channel"] = device_channel

    # 启动 AgentLoop 后台任务
    agent_task = asyncio.create_task(agent.run())

    # 启动 DeviceChannel outbound 消费者
    await device_channel.start_outbound_consumer()

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
        try:
            await agent_task
        except asyncio.CancelledError:
            pass
        await device_channel.stop()
        await agent.close_mcp()
        await runner.cleanup()
        logger.info("服务已关闭")


if __name__ == "__main__":
    asyncio.run(main())
