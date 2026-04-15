from __future__ import annotations

import sys
import time
import inspect
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any

from aiohttp import web
from loguru import logger

from config import (
    get_cron_config,
    get_provider_timeout_seconds,
    SERVER_DIR,
    WORKSPACE_DIR,
    generate_nanobot_config,
    get_server_config,
    get_tools_config,
    load_yaml_config,
    validate_config,
)
from nanobot.agent.loop import AgentLoop
from nanobot.bus.queue import MessageBus
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from services.app_runtime import AppRuntimeService
from services.computer_control import ComputerControlService

if TYPE_CHECKING:
    from channels.device_channel import DeviceChannel
    from nanobot.channels.whatsapp import WhatsAppChannel
    from nanobot.agent.tools.planning import PlanningBackend
    from services.desktop_voice_service import DesktopVoiceService


VERSION = "0.6.0"
_CORS_ALLOW_HEADERS = "Authorization, Content-Type, X-App-Token"
_CORS_ALLOW_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
_PLANNING_PASSTHROUGH_FIELDS = (
    "bundle_id",
    "created_via",
    "source_channel",
    "source_message_id",
    "source_session_id",
    "interaction_surface",
    "capture_source",
    "voice_path",
    "planning_surface",
    "owner_kind",
    "delivery_mode",
    "linked_task_id",
    "linked_event_id",
    "linked_reminder_id",
)


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
    agent_runtime: "ResolvedAgentRuntimeOptions"
    bus: MessageBus
    agent: AgentLoop
    app: web.Application
    device_channel: DeviceChannel
    desktop_voice_service: DesktopVoiceService
    whatsapp_channel: WhatsAppChannel | None
    asr_config: dict[str, Any]
    tts_config: dict[str, Any]
    device_config: dict[str, Any]


@dataclass
class ResolvedAgentRuntimeOptions:
    """Effective tool/runtime configuration wired into AgentLoop."""

    brave_api_key: str
    web_proxy: str | None
    exec_config: Any
    restrict_to_workspace: bool
    mcp_servers: dict[str, Any]
    cron_enabled: bool
    cron_store_path: Path | None
    cron_service: Any | None


