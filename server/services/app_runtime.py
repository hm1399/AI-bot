from __future__ import annotations

import asyncio
from collections import deque
from copy import deepcopy
from dataclasses import dataclass
import hmac
import inspect
import ipaddress
import json
import re
import uuid
from datetime import date, datetime
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web
from loguru import logger

from channels.device_channel import DEVICE_CHANNEL, DEVICE_CHAT_ID, DeviceChannel
from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.session.manager import Session, SessionManager
from nanobot.utils.atomic_write import atomic_write_text
from services.app_api import (
    AppResourceService,
    ResourceNotFoundError,
    ResourceValidationError,
    SettingsService,
)
from services.computer_control import ComputerControlError, ComputerControlService
from services.experience import ExperienceService
from services.planning import (
    PlanningBundleService,
    PlanningProjectionService,
    PlanningSummaryService,
)
from services.reminder_scheduler import ReminderScheduler


_EXPERIENCE_COMMAND_VERB_RE = re.compile(
    r"(切换|切到|切成|换成|换到|改成|改为|调成|设为|设置为|变成|进入|用)"
)
_SCENE_COMMAND_ALIASES: tuple[tuple[str, str, str], ...] = (
    ("专注模式", "focus", "专注模式"),
    ("focusmode", "focus", "专注模式"),
    ("下班模式", "offwork", "下班模式"),
    ("休息模式", "offwork", "下班模式"),
    ("offworkmode", "offwork", "下班模式"),
    ("会议模式", "meeting", "会议模式"),
    ("开会模式", "meeting", "会议模式"),
    ("meetingmode", "meeting", "会议模式"),
)
_SCENE_COMMAND_CONTEXT_ALIASES: tuple[tuple[str, str, str], ...] = (
    ("专注", "focus", "专注模式"),
    ("工作", "focus", "专注模式"),
    ("办公", "focus", "专注模式"),
    ("学习", "focus", "专注模式"),
    ("focus", "focus", "专注模式"),
    ("下班", "offwork", "下班模式"),
    ("休息", "offwork", "下班模式"),
    ("休闲", "offwork", "下班模式"),
    ("放松", "offwork", "下班模式"),
    ("生活", "offwork", "下班模式"),
    ("offwork", "offwork", "下班模式"),
    ("会议", "meeting", "会议模式"),
    ("开会", "meeting", "会议模式"),
    ("会中", "meeting", "会议模式"),
    ("meeting", "meeting", "会议模式"),
)
_PERSONA_COMMAND_ALIASES: tuple[tuple[str, str, str], ...] = (
    ("专注简洁人格", "focus_brief", "专注简洁"),
    ("专注简洁", "focus_brief", "专注简洁"),
    ("专注人格", "focus_brief", "专注简洁"),
    ("工作助手", "focus_brief", "专注简洁"),
    ("简洁助手", "focus_brief", "专注简洁"),
    ("focusbrief", "focus_brief", "专注简洁"),
    ("温暖陪伴人格", "companion_warm", "温暖陪伴"),
    ("温暖陪伴模式", "companion_warm", "温暖陪伴"),
    ("温暖陪伴", "companion_warm", "温暖陪伴"),
    ("陪伴模式", "companion_warm", "温暖陪伴"),
    ("暖心陪伴", "companion_warm", "温暖陪伴"),
    ("陪伴人格", "companion_warm", "温暖陪伴"),
    ("陪伴助手", "companion_warm", "温暖陪伴"),
    ("温暖助手", "companion_warm", "温暖陪伴"),
    ("companionwarm", "companion_warm", "温暖陪伴"),
    ("会议简洁人格", "meeting_brief", "会议简洁"),
    ("会议简洁", "meeting_brief", "会议简洁"),
    ("会议人格", "meeting_brief", "会议简洁"),
    ("会议助手", "meeting_brief", "会议简洁"),
    ("开会助手", "meeting_brief", "会议简洁"),
    ("meetingbrief", "meeting_brief", "会议简洁"),
    ("默认人格", "balanced", "平衡人格"),
    ("默认助手", "balanced", "平衡人格"),
    ("标准助手", "balanced", "平衡人格"),
    ("平衡人格", "balanced", "平衡人格"),
    ("平衡", "balanced", "平衡人格"),
    ("balanced", "balanced", "平衡人格"),
)
_ALLOWED_SCRIPTS_CONTRACT_VERSION = "object_map_v1"


@dataclass(frozen=True)
class _DevicePairingTransport:
    port: int
    secure: bool
    source: str


def _invoke_with_storage_support(factory: Any, *args: Any, storage_config: dict[str, Any] | None = None, **kwargs: Any) -> Any:
    """Call a constructor with storage_config only when it explicitly supports it."""
    try:
        signature = inspect.signature(factory)
    except (TypeError, ValueError):
        signature = None
    if storage_config and signature is not None and "storage_config" in signature.parameters:
        kwargs["storage_config"] = dict(storage_config)
    return factory(*args, **kwargs)


