from __future__ import annotations

import asyncio
from collections import deque
import hmac
import json
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
from services.planning import (
    PlanningBundleService,
    PlanningProjectionService,
    PlanningSummaryService,
)
from services.reminder_scheduler import ReminderScheduler


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
        version: str,
        start_time: float,
    ) -> None:
        self.cfg = cfg
        self.bus = bus
        self.sessions = sessions
        self.device_channel = device_channel
        self.desktop_voice_service = desktop_voice_service
        self.version = version
        self.start_time = start_time
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
        self._tasks: dict[str, dict[str, Any]] = {}
        self._task_order: list[str] = []
        self._event_history: deque[dict[str, Any]] = deque(maxlen=self.event_buffer_size)
        self._runtime_dir = self.sessions.workspace / "runtime"
        self._runtime_dir.mkdir(parents=True, exist_ok=True)
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
        self.resources = AppResourceService(self._runtime_dir)
        self.planning_bundle_service = PlanningBundleService(self.resources)
        self.planning_projection_service = PlanningProjectionService()
        self.planning_summary_service = PlanningSummaryService()
        self.reminder_scheduler = ReminderScheduler(
            self.resources,
            event_observer=self,
        )
        self.device_channel.set_active_app_session_resolver(self.get_active_app_session_id)
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
        app.router.add_get("/api/app/v1/device", self.handle_device)
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
    ) -> None:
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
        await self.refresh_planning_state()

    async def handle_bootstrap(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)

        self._ensure_app_session(self.default_session_id, title="主对话")
        return self._ok({
            "server_version": self.version,
            "capabilities": self._capabilities(),
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

        await self._broadcast_event(
            "settings.updated",
            payload=settings,
            scope="global",
        )

        if "device_volume" in payload and self.device_channel.connected:
            try:
                result = await self.device_channel.execute_app_command(
                    "set_volume",
                    {"level": int(settings["device_volume"])},
                    client_command_id=f"settings_volume_{uuid.uuid4().hex[:8]}",
                )
            except (RuntimeError, ValueError):
                logger.exception("Failed to apply device volume after settings update")
            else:
                await self._broadcast_event(
                    "device.command.accepted",
                    payload=result,
                    scope="global",
                )
        return self._ok(settings)

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

        session = self.sessions.get(session_id)
        if session is None:
            return self._error("SESSION_NOT_FOUND", "session does not exist", status=404)

        limit = self._parse_limit(request.query.get("limit"), default=50, maximum=200)
        messages = self._serialize_messages(session)
        before = request.query.get("before", "").strip() or None
        after = request.query.get("after", "").strip() or None
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
        msg = InboundMessage(
            channel="app",
            sender_id="flutter",
            chat_id=chat_id,
            content=content,
            metadata={"app_session_id": session.key, "source_channel": "app"},
        )
        client_message_id = str(payload.get("client_message_id") or "").strip()
        if client_message_id:
            msg.metadata["client_message_id"] = client_message_id

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
        return self._ok({"items": self.get_planning_timeline(date=target_date)})

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

    async def handle_device(self, request: web.Request) -> web.Response:
        if not self._is_authorized(request):
            return self._error("UNAUTHORIZED", "unauthorized", status=401)
        return self._ok(self.device_channel.get_snapshot())

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

        return {
            "current_task": current_task,
            "task_queue": task_queue,
            "chat": {
                "active_session_id": self.get_active_app_session_id(),
            },
            "device": self.device_channel.get_snapshot(),
            "desktop_voice": self._desktop_voice_runtime(),
            "voice": self._voice_runtime_state(),
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

    def get_planning_timeline(self, *, date: str | None = None) -> list[dict[str, Any]]:
        planning = self._planning_snapshot(date=date)
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
        return {
            "tasks": self.resources.task_store.list_items(),
            "events": self.resources.event_store.list_items(),
            "reminders": self.resources.reminder_store.list_items(),
            "notifications": self.resources.notification_store.list_items(),
        }

    def _planning_snapshot(self, *, date: str | None = None) -> dict[str, Any]:
        inputs = self._planning_inputs()
        overview = self.planning_projection_service.build_overview(**inputs)
        timeline = self.planning_projection_service.build_timeline(
            tasks=inputs["tasks"],
            events=inputs["events"],
            reminders=inputs["reminders"],
            target_date=date,
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
            "app_events": True,
            "event_replay": True,
            "app_auth_enabled": bool(self.auth_token),
        }

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
