from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any, Awaitable, Callable, Mapping

from nanobot.session.manager import Session, SessionManager

from .interaction_router import ExperienceInteractionRouter
from .models import (
    DEFAULT_PERSONA_PRESET,
    DEFAULT_PERSONA_FIELDS,
    DEFAULT_SCENE_MODE,
    INTERACTION_THROTTLE_SECONDS,
    SCENE_PERSONA_PRESETS,
    build_experience_catalog,
    build_persona_profile,
    build_physical_interaction_result,
    clean_optional_string,
    merge_persona_fields,
    normalize_persona_fields,
    normalize_persona_profile,
    normalize_scene_mode,
    persona_fields_from_settings,
    preset_fields,
)
from .store import ExperienceStore


ActionCallback = Callable[[str], Awaitable[dict[str, Any]]]
NotificationProvider = Callable[[], list[dict[str, Any]]]
SessionIdResolver = Callable[[], str]
StateProvider = Callable[[], dict[str, Any]]


async def _noop_action(_: str) -> dict[str, Any]:
    return {}


class ExperienceService:
    def __init__(
        self,
        settings_service: Any,
        sessions: SessionManager,
        runtime_dir: Path,
        *,
        active_session_id_resolver: SessionIdResolver | None = None,
        device_snapshot_provider: StateProvider | None = None,
        desktop_voice_snapshot_provider: StateProvider | None = None,
        computer_state_provider: StateProvider | None = None,
        notifications_provider: NotificationProvider | None = None,
        confirm_computer_action: ActionCallback | None = None,
        cancel_computer_action: ActionCallback | None = None,
        store: ExperienceStore | None = None,
        router: ExperienceInteractionRouter | None = None,
        storage_config: Mapping[str, Any] | None = None,
    ) -> None:
        self.settings_service = settings_service
        self.sessions = sessions
        self.active_session_id_resolver = active_session_id_resolver or (lambda: "app:main")
        self.device_snapshot_provider = device_snapshot_provider or (lambda: {})
        self.desktop_voice_snapshot_provider = desktop_voice_snapshot_provider or (lambda: {})
        self.computer_state_provider = computer_state_provider or (lambda: {})
        self.notifications_provider = notifications_provider or (lambda: [])
        self.confirm_computer_action = confirm_computer_action or _noop_action
        self.cancel_computer_action = cancel_computer_action or _noop_action
        self.store = store or ExperienceStore(
            runtime_dir,
            storage_config=storage_config,
        )
        self.router = router or ExperienceInteractionRouter()

    def get_catalog(self) -> dict[str, Any]:
        return build_experience_catalog()

    def configure_runtime(
        self,
        *,
        active_session_id_resolver: SessionIdResolver | None = None,
        device_snapshot_provider: StateProvider | None = None,
        desktop_voice_snapshot_provider: StateProvider | None = None,
        computer_state_provider: StateProvider | None = None,
        notifications_provider: NotificationProvider | None = None,
        confirm_computer_action: ActionCallback | None = None,
        cancel_computer_action: ActionCallback | None = None,
    ) -> None:
        if active_session_id_resolver is not None:
            self.active_session_id_resolver = active_session_id_resolver
        if device_snapshot_provider is not None:
            self.device_snapshot_provider = device_snapshot_provider
        if desktop_voice_snapshot_provider is not None:
            self.desktop_voice_snapshot_provider = desktop_voice_snapshot_provider
        if computer_state_provider is not None:
            self.computer_state_provider = computer_state_provider
        if notifications_provider is not None:
            self.notifications_provider = notifications_provider
        if confirm_computer_action is not None:
            self.confirm_computer_action = confirm_computer_action
        if cancel_computer_action is not None:
            self.cancel_computer_action = cancel_computer_action

    def get_runtime_snapshot(
        self,
        session_id: str | None = None,
        *,
        current_task: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self.get_public_snapshot(
            session_id=session_id,
            current_task=current_task,
        )

    def get_public_snapshot(
        self,
        *,
        session_id: str | None = None,
        device_snapshot: Mapping[str, Any] | None = None,
        voice_runtime: Mapping[str, Any] | None = None,
        computer_control_state: Mapping[str, Any] | None = None,
        current_task: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        resolved_session_id = self._resolve_session_id(session_id)
        session = self._get_session(resolved_session_id)
        settings = self._settings()
        runtime_override = self.store.get_runtime_override()
        scene_mode = self._resolve_scene_mode(
            settings=settings,
            session=session,
            runtime_override=runtime_override,
        )
        active_persona = self._resolve_active_persona(
            settings=settings,
            session=session,
            runtime_override=runtime_override,
            scene_mode=scene_mode,
        )
        daily_shake_state = self.store.get_daily_shake_state()
        physical_interaction = self._build_physical_policy(
            settings=settings,
            scene_mode=scene_mode,
            daily_shake_state=daily_shake_state,
            device_snapshot=device_snapshot,
            voice_runtime=voice_runtime,
            computer_control_state=computer_control_state,
            current_task=current_task,
        )
        return {
            **self.get_catalog(),
            "active_scene_mode": scene_mode,
            "active_persona": active_persona,
            "override_source": self._resolve_override_source(
                session=session,
                runtime_override=runtime_override,
                scene_mode=scene_mode,
            ),
            "daily_shake_state": daily_shake_state,
            "physical_interaction": physical_interaction,
            "last_interaction_result": self.store.get_last_interaction_result(),
        }

    def get_experience_payload(
        self,
        session_id: str | None = None,
        *,
        device_snapshot: Mapping[str, Any] | None = None,
        voice_runtime: Mapping[str, Any] | None = None,
        computer_control_state: Mapping[str, Any] | None = None,
        current_task: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        resolved_session_id = self._resolve_session_id(session_id)
        return {
            "session_id": resolved_session_id,
            "session_override": self.get_session_override(resolved_session_id),
            "runtime_override": self.store.get_runtime_override(),
            "experience": self.get_public_snapshot(
                session_id=resolved_session_id,
                device_snapshot=device_snapshot,
                voice_runtime=voice_runtime,
                computer_control_state=computer_control_state,
                current_task=current_task,
            ),
        }

    def get_session_override(self, session_id: str | None = None) -> dict[str, Any]:
        session = self._get_session(self._resolve_session_id(session_id))
        payload = {
            "scene_mode": None,
            "persona_profile": None,
            "persona_fields": None,
        }
        if session is None:
            return payload
        scene_mode = normalize_scene_mode(session.metadata.get("scene_mode"), allow_none=True)
        if scene_mode is not None:
            payload["scene_mode"] = scene_mode
        if isinstance(session.metadata.get("persona_profile"), Mapping):
            payload["persona_profile"] = deepcopy(dict(session.metadata["persona_profile"]))
        if isinstance(session.metadata.get("persona_fields"), Mapping):
            payload["persona_fields"] = deepcopy(dict(session.metadata["persona_fields"]))
        return payload

    def update_session_override(self, session_id: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        session = self.sessions.get_or_create(session_id)
        if self.patch_session(session, payload):
            self.sessions.save(session)
        return self.get_experience_payload(session_id)

    def patch_session(self, session: Session, payload: Mapping[str, Any]) -> bool:
        changed = False

        if "scene_mode" in payload:
            next_scene_mode = normalize_scene_mode(payload.get("scene_mode"), allow_none=True)
            if next_scene_mode is None:
                if session.metadata.pop("scene_mode", None) is not None:
                    changed = True
            elif session.metadata.get("scene_mode") != next_scene_mode:
                session.metadata["scene_mode"] = next_scene_mode
                changed = True

        if "persona_profile" in payload or "persona_profile_id" in payload:
            raw_profile = payload.get("persona_profile")
            if "persona_profile" not in payload:
                raw_profile = payload.get("persona_profile_id")
            if raw_profile is None:
                if session.metadata.pop("persona_profile", None) is not None:
                    changed = True
            else:
                normalized_profile = self._normalize_persona_profile_payload(raw_profile)
                if session.metadata.get("persona_profile") != normalized_profile:
                    session.metadata["persona_profile"] = normalized_profile
                    changed = True

        if "persona_fields" in payload:
            raw_fields = normalize_persona_fields(
                payload.get("persona_fields"),
                partial=True,
                allow_none=True,
            )
            if raw_fields is None or not raw_fields:
                if session.metadata.pop("persona_fields", None) is not None:
                    changed = True
            elif session.metadata.get("persona_fields") != raw_fields:
                session.metadata["persona_fields"] = raw_fields
                changed = True

        return changed

    def update_runtime_override(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        if "scene_mode" in payload:
            normalized["scene_mode"] = normalize_scene_mode(
                payload.get("scene_mode"),
                allow_none=True,
            )
        if "persona_profile" in payload or "persona_profile_id" in payload:
            raw_profile = payload.get("persona_profile")
            if "persona_profile" not in payload:
                raw_profile = payload.get("persona_profile_id")
            normalized["persona_profile"] = (
                None if raw_profile is None else self._normalize_persona_profile_payload(raw_profile)
            )
        if "persona_fields" in payload:
            normalized["persona_fields"] = normalize_persona_fields(
                payload.get("persona_fields"),
                partial=True,
                allow_none=True,
            )
        return self.store.set_runtime_override(normalized)

    def apply_runtime_override(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        runtime_payload = dict(payload)
        runtime_payload.pop("scope", None)
        runtime_payload.pop("session_id", None)
        return self.update_runtime_override(runtime_payload)

    def append_interaction_result(self, result: Mapping[str, Any]) -> dict[str, Any]:
        return self.store.record_interaction_result(dict(result))

    def inject_message_metadata(
        self,
        metadata: Mapping[str, Any] | None,
        *,
        session_id: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
    ) -> dict[str, Any]:
        payload = dict(metadata or {})
        snapshot = self.get_public_snapshot(session_id=session_id)
        active_persona = snapshot.get("active_persona") or {}
        payload.setdefault("scene_mode", snapshot.get("active_scene_mode"))
        payload.setdefault("persona_profile_id", active_persona.get("preset"))
        payload.setdefault("persona_voice_style", active_persona.get("voice_style"))
        if interaction_kind:
            payload["interaction_kind"] = interaction_kind
        if interaction_mode:
            payload["interaction_mode"] = interaction_mode
        if approval_source:
            payload["approval_source"] = approval_source
        return {key: value for key, value in payload.items() if value is not None}

    async def handle_interaction(
        self,
        interaction_kind: str,
        payload: Mapping[str, Any] | None = None,
        *,
        current_task: Mapping[str, Any] | None = None,
        device_snapshot: Mapping[str, Any] | None = None,
        voice_runtime: Mapping[str, Any] | None = None,
        computer_control_state: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        request = dict(payload or {})
        session_id = self._resolve_session_id(request.get("app_session_id"))
        snapshot = self.get_public_snapshot(
            session_id=session_id,
            device_snapshot=device_snapshot,
            voice_runtime=voice_runtime,
            computer_control_state=computer_control_state,
            current_task=current_task,
        )
        metadata = {
            "scene_mode": snapshot["active_scene_mode"],
            "persona_profile_id": snapshot["active_persona"].get("preset"),
            "persona_voice_style": snapshot["active_persona"].get("voice_style"),
            "override_source": snapshot["override_source"],
        }

        throttle_ttl = INTERACTION_THROTTLE_SECONDS.get(interaction_kind, 0.0)
        if self.store.is_throttled(interaction_kind, ttl_s=throttle_ttl):
            result = self._blocked_result(
                interaction_kind=interaction_kind,
                mode="blocked",
                title="交互节流",
                display_text="触发太快了，稍等一下再试。",
                blocked_reason="throttled",
                metadata=metadata,
            )
            return self.store.record_interaction_result(result)
        self.store.touch_interaction(interaction_kind)

        if interaction_kind == "tap":
            result = await self._handle_tap(
                request,
                snapshot=snapshot,
                computer_control_state=computer_control_state,
                metadata=metadata,
                current_task=current_task,
            )
        elif interaction_kind == "shake":
            result = self._handle_shake(
                request,
                snapshot=snapshot,
                session_id=session_id,
                metadata=metadata,
            )
        elif interaction_kind == "hold":
            result = self._handle_hold(
                request,
                snapshot=snapshot,
                metadata=metadata,
            )
        else:
            result = self._blocked_result(
                interaction_kind=interaction_kind,
                mode="blocked",
                title="未知交互",
                display_text="当前不支持这个物理交互。",
                blocked_reason="unsupported_interaction",
                metadata=metadata,
            )
        if interaction_kind == "shake":
            mode = str(result.get("mode") or "").strip()
            daily_shake_state = (
                self.store.record_valid_shake(mode)
                if mode in {"fortune", "random"}
                else self.store.get_daily_shake_state()
            )
            result = dict(result)
            result_metadata = dict(result.get("metadata") or {})
            result_metadata["daily_shake_state"] = daily_shake_state
            result["metadata"] = result_metadata
        return self.store.record_interaction_result(result)

    def _settings(self) -> dict[str, Any]:
        settings = self.settings_service.get_public_settings()
        return settings if isinstance(settings, dict) else {}

    def _resolve_session_id(self, candidate: Any) -> str:
        cleaned = clean_optional_string(candidate)
        if cleaned and cleaned.startswith("app:"):
            return cleaned
        return self.active_session_id_resolver()

    def _get_session(self, session_id: str) -> Session | None:
        if not session_id.startswith("app:"):
            return None
        return self.sessions.get(session_id)

    def _resolve_scene_mode(
        self,
        *,
        settings: Mapping[str, Any],
        session: Session | None,
        runtime_override: Mapping[str, Any],
    ) -> str:
        if session is not None:
            session_scene = normalize_scene_mode(session.metadata.get("scene_mode"), allow_none=True)
            if session_scene is not None:
                return session_scene
        runtime_scene = normalize_scene_mode(runtime_override.get("scene_mode"), allow_none=True)
        if runtime_scene is not None:
            return runtime_scene
        return normalize_scene_mode(settings.get("default_scene_mode"))

    def _resolve_active_persona(
        self,
        *,
        settings: Mapping[str, Any],
        session: Session | None,
        runtime_override: Mapping[str, Any],
        scene_mode: str,
    ) -> dict[str, Any]:
        scene_preset = SCENE_PERSONA_PRESETS.get(scene_mode)
        active_preset = scene_preset or DEFAULT_PERSONA_PRESET
        active_fields = merge_persona_fields(
            DEFAULT_PERSONA_FIELDS,
            persona_fields_from_settings(settings),
            preset_fields(scene_preset),
        )

        runtime_profile = runtime_override.get("persona_profile")
        if isinstance(runtime_profile, Mapping):
            runtime_preset = normalize_persona_profile(runtime_profile, allow_none=True)
            if runtime_preset is not None:
                active_preset = runtime_preset
                active_fields = merge_persona_fields(active_fields, preset_fields(runtime_preset), runtime_profile)
        runtime_fields = normalize_persona_fields(
            runtime_override.get("persona_fields"),
            partial=True,
            allow_none=True,
        )
        if runtime_fields:
            active_fields = merge_persona_fields(active_fields, runtime_fields)

        if session is not None:
            session_profile = session.metadata.get("persona_profile")
            if isinstance(session_profile, Mapping):
                session_preset = normalize_persona_profile(session_profile, allow_none=True)
                if session_preset is not None:
                    active_preset = session_preset
                    active_fields = merge_persona_fields(active_fields, preset_fields(session_preset), session_profile)
            session_fields = normalize_persona_fields(
                session.metadata.get("persona_fields"),
                partial=True,
                allow_none=True,
            )
            if session_fields:
                active_fields = merge_persona_fields(active_fields, session_fields)

        return build_persona_profile(
            active_preset,
            persona_fields=active_fields,
        )

    def _resolve_override_source(
        self,
        *,
        session: Session | None,
        runtime_override: Mapping[str, Any],
        scene_mode: str,
    ) -> str:
        if session is not None and any(
            key in session.metadata and session.metadata.get(key) is not None
            for key in ("scene_mode", "persona_profile", "persona_fields")
        ):
            return "session_override"
        if any(runtime_override.get(key) is not None for key in ("scene_mode", "persona_profile", "persona_fields")):
            return "runtime_override"
        if SCENE_PERSONA_PRESETS.get(scene_mode):
            return "scene_default"
        return "global_default"

    def _build_physical_policy(
        self,
        *,
        settings: Mapping[str, Any],
        scene_mode: str,
        daily_shake_state: Mapping[str, Any],
        device_snapshot: Mapping[str, Any] | None,
        voice_runtime: Mapping[str, Any] | None,
        computer_control_state: Mapping[str, Any] | None,
        current_task: Mapping[str, Any] | None,
    ) -> dict[str, Any]:
        device = dict(device_snapshot or self.device_snapshot_provider() or {})
        desktop = self._resolve_desktop_snapshot(voice_runtime)
        computer = dict(computer_control_state or self.computer_state_provider() or {})
        notifications = list(self.notifications_provider() or [])
        pending_actions = self._pending_actions(computer)
        history = self.store.list_history(limit=20)
        last_result = self.store.get_last_interaction_result() or {}
        pending_action = pending_actions[0] if pending_actions else {}
        pending_action_title = str(
            pending_action.get("title")
            or pending_action.get("label")
            or pending_action.get("action_id")
            or ""
        ).strip() or None
        pending_action_kind = str(
            pending_action.get("kind")
            or pending_action.get("action")
            or ""
        ).strip() or None

        enabled = bool(settings.get("physical_interaction_enabled", True))
        tap_enabled = bool(settings.get("tap_confirmation_enabled", True))
        shake_enabled = bool(settings.get("shake_enabled", True))
        device_connected = bool(device.get("connected"))
        bridge_ready = bool(desktop.get("ready"))
        pending_command = str((device.get("last_command") or {}).get("status") or "").lower() == "pending"
        high_priority_pending = any(
            str(item.get("priority") or "").lower() == "high"
            and not bool(item.get("read", False))
            for item in notifications
            if isinstance(item, Mapping)
        )
        desktop_status = str(desktop.get("status") or "").lower()
        device_state = str(device.get("state") or "").lower()
        speech_busy = bool(current_task) or desktop_status in {
            "listening",
            "transcribing",
            "responding",
            "speaking",
        } or device_state in {
            "listening",
            "processing",
            "responding",
            "speaking",
        }
        pending_confirmation = bool(pending_actions)

        hold_available = enabled and device_connected and bridge_ready and not pending_command
        tap_available = (
            enabled
            and tap_enabled
            and device_connected
            and pending_confirmation
            and not pending_command
        )
        shake_available = (
            enabled
            and shake_enabled
            and device_connected
            and not pending_command
            and not speech_busy
            and not high_priority_pending
        )

        hold_blocked_reason: str | None = None
        if not enabled:
            hold_blocked_reason = "physical_interaction_disabled"
        elif not device_connected:
            hold_blocked_reason = "device_offline"
        elif not bridge_ready:
            hold_blocked_reason = "desktop_bridge_unavailable"
        elif pending_command:
            hold_blocked_reason = "device_command_pending"

        tap_blocked_reason: str | None = None
        if not enabled:
            tap_blocked_reason = "physical_interaction_disabled"
        elif not device_connected:
            tap_blocked_reason = "device_offline"
        elif not tap_enabled:
            tap_blocked_reason = "tap_confirmation_disabled"
        elif pending_command:
            tap_blocked_reason = "device_command_pending"
        elif not pending_confirmation:
            tap_blocked_reason = "no_pending_confirmation"

        shake_blocked_reason: str | None = None
        if not enabled:
            shake_blocked_reason = "physical_interaction_disabled"
        elif not shake_enabled:
            shake_blocked_reason = "shake_disabled"
        elif not device_connected:
            shake_blocked_reason = "device_offline"
        elif pending_command:
            shake_blocked_reason = "device_command_pending"
        elif speech_busy:
            shake_blocked_reason = "voice_busy"
        elif high_priority_pending:
            shake_blocked_reason = "high_priority_pending"

        blocked_reasons = {
            "hold": hold_blocked_reason,
            "tap": tap_blocked_reason,
            "shake": shake_blocked_reason,
        }
        latest_interaction_at = clean_optional_string(last_result.get("created_at"))
        ready = hold_available or tap_available or shake_available
        if not enabled:
            status = "disabled"
            status_message = "物理交互已关闭。"
        elif pending_confirmation:
            status = "awaiting_confirmation"
            status_message = "当前有待确认动作，可用拍一拍确认，摇一摇会给出决策建议。"
        elif speech_busy:
            status = "busy"
            status_message = "当前语音链路忙碌中，先等当前流程结束。"
        elif ready:
            status = "ready"
            status_message = "设备可接收 hold / tap / shake 交互。"
        else:
            status = "blocked"
            status_message = "当前物理交互暂不可用。"
        primary_blocked_reason: str | None = None
        if status in {"disabled", "busy", "blocked"}:
            primary_blocked_reason = (
                hold_blocked_reason or tap_blocked_reason or shake_blocked_reason
            )

        return {
            "enabled": enabled,
            "device_connected": device_connected,
            "bridge_ready": bridge_ready,
            "hold_enabled": hold_available,
            "hold_available": hold_available,
            "tap_confirmation_enabled": tap_enabled,
            "tap_available": tap_available,
            "shake_enabled": shake_enabled,
            "shake_available": shake_available,
            "pending_confirmation": pending_confirmation,
            "pending_device_command": pending_command,
            "high_priority_pending": high_priority_pending,
            "speech_busy": speech_busy,
            "ready": ready,
            "status": status,
            "status_message": status_message,
            "blocked_reason": primary_blocked_reason,
            "latest_interaction_at": latest_interaction_at,
            "shake_mode": self.router.pick_shake_mode(
                scene_mode=scene_mode,
                physical_state={"pending_confirmation": pending_confirmation},
                daily_shake_state=dict(daily_shake_state),
            ),
            "blocked_reasons": blocked_reasons,
            "hold_blocked_reason": hold_blocked_reason,
            "tap_blocked_reason": tap_blocked_reason,
            "shake_blocked_reason": shake_blocked_reason,
            "pending_action_title": pending_action_title,
            "pending_action_kind": pending_action_kind,
            "history": history,
            "debug": {
                "pending_confirmation": pending_confirmation,
                "pending_device_command": pending_command,
                "high_priority_pending": high_priority_pending,
                "speech_busy": speech_busy,
            },
        }

    async def _handle_tap(
        self,
        payload: Mapping[str, Any],
        *,
        snapshot: Mapping[str, Any],
        computer_control_state: Mapping[str, Any] | None,
        metadata: Mapping[str, Any],
        current_task: Mapping[str, Any] | None,
    ) -> dict[str, Any]:
        physical = snapshot.get("physical_interaction") or {}
        try:
            tap_count = int(payload.get("tap_count") or 0)
        except (TypeError, ValueError):
            tap_count = 0

        if tap_count not in {1, 2, 3}:
            return self._blocked_result(
                interaction_kind="tap",
                mode="blocked",
                title="拍一拍",
                display_text="当前只支持 1 / 2 / 3 连拍。",
                blocked_reason="invalid_tap_count",
                metadata=metadata,
            )

        if tap_count == 3:
            if not current_task and not bool(physical.get("speech_busy")):
                return self._blocked_result(
                    interaction_kind="tap",
                    mode="interrupt",
                    title="打断",
                    display_text="当前没有可打断的流程。",
                    blocked_reason="no_active_operation",
                    metadata=metadata,
                )
            return build_physical_interaction_result(
                interaction_kind="tap",
                mode="interrupt",
                title="打断",
                short_result="interrupted",
                display_text="已请求打断当前流程。",
                voice_text="已请求打断当前流程。",
                animation_hint="interrupt",
                led_hint="blue",
                approval_source="physical_tap_thrice",
                history_entry={"tap_count": tap_count},
                metadata=dict(metadata),
            )

        if not physical.get("tap_available"):
            return self._blocked_result(
                interaction_kind="tap",
                mode="blocked",
                title="拍一拍确认",
                display_text="当前没有可用的拍一拍确认上下文。",
                blocked_reason=str(physical.get("tap_blocked_reason") or "tap_unavailable"),
                metadata=metadata,
            )

        pending_actions = self._pending_actions(computer_control_state or self.computer_state_provider() or {})
        if not pending_actions:
            return self._blocked_result(
                interaction_kind="tap",
                mode="blocked",
                title="拍一拍确认",
                display_text="当前没有待确认动作。",
                blocked_reason="no_pending_confirmation",
                metadata=metadata,
            )

        action = pending_actions[0]
        action_id = str(action.get("action_id") or "").strip()
        action_kind = str(action.get("kind") or action.get("action") or "").strip() or None
        action_title = str(action.get("title") or action_kind or "待确认动作")
        if not action_id:
            return self._blocked_result(
                interaction_kind="tap",
                mode="blocked",
                title="拍一拍确认",
                display_text="当前待确认动作缺少标识，暂时无法处理。",
                blocked_reason="invalid_pending_action",
                metadata=metadata,
            )

        if tap_count == 1:
            try:
                result = await self.confirm_computer_action(action_id)
            except Exception:
                return self._blocked_result(
                    interaction_kind="tap",
                    mode="blocked",
                    title="允许执行",
                    display_text="允许执行失败，请在应用内重试。",
                    blocked_reason="confirm_failed",
                    metadata=metadata,
                )
            result_metadata = self._normalize_action_result_metadata(result)
            action_kind = result_metadata.get("kind") or action_kind
            display_text = "已允许继续执行待确认动作。"
            voice_text = "已允许继续执行待确认动作。"
            if action_kind == "wechat_prepare_message":
                display_text = "已允许继续准备微信消息，仍需你手动确认发送。"
                voice_text = "已允许继续准备微信消息，仍需你手动确认发送。"
            return build_physical_interaction_result(
                interaction_kind="tap",
                mode="allow",
                title="允许执行",
                short_result="allowed",
                display_text=display_text,
                voice_text=voice_text,
                animation_hint="affirm",
                led_hint="green",
                approval_source="physical_tap_once",
                history_entry={
                    "tap_count": tap_count,
                    "action_id": action_id,
                    "action_title": action_title,
                },
                metadata={
                    **dict(metadata),
                    "action_id": action_id,
                    "action_kind": action_kind,
                    **result_metadata,
                },
            )

        try:
            result = await self.cancel_computer_action(action_id)
        except Exception:
            return self._blocked_result(
                interaction_kind="tap",
                mode="blocked",
                title="拒绝执行",
                display_text="拒绝执行失败，请在应用内重试。",
                blocked_reason="cancel_failed",
                metadata=metadata,
            )
        result_metadata = self._normalize_action_result_metadata(result)
        return build_physical_interaction_result(
            interaction_kind="tap",
            mode="reject",
            title="拒绝执行",
            short_result="rejected",
            display_text=f"已拒绝：{action_title}",
            voice_text="已拒绝待确认动作。",
            animation_hint="deny",
            led_hint="amber",
            approval_source="physical_tap_twice",
            history_entry={
                "tap_count": tap_count,
                "action_id": action_id,
                "action_title": action_title,
            },
            metadata={
                **dict(metadata),
                "action_id": action_id,
                "action_kind": action_kind,
                **result_metadata,
            },
        )

    def _handle_shake(
        self,
        payload: Mapping[str, Any],
        *,
        snapshot: Mapping[str, Any],
        session_id: str,
        metadata: Mapping[str, Any],
    ) -> dict[str, Any]:
        physical = snapshot.get("physical_interaction") or {}
        blocked_reason = str(physical.get("shake_blocked_reason") or "")
        if not physical.get("shake_available"):
            return self._blocked_result(
                interaction_kind="shake",
                mode="blocked",
                title="摇一摇",
                display_text="当前场景或设备状态不适合摇一摇。",
                blocked_reason=blocked_reason or "shake_unavailable",
                metadata=metadata,
            )
        result = self.router.route_shake(
            session_id=session_id,
            scene_mode=str(snapshot.get("active_scene_mode") or DEFAULT_SCENE_MODE),
            physical_state=dict(physical),
            daily_shake_state=dict(snapshot.get("daily_shake_state") or {}),
            requested_mode=clean_optional_string(payload.get("mode")),
        )
        merged_metadata = dict(metadata)
        merged_metadata["interaction_surface"] = "physical_device"
        result_metadata = dict(result.get("metadata") or {})
        result["metadata"] = {**merged_metadata, **result_metadata}
        return result

    def _handle_hold(
        self,
        payload: Mapping[str, Any],
        *,
        snapshot: Mapping[str, Any],
        metadata: Mapping[str, Any],
    ) -> dict[str, Any]:
        physical = snapshot.get("physical_interaction") or {}
        action = str(payload.get("action") or "long_press").strip() or "long_press"
        feedback_mode = clean_optional_string(payload.get("feedback_mode"))
        operation_status = clean_optional_string(payload.get("operation_status"))
        payload_blocked_reason = clean_optional_string(payload.get("blocked_reason"))
        if not physical.get("hold_available"):
            return self._blocked_result(
                interaction_kind="hold",
                mode="blocked",
                title="按住说话",
                display_text="桌面麦克风当前不可用。",
                blocked_reason=str(physical.get("hold_blocked_reason") or "hold_unavailable"),
                feedback_mode=feedback_mode,
                metadata=metadata,
            )
        if operation_status == "failed":
            return self._blocked_result(
                interaction_kind="hold",
                mode="blocked",
                title="按住说话",
                display_text="桌面麦克风当前不可用。",
                blocked_reason=payload_blocked_reason or "hold_operation_failed",
                feedback_mode=feedback_mode,
                metadata=metadata,
            )
        mode = "push_to_talk_stop" if action == "long_release" else "push_to_talk_start"
        display_text = "桌面麦克风按住说话已接管。"
        if mode == "push_to_talk_stop":
            display_text = "桌面麦克风按住说话已结束。"
        return build_physical_interaction_result(
            interaction_kind="hold",
            mode=mode,
            title="按住说话",
            short_result="ready",
            display_text=display_text,
            voice_text=None,
            feedback_mode=feedback_mode,
            history_entry={"action": action, "capture_source": "desktop_mic"},
            metadata={**dict(metadata), "capture_source": "desktop_mic"},
        )

    def _resolve_desktop_snapshot(self, voice_runtime: Mapping[str, Any] | None) -> dict[str, Any]:
        if isinstance(voice_runtime, Mapping):
            desktop = voice_runtime.get("desktop_bridge")
            if isinstance(desktop, Mapping):
                return dict(desktop)
            if "ready" in voice_runtime or "status" in voice_runtime:
                return dict(voice_runtime)
        snapshot = self.desktop_voice_snapshot_provider() or {}
        return dict(snapshot)

    @staticmethod
    def _pending_actions(computer_control_state: Mapping[str, Any] | None) -> list[dict[str, Any]]:
        payload = (computer_control_state or {}).get("pending_actions")
        if not isinstance(payload, list):
            return []
        return [dict(item) for item in payload if isinstance(item, Mapping)]

    @staticmethod
    def _normalize_action_result_metadata(result: Mapping[str, Any] | None) -> dict[str, Any]:
        payload = dict(result or {})
        metadata = dict(payload.get("metadata") or {})
        if "result" in payload and isinstance(payload.get("result"), Mapping):
            result_payload = dict(payload["result"])
            metadata.setdefault("delivery_mode", result_payload.get("delivery_mode"))
            metadata.setdefault("prepared", result_payload.get("prepared"))
        metadata.setdefault("status", payload.get("status"))
        metadata.setdefault("kind", payload.get("kind"))
        return {key: value for key, value in metadata.items() if value is not None}

    @staticmethod
    def _blocked_result(
        *,
        interaction_kind: str,
        mode: str,
        title: str,
        display_text: str,
        blocked_reason: str,
        feedback_mode: str | None = None,
        metadata: Mapping[str, Any],
    ) -> dict[str, Any]:
        return build_physical_interaction_result(
            interaction_kind=interaction_kind,
            mode=mode,
            title=title,
            short_result="blocked",
            display_text=display_text,
            voice_text=display_text,
            animation_hint="idle",
            feedback_mode=feedback_mode,
            metadata={**dict(metadata), "blocked_reason": blocked_reason},
            history_entry={"blocked_reason": blocked_reason},
        )

    @staticmethod
    def _normalize_persona_profile_payload(value: Any) -> dict[str, Any]:
        profile_preset = normalize_persona_profile(value) or normalize_persona_profile(None)
        extra_fields: Mapping[str, Any] | None = value if isinstance(value, Mapping) else None
        return build_persona_profile(profile_preset, persona_fields=extra_fields)
