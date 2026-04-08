from __future__ import annotations

import sys
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from aiohttp import web
from loguru import logger

from config import (
    get_provider_timeout_seconds,
    SERVER_DIR,
    WORKSPACE_DIR,
    generate_nanobot_config,
    get_server_config,
    load_yaml_config,
    validate_config,
)
from nanobot.agent.loop import AgentLoop
from nanobot.bus.queue import MessageBus
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from services.app_runtime import AppRuntimeService

if TYPE_CHECKING:
    from channels.device_channel import DeviceChannel
    from nanobot.channels.whatsapp import WhatsAppChannel
    from services.desktop_voice_service import DesktopVoiceService


VERSION = "0.6.0"


class ConfigValidationError(Exception):
    """Raised when the runtime configuration is invalid."""

    def __init__(self, errors: list[str]):
        super().__init__("\n".join(errors))
        self.errors = errors


@dataclass
class RuntimeComponents:
    """Runtime objects created during server bootstrap."""

    config: dict[str, Any]
    server_config: dict[str, Any]
    bus: MessageBus
    agent: AgentLoop
    app: web.Application
    device_channel: DeviceChannel
    desktop_voice_service: DesktopVoiceService
    whatsapp_channel: WhatsAppChannel | None
    asr_config: dict[str, Any]
    tts_config: dict[str, Any]
    device_config: dict[str, Any]


def setup_logging() -> None:
    """配置 loguru: 控制台 INFO + 文件 DEBUG。"""
    logger.remove()
    logger.add(
        sys.stderr,
        level="INFO",
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>",
    )
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


def load_runtime_config() -> tuple[dict[str, Any], dict[str, Any]]:
    """Load, validate, and normalize runtime config."""
    cfg = load_yaml_config()
    errors = validate_config(cfg)
    if errors:
        raise ConfigValidationError(errors)
    generate_nanobot_config(cfg)
    return cfg, get_server_config(cfg)


def create_agent(cfg: dict[str, Any]) -> tuple[MessageBus, AgentLoop]:
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
        request_timeout_seconds=get_provider_timeout_seconds(cfg),
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
    """发送一条测试消息验证 AgentLoop 能调用模型。"""
    logger.info("CLI 测试: 发送 '你好' ...")
    reply = await agent.process_direct("你好", session_key="test:cli")
    logger.info("AI 回复: {}", reply)