class AppRuntimeService:
    """Flutter App 本地局域网 API、事件流与共享运行态服务。"""

    def __init__(
        self,
        cfg: dict[str, Any],
        *,
        bus: MessageBus,
        sessions: SessionManager,
        device_channel: DeviceChannel,
        desktop_voice_service: Any | None = None,
        computer_control_service: ComputerControlService | None = None,
        version: str,
        start_time: float,
        agent_runtime: Any | None = None,
    ) -> None:
        self.cfg = cfg
        self.bus = bus
        self.sessions = sessions
        self.device_channel = device_channel
        self.desktop_voice_service = desktop_voice_service
        self.version = version
        self.start_time = start_time
        self.agent_runtime = agent_runtime
        self.auth_token = cfg.get("app", {}).get("auth_token", "").strip()
        self.default_session_id = cfg.get("app", {}).get("default_session_id", "app:main")
        self._active_app_session_id = self.default_session_id
        self.event_buffer_size = self._coerce_positive_int(
            cfg.get("app", {}).get("event_buffer_size"),
            default=500,
        )
        self.event_replay_limit = self._coerce_positive_int(
            cfg.get("app", {}).get("event_replay_limit"),
            default=200,
        )
        self._lock = asyncio.Lock()
        self._ws_clients: set[web.WebSocketResponse] = set()
        self._slow_client_drops = 0
        self._tasks: dict[str, dict[str, Any]] = {}
        self._task_order: list[str] = []
        self._event_history: deque[dict[str, Any]] = deque(maxlen=self.event_buffer_size)
        self._runtime_dir = self.sessions.workspace / "runtime"
        self._runtime_dir.mkdir(parents=True, exist_ok=True)
        self._storage_config = dict(cfg.get("storage") or {})
        self._todo_summary_path = self._runtime_dir / "todo_summary.json"
        self._calendar_summary_path = self._runtime_dir / "calendar_summary.json"
        self._todo_summary = self._load_summary_file(
            self._todo_summary_path,
            self._default_todo_summary(),
        )
        self._calendar_summary = self._load_summary_file(
            self._calendar_summary_path,
            self._default_calendar_summary(),
        )
        self.settings = SettingsService(self.cfg, self._runtime_dir)
        self.experience_service = _invoke_with_storage_support(
            ExperienceService,
            self.settings,
            self.sessions,
            self._runtime_dir,
            storage_config=self._storage_config,
        )
        self.resources = _invoke_with_storage_support(
            AppResourceService,
            self._runtime_dir,
            storage_config=self._storage_config,
        )
        self.computer_control_service = computer_control_service or ComputerControlService(
            self.cfg,
            runtime_dir=self._runtime_dir,
        )
        self.computer_control_service.set_event_callback(self.on_computer_action_event)
        self.planning_bundle_service = PlanningBundleService(self.resources)
        self.planning_projection_service = PlanningProjectionService()
        self.planning_summary_service = PlanningSummaryService()
        self.reminder_scheduler = ReminderScheduler(
            self.resources,
            event_observer=self,
        )
        self.experience_service.configure_runtime(
            active_session_id_resolver=self.get_active_app_session_id,
            device_snapshot_provider=self.device_channel.get_snapshot,
            desktop_voice_snapshot_provider=self._desktop_voice_runtime,
            computer_state_provider=self._computer_control_runtime_state,
            notifications_provider=self.resources.list_notifications,
            confirm_computer_action=self.computer_control_service.confirm_action,
            cancel_computer_action=self.computer_control_service.cancel_action,
        )
        self.device_channel.set_active_app_session_resolver(self.get_active_app_session_id)
        if hasattr(self.device_channel, "set_physical_interaction_handler"):
            self.device_channel.set_physical_interaction_handler(self._handle_physical_interaction)
        if self.desktop_voice_service is not None:
            self.desktop_voice_service.set_active_app_session_resolver(
                self.get_active_app_session_id,
            )

    def register_routes(self, app: web.Application) -> None:
        """注册 Flutter App 的 HTTP / WebSocket 接口。"""
        app.router.add_get("/api/app/v1/bootstrap", self.handle_bootstrap)
        app.router.add_get("/api/app/v1/settings", self.handle_get_settings)
        app.router.add_put("/api/app/v1/settings", self.handle_put_settings)
        app.router.add_post("/api/app/v1/settings/llm/test", self.handle_test_llm_settings)
        app.router.add_get("/api/app/v1/experience", self.handle_get_experience)
        app.router.add_patch("/api/app/v1/experience", self.handle_patch_experience)
        app.router.add_post("/api/app/v1/experience/interactions", self.handle_post_experience_interaction)
        app.router.add_get("/api/app/v1/sessions", self.handle_list_sessions)
        app.router.add_post("/api/app/v1/sessions", self.handle_create_session)
        app.router.add_post("/api/app/v1/sessions/active", self.handle_set_active_session)
        app.router.add_get("/api/app/v1/sessions/{session_id}", self.handle_get_session)
        app.router.add_patch("/api/app/v1/sessions/{session_id}", self.handle_patch_session)
        app.router.add_get("/api/app/v1/sessions/{session_id}/messages", self.handle_get_messages)
        app.router.add_post("/api/app/v1/sessions/{session_id}/messages", self.handle_post_message)
        app.router.add_get("/api/app/v1/tasks", self.handle_list_tasks)
        app.router.add_post("/api/app/v1/tasks", self.handle_create_task)
        app.router.add_patch("/api/app/v1/tasks/{task_id}", self.handle_patch_task)
        app.router.add_delete("/api/app/v1/tasks/{task_id}", self.handle_delete_task)
        app.router.add_get("/api/app/v1/events", self.handle_list_events)
        app.router.add_post("/api/app/v1/events", self.handle_create_event)
        app.router.add_patch("/api/app/v1/events/{event_id}", self.handle_patch_event)
        app.router.add_delete("/api/app/v1/events/{event_id}", self.handle_delete_event)
        app.router.add_get("/api/app/v1/notifications", self.handle_list_notifications)
        app.router.add_patch("/api/app/v1/notifications/{notification_id}", self.handle_patch_notification)
        app.router.add_post("/api/app/v1/notifications/read-all", self.handle_read_all_notifications)
        app.router.add_delete("/api/app/v1/notifications/{notification_id}", self.handle_delete_notification)
        app.router.add_delete("/api/app/v1/notifications", self.handle_delete_notifications)
        app.router.add_get("/api/app/v1/reminders", self.handle_list_reminders)
        app.router.add_post("/api/app/v1/reminders", self.handle_create_reminder)
        app.router.add_patch("/api/app/v1/reminders/{reminder_id}", self.handle_patch_reminder)
        app.router.add_post("/api/app/v1/reminders/{reminder_id}/actions", self.handle_post_reminder_action)
        app.router.add_post("/api/app/v1/reminders/{reminder_id}/snooze", self.handle_snooze_reminder)
        app.router.add_post("/api/app/v1/reminders/{reminder_id}/complete", self.handle_complete_reminder)
        app.router.add_delete("/api/app/v1/reminders/{reminder_id}", self.handle_delete_reminder)
        app.router.add_post("/api/app/v1/planning/bundles", self.handle_create_planning_bundle)
        app.router.add_get("/api/app/v1/planning/overview", self.handle_planning_overview)
        app.router.add_get("/api/app/v1/planning/timeline", self.handle_planning_timeline)
        app.router.add_get("/api/app/v1/planning/conflicts", self.handle_planning_conflicts)
        app.router.add_get("/api/app/v1/runtime/state", self.handle_runtime_state)
        app.router.add_post("/api/app/v1/runtime/stop", self.handle_runtime_stop)
        app.router.add_get("/api/app/v1/runtime/todo-summary", self.handle_todo_summary)
        app.router.add_post("/api/app/v1/runtime/todo-summary", self.handle_set_todo_summary)
        app.router.add_get("/api/app/v1/runtime/calendar-summary", self.handle_calendar_summary)
        app.router.add_post("/api/app/v1/runtime/calendar-summary", self.handle_set_calendar_summary)
        app.router.add_get("/api/app/v1/computer/state", self.handle_computer_state)
        app.router.add_post("/api/app/v1/computer/actions", self.handle_create_computer_action)
        app.router.add_post("/api/app/v1/computer/actions/{action_id}/confirm", self.handle_confirm_computer_action)
        app.router.add_post("/api/app/v1/computer/actions/{action_id}/cancel", self.handle_cancel_computer_action)
        app.router.add_get("/api/app/v1/computer/actions/recent", self.handle_list_recent_computer_actions)
        app.router.add_get("/api/app/v1/device", self.handle_device)
        app.router.add_post("/api/app/v1/device/pairing/bundle", self.handle_device_pairing_bundle)
        app.router.add_post("/api/app/v1/device/speak", self.handle_device_speak)
        app.router.add_post("/api/app/v1/device/commands", self.handle_device_command)
        app.router.add_get("/api/app/v1/capabilities", self.handle_capabilities)
        app.router.add_get("/ws/app/v1/events", self.handle_events_ws)

    async def start_background_tasks(self) -> None:
        await self.reminder_scheduler.start()
        await self.refresh_planning_state()

    async def stop_background_tasks(self) -> None:
        await self.reminder_scheduler.stop()

    async def on_inbound_published(self, msg: InboundMessage) -> None:
        """观察 inbound 队列，登记任务与 App 用户消息。"""
        if msg.channel == "system" or msg.content.strip().lower().startswith("/"):
            return

        now = self._now_iso()
        app_session_id = self._app_session_id_from_message(msg)
        msg.metadata = self.experience_service.inject_message_metadata(
            msg.metadata,
            session_id=app_session_id,
            interaction_kind=str(msg.metadata.get("interaction_kind") or "").strip() or None,
            interaction_mode=str(msg.metadata.get("interaction_mode") or "").strip() or None,
            approval_source=str(msg.metadata.get("approval_source") or "").strip() or None,
        )
        session_payload: dict[str, Any] | None = None
        async with self._lock:
            msg.metadata.setdefault("task_id", self._new_id("task"))
            task_id = msg.metadata["task_id"]
            msg.metadata.setdefault("message_id", self._new_id("msg"))
            if app_session_id:
                self._active_app_session_id = self._ensure_app_session(app_session_id).key
                msg.metadata.setdefault("assistant_message_id", self._new_id("msg"))
                session_payload = self._maybe_auto_title_session_unlocked(
                    app_session_id,
                    msg.content,
                )

            task = self._tasks.get(task_id)
            if task is None:
                task = {
                    "task_id": task_id,
                    "kind": "chat",
                    "source_channel": msg.channel,
                    "source_session_id": app_session_id or self._session_id_for(msg.channel, msg.chat_id),
                    "source_chat_id": msg.chat_id,
                    "summary": self._summarize(msg.content),
                    "stage": "queued",
                    "status": "queued",
                    "cancellable": True,
                    "created_at": now,
                    "started_at": None,
                    "updated_at": now,
                }
                self._tasks[task_id] = task
                self._task_order.append(task_id)
            else:
                task["updated_at"] = now

            queue_payload = self._build_queue_event_payload_unlocked()
            session_id = task["source_session_id"]
            user_message = None
            if app_session_id:
                user_message = self._build_message_payload(
                    message_id=msg.metadata["message_id"],
                    session_id=session_id,
                    role="user",
                    content=msg.content,
                    status="pending",
                    created_at=now,
                    metadata=self._session_message_metadata(msg.metadata, task_id),
                )

        await self._broadcast_event(
            "runtime.task.queue_changed",
            payload=queue_payload,
            scope="global",
        )
        if session_payload is not None:
            await self._broadcast_event(
                "session.updated",
                payload={"session": session_payload},
                scope="global",
                session_id=session_payload["session_id"],
            )
        if user_message is not None:
            await self._broadcast_event(
                "session.message.created",
                payload={"message": user_message},
                scope="session",
                session_id=session_id,
                task_id=task_id,
            )

    async def on_outbound_published(self, msg: OutboundMessage) -> None:
        """观察 outbound 队列，转成 App 实时事件与运行态更新。"""
        task_id = msg.metadata.get("task_id")
        if not task_id or not msg.content:
            return

        session_id = self._app_session_id_from_metadata(msg.metadata)
        if not session_id and msg.channel == "app":
            session_id = self._session_id_for(msg.channel, msg.chat_id)
        if msg.metadata.get("_progress"):
            kind = "tool_hint" if msg.metadata.get("_tool_hint") else "thinking"
            async with self._lock:
                task = self._tasks.get(task_id)
                if task is not None:
                    task["stage"] = kind
                    task["summary"] = self._summarize(msg.content)
                    task["updated_at"] = self._now_iso()
                current_payload = self._build_current_task_event_payload_unlocked()

            if session_id:
                await self._broadcast_event(
                    "session.message.progress",
                    payload={
                        "message_id": msg.metadata.get("assistant_message_id"),
                        "kind": kind,
                        "content": msg.content,
                        "tool_hint": bool(msg.metadata.get("_tool_hint")),
                        "metadata": self._session_message_metadata(msg.metadata, task_id),
                    },
                    scope="session",
                    session_id=session_id,
                    task_id=task_id,
                )
            await self._broadcast_event(
                "runtime.task.current_changed",
                payload=current_payload,
                scope="global",
                task_id=task_id,
            )
            return

        if session_id:
            await self._broadcast_event(
                "session.message.completed",
                payload={
                    "message": self._build_message_payload(
                        message_id=msg.metadata.get("assistant_message_id")
                        or msg.metadata.get("message_id")
                        or self._new_id("msg"),
                        session_id=session_id,
                        role="assistant",
                        content=msg.content,
                        status="completed",
                        created_at=self._now_iso(),
                        metadata=self._session_message_metadata(msg.metadata, task_id),
                    )
                },
                scope="session",
                session_id=session_id,
                task_id=task_id,
            )

    async def on_task_started(self, *, msg: InboundMessage, session_key: str) -> None:
        """Agent 开始实际处理任务。"""
        if msg.channel == "system" or msg.content.strip().lower().startswith("/"):
            return

        async with self._lock:
            task_id = msg.metadata.get("task_id")
            if not task_id:
                return
            task = self._tasks.get(task_id)
            if task is None:
                return
            if task["status"] != "running":
                now = self._now_iso()
                task["status"] = "running"
                task["stage"] = "thinking"
                task["started_at"] = task["started_at"] or now
                task["updated_at"] = now
            current_payload = self._build_current_task_event_payload_unlocked()
            queue_payload = self._build_queue_event_payload_unlocked()

        await self._broadcast_event(
            "runtime.task.current_changed",
            payload=current_payload,
            scope="global",
            session_id=session_key,
            task_id=task_id,
        )
        await self._broadcast_event(
            "runtime.task.queue_changed",
            payload=queue_payload,
            scope="global",
            session_id=session_key,
            task_id=task_id,
        )

    async def on_task_finished(
        self,
        *,
        msg: InboundMessage,
        session_key: str,
        response: OutboundMessage | None,
    ) -> None:
        """Agent 正常结束任务。"""
        if msg.channel == "system" or msg.content.strip().lower().startswith("/"):
            return
        await self._finalize_task(msg, session_key=session_key, status="completed")

    async def on_task_failed(self, *, msg: InboundMessage, session_key: str, error: str) -> None:
        """Agent 处理失败。"""
        if msg.channel == "system" or msg.content.strip().lower().startswith("/"):
            return
        await self._finalize_task(
            msg,
            session_key=session_key,
            status="failed",
            error=error,
        )

    async def on_task_cancelled(self, *, msg: InboundMessage, session_key: str) -> None:
        """Agent 任务被取消。"""
        if msg.channel == "system" or msg.content.strip().lower().startswith("/"):
            return
        await self._finalize_task(
            msg,
            session_key=session_key,
            status="cancelled",
            error="cancelled",
        )

    async def on_device_connection_changed(self, *, connected: bool, snapshot: dict[str, Any]) -> None:
        await self._broadcast_event(
            "device.connection.changed",
            payload={
                "connected": connected,
                "reconnect_count": snapshot.get("reconnect_count", 0),
                "device": snapshot,
            },
            scope="global",
        )

    async def on_device_state_changed(
        self,
        *,
        old_state: str,
        new_state: str,
        snapshot: dict[str, Any],
    ) -> None:
        await self._broadcast_event(
            "device.state.changed",
            payload={
                "state": new_state,
                "previous_state": old_state,
                "device": snapshot,
            },
            scope="global",
        )

    async def on_device_status_updated(self, *, snapshot: dict[str, Any]) -> None:
        await self._broadcast_event(
            "device.status.updated",
            payload={
                "battery": snapshot.get("battery"),
                "wifi_rssi": snapshot.get("wifi_rssi"),
                "charging": snapshot.get("charging"),
                "device": snapshot,
            },
            scope="global",
        )

    async def on_device_command_updated(
        self,
        *,
        result: dict[str, Any],
        snapshot: dict[str, Any],
    ) -> None:
        payload = dict(result)
        payload["device"] = snapshot
        await self._broadcast_event(
            "device.command.updated",
            payload=payload,
            scope="global",
        )

    async def on_device_interaction(
        self,
        *,
        kind: str,
        data: dict[str, Any],
    ) -> None:
        await self._handle_physical_interaction(kind, data)

    async def _handle_physical_interaction(
        self,
        kind: str,
        data: dict[str, Any],
    ) -> dict[str, Any]:
        runtime = await self.get_runtime_state()
        session_id = str(data.get("app_session_id") or self.get_active_app_session_id()).strip()
        if not session_id.startswith("app:"):
            session_id = self.get_active_app_session_id()
        current_task = runtime.get("current_task") if isinstance(runtime, dict) else None
        voice_runtime = runtime.get("voice") if isinstance(runtime, dict) else None
        computer_control = runtime.get("computer_control") if isinstance(runtime, dict) else None
        device_snapshot = runtime.get("device") if isinstance(runtime, dict) else None
        result = await self.experience_service.handle_interaction(
            kind,
            data,
            current_task=current_task if isinstance(current_task, dict) else None,
            device_snapshot=device_snapshot if isinstance(device_snapshot, dict) else None,
            voice_runtime=voice_runtime if isinstance(voice_runtime, dict) else None,
            computer_control_state=computer_control if isinstance(computer_control, dict) else None,
        )
        if result.get("mode") == "interrupt":
            device_state = getattr(self.device_channel, "state", None)
            device_will_publish_stop = str(
                getattr(device_state, "value", device_state) or ""
            ).lower() == "processing"
            await self.device_channel.interrupt_current_activity(notice="")
            task_id = ""
            if isinstance(current_task, dict):
                task_id = str(current_task.get("task_id") or "").strip()
            if task_id and not device_will_publish_stop:
                await self.bus.publish_inbound(InboundMessage(
                    channel="system",
                    sender_id="device",
                    chat_id=session_id or self.get_active_app_session_id(),
                    content="/stop",
                ))
        await self._broadcast_event(
            "runtime.experience.updated",
            payload={
                "experience": await self._runtime_experience_state(
                    session_id=session_id,
                    device_snapshot=device_snapshot if isinstance(device_snapshot, dict) else None,
                    voice_runtime=voice_runtime if isinstance(voice_runtime, dict) else None,
                    computer_control_state=computer_control if isinstance(computer_control, dict) else None,
                    current_task=current_task if isinstance(current_task, dict) else None,
                )
            },
            scope="global",
            session_id=session_id,
        )
        await self._broadcast_event(
            "device.interaction.recorded",
            payload={"result": result},
            scope="global",
            session_id=session_id,
        )
        return result

    async def on_desktop_voice_state_changed(self, *, snapshot: dict[str, Any]) -> None:
        await self._broadcast_event(
            "desktop_voice.state.changed",
            payload=snapshot,
            scope="global",
        )

    async def on_desktop_voice_transcript(
        self,
        *,
        transcript: str,
        metadata: dict[str, Any],
        snapshot: dict[str, Any],
    ) -> dict[str, Any] | None:
        await self._broadcast_event(
            "desktop_voice.transcript",
            payload={
                "text": transcript,
                "metadata": metadata,
                "state": snapshot,
            },
            scope="global",
            session_id=self._app_session_id_from_metadata(metadata),
            task_id=metadata.get("task_id"),
        )
        session_id = self._app_session_id_from_metadata(metadata)
        if not session_id:
            return None
        return await self._maybe_handle_experience_command(
            session_id=session_id,
            content=transcript,
            metadata=metadata,
        )

    async def on_desktop_voice_response(
        self,
        *,
        text: str,
        snapshot: dict[str, Any],
        metadata: dict[str, Any],
    ) -> None:
        await self._broadcast_event(
            "desktop_voice.response",
            payload={
                "text": text,
                "metadata": metadata,
                "state": snapshot,
            },
            scope="global",
            session_id=self._app_session_id_from_metadata(metadata),
            task_id=metadata.get("task_id"),
        )

    async def on_desktop_voice_error(
        self,
        *,
        code: str,
        message: str,
        snapshot: dict[str, Any],
    ) -> None:
        await self._broadcast_event(
            "desktop_voice.error",
            payload={
                "code": code,
                "message": message,
                "state": snapshot,
            },
            scope="global",
        )

    async def on_computer_action_event(
        self,
        *,
        event_type: str,
        action: dict[str, Any],
    ) -> None:
        await self._broadcast_event(
            event_type,
            payload={"action": action},
            scope="global",
            session_id=str(action.get("source_session_id") or "").strip() or None,
            task_id=str(action.get("action_id") or "").strip() or None,
        )

    async def on_reminder_triggered(
        self,
        *,
        reminder: dict[str, Any],
        notification: dict[str, Any],
    ) -> None:
        await self._broadcast_event(
            "reminder.updated",
            payload={"reminder": reminder},
            scope="global",
        )
        await self._broadcast_event(
            "notification.created",
            payload={"notification": notification},
            scope="global",
        )
        await self._broadcast_event(
            "reminder.triggered",
            payload={
                "reminder": reminder,
                "notification": notification,
            },
            scope="global",
        )
        await self._maybe_deliver_reminder_device_voice(
            reminder=reminder,
            notification=notification,
        )
        await self.refresh_planning_state()

    async def _maybe_deliver_reminder_device_voice(
        self,
        *,
        reminder: dict[str, Any],
        notification: dict[str, Any],
    ) -> None:
        if not self._should_deliver_device_voice(reminder, notification):
            return
        if not self._device_available_for_reminder_voice():
            return

        deliver = getattr(self.device_channel, "deliver_external_text_response", None)
        if not callable(deliver):
            logger.warning("Device channel missing reminder voice delivery helper")
            return

        try:
            await deliver(self._reminder_voice_text(reminder, notification))
        except Exception:
            logger.exception(
                "Failed to deliver reminder voice for {}",
                reminder.get("reminder_id"),
            )

    def _reminder_delivery_modes(
        self,
        reminder: dict[str, Any],
        notification: dict[str, Any],
    ) -> set[str]:
        reminder_mode = reminder.get("delivery_mode")
        if reminder_mode is not None:
            return self._normalize_delivery_modes(reminder_mode)
        metadata = notification.get("metadata")
        if isinstance(metadata, dict):
            return self._normalize_delivery_modes(metadata.get("delivery_mode"))
        return set()

    def _should_deliver_device_voice(
        self,
        reminder: dict[str, Any],
        notification: dict[str, Any],
    ) -> bool:
        modes = self._reminder_delivery_modes(reminder, notification)
        return bool(
            modes.intersection({"device_voice", "device_voice_and_notification"})
        )

    @staticmethod
    def _normalize_delivery_modes(value: Any) -> set[str]:
        if isinstance(value, str):
            cleaned = value.strip()
            if not cleaned:
                return set()
            normalized = cleaned.lower()
            if normalized in {
                "none",
                "device_voice",
                "device_voice_and_notification",
            }:
                return {normalized}
            separators = {",", "|", ";", "\n", "\t"}
            for separator in separators:
                normalized = normalized.replace(separator, " ")
            values = {
                part.strip()
                for part in normalized.split(" ")
                if part.strip()
            }
            if "device_voice_and_notification" in values:
                values.add("device_voice")
            return values
        if isinstance(value, (list, tuple, set)):
            values = {
                str(part).strip().lower()
                for part in value
                if str(part).strip()
            }
            if "device_voice_and_notification" in values:
                values.add("device_voice")
            return values
        return set()

    def _device_available_for_reminder_voice(self) -> bool:
        snapshot_getter = getattr(self.device_channel, "get_snapshot", None)
        if callable(snapshot_getter):
            try:
                snapshot = snapshot_getter() or {}
            except Exception:
                logger.exception("Failed to read device snapshot for reminder voice delivery")
            else:
                if bool(snapshot.get("connected")):
                    return True
        return bool(getattr(self.device_channel, "connected", False))

    @staticmethod
    def _reminder_voice_text(
        reminder: dict[str, Any],
        notification: dict[str, Any],
    ) -> str:
        title = (
            str(reminder.get("title") or notification.get("title") or "").strip()
            or "Reminder"
        )
        message = str(
            reminder.get("message") or notification.get("message") or ""
        ).strip()
        return message or title

    async def handle_bootstrap(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        self._ensure_app_session(self.default_session_id, title="主对话")
        return self._ok({
            "server_version": self.version,
            "capabilities": self._capabilities(),
            "agent_runtime": self._agent_runtime_summary(),
            "experience": self.experience_service.get_catalog(),
            "planning": self._planning_bootstrap(),
            "runtime": await self.get_runtime_state(),
            "sessions": self._list_app_sessions(limit=100),
            "event_stream": {
                "type": "websocket",
                "path": "/ws/app/v1/events",
                "resume": {
                    "query": "last_event_id",
                    "replay_limit": self.event_replay_limit,
                    "latest_event_id": self._latest_event_id(),
                },
            },
        })

    async def handle_get_settings(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.settings.get_public_settings())

    async def handle_put_settings(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        try:
            settings = self.settings.update_settings(payload)
        except ValueError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)

        self.device_channel.set_weather_config(self.cfg.get("weather", {}))
        apply_results = await self._build_settings_apply_results(
            payload=payload,
            settings=settings,
        )
        settings_payload = {
            "settings": settings,
            "apply_results": apply_results,
        }

        await self._broadcast_event(
            "settings.updated",
            payload=settings_payload,
            scope="global",
        )
        return self._ok(settings_payload)

    async def handle_test_llm_settings(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        ok, result, error = await self.settings.test_llm_connection(payload)
        if ok:
            return self._ok(result)

        assert error is not None
        return self._error(error["code"], error["message"], status=error.get("status", 400))

    async def handle_get_experience(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        session_id = request.query.get("session_id", "").strip() or self.get_active_app_session_id()
        return self._ok(self.experience_service.get_experience_payload(
            session_id=session_id,
            device_snapshot=self.device_channel.get_snapshot(),
            voice_runtime=self._voice_runtime_state(),
            computer_control_state=self._computer_control_runtime_state(),
        ))

    async def handle_patch_experience(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        if not isinstance(payload, dict):
            return self._error("INVALID_ARGUMENT", "experience payload must be an object", status=400)
        scope = str(payload.get("scope") or request.query.get("scope") or "runtime").strip().lower()
        scoped_session_id = str(
            payload.get("session_id") or request.query.get("session_id") or ""
        ).strip()
        if scope not in {"", "runtime", "global"}:
            return self._error("INVALID_ARGUMENT", "unsupported experience scope", status=400)
        if scoped_session_id or scope == "session":
            return self._error(
                "INVALID_ARGUMENT",
                "use /api/app/v1/sessions/{session_id} for session experience overrides",
                status=400,
            )
        self.experience_service.apply_runtime_override(payload)
        session_id = request.query.get("session_id", "").strip() or self.get_active_app_session_id()
        experience = self.experience_service.get_experience_payload(
            session_id=session_id,
            device_snapshot=self.device_channel.get_snapshot(),
            voice_runtime=self._voice_runtime_state(),
            computer_control_state=self._computer_control_runtime_state(),
        )
        await self._broadcast_event(
            "runtime.experience.updated",
            payload={"experience": experience["experience"]},
            scope="global",
            session_id=session_id,
        )
        return self._ok(experience)

    async def handle_post_experience_interaction(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        kind = str(payload.get("kind") or payload.get("interaction_kind") or "").strip().lower()
        if not kind:
            return self._error("INVALID_ARGUMENT", "interaction kind is required", status=400)

        interaction_payload = payload.get("payload")
        if interaction_payload is None:
            interaction_payload = {
                key: value
                for key, value in payload.items()
                if key not in {"kind", "interaction_kind"}
            }
        if not isinstance(interaction_payload, dict):
            return self._error("INVALID_ARGUMENT", "interaction payload must be an object", status=400)

        session_id = str(
            interaction_payload.get("app_session_id")
            or payload.get("session_id")
            or request.query.get("session_id")
            or self.get_active_app_session_id()
        ).strip() or self.get_active_app_session_id()
        interaction_payload = dict(interaction_payload)
        if session_id.startswith("app:"):
            interaction_payload.setdefault("app_session_id", session_id)

        result = await self._handle_physical_interaction(kind, interaction_payload)
        runtime = await self.get_runtime_state()
        current_task = runtime.get("current_task") if isinstance(runtime, dict) else None
        voice_runtime = runtime.get("voice") if isinstance(runtime, dict) else None
        computer_control = runtime.get("computer_control") if isinstance(runtime, dict) else None
        device_snapshot = runtime.get("device") if isinstance(runtime, dict) else None
        experience = await self._runtime_experience_state(
            session_id=session_id,
            device_snapshot=device_snapshot if isinstance(device_snapshot, dict) else None,
            voice_runtime=voice_runtime if isinstance(voice_runtime, dict) else None,
            computer_control_state=computer_control if isinstance(computer_control, dict) else None,
            current_task=current_task if isinstance(current_task, dict) else None,
        )
        return self._ok({
            "result": result,
            "experience": experience,
        })

    async def handle_list_sessions(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        self._ensure_app_session(self.default_session_id, title="主对话")
        limit = self._parse_limit(request.query.get("limit"), default=20, maximum=100)
        archived = self._parse_bool(request.query.get("archived"))
        pinned_first = self._parse_bool(request.query.get("pinned_first"), default=True)
        sessions = self._list_app_sessions(limit=limit, archived=archived, pinned_first=pinned_first)
        return self._ok(sessions)

    async def handle_create_session(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        session_id = f"app:{uuid.uuid4().hex[:8]}"
        title = str(payload.get("title") or "").strip()
        session = self._ensure_app_session(session_id)
        if title:
            session.metadata["title"] = title
            session.metadata["title_source"] = "user"
        else:
            session.metadata["title"] = self._placeholder_title_for(session_id)
            session.metadata["title_source"] = "default"
        session.updated_at = datetime.now()
        self.sessions.save(session)
        session_updates = self._set_active_app_session(session.key)
        for item in session_updates:
            await self._broadcast_event(
                "session.updated",
                payload={"session": item},
                scope="global",
                session_id=item["session_id"],
            )
        return self._ok(self._serialize_session(session), status=201)

    async def handle_get_session(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        session_id = request.match_info["session_id"]
        valid, error = self._validate_app_session_id(session_id)
        if not valid:
            return self._error("INVALID_ARGUMENT", error, status=400)

        session = self.sessions.get(session_id)
        if session is None:
            return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)
        return self._ok(self._serialize_session(session))

    async def handle_patch_session(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        session_id = request.match_info["session_id"]
        valid, error = self._validate_app_session_id(session_id)
        if not valid:
            return self._error("INVALID_ARGUMENT", error, status=400)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        session = self.sessions.get(session_id)
        if session is None:
            return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)

        changed = False
        session_updates: dict[str, dict[str, Any]] = {}
        fallback_session_id: str | None = None
        if "title" in payload:
            title = str(payload.get("title") or "").strip()
            if not title:
                return self._error("INVALID_ARGUMENT", "title must not be empty", status=400)
            if session.metadata.get("title") != title:
                session.metadata["title"] = title
                session.metadata["title_source"] = "user"
                changed = True
        if "pinned" in payload:
            pinned = payload.get("pinned")
            if not isinstance(pinned, bool):
                return self._error("INVALID_ARGUMENT", "pinned must be a boolean", status=400)
            if bool(session.metadata.get("pinned")) != pinned:
                session.metadata["pinned"] = pinned
                changed = True
        if "archived" in payload:
            archived = payload.get("archived")
            if not isinstance(archived, bool):
                return self._error("INVALID_ARGUMENT", "archived must be a boolean", status=400)
            if bool(session.metadata.get("archived")) != archived:
                if archived:
                    fallback_session_id = self._pick_fallback_active_session(excluding=session_id)
                    if fallback_session_id is None:
                        return self._error(
                            "INVALID_STATE",
                            "keep at least one active conversation before archiving this one",
                            status=409,
                        )
                session.metadata["archived"] = archived
                changed = True
                if archived and self.get_active_app_session_id() == session_id:
                    for item in self._set_active_app_session(
                        fallback_session_id,
                    ):
                        session_updates[item["session_id"]] = item
        if payload.get("active") is not None:
            active = payload.get("active")
            if not isinstance(active, bool):
                return self._error("INVALID_ARGUMENT", "active must be a boolean", status=400)
            if active:
                if bool(session.metadata.get("archived")):
                    return self._error(
                        "INVALID_STATE",
                        "archived conversations cannot become active",
                        status=409,
                    )
                for item in self._set_active_app_session(session_id):
                    session_updates[item["session_id"]] = item
        if any(
            key in payload
            for key in ("scene_mode", "persona_profile", "persona_profile_id", "persona_fields")
        ):
            if self.experience_service.patch_session(session, payload):
                changed = True
        if not changed and not session_updates:
            return self._ok(self._serialize_session(session))

        if changed:
            session.updated_at = datetime.now()
            self.sessions.save(session)
        session_updates[session_id] = self._serialize_session(session)
        for item in session_updates.values():
            await self._broadcast_event(
                "session.updated",
                payload={"session": item},
                scope="global",
                session_id=item["session_id"],
            )
        return self._ok(session_updates[session_id])

    async def handle_set_active_session(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        session_id = str(payload.get("session_id") or "").strip()
        valid, error = self._validate_app_session_id(session_id)
        if not valid:
            return self._error("INVALID_ARGUMENT", error, status=400)

        session = self.sessions.get(session_id)
        if session is None:
            return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)
        if bool(session.metadata.get("archived")):
            return self._error(
                "INVALID_STATE",
                "archived conversations cannot become active",
                status=409,
            )

        session_updates = self._set_active_app_session(session_id)
        for item in session_updates:
            await self._broadcast_event(
                "session.updated",
                payload={"session": item},
                scope="global",
                session_id=item["session_id"],
            )
        return self._ok(
            {
                "session_id": self._active_app_session_id,
                "session": self._serialize_session(session),
            }
        )

    async def handle_get_messages(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        session_id = request.match_info["session_id"]
        valid, error = self._validate_app_session_id(session_id)
        if not valid:
            return self._error("INVALID_ARGUMENT", error, status=400)

        limit = self._parse_limit(request.query.get("limit"), default=50, maximum=200)
        before = request.query.get("before", "").strip() or None
        after = request.query.get("after", "").strip() or None
        page_loader = getattr(self.sessions, "get_messages_page", None)
        if callable(page_loader):
            try:
                page = page_loader(
                    session_id,
                    before=before,
                    after=after,
                    limit=limit,
                )
            except KeyError:
                return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)
            except ValueError as exc:
                return self._error("INVALID_ARGUMENT", str(exc), status=400)
            if isinstance(page, dict):
                return self._ok(page)

        session = self.sessions.get(session_id)
        if session is None:
            return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)

        messages = self._serialize_messages(session)
        page, error = self._paginate_messages(
            session_id=session_id,
            messages=messages,
            before=before,
            after=after,
            limit=limit,
        )
        if error:
            return self._error("INVALID_ARGUMENT", error, status=400)
        return self._ok(page)

    async def handle_post_message(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        session_id = request.match_info["session_id"]
        valid, error = self._validate_app_session_id(session_id)
        if not valid:
            return self._error("INVALID_ARGUMENT", error, status=400)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        content = str(payload.get("content") or "").strip()
        if not content:
            return self._error("INVALID_ARGUMENT", "content is required", status=400)

        session = self._ensure_app_session(session_id)
        self._active_app_session_id = session.key
        chat_id = session_id.split(":", 1)[1]
        metadata = self.experience_service.inject_message_metadata(
            {"app_session_id": session.key, "source_channel": "app"},
            session_id=session.key,
        )
        msg = InboundMessage(
            channel="app",
            sender_id="flutter",
            chat_id=chat_id,
            content=content,
            metadata=metadata,
        )
        client_message_id = str(payload.get("client_message_id") or "").strip()
        if client_message_id:
            msg.metadata["client_message_id"] = client_message_id

        command_result = await self._maybe_handle_experience_command(
            session_id=session.key,
            content=content,
            metadata=msg.metadata,
        )
        if command_result is not None:
            return self._ok({
                "accepted_message": command_result["accepted_message"],
                "assistant_message": command_result["assistant_message"],
                "task_id": command_result["task_id"],
                "queued": False,
            })

        await self.bus.publish_inbound(msg)

        return self._ok({
            "accepted_message": self._build_message_payload(
                message_id=msg.metadata["message_id"],
                session_id=session.key,
                role="user",
                content=content,
                status="pending",
                created_at=self._now_iso(),
                metadata=self._session_message_metadata(msg.metadata, msg.metadata["task_id"]),
            ),
            "task_id": msg.metadata["task_id"],
            "queued": True,
        }, status=202)

    async def handle_list_tasks(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            result = self.resources.list_tasks(
                completed=self._parse_bool(request.query.get("completed"), default=None),
                priority=request.query.get("priority", "").strip() or None,
                limit=self._parse_limit(request.query.get("limit"), default=50, maximum=200),
            )
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        return self._ok(result)

    async def handle_create_task(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            task = self.resources.create_task(
                self.planning_bundle_service.attach_metadata(
                    payload,
                    source_metadata={
                        "created_via": "app_manual",
                        "source_channel": "app",
                    },
                )
            )
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        await self.refresh_planning_state()
        await self._broadcast_event("task.created", payload={"task": task}, scope="global")
        return self._ok(task, status=201)

    async def handle_patch_task(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            task = self.resources.update_task(request.match_info["task_id"], payload)
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "task does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("task.updated", payload={"task": task}, scope="global")
        return self._ok(task)

    async def handle_delete_task(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            task = self.resources.delete_task(request.match_info["task_id"])
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "task does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("task.deleted", payload={"task": task}, scope="global")
        return self._ok({"deleted": True, "task_id": task["task_id"]})

    async def handle_list_events(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        result = self.resources.list_events(
            limit=self._parse_limit(request.query.get("limit"), default=50, maximum=200),
        )
        return self._ok(result)

    async def handle_create_event(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            event = self.resources.create_event(
                self.planning_bundle_service.attach_metadata(
                    payload,
                    source_metadata={
                        "created_via": "app_manual",
                        "source_channel": "app",
                    },
                )
            )
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        await self.refresh_planning_state()
        await self._broadcast_event("event.created", payload={"event": event}, scope="global")
        return self._ok(event, status=201)

    async def handle_patch_event(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            event = self.resources.update_event(request.match_info["event_id"], payload)
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "event does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("event.updated", payload={"event": event}, scope="global")
        return self._ok(event)

    async def handle_delete_event(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            event = self.resources.delete_event(request.match_info["event_id"])
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "event does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("event.deleted", payload={"event": event}, scope="global")
        return self._ok({"deleted": True, "event_id": event["event_id"]})

    async def handle_list_notifications(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.resources.list_notifications())

    async def handle_patch_notification(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            notification = self.resources.update_notification(
                request.match_info["notification_id"],
                payload,
            )
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "notification does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event(
            "notification.updated",
            payload={"notification": notification},
            scope="global",
        )
        return self._ok(notification)

    async def handle_read_all_notifications(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        summary = self.resources.mark_all_notifications_read()
        for item in summary.pop("changed_items"):
            await self._broadcast_event(
                "notification.updated",
                payload={"notification": item},
                scope="global",
            )
        await self.refresh_planning_state()
        return self._ok(summary)

    async def handle_delete_notification(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            notification = self.resources.delete_notification(request.match_info["notification_id"])
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "notification does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event(
            "notification.deleted",
            payload={"notification": notification},
            scope="global",
        )
        return self._ok({"deleted": True, "notification_id": notification["notification_id"]})

    async def handle_delete_notifications(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        summary = self.resources.clear_notifications()
        for item in summary["deleted_items"]:
            await self._broadcast_event(
                "notification.deleted",
                payload={"notification": item},
                scope="global",
            )
        await self.refresh_planning_state()
        return self._ok({"deleted_count": summary["deleted_count"]})

    async def handle_list_reminders(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.resources.list_reminders(
            limit=self._parse_limit(request.query.get("limit"), default=50, maximum=200),
        ))

    async def handle_create_reminder(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        try:
            reminder = self.resources.create_reminder(
                self.planning_bundle_service.attach_metadata(
                    payload,
                    source_metadata={
                        "created_via": "app_manual",
                        "source_channel": "app",
                    },
                )
            )
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        reminder = await self.reminder_scheduler.sync_reminder(reminder["reminder_id"]) or reminder
        await self.refresh_planning_state()
        await self._broadcast_event("reminder.created", payload={"reminder": reminder}, scope="global")
        return self._ok(reminder, status=201)

    async def handle_patch_reminder(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        runtime_fields = {
            "completed_at",
            "last_triggered_at",
            "next_trigger_at",
            "snoozed_until",
            "status",
        }
        if runtime_fields.intersection(payload):
            return self._error(
                "INVALID_ARGUMENT",
                "runtime reminder fields must use the reminder action endpoints",
                status=400,
            )
        try:
            reminder = self.resources.update_reminder(request.match_info["reminder_id"], payload)
        except ResourceValidationError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "reminder does not exist", status=404)
        reminder = await self.reminder_scheduler.sync_reminder(reminder["reminder_id"]) or reminder
        await self.refresh_planning_state()
        await self._broadcast_event("reminder.updated", payload={"reminder": reminder}, scope="global")
        return self._ok(reminder)

    async def handle_post_reminder_action(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        action = str(payload.get("action") or "").strip().lower()
        if action == "snooze":
            return await self.handle_snooze_reminder(request)
        if action == "complete":
            return await self.handle_complete_reminder(request)
        return self._error(
            "INVALID_ARGUMENT",
            "action must be one of: complete, snooze",
            status=400,
        )

    async def handle_delete_reminder(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            reminder = self.resources.delete_reminder(request.match_info["reminder_id"])
        except ResourceNotFoundError as exc:
            return self._error(exc.args[0], "reminder does not exist", status=404)
        await self.reminder_scheduler.sync_all()
        await self.refresh_planning_state()
        await self._broadcast_event("reminder.deleted", payload={"reminder": reminder}, scope="global")
        return self._ok({"deleted": True, "reminder_id": reminder["reminder_id"]})

    async def handle_snooze_reminder(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            payload = {}
        until = str(
            payload.get("until")
            or payload.get("snoozed_until")
            or ""
        ).strip() or None
        raw_minutes = payload.get("minutes") if "minutes" in payload else payload.get("delay_minutes")
        if raw_minutes is None:
            delay_minutes = 10
        else:
            try:
                delay_minutes = int(raw_minutes)
            except (TypeError, ValueError):
                return self._error("INVALID_ARGUMENT", "minutes must be a positive integer", status=400)
            if delay_minutes < 1:
                return self._error("INVALID_ARGUMENT", "minutes must be a positive integer", status=400)
        try:
            reminder = await self.reminder_scheduler.snooze_reminder(
                request.match_info["reminder_id"],
                snoozed_until=until,
                delay_minutes=delay_minutes,
            )
        except ValueError as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)
        if reminder is None:
            return self._error("REMINDER_NOT_FOUND", "reminder does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("reminder.updated", payload={"reminder": reminder}, scope="global")
        return self._ok(reminder)

    async def handle_complete_reminder(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        reminder = await self.reminder_scheduler.complete_reminder(request.match_info["reminder_id"])
        if reminder is None:
            return self._error("REMINDER_NOT_FOUND", "reminder does not exist", status=404)
        await self.refresh_planning_state()
        await self._broadcast_event("reminder.updated", payload={"reminder": reminder}, scope="global")
        return self._ok(reminder)

    async def handle_create_planning_bundle(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        task_payloads = list(payload.get("tasks") or [])
        event_payloads = list(payload.get("events") or [])
        reminder_payloads = list(payload.get("reminders") or [])
        notification_payloads = list(payload.get("notifications") or [])
        if isinstance(payload.get("task"), dict):
            task_payloads.append(dict(payload["task"]))
        if isinstance(payload.get("event"), dict):
            event_payloads.append(dict(payload["event"]))
        if isinstance(payload.get("reminder"), dict):
            reminder_payloads.append(dict(payload["reminder"]))
        if isinstance(payload.get("notification"), dict):
            notification_payloads.append(dict(payload["notification"]))

        if not any((task_payloads, event_payloads, reminder_payloads, notification_payloads)):
            return self._error(
                "INVALID_ARGUMENT",
                "at least one planning resource is required",
                status=400,
            )

        source_metadata = payload.get("source_metadata")
        if source_metadata is None:
            source_metadata = {}
        if not isinstance(source_metadata, dict):
            return self._error("INVALID_ARGUMENT", "source_metadata must be an object", status=400)
        merged_source_metadata = self.planning_bundle_service.build_source_metadata(
            {
                "created_via": "app_manual",
                "source_channel": "app",
                **source_metadata,
            },
            bundle_id=str(payload.get("bundle_id") or "").strip() or None,
            created_via=str(payload.get("created_via") or "").strip() or None,
            source_channel=str(payload.get("source_channel") or "").strip() or None,
            source_message_id=str(payload.get("source_message_id") or "").strip() or None,
            source_session_id=str(payload.get("source_session_id") or "").strip() or None,
            interaction_surface=str(payload.get("interaction_surface") or "").strip() or None,
            planning_surface=str(payload.get("planning_surface") or "").strip() or None,
            owner_kind=str(payload.get("owner_kind") or "").strip() or None,
            delivery_mode=str(payload.get("delivery_mode") or "").strip() or None,
            capture_source=str(payload.get("capture_source") or "").strip() or None,
            voice_path=str(payload.get("voice_path") or "").strip() or None,
            scene_mode=str(payload.get("scene_mode") or "").strip() or None,
            persona_profile_id=str(payload.get("persona_profile_id") or "").strip() or None,
            persona_voice_style=str(payload.get("persona_voice_style") or "").strip() or None,
            interaction_kind=str(payload.get("interaction_kind") or "").strip() or None,
            interaction_mode=str(payload.get("interaction_mode") or "").strip() or None,
            approval_source=str(payload.get("approval_source") or "").strip() or None,
            linked_task_id=str(payload.get("linked_task_id") or "").strip() or None,
            linked_event_id=str(payload.get("linked_event_id") or "").strip() or None,
            linked_reminder_id=str(payload.get("linked_reminder_id") or "").strip() or None,
        )

        try:
            bundle = self.planning_bundle_service.create_bundle(
                tasks=task_payloads,
                events=event_payloads,
                reminders=reminder_payloads,
                notifications=notification_payloads,
                source_metadata=merged_source_metadata,
                bundle_id=str(payload.get("bundle_id") or "").strip() or None,
            )
        except (ResourceValidationError, ValueError) as exc:
            return self._error("INVALID_ARGUMENT", str(exc), status=400)

        synced_reminders: list[dict[str, Any]] = []
        for reminder in bundle["reminders"]:
            synced = await self.reminder_scheduler.sync_reminder(reminder["reminder_id"]) or reminder
            synced_reminders.append(synced)
        bundle["reminders"] = synced_reminders

        await self.refresh_planning_state()
        for task in bundle["tasks"]:
            await self._broadcast_event("task.created", payload={"task": task}, scope="global")
        for event in bundle["events"]:
            await self._broadcast_event("event.created", payload={"event": event}, scope="global")
        for reminder in bundle["reminders"]:
            await self._broadcast_event("reminder.created", payload={"reminder": reminder}, scope="global")
        for notification in bundle["notifications"]:
            await self._broadcast_event(
                "notification.created",
                payload={"notification": notification},
                scope="global",
            )
        return self._ok(bundle, status=201)

    async def handle_planning_overview(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.get_planning_overview())

    async def handle_planning_timeline(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        target_date = request.query.get("date")
        if target_date:
            try:
                date.fromisoformat(target_date)
            except ValueError:
                return self._error("INVALID_ARGUMENT", "date must use YYYY-MM-DD", status=400)
        surface = self._normalize_planning_surface(request.query.get("surface"))
        return self._ok({
            "items": self.get_planning_timeline(
                date=target_date,
                surface=surface,
            )
        })

    async def handle_planning_conflicts(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok({"items": self.get_planning_conflicts()})

    async def handle_runtime_state(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(await self.get_runtime_state())

    async def handle_runtime_stop(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            payload = {}

        task_id = str(payload.get("task_id") or "").strip()
        async with self._lock:
            if not task_id:
                current_id = self._get_current_task_id_unlocked()
                task_id = current_id or ""
            task = self._tasks.get(task_id) if task_id else None

        if not task_id or task is None:
            return self._error("TASK_NOT_FOUND", "task does not exist", status=404)
        if not task.get("cancellable", False):
            return self._error("TASK_NOT_CANCELLABLE", "task is not cancellable", status=400)

        await self.bus.publish_inbound(InboundMessage(
            channel="system",
            sender_id="app",
            chat_id=task["source_session_id"],
            content="/stop",
        ))
        return self._ok({"task_id": task_id, "stopping": True})

    async def handle_todo_summary(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.get_todo_summary())

    async def handle_set_todo_summary(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        summary, error = await self.set_todo_summary(payload)
        if error:
            return self._error("INVALID_ARGUMENT", error, status=400)
        return self._ok(summary)

    async def handle_calendar_summary(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.get_calendar_summary())

    async def handle_set_calendar_summary(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)
        summary, error = await self.set_calendar_summary(payload)
        if error:
            return self._error("INVALID_ARGUMENT", error, status=400)
        return self._ok(summary)

    async def handle_computer_state(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.computer_control_service.get_state())

    async def handle_create_computer_action(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        kind = str(payload.get("action") or payload.get("kind") or "").strip()
        if not kind:
            return self._error("INVALID_ARGUMENT", "action is required", status=400)

        arguments = payload.get("arguments")
        if arguments is None:
            arguments = payload.get("params")
        if arguments is None:
            arguments = payload.get("target", {})
        if not isinstance(arguments, dict):
            return self._error("INVALID_ARGUMENT", "arguments must be an object", status=400)

        try:
            action = await self.computer_control_service.request_action({
                **payload,
                "action": kind,
                "arguments": arguments,
                "requested_via": str(payload.get("requested_via") or "app").strip() or "app",
                "source_session_id": str(
                    payload.get("source_session_id")
                    or payload.get("session_id")
                    or self.get_active_app_session_id()
                ).strip()
                or None,
                "reason": str(payload.get("reason") or "").strip() or None,
                "requires_confirmation": self._parse_optional_bool(payload.get("requires_confirmation")),
                "metadata": payload.get("metadata") if isinstance(payload.get("metadata"), dict) else None,
            })
        except ComputerControlError as exc:
            return self._error(exc.code, exc.message, status=exc.status)

        return self._ok(action, status=201)

    async def handle_confirm_computer_action(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            action = await self.computer_control_service.confirm_action(request.match_info["action_id"])
        except ComputerControlError as exc:
            return self._error(exc.code, exc.message, status=exc.status)
        return self._ok(action)

    async def handle_cancel_computer_action(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        try:
            action = await self.computer_control_service.cancel_action(request.match_info["action_id"])
        except ComputerControlError as exc:
            return self._error(exc.code, exc.message, status=exc.status)
        return self._ok(action)

    async def handle_list_recent_computer_actions(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        limit = self._parse_limit(request.query.get("limit"), default=20, maximum=100)
        return self._ok({
            "items": self.computer_control_service.list_recent_actions(limit=limit),
        })

    async def handle_device(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.device_channel.get_snapshot())

    async def handle_device_pairing_bundle(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        host, error = self._normalize_device_pairing_host(payload)
        if error:
            return self._error("INVALID_ARGUMENT", error, status=400)

        return self._ok({
            "transport": "serial",
            "bundle": self._build_device_pairing_bundle(host, request=request),
        })

    async def handle_device_speak(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        text = str(payload.get("text") or "").strip()
        if not text:
            return self._error("INVALID_ARGUMENT", "text is required", status=400)
        if not self.device_channel.connected:
            return self._error("DEVICE_OFFLINE", "device is offline", status=409)

        await self.device_channel.send_outbound(OutboundMessage(
            channel=DEVICE_CHANNEL,
            chat_id=DEVICE_CHAT_ID,
            content=text,
            metadata={"source": "voice"},
        ))
        return self._ok({"accepted": True, "text": text})

    async def handle_device_command(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        payload = await self._read_json(request)
        if payload is None:
            return self._error("INVALID_ARGUMENT", "invalid json body", status=400)

        command = payload.get("command")
        if not isinstance(command, str) or not command.strip():
            return self._error("INVALID_ARGUMENT", "command is required", status=400)

        params = payload.get("params", {})
        if not isinstance(params, dict):
            return self._error("INVALID_ARGUMENT", "params must be an object", status=400)
        if not self.device_channel.connected:
            return self._error("DEVICE_OFFLINE", "device is offline", status=409)

        try:
            result = await self.device_channel.execute_app_command(
                command.strip(),
                params,
                client_command_id=str(payload.get("client_command_id") or "").strip() or None,
            )
        except RuntimeError as exc:
            if str(exc) == "DEVICE_OFFLINE":
                return self._error("DEVICE_OFFLINE", "device is offline", status=409)
            raise
        except ValueError as exc:
            if str(exc) == "COMMAND_NOT_SUPPORTED":
                return self._error("COMMAND_NOT_SUPPORTED", "command is not supported", status=400)
            return self._error("INVALID_ARGUMENT", "invalid command params", status=400)

        await self._broadcast_event(
            "device.command.accepted",
            payload=result,
            scope="global",
        )
        return self._ok(result)

    async def handle_capabilities(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self._capabilities())

    async def handle_events_ws(self, request: web.Request) -> web.StreamResponse:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)
        await self._attach_event_client(
            ws,
            last_event_id=request.query.get("last_event_id", "").strip() or None,
            replay_limit=self._parse_limit(
                request.query.get("replay_limit"),
                default=self.event_replay_limit,
                maximum=max(self.event_replay_limit, self.event_buffer_size),
            ),
        )

        try:
            async for msg in ws:
                if msg.type == WSMsgType.ERROR:
                    logger.warning("App events websocket error: {}", ws.exception())
        finally:
            self._ws_clients.discard(ws)

        return ws

    async def get_runtime_state(self) -> dict[str, Any]:
        """构建共享运行态快照。"""
        async with self._lock:
            current_task_id = self._get_current_task_id_unlocked()
            current_task = self._serialize_runtime_task(self._tasks.get(current_task_id)) if current_task_id else None
            task_queue = [
                self._serialize_runtime_task(self._tasks[task_id], for_queue=True)
                for task_id in self._task_order
                if task_id in self._tasks
                and self._tasks[task_id]["status"] in {"queued", "running"}
                and task_id != current_task_id
            ]

        device_snapshot = self._device_runtime_state()
        desktop_voice = self._desktop_voice_runtime()
        voice_runtime = self._voice_runtime_state()
        computer_control = self._computer_control_runtime_state()
        return {
            "current_task": current_task,
            "task_queue": task_queue,
            "chat": {
                "active_session_id": self.get_active_app_session_id(),
            },
            "agent_runtime": self._agent_runtime_summary(),
            "computer_control": computer_control,
            "device": device_snapshot,
            "desktop_voice": desktop_voice,
            "voice": voice_runtime,
            "storage": self._storage_runtime_state(),
            "transport": self._transport_runtime_state(),
            "experience": await self._runtime_experience_state(
                session_id=self.get_active_app_session_id(),
                device_snapshot=device_snapshot,
                voice_runtime=voice_runtime,
                computer_control_state=computer_control,
                current_task=current_task,
            ),
            "reminders": {
                "scheduler_running": self.reminder_scheduler.is_running(),
            },
            "planning": self._planning_runtime_state(),
            "todo_summary": self.get_todo_summary(),
            "calendar_summary": self.get_calendar_summary(),
        }

    def get_todo_summary(self) -> dict[str, Any]:
        """返回当前 Todo 摘要快照。"""
        return dict(self._todo_summary)

    def get_calendar_summary(self) -> dict[str, Any]:
        """返回当前日历摘要快照。"""
        return dict(self._calendar_summary)

    def get_planning_overview(self) -> dict[str, Any]:
        planning = self._planning_snapshot()
        return dict(planning["overview"])

    def get_planning_timeline(
        self,
        *,
        date: str | None = None,
        surface: str | None = None,
    ) -> list[dict[str, Any]]:
        planning = self._planning_snapshot(date=date, surface=surface)
        return [dict(item) for item in planning["timeline"]]

    def get_planning_conflicts(self) -> list[dict[str, Any]]:
        planning = self._planning_snapshot()
        return [dict(item) for item in planning["conflicts"]]

    async def set_todo_summary(self, payload: dict[str, Any]) -> tuple[dict[str, Any], str | None]:
        """更新 Todo 摘要，并在变更时广播事件。"""
        async with self._lock:
            updated, error = self._normalize_todo_summary(self._todo_summary, payload)
            if error:
                return {}, error
            changed = updated != self._todo_summary
            self._todo_summary = updated
            if changed:
                self._save_summary_file(self._todo_summary_path, updated)

        if changed:
            await self._broadcast_event(
                "todo.summary.changed",
                payload=dict(updated),
                scope="global",
            )
        return dict(updated), None

    async def set_calendar_summary(self, payload: dict[str, Any]) -> tuple[dict[str, Any], str | None]:
        """更新日历摘要，并在变更时广播事件。"""
        async with self._lock:
            updated, error = self._normalize_calendar_summary(self._calendar_summary, payload)
            if error:
                return {}, error
            changed = updated != self._calendar_summary
            self._calendar_summary = updated
            if changed:
                self._save_summary_file(self._calendar_summary_path, updated)

        if changed:
            await self._broadcast_event(
                "calendar.summary.changed",
                payload=dict(updated),
                scope="global",
            )
        return dict(updated), None

    async def refresh_planning_state(self) -> None:
        changed_events = await self._refresh_summary_files_from_resources()
        for event_type, payload in changed_events:
            await self._broadcast_event(event_type, payload=payload, scope="global")
        overview = self.get_planning_overview()
        await self._broadcast_event(
            "planning.changed",
            payload={
                "updated_at": self._now_iso(),
                "counts": overview.get("counts", {}),
                "highlights": overview.get("highlights", {}),
            },
            scope="global",
        )

    async def _build_settings_apply_results(
        self,
        *,
        payload: dict[str, Any],
        settings: dict[str, Any],
    ) -> dict[str, Any]:
        results: dict[str, Any] = {}
        save_and_apply_fields = {
            "device_volume",
            "led_enabled",
            "led_brightness",
            "led_color",
        }
        config_only_fields = {
            "led_mode",
            "wake_word",
            "auto_listen",
        }
        experience_applied_fields = {
            "default_scene_mode",
            "persona_tone_style",
            "persona_reply_length",
            "persona_proactivity",
            "persona_voice_style",
            "physical_interaction_enabled",
            "shake_enabled",
            "tap_confirmation_enabled",
        }

        for field in payload:
            if field in save_and_apply_fields:
                results[field] = await self._apply_device_setting(
                    field=field,
                    value=settings.get(field),
                )
            elif field in config_only_fields:
                results[field] = {
                    "mode": "config_only",
                    "status": "saved_only",
                    "reason": "config_saved_but_not_runtime_applied",
                }
            elif field in experience_applied_fields:
                results[field] = {
                    "mode": "runtime_applied",
                    "status": "applied",
                }
        return results

    async def _apply_device_setting(
        self,
        *,
        field: str,
        value: Any,
    ) -> dict[str, Any]:
        if field == "device_volume":
            command = "set_volume"
            params = {"level": int(value)}
        elif field == "led_enabled":
            command = "toggle_led"
            params = {"enabled": bool(value)}
        elif field == "led_brightness":
            command = "set_led_brightness"
            params = {"level": int(value)}
        elif field == "led_color":
            command = "set_led_color"
            params = {"color": str(value)}
        else:
            return {
                "mode": "save_and_apply",
                "status": "failed",
                "reason": "unsupported_command",
            }
        if not self.device_channel.connected:
            return {
                "mode": "save_and_apply",
                "status": "saved_only",
                "reason": "device_offline",
                "command": command,
            }

        client_command_id = f"settings_{field}_{uuid.uuid4().hex[:8]}"
        try:
            result = await self.device_channel.execute_app_command(
                command,
                params,
                client_command_id=client_command_id,
            )
        except RuntimeError as exc:
            reason = "device_offline" if str(exc) == "DEVICE_OFFLINE" else "apply_failed"
            return {
                "mode": "save_and_apply",
                "status": "saved_only" if reason == "device_offline" else "failed",
                "reason": reason,
                "command": command,
            }
        except ValueError as exc:
            reason = "unsupported_command" if str(exc) == "COMMAND_NOT_SUPPORTED" else "invalid_argument"
            return {
                "mode": "save_and_apply",
                "status": "failed",
                "reason": reason,
                "command": command,
            }

        await self._broadcast_event(
            "device.command.accepted",
            payload=result,
            scope="global",
        )
        return {
            "mode": "save_and_apply",
            "status": "pending",
            "reason": None,
            "command": command,
            "command_id": result.get("command_id"),
            "client_command_id": result.get("client_command_id"),
        }

    async def _finalize_task(
        self,
        msg: InboundMessage,
        *,
        session_key: str,
        status: str,
        error: str | None = None,
    ) -> None:
        async with self._lock:
            task_id = msg.metadata.get("task_id")
            if not task_id:
                return
            task = self._tasks.get(task_id)
            if task is None:
                return
            task["status"] = status
            task["stage"] = status
            task["updated_at"] = self._now_iso()
            current_payload = self._build_current_task_event_payload_unlocked()
            queue_payload = self._build_queue_event_payload_unlocked()
            should_emit_failed = bool(self._app_session_id_from_message(msg)) and status in {"failed", "cancelled"}
            session_id = task["source_session_id"]

        await self._broadcast_event(
            "runtime.task.current_changed",
            payload=current_payload,
            scope="global",
            session_id=session_key,
            task_id=msg.metadata.get("task_id"),
        )
        await self._broadcast_event(
            "runtime.task.queue_changed",
            payload=queue_payload,
            scope="global",
            session_id=session_key,
            task_id=msg.metadata.get("task_id"),
        )

        if should_emit_failed:
            await self._broadcast_event(
                "session.message.failed",
                payload={
                    "message_id": msg.metadata.get("assistant_message_id"),
                    "reason": error or status,
                },
                scope="session",
                session_id=session_id,
                task_id=msg.metadata.get("task_id"),
            )

    async def _broadcast_event(
        self,
        event_type: str,
        *,
        payload: dict[str, Any],
        scope: str,
        session_id: str | None = None,
        task_id: str | None = None,
    ) -> None:
        event = self._make_event(
            event_type=event_type,
            payload=payload,
            scope=scope,
            session_id=session_id,
            task_id=task_id,
        )
        self._event_history.append(event)

        if not self._ws_clients:
            return

        dead_clients: list[web.WebSocketResponse] = []
        for ws in tuple(self._ws_clients):
            try:
                await ws.send_json(event)
            except Exception:
                dead_clients.append(ws)
        for ws in dead_clients:
            self._ws_clients.discard(ws)

    async def _broadcast_direct(
        self,
        ws: web.WebSocketResponse,
        event_type: str,
        *,
        payload: dict[str, Any],
        scope: str,
    ) -> None:
        await ws.send_json({
            "event_id": self._new_id("evt"),
            "event_type": event_type,
            "scope": scope,
            "occurred_at": self._now_iso(),
            "session_id": None,
            "task_id": None,
            "payload": payload,
        })

    def _list_app_sessions(
        self,
        *,
        limit: int,
        archived: bool | None = None,
        pinned_first: bool = True,
    ) -> list[dict[str, Any]]:
        list_app_sessions = getattr(self.sessions, "list_app_sessions", None)
        if callable(list_app_sessions):
            payload = list_app_sessions(
                limit=limit,
                archived=archived,
                pinned_first=pinned_first,
                active_session_id=self.get_active_app_session_id(),
            )
            if isinstance(payload, list):
                return [dict(item) for item in payload if isinstance(item, dict)]

        sessions: list[dict[str, Any]] = []
        for item in self.sessions.list_sessions():
            key = item.get("key", "")
            if not key.startswith("app:"):
                continue
            session = self.sessions.get(key)
            if session is None:
                continue
            data = self._serialize_session(session)
            if archived is not None and data["archived"] != archived:
                continue
            sessions.append(data)

        sessions.sort(key=lambda item: item["last_message_at"] or "", reverse=True)
        if pinned_first:
            sessions.sort(key=lambda item: not item["pinned"])
        if limit:
            sessions = sessions[:limit]
        return sessions

    def _serialize_session(self, session: Session) -> dict[str, Any]:
        get_session_summary = getattr(self.sessions, "get_session_summary", None)
        if callable(get_session_summary):
            payload = get_session_summary(
                session.key,
                active_session_id=self.get_active_app_session_id(),
            )
            if isinstance(payload, dict):
                return dict(payload)
        session = self._ensure_app_session(session.key, title=session.metadata.get("title"))
        visible_messages = self._serialize_messages(session)
        last_message = visible_messages[-1] if visible_messages else None
        return {
            "session_id": session.key,
            "channel": "app",
            "title": session.metadata.get("title") or self._placeholder_title_for(session.key),
            "summary": (last_message or {}).get("content", "")[:80],
            "last_message_at": (last_message or {}).get("created_at") or session.updated_at.isoformat(),
            "message_count": len(visible_messages),
            "pinned": bool(session.metadata.get("pinned", session.key == self.default_session_id)),
            "archived": bool(session.metadata.get("archived", False)),
            "active": session.key == self.get_active_app_session_id(),
            "scene_mode": session.metadata.get("scene_mode"),
            "persona_profile": session.metadata.get("persona_profile"),
            "persona_profile_id": (
                session.metadata.get("persona_profile", {}).get("preset")
                if isinstance(session.metadata.get("persona_profile"), dict)
                else None
            ),
            "persona_fields": deepcopy(session.metadata.get("persona_fields") or {}),
        }

    def _serialize_messages(self, session: Session) -> list[dict[str, Any]]:
        messages: list[dict[str, Any]] = []
        visible_index = 0
        for entry in session.messages:
            role = entry.get("role")
            if role not in {"user", "assistant", "system"}:
                continue
            content = self._content_to_text(entry.get("content"))
            if not content:
                continue
            visible_index += 1
            messages.append(self._build_message_payload(
                message_id=entry.get("message_id") or f"msg_{session.key.replace(':', '_')}_{visible_index}",
                session_id=session.key,
                role=role,
                content=content,
                status="completed",
                created_at=entry.get("timestamp") or session.updated_at.isoformat(),
                metadata=self._extract_message_metadata(entry),
            ))
        return messages

    def _serialize_runtime_task(
        self,
        task: dict[str, Any] | None,
        *,
        for_queue: bool = False,
    ) -> dict[str, Any] | None:
        if task is None:
            return None
        data = {
            "task_id": task["task_id"],
            "kind": task["kind"],
            "source_channel": task["source_channel"],
            "source_session_id": task["source_session_id"],
            "summary": task["summary"],
            "stage": task["stage"],
            "cancellable": task["cancellable"],
        }
        if not for_queue:
            data["started_at"] = task["started_at"]
        return data

    def _build_message_payload(
        self,
        *,
        message_id: str | None,
        session_id: str,
        role: str,
        content: str,
        status: str,
        created_at: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        return {
            "message_id": message_id or self._new_id("msg"),
            "session_id": session_id,
            "role": role,
            "content": content,
            "content_type": "text",
            "status": status,
            "created_at": created_at,
            "metadata": metadata,
        }

    async def _attach_event_client(
        self,
        ws: web.WebSocketResponse,
        *,
        last_event_id: str | None,
        replay_limit: int,
    ) -> None:
        """注册一个事件客户端，并按需回放断线期间的事件。"""
        self._ws_clients.add(ws)
        hello_payload, replay_events = self._build_replay_payload(
            last_event_id=last_event_id,
            replay_limit=replay_limit,
        )
        await self._broadcast_direct(
            ws,
            "system.hello",
            payload=hello_payload,
            scope="global",
        )
        for event in replay_events:
            await ws.send_json(event)

    def _build_current_task_event_payload_unlocked(self) -> dict[str, Any]:
        current_task_id = self._get_current_task_id_unlocked()
        return {
            "current_task": self._serialize_runtime_task(self._tasks.get(current_task_id))
            if current_task_id else None
        }

    def _build_queue_event_payload_unlocked(self) -> dict[str, Any]:
        current_task_id = self._get_current_task_id_unlocked()
        return {
            "task_queue": [
                self._serialize_runtime_task(self._tasks[task_id], for_queue=True)
                for task_id in self._task_order
                if task_id in self._tasks
                and self._tasks[task_id]["status"] in {"queued", "running"}
                and task_id != current_task_id
            ]
        }

    def _get_current_task_id_unlocked(self) -> str | None:
        running_ids = [
            task_id
            for task_id in self._task_order
            if task_id in self._tasks and self._tasks[task_id]["status"] == "running"
        ]
        return running_ids[-1] if running_ids else None

    def _ensure_app_session(self, session_id: str, title: str | None = None) -> Session:
        session = self.sessions.get_or_create(session_id)
        changed = False
        if session.metadata.get("channel") != "app":
            session.metadata["channel"] = "app"
            changed = True
        desired_title = title or session.metadata.get("title") or self._placeholder_title_for(session_id)
        if session.metadata.get("title") != desired_title:
            session.metadata["title"] = desired_title
            changed = True
        desired_title_source = self._coerce_title_source(
            session.metadata.get("title_source"),
            session_id=session_id,
            title=session.metadata.get("title"),
        )
        if session.metadata.get("title_source") != desired_title_source:
            session.metadata["title_source"] = desired_title_source
            changed = True
        if "pinned" not in session.metadata:
            session.metadata["pinned"] = session_id == self.default_session_id
            changed = True
        if "archived" not in session.metadata:
            session.metadata["archived"] = False
            changed = True
        if changed:
            session.updated_at = datetime.now()
            self.sessions.save(session)
        return session

    def _build_replay_payload(
        self,
        *,
        last_event_id: str | None,
        replay_limit: int,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        history = list(self._event_history)
        latest_event_id = history[-1]["event_id"] if history else None
        resume = {
            "requested": bool(last_event_id),
            "accepted": False,
            "replayed_count": 0,
            "replay_limit": replay_limit,
            "latest_event_id": latest_event_id,
            "history_size": len(history),
            "should_refetch_bootstrap": False,
            "reason": None,
        }

        replay_events: list[dict[str, Any]] = []
        if last_event_id:
            matched_index = next(
                (index for index, event in enumerate(history) if event["event_id"] == last_event_id),
                None,
            )
            if matched_index is None:
                resume["should_refetch_bootstrap"] = True
                resume["reason"] = "last_event_id_not_found"
            else:
                missed_events = history[matched_index + 1:]
                if len(missed_events) > replay_limit:
                    resume["should_refetch_bootstrap"] = True
                    resume["reason"] = "replay_limit_exceeded"
                else:
                    replay_events = missed_events
                    resume["accepted"] = True
                    resume["replayed_count"] = len(replay_events)

        hello_payload = {
            "server_version": self.version,
            "protocol_version": "app-v1",
            "ts": self._now_iso(),
            "resume": resume,
        }
        return hello_payload, replay_events

    def _make_event(
        self,
        *,
        event_type: str,
        payload: dict[str, Any],
        scope: str,
        session_id: str | None = None,
        task_id: str | None = None,
    ) -> dict[str, Any]:
        return {
            "event_id": self._new_id("evt"),
            "event_type": event_type,
            "scope": scope,
            "occurred_at": self._now_iso(),
            "session_id": session_id,
            "task_id": task_id,
            "payload": payload,
        }

    def _paginate_messages(
        self,
        *,
        session_id: str,
        messages: list[dict[str, Any]],
        before: str | None,
        after: str | None,
        limit: int,
    ) -> tuple[dict[str, Any], str | None]:
        id_to_index = {message["message_id"]: index for index, message in enumerate(messages)}

        if before and before not in id_to_index:
            return {}, "before cursor not found"
        if after and after not in id_to_index:
            return {}, "after cursor not found"

        slice_start = id_to_index[after] + 1 if after else 0
        slice_end = id_to_index[before] if before else len(messages)
        if slice_end < slice_start:
            slice_end = slice_start

        anchor_on_before = before is not None or after is None
        if limit and (slice_end - slice_start) > limit:
            if anchor_on_before:
                result_start = max(slice_start, slice_end - limit)
                result_end = slice_end
            else:
                result_start = slice_start
                result_end = min(slice_end, slice_start + limit)
        else:
            result_start = slice_start
            result_end = slice_end

        items = messages[result_start:result_end]
        return {
            "session_id": session_id,
            "items": items,
            "page_info": {
                "limit": limit,
                "before": before,
                "after": after,
                "returned": len(items),
                "has_more_before": result_start > slice_start,
                "has_more_after": result_end < slice_end,
                "next_before": items[0]["message_id"] if items and result_start > slice_start else None,
                "next_after": items[-1]["message_id"] if items and result_end < slice_end else None,
            },
        }, None

    @staticmethod
    def _extract_message_metadata(entry: dict[str, Any]) -> dict[str, Any]:
        metadata: dict[str, Any] = {}
        for key in (
            "task_id",
            "client_message_id",
            "source",
            "interaction_surface",
            "capture_source",
            "voice_path",
            "source_channel",
            "reply_language",
            "emotion",
            "app_session_id",
        ):
            if entry.get(key) is not None:
                metadata[key] = entry[key]
        if entry.get("tool_results") is not None:
            metadata["tool_results"] = entry["tool_results"]
        return metadata

    def _planning_inputs(self) -> dict[str, list[dict[str, Any]]]:
        planning_inputs = getattr(self.resources, "planning_inputs", None)
        if callable(planning_inputs):
            payload = planning_inputs()
            if isinstance(payload, dict):
                return {
                    "tasks": list(payload.get("tasks", [])),
                    "events": list(payload.get("events", [])),
                    "reminders": list(payload.get("reminders", [])),
                    "notifications": list(payload.get("notifications", [])),
                }
        return {
            "tasks": self.resources.task_store.list_items(),
            "events": self.resources.event_store.list_items(),
            "reminders": self.resources.reminder_store.list_items(),
            "notifications": self.resources.notification_store.list_items(),
        }

    def _planning_snapshot(
        self,
        *,
        date: str | None = None,
        surface: str | None = None,
    ) -> dict[str, Any]:
        inputs = self._planning_inputs()
        overview = self.planning_projection_service.build_overview(**inputs)
        timeline = self._build_planning_timeline_projection(
            tasks=inputs["tasks"],
            events=inputs["events"],
            reminders=inputs["reminders"],
            target_date=date,
            surface=surface,
        )
        conflicts = self.planning_projection_service.build_conflicts(
            tasks=inputs["tasks"],
            events=inputs["events"],
            reminders=inputs["reminders"],
        )
        return {
            "overview": overview,
            "timeline": timeline,
            "conflicts": conflicts,
        }

    def _build_planning_timeline_projection(
        self,
        *,
        tasks: list[dict[str, Any]],
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
        target_date: str | None = None,
        surface: str | None = None,
    ) -> list[dict[str, Any]]:
        build_timeline = self.planning_projection_service.build_timeline
        kwargs: dict[str, Any] = {
            "tasks": tasks,
            "events": events,
            "reminders": reminders,
        }

        parameter_names: set[str] | None = None
        try:
            parameter_names = set(inspect.signature(build_timeline).parameters)
        except (TypeError, ValueError):
            parameter_names = None

        if target_date is not None:
            if parameter_names is not None and "date" in parameter_names and "target_date" not in parameter_names:
                kwargs["date"] = target_date
            else:
                kwargs["target_date"] = target_date
        if surface is not None:
            if parameter_names is None or "surface" in parameter_names:
                kwargs["surface"] = surface
            elif "interaction_surface" in parameter_names:
                kwargs["interaction_surface"] = surface

        try:
            return build_timeline(**kwargs)
        except TypeError:
            fallback_kwargs = {
                "tasks": tasks,
                "events": events,
                "reminders": reminders,
            }
            if target_date is not None:
                fallback_kwargs["target_date"] = target_date
            return build_timeline(**fallback_kwargs)

    @staticmethod
    def _normalize_planning_surface(value: Any) -> str | None:
        if not isinstance(value, str):
            return None
        cleaned = value.strip().lower()
        if cleaned in {"agenda", "tasks", "hidden"}:
            return cleaned
        return None

    async def _refresh_summary_files_from_resources(self) -> list[tuple[str, dict[str, Any]]]:
        inputs = self._planning_inputs()
        derived = self.planning_summary_service.derive_all(
            tasks=inputs["tasks"],
            events=inputs["events"],
            reminders=inputs["reminders"],
        )

        changed_events: list[tuple[str, dict[str, Any]]] = []
        async with self._lock:
            todo_summary = derived["todo_summary"]
            if todo_summary != self._todo_summary:
                self._todo_summary = dict(todo_summary)
                self._save_summary_file(self._todo_summary_path, self._todo_summary)
                changed_events.append(("todo.summary.changed", dict(self._todo_summary)))

            calendar_summary = derived["calendar_summary"]
            if calendar_summary != self._calendar_summary:
                self._calendar_summary = dict(calendar_summary)
                self._save_summary_file(self._calendar_summary_path, self._calendar_summary)
                changed_events.append(("calendar.summary.changed", dict(self._calendar_summary)))

        return changed_events

    @staticmethod
    def _default_todo_summary() -> dict[str, Any]:
        return {
            "enabled": False,
            "pending_count": 0,
            "overdue_count": 0,
            "next_due_at": None,
        }

    @staticmethod
    def _default_calendar_summary() -> dict[str, Any]:
        return {
            "enabled": False,
            "today_count": 0,
            "next_event_at": None,
            "next_event_title": None,
        }

    def _load_summary_file(self, path: Path, default: dict[str, Any]) -> dict[str, Any]:
        if not path.exists():
            return dict(default)
        try:
            with open(path, encoding="utf-8") as f:
                payload = json.load(f)
            if not isinstance(payload, dict):
                raise ValueError("summary file must be a json object")
        except Exception:
            logger.warning("Failed to load summary file {}", path)
            return dict(default)
        merged = dict(default)
        merged.update(payload)
        return merged

    @staticmethod
    def _save_summary_file(path: Path, summary: dict[str, Any]) -> None:
        def _write(handle) -> None:
            json.dump(summary, handle, ensure_ascii=False, indent=2)

        atomic_write_text(path, _write, encoding="utf-8")

    def _normalize_todo_summary(
        self,
        current: dict[str, Any],
        payload: dict[str, Any],
    ) -> tuple[dict[str, Any], str | None]:
        summary = dict(self._default_todo_summary())
        summary.update(current)
        summary["enabled"] = self._normalize_bool_field(
            payload,
            key="enabled",
            current=summary["enabled"],
        )
        counts, error = self._normalize_nonnegative_int_fields(
            payload,
            current=summary,
            keys=("pending_count", "overdue_count"),
        )
        if error:
            return {}, error
        summary.update(counts)
        next_due_at, error = self._normalize_optional_string_field(
            payload,
            key="next_due_at",
            current=summary["next_due_at"],
        )
        if error:
            return {}, error
        summary["next_due_at"] = next_due_at
        if not summary["enabled"]:
            summary = self._default_todo_summary()
        return summary, None

    def _normalize_calendar_summary(
        self,
        current: dict[str, Any],
        payload: dict[str, Any],
    ) -> tuple[dict[str, Any], str | None]:
        summary = dict(self._default_calendar_summary())
        summary.update(current)
        summary["enabled"] = self._normalize_bool_field(
            payload,
            key="enabled",
            current=summary["enabled"],
        )
        counts, error = self._normalize_nonnegative_int_fields(
            payload,
            current=summary,
            keys=("today_count",),
        )
        if error:
            return {}, error
        summary.update(counts)
        next_event_at, error = self._normalize_optional_string_field(
            payload,
            key="next_event_at",
            current=summary["next_event_at"],
        )
        if error:
            return {}, error
        next_event_title, error = self._normalize_optional_string_field(
            payload,
            key="next_event_title",
            current=summary["next_event_title"],
        )
        if error:
            return {}, error
        summary["next_event_at"] = next_event_at
        summary["next_event_title"] = next_event_title
        if not summary["enabled"]:
            summary = self._default_calendar_summary()
        return summary, None

    @staticmethod
    def _normalize_bool_field(payload: dict[str, Any], *, key: str, current: bool) -> bool:
        value = payload.get(key, current)
        return value if isinstance(value, bool) else current

    @staticmethod
    def _normalize_nonnegative_int_fields(
        payload: dict[str, Any],
        *,
        current: dict[str, Any],
        keys: tuple[str, ...],
    ) -> tuple[dict[str, int], str | None]:
        normalized: dict[str, int] = {}
        for key in keys:
            value = payload.get(key, current[key])
            if not isinstance(value, int) or value < 0:
                return {}, f"{key} must be a non-negative integer"
            normalized[key] = value
        return normalized, None

    @staticmethod
    def _normalize_optional_string_field(
        payload: dict[str, Any],
        *,
        key: str,
        current: str | None,
    ) -> tuple[str | None, str | None]:
        if key not in payload:
            return current, None
        value = payload[key]
        if value is None:
            return None, None
        if not isinstance(value, str):
            return None, f"{key} must be a string or null"
        cleaned = value.strip()
        return cleaned or None, None

    def _is_authorized(self, request: web.Request) -> bool:
        if not self.auth_token:
            return True
        candidate = self._extract_token(request)
        if not candidate:
            return False
        return hmac.compare_digest(candidate, self.auth_token)

    @staticmethod
    def _extract_token(request: web.Request) -> str:
        auth_header = request.headers.get("Authorization", "").strip()
        if auth_header.startswith("Bearer "):
            return auth_header[7:].strip()

        header_token = request.headers.get("X-App-Token", "").strip()
        if header_token:
            return header_token

        return request.query.get("token", "").strip()

    def _validate_app_session_id(self, session_id: str) -> tuple[bool, str]:
        if not session_id.startswith("app:"):
            return False, "session_id must start with 'app:'"
        if ":" not in session_id or not session_id.split(":", 1)[1].strip():
            return False, "session_id suffix is required"
        return True, ""

    def _desktop_voice_runtime(self) -> dict[str, Any]:
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

    def _device_runtime_state(self) -> dict[str, Any]:
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

    def _voice_runtime_state(self) -> dict[str, Any]:
        settings = self.settings.get_public_settings()
        desktop = self._desktop_voice_runtime()
        return {
            "pipeline_ready": bool(self.device_channel.asr and desktop.get("ready")),
            "desktop_bridge": desktop,
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

    def _planning_runtime_state(self) -> dict[str, Any]:
        overview = self.get_planning_overview()
        counts = overview.get("counts", {})
        return {
            "available": True,
            "overview_ready": True,
            "timeline_ready": True,
            "conflicts_ready": True,
            "conflict_count": int(counts.get("conflict_count", 0) or 0),
            "generated_at": overview.get("generated_at"),
        }

    def _storage_runtime_state(self) -> dict[str, Any]:
        sqlite_path = self._storage_config.get("sqlite_path")
        sqlite_path_value = str(sqlite_path).strip() if sqlite_path is not None else ""
        state = {
            "session_mode": str(
                self._storage_config.get("session_storage_mode", "json")
            ).strip().lower() or "json",
            "planning_mode": str(
                self._storage_config.get("planning_storage_mode", "json")
            ).strip().lower() or "json",
            "experience_mode": str(
                self._storage_config.get("experience_storage_mode", "json")
            ).strip().lower() or "json",
            "computer_action_mode": str(
                self._storage_config.get("computer_action_storage_mode", "json")
            ).strip().lower() or "json",
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
                state["session_mode"] = str(payload.get("mode") or state["session_mode"])
                state["sqlite_path"] = payload.get("sqlite_path") or state["sqlite_path"]
                state["schema_version"] = max(
                    int(state["schema_version"] or 0),
                    int(payload.get("schema_version", 0) or 0),
                )
                state["latest_imported_at"] = (
                    payload.get("latest_imported_at") or state["latest_imported_at"]
                )

        planning_runtime_state = getattr(self.resources, "storage_runtime_state", None)
        if callable(planning_runtime_state):
            payload = planning_runtime_state()
            if isinstance(payload, dict):
                state["planning_mode"] = str(payload.get("mode") or state["planning_mode"])
                state["sqlite_path"] = payload.get("sqlite_path") or state["sqlite_path"]
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
        return state

    def _transport_runtime_state(self) -> dict[str, Any]:
        runtime_state = getattr(self.bus, "runtime_state", None)
        state = runtime_state() if callable(runtime_state) else {}
        if not isinstance(state, dict):
            state = {}
        state.setdefault("bus_inbound_depth", int(getattr(self.bus, "inbound_size", 0) or 0))
        state.setdefault("bus_outbound_depth", int(getattr(self.bus, "outbound_size", 0) or 0))
        state.setdefault("ws_client_count", len(self._ws_clients))
        state.setdefault("slow_client_drops", self._slow_client_drops)
        return state

    def _computer_control_runtime_state(self) -> dict[str, Any]:
        state = dict(self.computer_control_service.get_state())
        state.setdefault(
            "allowed_scripts_contract_version",
            _ALLOWED_SCRIPTS_CONTRACT_VERSION,
        )
        return state

    async def _runtime_experience_state(
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
            device_snapshot=device_snapshot or self.device_channel.get_snapshot(),
            voice_runtime=voice_runtime or self._voice_runtime_state(),
            computer_control_state=computer_control_state or self._computer_control_runtime_state(),
            current_task=current_task,
        )

    @staticmethod
    def _planning_bootstrap() -> dict[str, Any]:
        return {
            "overview": True,
            "timeline": True,
            "conflicts": True,
            "bundle_create_path": "/api/app/v1/planning/bundles",
            "reminder_actions_path": "/api/app/v1/reminders/{reminder_id}/actions",
            "overview_path": "/api/app/v1/planning/overview",
            "timeline_path": "/api/app/v1/planning/timeline",
            "conflicts_path": "/api/app/v1/planning/conflicts",
        }

    def _agent_runtime_summary(self) -> dict[str, Any]:
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
        allowed_scripts = sorted((getattr(policy, "allowed_scripts", {}) or {}).keys())
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
                "allowed_scripts_contract_version": _ALLOWED_SCRIPTS_CONTRACT_VERSION,
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

    def _capabilities(self) -> dict[str, Any]:
        desktop = self._desktop_voice_runtime()
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
            "agent_runtime": self._agent_runtime_summary(),
        }

    def _build_device_pairing_bundle(
        self,
        host: str,
        *,
        request: web.Request | None = None,
    ) -> dict[str, Any]:
        device_token = str(self.cfg.get("device", {}).get("auth_token", "") or "").strip()
        transport = self._resolve_device_pairing_transport(request)
        return {
            "server": {
                "host": host,
                "port": transport.port,
                "path": "/ws/device",
                "secure": transport.secure,
            },
            "auth": {
                "device_token": device_token,
                "required": bool(device_token),
            },
        }

    def _resolve_device_pairing_transport(
        self,
        request: web.Request | None,
    ) -> _DevicePairingTransport:
        cfg_port = self._device_pairing_server_port()
        cfg_secure = self._device_pairing_server_secure()
        if request is None:
            return _DevicePairingTransport(
                port=cfg_port,
                secure=cfg_secure,
                source="cfg.server",
            )

        request_port = self._device_pairing_request_port(request)
        request_secure = self._device_pairing_request_secure(request)
        fallback_fields: list[str] = []

        port = request_port if request_port is not None else cfg_port
        if request_port is None:
            fallback_fields.append("port")
        secure = request_secure if request_secure is not None else cfg_secure
        if request_secure is None:
            fallback_fields.append("secure")

        if fallback_fields:
            logger.info(
                "Device pairing bundle fallback to cfg.server for {}",
                ", ".join(fallback_fields),
            )

        return _DevicePairingTransport(
            port=port,
            secure=secure,
            source="request" if not fallback_fields else "cfg.server",
        )

    def _device_pairing_server_port(self) -> int:
        raw = self.cfg.get("server", {}).get("port", 8765)
        try:
            port = int(raw)
        except (TypeError, ValueError):
            return 8765
        return port if 1 <= port <= 65535 else 8765

    def _device_pairing_server_secure(self) -> bool:
        secure = self.cfg.get("server", {}).get("secure", False)
        if isinstance(secure, bool):
            return secure
        if isinstance(secure, str):
            parsed = self._parse_bool(secure, default=None)
            if parsed is not None:
                return parsed
        return False

    @classmethod
    def _device_pairing_request_secure(
        cls,
        request: web.Request,
    ) -> bool | None:
        forwarded = cls._parse_forwarded_header(request.headers.get("Forwarded"))
        raw_scheme = (
            request.headers.get("X-Forwarded-Proto")
            or forwarded.get("proto")
            or getattr(request, "scheme", None)
        )
        if not isinstance(raw_scheme, str):
            return None
        scheme = raw_scheme.split(",", 1)[0].strip().lower()
        if scheme in {"https", "wss"}:
            return True
        if scheme in {"http", "ws"}:
            return False
        return None

    @classmethod
    def _device_pairing_request_port(
        cls,
        request: web.Request,
    ) -> int | None:
        forwarded = cls._parse_forwarded_header(request.headers.get("Forwarded"))
        candidates = (
            request.headers.get("X-Forwarded-Port"),
            cls._port_from_host_value(request.headers.get("X-Forwarded-Host")),
            cls._port_from_host_value(forwarded.get("host")),
        )
        for candidate in candidates:
            port = cls._parse_optional_port(candidate)
            if port is not None:
                return port

        request_url = getattr(request, "url", None)
        try:
            request_port = request_url.port if request_url is not None else None
        except ValueError:
            request_port = None
        if isinstance(request_port, int) and 1 <= request_port <= 65535:
            return request_port

        request_host = request.headers.get("Host") or getattr(request, "host", None)
        return cls._port_from_host_value(request_host)

    @staticmethod
    def _parse_forwarded_header(value: str | None) -> dict[str, str]:
        if not isinstance(value, str) or not value.strip():
            return {}
        first = value.split(",", 1)[0]
        parsed: dict[str, str] = {}
        for item in first.split(";"):
            key, _, raw_value = item.partition("=")
            if not _:
                continue
            cleaned_key = key.strip().lower()
            cleaned_value = raw_value.strip().strip('"')
            if cleaned_key and cleaned_value:
                parsed[cleaned_key] = cleaned_value
        return parsed

    @classmethod
    def _port_from_host_value(cls, value: Any) -> int | None:
        if not isinstance(value, str):
            return None
        host = value.strip()
        if not host:
            return None
        if host.startswith("["):
            closing = host.find("]")
            if closing == -1:
                return None
            remainder = host[closing + 1:].strip()
            if not remainder.startswith(":"):
                return None
            return cls._parse_optional_port(remainder[1:])
        if host.count(":") == 1:
            return cls._parse_optional_port(host.rsplit(":", 1)[1])
        return None

    @staticmethod
    def _parse_optional_port(value: Any) -> int | None:
        if value is None:
            return None
        try:
            port = int(str(value).strip())
        except (TypeError, ValueError):
            return None
        return port if 1 <= port <= 65535 else None

    @classmethod
    def _normalize_device_pairing_host(cls, payload: dict[str, Any]) -> tuple[str, str | None]:
        raw_host = payload.get("host")
        if raw_host is None and isinstance(payload.get("server"), dict):
            raw_host = payload["server"].get("host")
        if not isinstance(raw_host, str):
            return "", "host is required"

        host = raw_host.strip()
        if not host:
            return "", "host is required"
        if any(char.isspace() for char in host):
            return "", "host must be a bare hostname or IP address"
        if any(token in host for token in ("://", "/", "?", "#")):
            return "", "host must be a bare hostname or IP address"

        if host.startswith("[") and host.endswith("]"):
            host = host[1:-1].strip()
        if not host or "[" in host or "]" in host:
            return "", "host must be a bare hostname or IP address"

        lowered = host.lower()
        if lowered == "localhost" or lowered.endswith(".localhost"):
            return "", "host must be reachable from the device"

        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            if ":" in host:
                return "", "host must be a bare hostname or IP address"
            return host, None

        if address.is_loopback or address.is_unspecified:
            return "", "host must be reachable from the device"
        return host, None

    @staticmethod
    def _app_session_id_from_metadata(metadata: dict[str, Any] | None) -> str | None:
        if not isinstance(metadata, dict):
            return None
        candidate = str(metadata.get("app_session_id") or "").strip()
        return candidate or None

    def get_active_app_session_id(self) -> str:
        candidate = str(self._active_app_session_id or "").strip()
        if candidate.startswith("app:"):
            return candidate
        return self.default_session_id

    def _set_active_app_session(self, session_id: str) -> list[dict[str, Any]]:
        previous = self.get_active_app_session_id()
        next_session = self._ensure_app_session(session_id).key
        self._active_app_session_id = next_session
        affected_ids: list[str] = []
        for candidate in (previous, next_session):
            if candidate and candidate not in affected_ids:
                affected_ids.append(candidate)
        return [self._serialize_session(self._ensure_app_session(item)) for item in affected_ids]

    def _pick_fallback_active_session(self, *, excluding: str | None = None) -> str | None:
        sessions = self._list_app_sessions(limit=200, archived=False, pinned_first=True)
        for item in sessions:
            session_id = item.get("session_id")
            if isinstance(session_id, str) and session_id and session_id != excluding:
                return session_id
        return None

    def _app_session_id_from_message(self, msg: InboundMessage) -> str | None:
        metadata_session = self._app_session_id_from_metadata(msg.metadata)
        if metadata_session:
            return metadata_session
        if msg.channel == "app":
            return self._session_id_for(msg.channel, msg.chat_id)
        if msg.session_key_override and msg.session_key_override.startswith("app:"):
            return msg.session_key_override
        return None

    async def _maybe_handle_experience_command(
        self,
        *,
        session_id: str,
        content: str,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        command = self._parse_experience_command(content)
        if command is None:
            return None

        session = self._ensure_app_session(session_id)
        self._active_app_session_id = session.key
        self._maybe_auto_title_session_unlocked(session.key, content)

        before_snapshot = self.experience_service.get_public_snapshot(session_id=session.key)
        self.experience_service.patch_session(session, command["patch"])
        after_snapshot = self.experience_service.get_public_snapshot(session_id=session.key)
        response_text = self._build_experience_command_response(
            command=command,
            before_snapshot=before_snapshot,
        )

        task_id = str((metadata or {}).get("task_id") or self._new_id("task"))
        user_message_id = str((metadata or {}).get("message_id") or self._new_id("msg"))
        assistant_message_id = str(
            (metadata or {}).get("assistant_message_id") or self._new_id("msg")
        )
        message_metadata = self.experience_service.inject_message_metadata(
            {
                **dict(metadata or {}),
                "app_session_id": session.key,
                "task_id": task_id,
                "message_id": user_message_id,
                "assistant_message_id": assistant_message_id,
            },
            session_id=session.key,
            interaction_kind="experience_command",
            interaction_mode=command["command_type"],
        )
        user_message_metadata = self._session_message_metadata(message_metadata, task_id)
        assistant_message_metadata = self._session_message_metadata(
            {
                **message_metadata,
                "message_id": assistant_message_id,
            },
            task_id,
        )

        user_created_at = datetime.now().astimezone().isoformat(timespec="microseconds")
        assistant_created_at = datetime.now().astimezone().isoformat(timespec="microseconds")
        session.add_message(
            "user",
            content,
            timestamp=user_created_at,
            message_id=user_message_id,
            **user_message_metadata,
        )
        session.add_message(
            "assistant",
            response_text,
            timestamp=assistant_created_at,
            message_id=assistant_message_id,
            **assistant_message_metadata,
        )
        self.sessions.save(session)

        session_payload = self._serialize_session(session)
        accepted_message = self._build_message_payload(
            message_id=user_message_id,
            session_id=session.key,
            role="user",
            content=content,
            status="completed",
            created_at=user_created_at,
            metadata=user_message_metadata,
        )
        assistant_message = self._build_message_payload(
            message_id=assistant_message_id,
            session_id=session.key,
            role="assistant",
            content=response_text,
            status="completed",
            created_at=assistant_created_at,
            metadata=assistant_message_metadata,
        )

        await self._broadcast_event(
            "session.updated",
            payload={"session": session_payload},
            scope="global",
            session_id=session.key,
        )
        await self._broadcast_event(
            "session.message.created",
            payload={"message": accepted_message},
            scope="session",
            session_id=session.key,
            task_id=task_id,
        )
        await self._broadcast_event(
            "session.message.completed",
            payload={"message": assistant_message},
            scope="session",
            session_id=session.key,
            task_id=task_id,
        )

        experience_payload = self.experience_service.get_experience_payload(
            session_id=session.key,
            device_snapshot=self.device_channel.get_snapshot(),
            voice_runtime=self._voice_runtime_state(),
            computer_control_state=self._computer_control_runtime_state(),
        )
        await self._broadcast_event(
            "runtime.experience.updated",
            payload={"experience": experience_payload["experience"]},
            scope="global",
            session_id=session.key,
        )

        return {
            "handled": True,
            "task_id": task_id,
            "accepted_message": accepted_message,
            "assistant_message": assistant_message,
            "response_text": response_text,
            "outbound_metadata": {
                **message_metadata,
                "message_id": assistant_message_id,
            },
            "experience": after_snapshot,
        }

    def _parse_experience_command(self, content: str) -> dict[str, Any] | None:
        normalized = self._normalize_experience_command_text(content)
        if not normalized or _EXPERIENCE_COMMAND_VERB_RE.search(normalized) is None:
            return None

        scene = self._extract_scene_command(normalized)
        persona = self._extract_persona_command(normalized)
        if scene is None and persona is None:
            return None

        patch: dict[str, Any] = {}
        if scene is not None:
            patch["scene_mode"] = scene["id"]
        if persona is not None:
            patch["persona_profile"] = {"preset": persona["id"]}

        command_type = "scene_persona_switch"
        if scene is None:
            command_type = "persona_switch"
        elif persona is None:
            command_type = "scene_switch"

        return {
            "patch": patch,
            "scene": scene,
            "persona": persona,
            "command_type": command_type,
        }

    def _extract_scene_command(self, normalized: str) -> dict[str, str] | None:
        collapsed = self._normalize_experience_alias(normalized)
        for alias, scene_mode, label in _SCENE_COMMAND_ALIASES:
            if alias in collapsed:
                return {"id": scene_mode, "label": label}

        if not any(token in collapsed for token in ("场景", "模式", "scene", "mode")):
            return None
        for alias, scene_mode, label in _SCENE_COMMAND_CONTEXT_ALIASES:
            if alias in collapsed:
                return {"id": scene_mode, "label": label}
        return None

    def _extract_persona_command(self, normalized: str) -> dict[str, str] | None:
        collapsed = self._normalize_experience_alias(normalized)
        for alias, persona_profile_id, label in _PERSONA_COMMAND_ALIASES:
            if alias in collapsed:
                return {"id": persona_profile_id, "label": label}
        if not any(token in collapsed for token in ("人格", "角色", "风格", "语气", "persona")):
            return None
        return None

    @staticmethod
    def _build_experience_command_response(
        *,
        command: dict[str, Any],
        before_snapshot: dict[str, Any],
    ) -> str:
        parts: list[str] = []
        scene = command.get("scene")
        if isinstance(scene, dict):
            scene_id = str(scene.get("id") or "").strip()
            scene_label = str(scene.get("label") or scene_id).strip()
            if scene_id and scene_id == before_snapshot.get("active_scene_mode"):
                parts.append(f"当前会话已经是{scene_label}。")
            elif scene_label:
                parts.append(f"已切换到{scene_label}。")

        persona = command.get("persona")
        if isinstance(persona, dict):
            persona_id = str(persona.get("id") or "").strip()
            persona_label = str(persona.get("label") or persona_id).strip()
            active_persona = before_snapshot.get("active_persona") or {}
            active_persona_id = str(active_persona.get("preset") or "").strip()
            if persona_id and persona_id == active_persona_id:
                parts.append(f"当前人格已经是{persona_label}。")
            elif persona_label:
                parts.append(f"已将人格切换为{persona_label}。")

        return "".join(parts) or "已更新当前会话的人格和场景。"

    @staticmethod
    def _normalize_experience_command_text(content: str) -> str:
        lowered = str(content or "").strip().lower()
        for token in ("，", "。", ",", ".", "！", "!", "？", "?", "；", ";", "：", ":"):
            lowered = lowered.replace(token, " ")
        return " ".join(lowered.split())

    @staticmethod
    def _normalize_experience_alias(content: str) -> str:
        return re.sub(r"\s+", "", str(content or "").strip().lower())

    @staticmethod
    def _session_message_metadata(metadata: dict[str, Any], task_id: str) -> dict[str, Any]:
        payload = {
            "task_id": task_id,
            "client_message_id": metadata.get("client_message_id"),
            "source": metadata.get("source"),
            "interaction_surface": metadata.get("interaction_surface"),
            "capture_source": metadata.get("capture_source"),
            "voice_path": metadata.get("voice_path"),
            "source_channel": metadata.get("source_channel"),
            "reply_language": metadata.get("reply_language"),
            "emotion": metadata.get("emotion"),
            "app_session_id": metadata.get("app_session_id"),
            "scene_mode": metadata.get("scene_mode"),
            "persona_profile_id": metadata.get("persona_profile_id"),
            "persona_voice_style": metadata.get("persona_voice_style"),
            "interaction_kind": metadata.get("interaction_kind"),
            "interaction_mode": metadata.get("interaction_mode"),
            "approval_source": metadata.get("approval_source"),
            "tool_results": metadata.get("tool_results"),
        }
        return {key: value for key, value in payload.items() if value is not None}

    @staticmethod
    def _parse_limit(raw: str | None, *, default: int, maximum: int) -> int:
        if not raw:
            return default
        try:
            value = int(raw)
        except ValueError:
            return default
        return max(1, min(value, maximum))

    @staticmethod
    def _parse_bool(raw: str | None, *, default: bool | None = None) -> bool | None:
        if raw is None:
            return default
        lowered = raw.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
        return default

    @staticmethod
    def _parse_optional_bool(raw: Any) -> bool | None:
        if raw is None:
            return None
        if isinstance(raw, bool):
            return raw
        if isinstance(raw, str):
            return AppRuntimeService._parse_bool(raw, default=None)
        return None

    @staticmethod
    async def _read_json(request: web.Request) -> dict[str, Any] | None:
        if request.content_length in (None, 0):
            return {}
        try:
            data = await request.json()
        except (json.JSONDecodeError, UnicodeDecodeError):
            return None
        return data if isinstance(data, dict) else None

    @staticmethod
    def _content_to_text(content: Any) -> str:
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "text" and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif item.get("type") == "image_url":
                    parts.append("[image]")
            return "\n".join(part for part in parts if part).strip()
        return ""

    @staticmethod
    def _placeholder_title_for(session_id: str) -> str:
        if session_id == "app:main":
            return "主对话"
        return "新对话"

    @classmethod
    def _is_defaultish_title(cls, session_id: str, title: Any) -> bool:
        if not isinstance(title, str):
            return True
        cleaned = title.strip()
        if not cleaned:
            return True
        session_suffix = session_id.split(":", 1)[1].strip() if ":" in session_id else session_id.strip()
        return cleaned in {
            session_suffix,
            cls._placeholder_title_for(session_id),
            "New conversation",
            "Conversation",
            "Untitled session",
        }

    @classmethod
    def _coerce_title_source(
        cls,
        raw: Any,
        *,
        session_id: str,
        title: Any,
    ) -> str:
        cleaned = str(raw or "").strip().lower()
        if cleaned in {"user", "auto", "default"}:
            return cleaned
        return "default" if cls._is_defaultish_title(session_id, title) else "user"

    def _maybe_auto_title_session_unlocked(
        self,
        session_id: str,
        content: str,
    ) -> dict[str, Any] | None:
        if not session_id.startswith("app:") or session_id == self.default_session_id:
            return None
        session = self._ensure_app_session(session_id)
        if session.metadata.get("title_source") != "default":
            return None
        if any(
            entry.get("role") == "user" and self._content_to_text(entry.get("content"))
            for entry in session.messages
        ):
            return None
        next_title = self._auto_title_for_content(content)
        if not next_title:
            return None
        session.metadata["title"] = next_title
        session.metadata["title_source"] = "auto"
        session.updated_at = datetime.now()
        self.sessions.save(session)
        return self._serialize_session(session)

    @staticmethod
    def _auto_title_for_content(content: str) -> str | None:
        normalized = " ".join(content.strip().split())
        if not normalized:
            return None
        cleaned = normalized.strip(" ，。,.!?！？；;：:\"'“”()（）[]【】")
        if not cleaned:
            return None
        limit = 24
        if len(cleaned) <= limit:
            return cleaned
        return f"{cleaned[:limit].rstrip()}…"

    @staticmethod
    def _summarize(content: str) -> str:
        text = " ".join(content.strip().split())
        return text[:80] if len(text) <= 80 else f"{text[:77]}..."

    @staticmethod
    def _session_id_for(channel: str, chat_id: str) -> str:
        return f"{channel}:{chat_id}"

    @staticmethod
    def _new_id(prefix: str) -> str:
        return f"{prefix}_{uuid.uuid4().hex[:12]}"

    def _latest_event_id(self) -> str | None:
        return self._event_history[-1]["event_id"] if self._event_history else None

    @staticmethod
    def _coerce_positive_int(raw: Any, *, default: int) -> int:
        try:
            value = int(raw)
        except (TypeError, ValueError):
            return default
        return value if value > 0 else default

    @staticmethod
    def _now_iso() -> str:
        return datetime.now().astimezone().isoformat(timespec="seconds")

    def _ok(self, data: Any, *, status: int = 200) -> web.Response:
        return web.json_response({
            "ok": True,
            "data": data,
            "request_id": self._new_id("req"),
            "ts": self._now_iso(),
        }, status=status)

    def _error(self, code: str, message: str, *, status: int) -> web.Response:
        return web.json_response({
            "ok": False,
            "error": {
                "code": code,
                "message": message,
            },
            "request_id": self._new_id("req"),
            "ts": self._now_iso(),
        }, status=status)
