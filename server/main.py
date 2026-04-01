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

from loguru import logger

from bootstrap import (
    ConfigValidationError,
    VERSION,
    build_runtime,
    log_startup_summary,
    run_cli_test,
    setup_logging,
)
from services.outbound_router import UnifiedOutboundRouter

_start_time: float = 0


async def main() -> None:
    global _start_time
    _start_time = time.monotonic()

    # 配置日志 (Phase 6.3)
    setup_logging()
    logger.info("AI-Bot 服务端 v{}", VERSION)

    try:
        runtime = build_runtime(_start_time)
    except ConfigValidationError as exc:
        for err in exc.errors:
            logger.error("配置错误: {}", err)
        sys.exit(1)

    # CLI 测试模式
    if "--test" in sys.argv:
        await run_cli_test(runtime.agent)
        return

    whatsapp_task: asyncio.Task | None = None
    if runtime.whatsapp_channel:
        wa_cfg = runtime.config.get("whatsapp", {})
        whatsapp_task = asyncio.create_task(runtime.whatsapp_channel.start())
        logger.info("WhatsApp channel 已启用，bridge: {}", wa_cfg.get("bridge_url"))

    # 启动 AgentLoop 后台任务
    agent_task = asyncio.create_task(runtime.agent.run())

    outbound_router = UnifiedOutboundRouter(
        runtime.bus,
        runtime.device_channel,
        runtime.whatsapp_channel,
    )
    outbound_task = asyncio.create_task(outbound_router.run())

    from aiohttp import web

    runner = web.AppRunner(runtime.app)
    await runner.setup()
    site = web.TCPSite(
        runner,
        runtime.server_config["host"],
        runtime.server_config["port"],
    )
    await site.start()

    log_startup_summary(runtime)

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
    await runtime.device_channel.stop()

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
    if runtime.whatsapp_channel:
        await runtime.whatsapp_channel.stop()
        if whatsapp_task:
            whatsapp_task.cancel()
            try:
                await whatsapp_task
            except asyncio.CancelledError:
                pass
    await runtime.agent.close_mcp()
    await runner.cleanup()

    uptime = time.monotonic() - _start_time
    logger.info("服务已关闭 (运行 {:.0f}s)", uptime)


if __name__ == "__main__":
    asyncio.run(main())