def create_device_channel(cfg: dict[str, Any], bus: MessageBus) -> tuple[DeviceChannel, dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Create ASR/TTS services and device channel."""
    from channels.device_channel import DeviceChannel
    from services.asr import ASRService
    from services.tts import TTSService

    asr_cfg = cfg.get("asr", {})
    tts_cfg = cfg.get("tts", {})
    device_cfg = cfg.get("device", {})

    asr_service = ASRService(
        model=asr_cfg.get("model", "FunAudioLLM/SenseVoiceSmall"),
        language=asr_cfg.get("language", "auto"),
        device=asr_cfg.get("device", "cpu"),
        use_vad=asr_cfg.get("use_vad", True),
        use_itn=asr_cfg.get("use_itn", True),
    )
    tts_service = TTSService(
        voice=tts_cfg.get("voice", "zh-CN-XiaoxiaoNeural"),
    )
    device_channel = DeviceChannel(
        bus,
        asr=asr_service,
        tts=tts_service,
        auth_token=device_cfg.get("auth_token", ""),
    )
    device_channel.set_weather_config(cfg.get("weather", {}))
    return device_channel, asr_cfg, tts_cfg, device_cfg


def create_whatsapp_channel(cfg: dict[str, Any], bus: MessageBus) -> WhatsAppChannel | None:
    """Create WhatsApp channel when enabled."""
    wa_cfg = cfg.get("whatsapp", {})
    if not wa_cfg.get("enabled", False):
        return None

    from nanobot.channels.whatsapp import WhatsAppChannel
    from nanobot.config.schema import WhatsAppConfig

    whatsapp_config = WhatsAppConfig(
        enabled=True,
        bridge_url=wa_cfg.get("bridge_url", "ws://localhost:3001"),
        bridge_token=wa_cfg.get("bridge_token", ""),
        self_only=wa_cfg.get("self_only", False),
        allow_from=wa_cfg.get("allow_from", ["*"]),
    )
    return WhatsAppChannel(whatsapp_config, bus)


def create_http_app(
    cfg: dict[str, Any],
    bus: MessageBus,
    agent: AgentLoop,
    device_channel: DeviceChannel,
    desktop_voice_service: DesktopVoiceService,
    *,
    start_time: float,
) -> web.Application:
    """Create the aiohttp application and register routes."""

    app_runtime = AppRuntimeService(
        cfg,
        bus=bus,
        sessions=agent.sessions,
        device_channel=device_channel,
        desktop_voice_service=desktop_voice_service,
        version=VERSION,
        start_time=start_time,
    )
    bus.add_observer(app_runtime)
    agent.task_observer = app_runtime
    device_channel.set_event_observer(app_runtime)
    device_channel.set_desktop_voice_bridge(desktop_voice_service)
    desktop_voice_service.set_event_observer(app_runtime)

    async def health_handler(request: web.Request) -> web.Response:
        nanobot_cfg = cfg.get("nanobot", {})
        uptime = time.monotonic() - start_time
        return web.json_response({
            "status": "ok",
            "version": VERSION,
            "uptime_s": round(uptime),
            "model": nanobot_cfg.get("model", "unknown"),
            "provider": nanobot_cfg.get("provider", "unknown"),
            "asr_model": cfg.get("asr", {}).get("model", "base"),
            "tts_voice": cfg.get("tts", {}).get("voice", "zh-CN-XiaoxiaoNeural"),
            "device_connected": device_channel.connected,
            "device_state": device_channel.state.value,
        })

    async def device_info_handler(request: web.Request) -> web.Response:
        return web.json_response(device_channel.get_snapshot())

    app = web.Application()
    app.router.add_get("/api/health", health_handler)
    app.router.add_get("/api/device", device_info_handler)
    device_channel.register_routes(app)
    desktop_voice_service.register_routes(app)
    app_runtime.register_routes(app)

    app["bus"] = bus
    app["agent"] = agent
    app["device_channel"] = device_channel
    app["desktop_voice_service"] = desktop_voice_service
    app["config"] = cfg
    app["app_runtime"] = app_runtime
    return app


def build_runtime(start_time: float) -> RuntimeComponents:
    """Build the full server runtime without starting background tasks."""
    from services.desktop_voice_service import DesktopVoiceService

    cfg, server_cfg = load_runtime_config()
    bus, agent = create_agent(cfg)
    device_channel, asr_cfg, tts_cfg, device_cfg = create_device_channel(cfg, bus)
    desktop_voice_service = DesktopVoiceService(
        bus=bus,
        asr=device_channel.asr,
        device_channel=device_channel,
        auth_token=cfg.get("desktop_voice", {}).get("auth_token", "") or cfg.get("app", {}).get("auth_token", ""),
        default_app_session_id=cfg.get("app", {}).get("default_session_id", "app:main"),
    )
    whatsapp_channel = create_whatsapp_channel(cfg, bus)
    app = create_http_app(
        cfg,
        bus,
        agent,
        device_channel,
        desktop_voice_service,
        start_time=start_time,
    )
    return RuntimeComponents(
        config=cfg,
        server_config=server_cfg,
        bus=bus,
        agent=agent,
        app=app,
        device_channel=device_channel,
        desktop_voice_service=desktop_voice_service,
        whatsapp_channel=whatsapp_channel,
        asr_config=asr_cfg,
        tts_config=tts_cfg,
        device_config=device_cfg,
    )


def log_startup_summary(runtime: RuntimeComponents) -> None:
    """Log current server startup summary."""
    nanobot_cfg = runtime.config.get("nanobot", {})
    logger.info(
        "服务已启动: http://{}:{}",
        runtime.server_config["host"],
        runtime.server_config["port"],
    )
    logger.info("  模型: {} ({})", nanobot_cfg.get("model"), nanobot_cfg.get("provider"))
    logger.info(
        "  ASR: {} | TTS: {}",
        runtime.asr_config.get("model", "base"),
        runtime.tts_config.get("voice"),
    )
    logger.info(
        "  Device Auth: {}",
        "enabled" if runtime.device_config.get("auth_token") else "disabled",
    )
    logger.info(
        "  App Auth: {}",
        "enabled" if runtime.config.get("app", {}).get("auth_token") else "disabled",
    )
    logger.info("  健康检查: http://localhost:{}/api/health", runtime.server_config["port"])
    logger.info("  App Bootstrap: http://localhost:{}/api/app/v1/bootstrap", runtime.server_config["port"])
    logger.info("  App Events: ws://localhost:{}/ws/app/v1/events", runtime.server_config["port"])
    logger.info("  WebSocket: ws://localhost:{}/ws/device", runtime.server_config["port"])