class AppPlanningBackend:
    """Default planning facade used by AgentLoop when no shared runtime is injected."""

    def __init__(
        self,
        resources: Any,
        reminder_scheduler: Any | None = None,
        *,
        runtime_service: Any | None = None,
    ) -> None:
        self.resources = resources
        self.reminder_scheduler = reminder_scheduler
        self.runtime_service = runtime_service

    @staticmethod
    def _merge_passthrough_fields(
        resource: dict[str, Any],
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        merged = dict(resource)
        for field in _PLANNING_PASSTHROUGH_FIELDS:
            incoming = payload.get(field)
            if incoming is None:
                continue
            if merged.get(field) in {None, ""}:
                merged[field] = incoming
        return merged

    async def _emit(self, event_type: str, payload: dict[str, Any]) -> None:
        if self.runtime_service is None:
            return
        await self.runtime_service.refresh_planning_state()
        await self.runtime_service._broadcast_event(  # noqa: SLF001
            event_type,
            payload=payload,
            scope="global",
        )

    async def list_tasks(
        self,
        *,
        completed: bool | None = None,
        limit: int | None = None,
    ) -> dict[str, Any]:
        return self.resources.list_tasks(completed=completed, limit=limit)

    async def create_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._merge_passthrough_fields(self.resources.create_task(payload), payload)
        await self._emit("task.created", {"task": task})
        return task

    async def update_task(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        task = self.resources.update_task(task_id, payload)
        await self._emit("task.updated", {"task": task})
        return task

    async def list_events(self, *, limit: int | None = None) -> dict[str, Any]:
        return self.resources.list_events(limit=limit)

    async def create_event(self, payload: dict[str, Any]) -> dict[str, Any]:
        event = self._merge_passthrough_fields(self.resources.create_event(payload), payload)
        await self._emit("event.created", {"event": event})
        return event

    async def update_event(self, event_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        event = self.resources.update_event(event_id, payload)
        await self._emit("event.updated", {"event": event})
        return event

    async def create_reminder(self, payload: dict[str, Any]) -> dict[str, Any]:
        reminder = self._merge_passthrough_fields(self.resources.create_reminder(payload), payload)
        if self.reminder_scheduler is None:
            await self._emit("reminder.created", {"reminder": reminder})
            return reminder
        reminder = (
            await self.reminder_scheduler.sync_reminder(reminder["reminder_id"])
            or reminder
        )
        reminder = self._merge_passthrough_fields(reminder, payload)
        await self._emit("reminder.created", {"reminder": reminder})
        return reminder

    async def update_reminder(self, reminder_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        reminder = self.resources.update_reminder(reminder_id, payload)
        if self.reminder_scheduler is None:
            await self._emit("reminder.updated", {"reminder": reminder})
            return reminder
        reminder = await self.reminder_scheduler.sync_reminder(reminder["reminder_id"]) or reminder
        await self._emit("reminder.updated", {"reminder": reminder})
        return reminder

    async def snooze_reminder(
        self,
        reminder_id: str,
        *,
        snoozed_until: str | None = None,
        delay_minutes: int = 10,
    ) -> dict[str, Any]:
        if self.reminder_scheduler is None:
            reminder = self.resources.update_reminder(
                reminder_id,
                {
                    "enabled": True,
                    "snoozed_until": snoozed_until,
                    "next_trigger_at": snoozed_until,
                    "status": "snoozed",
                },
            )
        else:
            reminder = await self.reminder_scheduler.snooze_reminder(
                reminder_id,
                snoozed_until=snoozed_until,
                delay_minutes=delay_minutes,
            )
        if reminder is None:
            raise KeyError(reminder_id)
        await self._emit("reminder.updated", {"reminder": reminder})
        return reminder

    async def complete_reminder(self, reminder_id: str) -> dict[str, Any]:
        if self.reminder_scheduler is None:
            reminder = self.resources.update_reminder(
                reminder_id,
                {
                    "enabled": False,
                    "completed_at": datetime.now().astimezone().isoformat(timespec="seconds"),
                    "next_trigger_at": None,
                    "snoozed_until": None,
                    "status": "completed",
                },
            )
        else:
            reminder = await self.reminder_scheduler.complete_reminder(reminder_id)
        if reminder is None:
            raise KeyError(reminder_id)
        await self._emit("reminder.updated", {"reminder": reminder})
        return reminder

    async def list_reminders(self, *, limit: int | None = None) -> dict[str, Any]:
        return self.resources.list_reminders(limit=limit)


class _NullDesktopVoiceService:
    enable_local_microphone = False

    def get_snapshot(self) -> dict[str, Any]:
        return {
            "connected": False,
            "ready": False,
            "status": "idle",
            "capture_active": False,
            "client_count": 0,
            "device_feedback_available": False,
            "asr_available": False,
            "wake_word_active": False,
            "auto_listen_active": False,
        }

    def register_routes(self, app: web.Application) -> None:
        return None

    def set_event_observer(self, observer: Any) -> None:
        return None

    def set_active_app_session_resolver(self, resolver: Any) -> None:
        return None


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


def resolve_agent_runtime_options(cfg: dict[str, Any]) -> ResolvedAgentRuntimeOptions:
    """Resolve the effective runtime/tool options used by AgentLoop."""
    from nanobot.config.schema import ExecToolConfig

    tools_cfg = get_tools_config(cfg)
    cron_cfg = get_cron_config(cfg)
    exec_cfg = tools_cfg["exec"]
    cron_enabled = bool(cron_cfg.get("enabled", False))
    cron_store_path = Path(str(cron_cfg.get("store_path") or "")).expanduser()
    cron_service = None
    if cron_enabled:
        from nanobot.cron.service import CronService

        cron_service = CronService(cron_store_path)

    return ResolvedAgentRuntimeOptions(
        brave_api_key=str(tools_cfg["web"]["search"].get("api_key") or "").strip(),
        web_proxy=tools_cfg["web"].get("proxy"),
        exec_config=ExecToolConfig(
            timeout=exec_cfg["timeout"],
            path_append=exec_cfg["path_append"],
        ),
        restrict_to_workspace=bool(tools_cfg["restrict_to_workspace"]),
        mcp_servers=deepcopy(tools_cfg["mcp_servers"]),
        cron_enabled=cron_enabled,
        cron_store_path=cron_store_path if cron_enabled else None,
        cron_service=cron_service,
    )


def _create_default_planning_backend(cfg: dict[str, Any] | None = None) -> AppPlanningBackend:
    """Build a standalone planning facade for the agent bootstrap path."""
    from services.reminder_scheduler import ReminderScheduler

    runtime_dir = WORKSPACE_DIR / "runtime"
    resources = _build_resource_service(runtime_dir, cfg or {})
    reminder_scheduler = ReminderScheduler(resources)
    return AppPlanningBackend(resources, reminder_scheduler)


def _invoke_with_storage_support(factory: Any, *args: Any, storage_config: dict[str, Any] | None = None, **kwargs: Any) -> Any:
    """Call a constructor with storage_config only when it explicitly supports it."""
    target = factory
    try:
        signature = inspect.signature(target)
    except (TypeError, ValueError):
        signature = None

    if storage_config and signature is not None and "storage_config" in signature.parameters:
        kwargs["storage_config"] = dict(storage_config)
    return target(*args, **kwargs)


def _build_session_manager(workspace: Path, cfg: dict[str, Any]) -> SessionManager:
    storage_config = cfg.get("storage", {})
    return _invoke_with_storage_support(
        SessionManager,
        workspace,
        storage_config=storage_config,
    )


def _build_resource_service(runtime_dir: Path, cfg: dict[str, Any]) -> Any:
    from services.app_api.resource_service import AppResourceService

    storage_config = cfg.get("storage", {})
    return _invoke_with_storage_support(
        AppResourceService,
        runtime_dir,
        storage_config=storage_config,
    )


def create_agent(
    cfg: dict[str, Any],
    *,
    planning_backend: PlanningBackend | None = None,
    runtime_options: ResolvedAgentRuntimeOptions | None = None,
) -> tuple[MessageBus, AgentLoop]:
    """根据配置创建 MessageBus 和 AgentLoop。"""
    nanobot_cfg = cfg.get("nanobot", {})
    api_key = nanobot_cfg.get("api_key", "")
    model = nanobot_cfg.get("model", "claude-sonnet-4-6")
    provider_name = nanobot_cfg.get("provider", "anthropic")
    resolved_runtime = runtime_options or resolve_agent_runtime_options(cfg)

    bus = MessageBus()
    provider = LiteLLMProvider(
        api_key=api_key,
        default_model=model,
        provider_name=provider_name,
        request_timeout_seconds=get_provider_timeout_seconds(cfg),
    )
    session_manager = _build_session_manager(WORKSPACE_DIR, cfg)
    resolved_planning_backend = planning_backend or _create_default_planning_backend(cfg)

    agent = AgentLoop(
        bus=bus,
        provider=provider,
        workspace=WORKSPACE_DIR,
        model=model,
        max_iterations=nanobot_cfg.get("max_tool_iterations", 20),
        temperature=nanobot_cfg.get("temperature", 0.1),
        max_tokens=nanobot_cfg.get("max_tokens", 8192),
        memory_window=nanobot_cfg.get("memory_window", 50),
        brave_api_key=resolved_runtime.brave_api_key or None,
        web_proxy=resolved_runtime.web_proxy,
        exec_config=resolved_runtime.exec_config,
        cron_service=resolved_runtime.cron_service,
        restrict_to_workspace=resolved_runtime.restrict_to_workspace,
        session_manager=session_manager,
        mcp_servers=deepcopy(resolved_runtime.mcp_servers),
        planning_backend=resolved_planning_backend,
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
    desktop_voice_service: DesktopVoiceService | None = None,
    *,
    start_time: float,
    computer_control_service: ComputerControlService | None = None,
    agent_runtime: ResolvedAgentRuntimeOptions | None = None,
) -> web.Application:
    """Create the aiohttp application and register routes."""
    from nanobot.agent.tools.computer_control import ComputerControlTool

    @web.middleware
    async def cors_middleware(
        request: web.Request,
        handler,
    ) -> web.StreamResponse:
        if request.method == "OPTIONS":
            response: web.StreamResponse = web.Response(status=204)
        else:
            try:
                response = await handler(request)
            except web.HTTPException as exc:
                response = exc

        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Headers"] = _CORS_ALLOW_HEADERS
        response.headers["Access-Control-Allow-Methods"] = _CORS_ALLOW_METHODS
        return response

    resolved_sessions = getattr(agent, "sessions", None)
    if not hasattr(resolved_sessions, "workspace"):
        resolved_sessions = _build_session_manager(WORKSPACE_DIR, cfg)

    resolved_desktop_voice_service = desktop_voice_service or _NullDesktopVoiceService()
    runtime_dir = getattr(resolved_sessions, "workspace", WORKSPACE_DIR)
    if not isinstance(runtime_dir, Path):
        runtime_dir = WORKSPACE_DIR
    resolved_agent_runtime = agent_runtime or resolve_agent_runtime_options(cfg)
    resolved_computer_control_service = computer_control_service or ComputerControlService(
        cfg,
        runtime_dir=runtime_dir / "runtime",
    )

    app_runtime = AppRuntimeService(
        cfg,
        bus=bus,
        sessions=resolved_sessions,
        device_channel=device_channel,
        desktop_voice_service=resolved_desktop_voice_service,
        computer_control_service=resolved_computer_control_service,
        version=VERSION,
        start_time=start_time,
        agent_runtime=resolved_agent_runtime,
    )
    from nanobot.agent.tools.planning import PlanningTool

    shared_planning_backend = AppPlanningBackend(
        app_runtime.resources,
        app_runtime.reminder_scheduler,
        runtime_service=app_runtime,
    )
    bus.add_observer(app_runtime)
    agent.task_observer = app_runtime
    agent.planning_backend = shared_planning_backend
    setattr(agent, "computer_control_service", resolved_computer_control_service)
    if hasattr(agent, "computer_control_backend"):
        agent.computer_control_backend = (
            resolved_computer_control_service
            if resolved_computer_control_service.supported_actions()
            else None
        )
    if hasattr(agent, "tools") and hasattr(agent.tools, "register"):
        if (
            resolved_computer_control_service.supported_actions()
            and hasattr(agent.tools, "has")
            and not agent.tools.has("computer_control")
        ):
            agent.tools.register(
                ComputerControlTool(resolved_computer_control_service)
            )
        agent.tools.register(PlanningTool(shared_planning_backend))
    if hasattr(device_channel, "set_event_observer"):
        device_channel.set_event_observer(app_runtime)
    if hasattr(device_channel, "set_desktop_voice_bridge"):
        device_channel.set_desktop_voice_bridge(resolved_desktop_voice_service)
    if hasattr(resolved_desktop_voice_service, "set_event_observer"):
        resolved_desktop_voice_service.set_event_observer(app_runtime)

    async def health_handler(request: web.Request) -> web.Response:
        nanobot_cfg = cfg.get("nanobot", {})
        uptime = time.monotonic() - start_time
        device_state = getattr(getattr(device_channel, "state", None), "value", None) or "unknown"
        startup_state = request.app.get("startup_state", {})
        if not isinstance(startup_state, dict):
            startup_state = {}
        return web.json_response({
            "status": "ok",
            "ready": bool(startup_state.get("ready", False)),
            "startup_phase": str(startup_state.get("startup_phase") or "bootstrapping"),
            "version": VERSION,
            "uptime_s": round(uptime),
            "model": nanobot_cfg.get("model", "unknown"),
            "provider": nanobot_cfg.get("provider", "unknown"),
            "asr_model": cfg.get("asr", {}).get("model", "base"),
            "tts_voice": cfg.get("tts", {}).get("voice", "zh-CN-XiaoxiaoNeural"),
            "server_port": request.app.get("server_config", {}).get(
                "port",
                cfg.get("server", {}).get("port", 8765),
            ),
            "device_connected": device_channel.connected,
            "device_state": device_state,
        })

    async def device_info_handler(request: web.Request) -> web.Response:
        return web.json_response(device_channel.get_snapshot())

    app = web.Application(middlewares=[cors_middleware])
    app["server_config"] = get_server_config(cfg)
    app["startup_state"] = {
        "ready": False,
        "startup_phase": "bootstrapping",
    }
    app["agent_runtime"] = resolved_agent_runtime
    app.router.add_get("/api/health", health_handler)
    app.router.add_get("/api/device", device_info_handler)
    device_channel.register_routes(app)
    if hasattr(resolved_desktop_voice_service, "register_routes"):
        resolved_desktop_voice_service.register_routes(app)
    app_runtime.register_routes(app)

    app["bus"] = bus
    app["agent"] = agent
    app["device_channel"] = device_channel
    app["desktop_voice_service"] = resolved_desktop_voice_service
    app["computer_control_service"] = resolved_computer_control_service
    app["config"] = cfg
    app["app_runtime"] = app_runtime
    return app


def build_runtime(start_time: float) -> RuntimeComponents:
    """Build the full server runtime without starting background tasks."""
    from services.desktop_voice_service import DesktopVoiceService

    cfg, server_cfg = load_runtime_config()
    agent_runtime = resolve_agent_runtime_options(cfg)
    bus, agent = create_agent(cfg, runtime_options=agent_runtime)
    device_channel, asr_cfg, tts_cfg, device_cfg = create_device_channel(cfg, bus)
    desktop_voice_service = DesktopVoiceService(
        bus=bus,
        asr=device_channel.asr,
        device_channel=device_channel,
        auth_token=cfg.get("desktop_voice", {}).get("auth_token", "") or cfg.get("app", {}).get("auth_token", ""),
        default_app_session_id=cfg.get("app", {}).get("default_session_id", "app:main"),
        enable_local_microphone=cfg.get("desktop_voice", {}).get("enable_local_microphone", True),
    )
    whatsapp_channel = create_whatsapp_channel(cfg, bus)
    app = create_http_app(
        cfg,
        bus,
        agent,
        device_channel,
        desktop_voice_service,
        start_time=start_time,
        agent_runtime=agent_runtime,
    )
    return RuntimeComponents(
        config=cfg,
        server_config=server_cfg,
        agent_runtime=agent_runtime,
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
    logger.info(
        "  Desktop Voice: embedded-local-mic {}",
        "enabled" if runtime.desktop_voice_service.enable_local_microphone else "disabled",
    )
    logger.info(
        "  Computer Control: {}",
        "enabled" if runtime.config.get("computer_control", {}).get("enabled", False) else "disabled",
    )
    logger.info(
        "  Agent Runtime: exec={}s | workspace_restricted={} | web_search={} | mcp={} | cron={}",
        getattr(runtime.agent_runtime.exec_config, "timeout", 60),
        runtime.agent_runtime.restrict_to_workspace,
        bool(runtime.agent_runtime.brave_api_key),
        bool(runtime.agent_runtime.mcp_servers),
        runtime.agent_runtime.cron_enabled,
    )
    wa_cfg = runtime.config.get("whatsapp", {})
    logger.info(
        "  WhatsApp: {}",
        "enabled" if wa_cfg.get("enabled", False) else "disabled (optional)",
    )
    logger.info("  健康检查: http://localhost:{}/api/health", runtime.server_config["port"])
    logger.info("  App Bootstrap: http://localhost:{}/api/app/v1/bootstrap", runtime.server_config["port"])
    logger.info("  App Events: ws://localhost:{}/ws/app/v1/events", runtime.server_config["port"])
    logger.info("  WebSocket: ws://localhost:{}/ws/device", runtime.server_config["port"])
