from __future__ import annotations

from copy import deepcopy
from typing import Any, Callable


class RuntimeProjectionService:
    """Builds runtime diagnostics and capability projections for app clients."""

    def __init__(
        self,
        cfg: dict[str, Any],
        *,
        settings: Any,
        bus: Any,
        sessions: Any,
        resources: Any,
        reminder_scheduler: Any,
        computer_control_service: Any,
        device_channel: Any,
        desktop_voice_service: Any | None,
        experience_service: Any,
        planning_runtime_service: Any,
        agent_runtime: Any | None,
        auth_token: str,
        allowed_scripts_contract_version: str,
        get_active_app_session_id: Callable[[], str],
        get_outbound_router: Callable[[], Any | None],
        get_realtime_snapshot: Callable[[], dict[str, Any]],
    ) -> None:
        self.cfg = cfg
        self.settings = settings
        self.bus = bus
        self.sessions = sessions
        self.resources = resources
        self.reminder_scheduler = reminder_scheduler
        self.computer_control_service = computer_control_service
        self.device_channel = device_channel
        self.desktop_voice_service = desktop_voice_service
        self.experience_service = experience_service
        self.planning_runtime_service = planning_runtime_service
        self.agent_runtime = agent_runtime
        self.auth_token = auth_token
        self.allowed_scripts_contract_version = allowed_scripts_contract_version
        self._storage_config = dict(cfg.get("storage") or {})
        self._get_active_app_session_id = get_active_app_session_id
        self._get_outbound_router = get_outbound_router
        self._get_realtime_snapshot = get_realtime_snapshot

    async def build_runtime_state(
        self,
        *,
        current_task: dict[str, Any] | None,
        task_queue: list[dict[str, Any]],
    ) -> dict[str, Any]:
        device_snapshot = self.device_runtime_state()
        desktop_voice = self.desktop_voice_runtime()
        voice_runtime = self.voice_runtime_state(desktop=desktop_voice)
        computer_control = self.computer_control_runtime_state()
        return {
            "current_task": current_task,
            "task_queue": task_queue,
            "chat": {
                "active_session_id": self._get_active_app_session_id(),
            },
            "agent_runtime": self.agent_runtime_summary(),
            "computer_control": computer_control,
            "device": device_snapshot,
            "desktop_voice": desktop_voice,
            "voice": voice_runtime,
            "storage": self.storage_runtime_state(),
            "transport": self.transport_runtime_state(),
            "experience": await self.runtime_experience_state(
                session_id=self._get_active_app_session_id(),
                device_snapshot=device_snapshot,
                voice_runtime=voice_runtime,
                computer_control_state=computer_control,
                current_task=current_task,
            ),
            "reminders": self.reminder_runtime_state(),
            "planning": self.planning_runtime_state(),
            "todo_summary": self.planning_runtime_service.get_todo_summary(),
            "calendar_summary": self.planning_runtime_service.get_calendar_summary(),
        }

    def desktop_voice_runtime(self) -> dict[str, Any]:
        if self.desktop_voice_service is None:
            return {
                "connected": False,
                "ready": False,
                "status": "idle",
                "capture_active": False,
                "client_count": 0,
                "device_feedback_available": bool(self.device_channel.connected),
                "asr_available": bool(self.device_channel.asr),
                "wake_word_active": False,
                "auto_listen_active": False,
            }
        return self.desktop_voice_service.get_snapshot()

    def device_runtime_state(self) -> dict[str, Any]:
        snapshot = dict(self.device_channel.get_snapshot())
        capabilities = snapshot.get("display_capabilities")
        if not isinstance(capabilities, dict):
            battery = snapshot.get("battery")
            battery_available = False
            try:
                battery_available = int(battery) >= 0
            except (TypeError, ValueError):
                battery_available = False
            capabilities = {
                "text_reply_available": True,
                "display_update_hint_available": True,
                "status_bar_available": False,
                "weather_available": False,
                "battery_telemetry_available": battery_available,
                "charging_telemetry_available": battery_available,
            }
        snapshot["display_capabilities"] = dict(capabilities)
        return snapshot

    def voice_runtime_state(
        self,
        *,
        desktop: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        settings = self.settings.get_public_settings()
        desktop_snapshot = desktop or self.desktop_voice_runtime()
        return {
            "pipeline_ready": bool(
                self.device_channel.asr and desktop_snapshot.get("ready")
            ),
            "desktop_bridge": desktop_snapshot,
            "device_feedback_available": bool(self.device_channel.connected),
            "wake_word": {
                "configured_value": settings.get("wake_word"),
                "configured": bool(settings.get("wake_word")),
                "implemented": False,
                "active": False,
                "reason": "configured_only_not_runtime_enabled",
            },
            "auto_listen": {
                "configured_value": bool(settings.get("auto_listen", False)),
                "configured": True,
                "implemented": False,
                "active": False,
                "reason": "configured_only_not_runtime_enabled",
            },
        }

    def planning_runtime_state(self) -> dict[str, Any]:
        return self.planning_runtime_service.planning_runtime_state()

    def reminder_runtime_state(self) -> dict[str, Any]:
        runtime_state = getattr(self.reminder_scheduler, "runtime_state", None)
        if callable(runtime_state):
            payload = runtime_state()
            if isinstance(payload, dict):
                payload.setdefault(
                    "scheduler_running",
                    bool(payload.get("running", False)),
                )
                return payload
        return {
            "running": self.reminder_scheduler.is_running(),
            "scheduler_running": self.reminder_scheduler.is_running(),
        }

    def storage_runtime_state(self) -> dict[str, Any]:
        sqlite_path = self._storage_config.get("sqlite_path")
        sqlite_path_value = str(sqlite_path).strip() if sqlite_path is not None else ""
        state = {
            "session_mode": str(
                self._storage_config.get("session_storage_mode", "json")
            ).strip().lower()
            or "json",
            "planning_mode": str(
                self._storage_config.get("planning_storage_mode", "json")
            ).strip().lower()
            or "json",
            "experience_mode": str(
                self._storage_config.get("experience_storage_mode", "json")
            ).strip().lower()
            or "json",
            "computer_action_mode": str(
                self._storage_config.get("computer_action_storage_mode", "json")
            ).strip().lower()
            or "json",
            "sqlite_path": sqlite_path_value or None,
            "schema_version": 0,
            "latest_imported_at": None,
            "shadow_failures": 0,
            "mismatch_count": 0,
        }
        session_runtime_state = getattr(self.sessions, "storage_runtime_state", None)
        if callable(session_runtime_state):
            payload = session_runtime_state()
            if isinstance(payload, dict):
                state["session_store"] = deepcopy(payload)
                state["session_mode"] = str(payload.get("mode") or state["session_mode"])
                state["sqlite_path"] = payload.get("sqlite_path") or state["sqlite_path"]
                state["session_sqlite_ready"] = bool(payload.get("sqlite_ready", False))
                state["schema_version"] = max(
                    int(state["schema_version"] or 0),
                    int(payload.get("schema_version", 0) or 0),
                )
                state["latest_imported_at"] = (
                    payload.get("latest_imported_at") or state["latest_imported_at"]
                )

        session_store_diagnostics = getattr(self.sessions, "session_store_diagnostics", None)
        if callable(session_store_diagnostics):
            payload = session_store_diagnostics()
            if isinstance(payload, dict):
                state["session_store"] = deepcopy(payload)

        planning_runtime_state = getattr(self.resources, "storage_runtime_state", None)
        if callable(planning_runtime_state):
            payload = planning_runtime_state()
            if isinstance(payload, dict):
                state["planning_store"] = deepcopy(payload)
                state["planning_mode"] = str(payload.get("mode") or state["planning_mode"])
                state["sqlite_path"] = payload.get("sqlite_path") or state["sqlite_path"]
                state["planning_sqlite_ready"] = bool(payload.get("sqlite_ready", False))
                state["schema_version"] = max(
                    int(state["schema_version"] or 0),
                    int(payload.get("schema_version", 0) or 0),
                )
                state["latest_imported_at"] = (
                    payload.get("latest_imported_at") or state["latest_imported_at"]
                )
                state["shadow_failures"] = int(payload.get("shadow_failures", 0) or 0)
                state["mismatch_count"] = int(payload.get("mismatch_count", 0) or 0)
                mismatch_domains = payload.get("mismatch_domains")
                if isinstance(mismatch_domains, dict):
                    state["mismatch_domains"] = dict(mismatch_domains)
        planning_store_diagnostics = getattr(
            self.resources,
            "planning_store_diagnostics",
            None,
        )
        if callable(planning_store_diagnostics):
            payload = planning_store_diagnostics()
            if isinstance(payload, dict):
                state["planning_store"] = deepcopy(payload)
        return state

    def transport_runtime_state(self) -> dict[str, Any]:
        state: dict[str, Any] = {}
        metrics_snapshot = getattr(self.bus, "metrics_snapshot", None)
        if callable(metrics_snapshot):
            payload = metrics_snapshot()
            if isinstance(payload, dict):
                state["bus"] = deepcopy(payload)
        inbound_metrics = state.get("bus", {}).get("inbound", {})
        outbound_metrics = state.get("bus", {}).get("outbound", {})
        observer_metrics = state.get("bus", {}).get("observers", {})
        state.setdefault(
            "bus_inbound_depth",
            int(inbound_metrics.get("depth", getattr(self.bus, "inbound_size", 0)) or 0),
        )
        state.setdefault(
            "bus_outbound_depth",
            int(outbound_metrics.get("depth", getattr(self.bus, "outbound_size", 0)) or 0),
        )
        if inbound_metrics:
            state["bus_inbound_reserved_depth"] = int(
                inbound_metrics.get("reserved_depth", 0) or 0
            )
            state["bus_inbound_rejected_total"] = int(
                inbound_metrics.get("rejected_total", 0) or 0
            )
        if outbound_metrics:
            state["bus_outbound_reserved_depth"] = int(
                outbound_metrics.get("reserved_depth", 0) or 0
            )
            state["bus_outbound_rejected_total"] = int(
                outbound_metrics.get("rejected_total", 0) or 0
            )
        if observer_metrics:
            state["observer_pending_notifications"] = int(
                observer_metrics.get("pending_notifications", 0) or 0
            )

        state.update(self._get_realtime_snapshot())

        outbound_router = self._get_outbound_router()
        if outbound_router is not None:
            lane_snapshot = getattr(outbound_router, "lane_snapshot", None)
            if callable(lane_snapshot):
                payload = lane_snapshot()
                if isinstance(payload, dict):
                    state["outbound_lanes"] = deepcopy(payload)
        return state

    def computer_control_runtime_state(self) -> dict[str, Any]:
        state = dict(self.computer_control_service.get_state())
        state.setdefault(
            "allowed_scripts_contract_version",
            self.allowed_scripts_contract_version,
        )
        return state

    async def runtime_experience_state(
        self,
        *,
        session_id: str | None,
        device_snapshot: dict[str, Any] | None = None,
        voice_runtime: dict[str, Any] | None = None,
        computer_control_state: dict[str, Any] | None = None,
        current_task: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self.experience_service.get_public_snapshot(
            session_id=session_id,
            device_snapshot=device_snapshot or self.device_runtime_state(),
            voice_runtime=voice_runtime or self.voice_runtime_state(),
            computer_control_state=computer_control_state
            or self.computer_control_runtime_state(),
            current_task=current_task,
        )

    def agent_runtime_summary(self) -> dict[str, Any]:
        runtime = self.agent_runtime
        exec_config = getattr(runtime, "exec_config", None)
        web_proxy = str(getattr(runtime, "web_proxy", "") or "").strip()
        brave_api_key = str(getattr(runtime, "brave_api_key", "") or "").strip()
        mcp_servers = getattr(runtime, "mcp_servers", {}) or {}
        policy = getattr(self.computer_control_service, "policy", None)

        exec_timeout = 60
        path_append = ""
        if exec_config is not None:
            try:
                exec_timeout = int(getattr(exec_config, "timeout", 60))
            except (TypeError, ValueError):
                exec_timeout = 60
            path_append = str(getattr(exec_config, "path_append", "") or "").strip()

        allowed_apps = sorted(getattr(policy, "allowed_apps", set()) or [])
        allowed_shortcuts = sorted(getattr(policy, "allowed_shortcuts", set()) or [])
        allowed_scripts = sorted(
            (getattr(policy, "allowed_scripts", {}) or {}).keys()
        )
        allowed_path_roots = [
            str(path)
            for path in sorted(
                getattr(policy, "allowed_path_roots", []) or [],
                key=lambda item: str(item),
            )
        ]
        allowed_wechat_contacts = sorted(
            getattr(policy, "allowed_wechat_contacts", set()) or [],
        )
        permission_profile = {
            "api_auth": {
                "app_auth_required": bool(self.auth_token),
                "device_auth_required": bool(
                    str(self.cfg.get("device", {}).get("auth_token", "") or "").strip()
                ),
            },
            "exec": {
                "workspace_restricted": bool(
                    getattr(runtime, "restrict_to_workspace", False)
                ),
                "timeout_s": exec_timeout,
                "path_append_configured": bool(path_append),
            },
            "web": {
                "search_enabled": bool(brave_api_key),
                "fetch_enabled": True,
                "proxy_configured": bool(web_proxy),
            },
            "mcp": {
                "enabled": bool(mcp_servers),
                "server_names": sorted(str(name) for name in mcp_servers.keys()),
            },
            "cron": {
                "enabled": bool(getattr(runtime, "cron_enabled", False)),
            },
            "computer_control": {
                "enabled": bool(getattr(policy, "enabled", False)),
                "available": self.computer_control_service.is_available(),
                "supported_actions": self.computer_control_service.supported_actions(),
                "allowed_scripts_contract_version": self.allowed_scripts_contract_version,
                "confirm_medium_risk": bool(
                    getattr(policy, "confirm_medium_risk", False)
                ),
                "allowed_apps": allowed_apps,
                "allowed_shortcuts": allowed_shortcuts,
                "allowed_scripts": allowed_scripts,
                "allowed_path_roots": allowed_path_roots,
                "wechat_enabled": bool(getattr(policy, "wechat_enabled", False)),
                "allowed_wechat_contacts": allowed_wechat_contacts,
                "permission_hints": self.computer_control_service.permission_hints(),
                "adapter_error_present": bool(
                    getattr(self.computer_control_service, "adapter_error", None)
                ),
            },
        }
        return {
            "workspace_restricted": permission_profile["exec"]["workspace_restricted"],
            "web_search_enabled": permission_profile["web"]["search_enabled"],
            "web_fetch_enabled": permission_profile["web"]["fetch_enabled"],
            "mcp_enabled": permission_profile["mcp"]["enabled"],
            "cron_enabled": permission_profile["cron"]["enabled"],
            "exec_timeout_s": exec_timeout,
            "permission_profile": permission_profile,
        }

    def capabilities(self) -> dict[str, Any]:
        desktop = self.desktop_voice_runtime()
        return {
            "chat": True,
            "device_control": True,
            "device_commands": True,
            "voice_pipeline": bool(self.device_channel.asr and desktop.get("ready")),
            "desktop_voice": {
                "http_path": "/api/desktop-voice/v1/state",
                "ws_path": "/ws/desktop-voice",
                "desktop_client_ready": bool(desktop.get("ready")),
                "capture_source": "desktop_mic",
                "device_feedback_available": bool(self.device_channel.connected),
                "local_speaker_output": False,
            },
            "wake_word": False,
            "auto_listen": False,
            "whatsapp_bridge": bool(self.cfg.get("whatsapp", {}).get("enabled", False)),
            "settings": True,
            "tasks": True,
            "events": True,
            "notifications": True,
            "reminders": True,
            "reminder_actions": True,
            "planning": True,
            "planning_bundle": True,
            "planning_overview": True,
            "planning_timeline": True,
            "planning_conflicts": True,
            "todo_summary": True,
            "calendar_summary": True,
            "computer_control": self.computer_control_service.is_available(),
            "computer_actions": self.computer_control_service.supported_actions(),
            "experience": True,
            "app_events": True,
            "event_replay": True,
            "app_auth_enabled": bool(self.auth_token),
            "agent_runtime": self.agent_runtime_summary(),
        }
