"""Planning tool for tasks, events, and reminders."""

from __future__ import annotations

import json
from contextvars import ContextVar
from copy import deepcopy
from datetime import date, datetime, timedelta
from typing import Any, Protocol
from uuid import uuid4

from nanobot.agent.tools.base import Tool


class PlanningBackend(Protocol):
    """Injected planning facade used by the planning tool."""

    async def list_tasks(
        self,
        *,
        completed: bool | None = None,
        limit: int | None = None,
    ) -> dict[str, Any]:
        ...

    async def create_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def update_task(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def list_events(self, *, limit: int | None = None) -> dict[str, Any]:
        ...

    async def create_event(self, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def update_event(self, event_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def create_reminder(self, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def update_reminder(self, reminder_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        ...

    async def snooze_reminder(
        self,
        reminder_id: str,
        *,
        snoozed_until: str | None = None,
        delay_minutes: int = 10,
    ) -> dict[str, Any]:
        ...

    async def complete_reminder(self, reminder_id: str) -> dict[str, Any]:
        ...

    async def list_reminders(self, *, limit: int | None = None) -> dict[str, Any]:
        ...


class PlanningTool(Tool):
    """Tool for lightweight planning actions backed by injected services."""

    _SUPPORTED_ACTIONS = (
        "create_task",
        "create_event",
        "create_reminder",
        "complete_task",
        "snooze_reminder",
        "list_today",
    )
    _SUPPORTED_PRIORITIES = {"high", "medium", "low"}
    _SUPPORTED_REPEATS = {"daily", "once", "weekdays", "weekends"}
    _SUPPORTED_PLANNING_SURFACES = {"agenda", "tasks", "hidden"}
    _SUPPORTED_OWNER_KINDS = {"user", "assistant"}
    _SUPPORTED_DELIVERY_MODES = {"none", "device_voice", "device_voice_and_notification"}
    _REQUEST_METADATA_KEYS = (
        "source",
        "interaction_surface",
        "capture_source",
        "voice_path",
        "planning_surface",
        "owner_kind",
        "delivery_mode",
        "reply_language",
        "emotion",
        "app_session_id",
        "scene_mode",
        "persona_profile_id",
        "persona_voice_style",
        "interaction_kind",
        "interaction_mode",
        "approval_source",
    )

    def __init__(self, backend: PlanningBackend):
        self._backend = backend
        self._source_channel_var: ContextVar[str] = ContextVar(
            "planning_source_channel",
            default="",
        )
        self._source_chat_id_var: ContextVar[str] = ContextVar(
            "planning_source_chat_id",
            default="",
        )
        self._source_message_id_var: ContextVar[str | None] = ContextVar(
            "planning_source_message_id",
            default=None,
        )
        self._task_id_var: ContextVar[str | None] = ContextVar(
            "planning_task_id",
            default=None,
        )
        self._runtime_metadata_var: ContextVar[dict[str, Any]] = ContextVar(
            "planning_runtime_metadata",
            default={},
        )
        self._turn_results_var: ContextVar[list[dict[str, Any]]] = ContextVar(
            "planning_turn_results",
            default=[],
        )
        self._turn_bundle_id_var: ContextVar[str | None] = ContextVar(
            "planning_turn_bundle_id",
            default=None,
        )

    def start_turn(self) -> None:
        """Reset per-turn structured tool results."""
        self._turn_results_var.set([])
        self._turn_bundle_id_var.set(None)

    def consume_turn_results(self) -> list[dict[str, Any]]:
        """Return and clear structured results for the current turn."""
        results = deepcopy(self._turn_results_var.get())
        self._turn_results_var.set([])
        return results

    def set_context(
        self,
        channel: str,
        chat_id: str,
        message_id: str | None = None,
        task_id: str | None = None,
        *,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Set per-turn request context so created resources stay attributable."""
        self._source_channel_var.set(channel)
        self._source_chat_id_var.set(chat_id)
        self._source_message_id_var.set(message_id)
        self._task_id_var.set(task_id)
        self._runtime_metadata_var.set(deepcopy(metadata or {}))

    @property
    def name(self) -> str:
        return "planning"

    @property
    def description(self) -> str:
        return (
            "Manage lightweight planning data. Actions: create_task, create_event, "
            "create_reminder, complete_task, snooze_reminder, list_today. "
            "Use create_event for calendar items like trips, appointments, and "
            "scheduled outings. For 'remind me' or 'wake me at' requests, prefer "
            "a task with owner_kind=assistant plus a reminder with "
            "planning_surface=hidden and delivery_mode=device_voice_and_notification "
            "instead of an agenda event. When the user "
            "asks what is due today, tomorrow, or on a "
            "specific date, call list_today before answering."
        )

    @property
    def parameters(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": list(self._SUPPORTED_ACTIONS),
                    "description": (
                        "Planning action to execute. Use create_event for itinerary/calendar "
                        "items. Use create_task plus create_reminder for reminder-style "
                        "requests. Use list_today for today/tomorrow/date queries."
                    ),
                },
                "title": {"type": "string", "description": "Resource title."},
                "description": {"type": "string", "description": "Optional task/event description."},
                "priority": {
                    "type": "string",
                    "enum": sorted(self._SUPPORTED_PRIORITIES),
                    "description": "Task priority.",
                },
                "due_at": {
                    "type": "string",
                    "description": "ISO datetime for task due time.",
                },
                "start_at": {
                    "type": "string",
                    "description": "ISO datetime when an event starts.",
                },
                "end_at": {
                    "type": "string",
                    "description": "ISO datetime when an event ends.",
                },
                "location": {"type": "string", "description": "Optional event location."},
                "time": {
                    "type": "string",
                    "description": "Reminder time as ISO datetime or HH:MM[:SS].",
                },
                "message": {"type": "string", "description": "Optional reminder message."},
                "repeat": {
                    "type": "string",
                    "description": "Reminder repeat cadence.",
                },
                "task_id": {"type": "string", "description": "Task id for updates."},
                "reminder_id": {"type": "string", "description": "Reminder id for updates."},
                "until": {
                    "type": "string",
                    "description": "ISO datetime to snooze a reminder until.",
                },
                "minutes": {
                    "type": "integer",
                    "minimum": 1,
                    "description": "Alternative snooze duration in minutes.",
                },
                "date": {
                    "type": "string",
                    "description": (
                        "Target day for list_today. Accepts YYYY-MM-DD, today, or tomorrow. "
                        "Use it whenever the user asks about tomorrow or a specific date."
                    ),
                },
                "created_via": {"type": "string", "description": "Optional origin label."},
                "source_channel": {"type": "string", "description": "Optional source channel."},
                "source_message_id": {"type": "string", "description": "Optional source message id."},
                "source_session_id": {"type": "string", "description": "Optional source session id."},
                "planning_surface": {
                    "type": "string",
                    "enum": sorted(self._SUPPORTED_PLANNING_SURFACES),
                    "description": (
                        "Optional planning surface. Use agenda, tasks, or hidden."
                    ),
                },
                "owner_kind": {
                    "type": "string",
                    "enum": sorted(self._SUPPORTED_OWNER_KINDS),
                    "description": "Optional ownership hint. Use user or assistant.",
                },
                "delivery_mode": {
                    "type": "string",
                    "enum": sorted(self._SUPPORTED_DELIVERY_MODES),
                    "description": (
                        "Optional delivery mode. Use none, device_voice, or device_voice_and_notification."
                    ),
                },
                "linked_task_id": {"type": "string", "description": "Optional linked task id."},
                "linked_event_id": {"type": "string", "description": "Optional linked event id."},
                "linked_reminder_id": {"type": "string", "description": "Optional linked reminder id."},
                "interaction_surface": {
                    "type": "string",
                    "description": "Optional physical interaction surface provenance.",
                },
                "capture_source": {
                    "type": "string",
                    "description": "Optional physical capture source provenance.",
                },
                "voice_path": {
                    "type": "string",
                    "description": "Optional voice path provenance.",
                },
                "scene_mode": {
                    "type": "string",
                    "description": "Optional runtime scene mode for audit/provenance.",
                },
                "persona_profile_id": {
                    "type": "string",
                    "description": "Optional runtime persona profile id for audit/provenance.",
                },
                "persona_voice_style": {
                    "type": "string",
                    "description": "Optional runtime persona voice style for audit/provenance.",
                },
                "interaction_kind": {
                    "type": "string",
                    "description": "Optional runtime interaction kind for audit/provenance.",
                },
                "interaction_mode": {
                    "type": "string",
                    "description": "Optional runtime interaction mode for audit/provenance.",
                },
                "approval_source": {
                    "type": "string",
                    "description": "Optional approval provenance for audit records.",
                },
            },
            "required": ["action"],
        }

    async def execute(self, action: str, **kwargs: Any) -> str:
        bundle_id = self._bundle_id_for_turn()
        try:
            if action == "create_task":
                result = await self._create_task(bundle_id=bundle_id, **kwargs)
            elif action == "create_event":
                result = await self._create_event(bundle_id=bundle_id, **kwargs)
            elif action == "create_reminder":
                result = await self._create_reminder(bundle_id=bundle_id, **kwargs)
            elif action == "complete_task":
                result = await self._complete_task(bundle_id=bundle_id, **kwargs)
            elif action == "snooze_reminder":
                result = await self._snooze_reminder(bundle_id=bundle_id, **kwargs)
            elif action == "list_today":
                result = await self._list_today(bundle_id=bundle_id, **kwargs)
            else:
                return f"Error: unsupported action '{action}'"
        except KeyError as exc:
            target = str(exc.args[0]) if exc.args else "resource"
            return f"Error: {target} not found"
        except ValueError as exc:
            return f"Error: {exc}"

        turn_results = list(self._turn_results_var.get())
        turn_results.append(deepcopy(result))
        self._turn_results_var.set(turn_results)
        return json.dumps(result, ensure_ascii=False)

    async def _create_task(
        self,
        *,
        bundle_id: str,
        title: str | None = None,
        description: str | None = None,
        priority: str | None = None,
        due_at: str | None = None,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_message_id: str | None = None,
        source_session_id: str | None = None,
        interaction_surface: str | None = None,
        capture_source: str | None = None,
        voice_path: str | None = None,
        planning_surface: str | None = None,
        owner_kind: str | None = None,
        delivery_mode: str | None = None,
        scene_mode: str | None = None,
        persona_profile_id: str | None = None,
        persona_voice_style: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
        linked_event_id: str | None = None,
        linked_reminder_id: str | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        clean_title = self._require_text(title, "title")
        clean_priority = self._normalize_priority(priority)
        normalized_due_at = self._normalize_datetime(due_at, "due_at") if due_at else None
        request_metadata = self._build_request_metadata(
            created_via=created_via,
            source_channel=source_channel,
            source_message_id=source_message_id,
            source_session_id=source_session_id,
            interaction_surface=interaction_surface,
            capture_source=capture_source,
            voice_path=voice_path,
            planning_surface=planning_surface,
            owner_kind=owner_kind,
            delivery_mode=delivery_mode,
            scene_mode=scene_mode,
            persona_profile_id=persona_profile_id,
            persona_voice_style=persona_voice_style,
            interaction_kind=interaction_kind,
            interaction_mode=interaction_mode,
            approval_source=approval_source,
        )
        metadata = self._build_creation_metadata(
            resource_type="task",
            bundle_id=bundle_id,
            request_metadata=request_metadata,
            linked_event_id=linked_event_id,
            linked_reminder_id=linked_reminder_id,
        )
        task = await self._backend.create_task(
            {
                "title": clean_title,
                "description": self._clean_optional_text(description),
                "priority": clean_priority,
                "due_at": normalized_due_at,
                **metadata,
            }
        )
        await self._backfill_linked_resources(
            task_id=task["task_id"],
            event_id=task.get("linked_event_id"),
            reminder_id=task.get("linked_reminder_id"),
        )
        return self._result_payload(
            bundle_id=bundle_id,
            action="create_task",
            resource_ids={"task_id": task["task_id"]},
            normalized_times={"due_at": task.get("due_at") or normalized_due_at},
            result={"task": task},
            message=f"Created task '{task.get('title') or clean_title}'.",
            request_metadata=request_metadata,
        )

    async def _create_event(
        self,
        *,
        bundle_id: str,
        title: str | None = None,
        start_at: str | None = None,
        end_at: str | None = None,
        description: str | None = None,
        location: str | None = None,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_message_id: str | None = None,
        source_session_id: str | None = None,
        interaction_surface: str | None = None,
        capture_source: str | None = None,
        voice_path: str | None = None,
        planning_surface: str | None = None,
        owner_kind: str | None = None,
        delivery_mode: str | None = None,
        scene_mode: str | None = None,
        persona_profile_id: str | None = None,
        persona_voice_style: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
        linked_task_id: str | None = None,
        linked_reminder_id: str | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        clean_title = self._require_text(title, "title")
        normalized_start_at = self._normalize_datetime(start_at, "start_at")
        normalized_end_at = self._normalize_datetime(end_at, "end_at")
        start_dt = self._parse_iso_datetime(normalized_start_at, "start_at")
        end_dt = self._parse_iso_datetime(normalized_end_at, "end_at")
        if end_dt <= start_dt:
            raise ValueError("end_at must be after start_at")

        conflicts = await self._detect_event_conflicts(start_dt, end_dt)
        request_metadata = self._build_request_metadata(
            created_via=created_via,
            source_channel=source_channel,
            source_message_id=source_message_id,
            source_session_id=source_session_id,
            interaction_surface=interaction_surface,
            capture_source=capture_source,
            voice_path=voice_path,
            planning_surface=planning_surface,
            owner_kind=owner_kind,
            delivery_mode=delivery_mode,
            scene_mode=scene_mode,
            persona_profile_id=persona_profile_id,
            persona_voice_style=persona_voice_style,
            interaction_kind=interaction_kind,
            interaction_mode=interaction_mode,
            approval_source=approval_source,
        )
        metadata = self._build_creation_metadata(
            resource_type="event",
            bundle_id=bundle_id,
            request_metadata=request_metadata,
            linked_task_id=linked_task_id,
            linked_reminder_id=linked_reminder_id,
        )
        event = await self._backend.create_event(
            {
                "title": clean_title,
                "start_at": normalized_start_at,
                "end_at": normalized_end_at,
                "description": self._clean_optional_text(description),
                "location": self._clean_optional_text(location),
                **metadata,
            }
        )
        await self._backfill_linked_resources(
            task_id=event.get("linked_task_id"),
            event_id=event["event_id"],
            reminder_id=event.get("linked_reminder_id"),
        )
        return self._result_payload(
            bundle_id=bundle_id,
            action="create_event",
            resource_ids={"event_id": event["event_id"]},
            normalized_times={
                "start_at": event.get("start_at") or normalized_start_at,
                "end_at": event.get("end_at") or normalized_end_at,
            },
            conflicts=conflicts,
            confirmation_needed=bool(conflicts),
            result={"event": event},
            message=f"Created event '{event.get('title') or clean_title}'.",
            request_metadata=request_metadata,
        )

    async def _create_reminder(
        self,
        *,
        bundle_id: str,
        title: str | None = None,
        time: str | None = None,
        message: str | None = None,
        repeat: str | None = None,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_message_id: str | None = None,
        source_session_id: str | None = None,
        interaction_surface: str | None = None,
        capture_source: str | None = None,
        voice_path: str | None = None,
        planning_surface: str | None = None,
        owner_kind: str | None = None,
        delivery_mode: str | None = None,
        scene_mode: str | None = None,
        persona_profile_id: str | None = None,
        persona_voice_style: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
        linked_task_id: str | None = None,
        linked_event_id: str | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        clean_title = self._require_text(title, "title")
        normalized_time = self._normalize_reminder_time(time)
        normalized_repeat = self._resolve_reminder_repeat(repeat, normalized_time)
        request_metadata = self._build_request_metadata(
            created_via=created_via,
            source_channel=source_channel,
            source_message_id=source_message_id,
            source_session_id=source_session_id,
            interaction_surface=interaction_surface,
            capture_source=capture_source,
            voice_path=voice_path,
            planning_surface=planning_surface,
            owner_kind=owner_kind,
            delivery_mode=delivery_mode,
            scene_mode=scene_mode,
            persona_profile_id=persona_profile_id,
            persona_voice_style=persona_voice_style,
            interaction_kind=interaction_kind,
            interaction_mode=interaction_mode,
            approval_source=approval_source,
        )
        if request_metadata.get("delivery_mode") is None:
            default_delivery_mode = self._default_delivery_mode_for_resource(
                resource_type="reminder",
                request_metadata=request_metadata,
            )
            if default_delivery_mode is not None:
                request_metadata["delivery_mode"] = default_delivery_mode
        metadata = self._build_creation_metadata(
            resource_type="reminder",
            bundle_id=bundle_id,
            request_metadata=request_metadata,
            linked_task_id=linked_task_id,
            linked_event_id=linked_event_id,
        )
        reminder = await self._backend.create_reminder(
            {
                "title": clean_title,
                "time": normalized_time,
                "message": self._clean_optional_text(message),
                "repeat": normalized_repeat,
                "enabled": True,
                **metadata,
            }
        )
        updated_task, _, _ = await self._backfill_linked_resources(
            task_id=reminder.get("linked_task_id"),
            event_id=reminder.get("linked_event_id"),
            reminder_id=reminder["reminder_id"],
            linked_task_delivery_mode=self._clean_optional_text(reminder.get("delivery_mode")),
        )
        if updated_task is not None:
            self._sync_turn_result_resource(
                action="create_task",
                resource_key="task_id",
                resource_id=str(updated_task["task_id"]),
                resource_type="task",
                resource=updated_task,
                request_metadata_patch={
                    "delivery_mode": self._clean_optional_text(updated_task.get("delivery_mode")),
                },
            )
        return self._result_payload(
            bundle_id=bundle_id,
            action="create_reminder",
            resource_ids={"reminder_id": reminder["reminder_id"]},
            normalized_times={
                "time": reminder.get("time") or normalized_time,
                "next_trigger_at": reminder.get("next_trigger_at"),
            },
            result={"reminder": reminder},
            message=f"Created reminder '{reminder.get('title') or clean_title}'.",
            request_metadata=request_metadata,
        )

    async def _complete_task(
        self,
        *,
        bundle_id: str,
        task_id: str | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        clean_task_id = self._require_text(task_id, "task_id")
        task = await self._backend.update_task(clean_task_id, {"completed": True})
        request_metadata = self._build_request_metadata()
        return self._result_payload(
            bundle_id=bundle_id,
            action="complete_task",
            resource_ids={"task_id": task["task_id"]},
            normalized_times={"due_at": task.get("due_at")},
            result={"task": task},
            message=f"Completed task '{task.get('title') or clean_task_id}'.",
            request_metadata=request_metadata,
        )

    async def _snooze_reminder(
        self,
        *,
        bundle_id: str,
        reminder_id: str | None = None,
        until: str | None = None,
        minutes: int | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        clean_reminder_id = self._require_text(reminder_id, "reminder_id")
        reminder = await self._get_reminder(clean_reminder_id)
        normalized_until = self._resolve_snooze_time(reminder, until=until, minutes=minutes)
        updated = await self._backend.snooze_reminder(
            clean_reminder_id,
            snoozed_until=normalized_until,
            delay_minutes=minutes or 10,
        )
        request_metadata = self._build_request_metadata()
        return self._result_payload(
            bundle_id=bundle_id,
            action="snooze_reminder",
            resource_ids={"reminder_id": updated["reminder_id"]},
            normalized_times={
                "snoozed_until": updated.get("snoozed_until") or normalized_until,
                "next_trigger_at": updated.get("next_trigger_at"),
            },
            result={"reminder": updated},
            message=f"Snoozed reminder '{updated.get('title') or clean_reminder_id}'.",
            request_metadata=request_metadata,
        )

    async def _list_today(
        self,
        *,
        bundle_id: str,
        date: str | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        target_day = self._normalize_date(date)
        tasks_result = await self._backend.list_tasks(completed=False, limit=200)
        events_result = await self._backend.list_events(limit=200)
        reminders_result = await self._backend.list_reminders(limit=200)

        tasks = [
            task for task in tasks_result.get("items", [])
            if self._matches_day(task.get("due_at"), target_day)
            and self._planning_surface_matches(
                task,
                resource_type="task",
                allowed_surfaces={"tasks"},
            )
        ]
        events = [
            event for event in events_result.get("items", [])
            if self._event_matches_day(event, target_day)
            and self._planning_surface_matches(
                event,
                resource_type="event",
                allowed_surfaces={"agenda"},
            )
        ]
        reminders = [
            reminder for reminder in reminders_result.get("items", [])
            if self._reminder_matches_day(reminder, target_day)
        ]

        request_metadata = self._build_request_metadata()
        return self._result_payload(
            bundle_id=bundle_id,
            action="list_today",
            resource_ids={
                "task_ids": [task["task_id"] for task in tasks],
                "event_ids": [event["event_id"] for event in events],
                "reminder_ids": [reminder["reminder_id"] for reminder in reminders],
            },
            normalized_times={"date": target_day.isoformat()},
            result={
                "date": target_day.isoformat(),
                "tasks": tasks,
                "events": events,
                "reminders": reminders,
            },
            message=f"Listed planning items for {target_day.isoformat()}.",
            request_metadata=request_metadata,
        )

    async def _detect_event_conflicts(
        self,
        start_dt: datetime,
        end_dt: datetime,
    ) -> list[dict[str, Any]]:
        result = await self._backend.list_events(limit=200)
        conflicts: list[dict[str, Any]] = []
        for event in result.get("items", []):
            try:
                existing_start = self._parse_iso_datetime(event.get("start_at"), "start_at")
                existing_end = self._parse_iso_datetime(event.get("end_at"), "end_at")
            except ValueError:
                continue
            if start_dt < existing_end and end_dt > existing_start:
                conflicts.append(
                    {
                        "kind": "event_overlap",
                        "event_id": event.get("event_id"),
                        "title": event.get("title"),
                        "start_at": event.get("start_at"),
                        "end_at": event.get("end_at"),
                    }
                )
        return conflicts

    async def _get_reminder(self, reminder_id: str) -> dict[str, Any]:
        result = await self._backend.list_reminders(limit=200)
        for reminder in result.get("items", []):
            if reminder.get("reminder_id") == reminder_id:
                return reminder
        raise KeyError(reminder_id)

    def _resolve_snooze_time(
        self,
        reminder: dict[str, Any],
        *,
        until: str | None,
        minutes: int | None,
    ) -> str:
        if until:
            return self._normalize_datetime(until, "until")
        if minutes is None or minutes < 1:
            raise ValueError("provide either until or minutes for snooze_reminder")

        base_value = reminder.get("next_trigger_at") or reminder.get("time")
        if isinstance(base_value, str) and "T" in base_value:
            base_dt = self._parse_iso_datetime(base_value, "time")
        else:
            base_dt = datetime.now().astimezone()
        return (base_dt + timedelta(minutes=minutes)).isoformat()

    def _bundle_id_for_turn(self) -> str:
        bundle_id = self._turn_bundle_id_var.get()
        if bundle_id is None:
            bundle_id = f"planning_{uuid4().hex}"
            self._turn_bundle_id_var.set(bundle_id)
        return bundle_id

    def _build_creation_metadata(
        self,
        *,
        resource_type: str,
        bundle_id: str,
        request_metadata: dict[str, Any],
        linked_task_id: str | None = None,
        linked_event_id: str | None = None,
        linked_reminder_id: str | None = None,
    ) -> dict[str, Any]:
        recent_resource_ids = self._latest_created_resource_ids()
        metadata: dict[str, Any] = {
            "bundle_id": bundle_id,
            "created_via": request_metadata.get("created_via") or "agent",
            "source_channel": request_metadata.get("source_channel") or "agent",
            "interaction_surface": request_metadata.get("interaction_surface"),
            "capture_source": request_metadata.get("capture_source"),
            "voice_path": request_metadata.get("voice_path"),
            "planning_surface": request_metadata.get("planning_surface"),
            "owner_kind": request_metadata.get("owner_kind"),
            "delivery_mode": request_metadata.get("delivery_mode"),
        }
        optional_source_fields = {
            "source_message_id": request_metadata.get("source_message_id"),
            "source_session_id": request_metadata.get("source_session_id"),
        }
        metadata.update({key: value for key, value in optional_source_fields.items() if value is not None})

        if resource_type != "task":
            metadata["linked_task_id"] = self._clean_optional_text(linked_task_id) or recent_resource_ids.get("task_id")
        if resource_type != "event":
            metadata["linked_event_id"] = self._clean_optional_text(linked_event_id) or recent_resource_ids.get("event_id")
        if resource_type != "reminder":
            metadata["linked_reminder_id"] = self._clean_optional_text(linked_reminder_id) or recent_resource_ids.get("reminder_id")
        return {key: value for key, value in metadata.items() if value is not None}

    def _build_request_metadata(
        self,
        *,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_message_id: str | None = None,
        source_session_id: str | None = None,
        interaction_surface: str | None = None,
        capture_source: str | None = None,
        voice_path: str | None = None,
        planning_surface: str | None = None,
        owner_kind: str | None = None,
        delivery_mode: str | None = None,
        scene_mode: str | None = None,
        persona_profile_id: str | None = None,
        persona_voice_style: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
    ) -> dict[str, Any]:
        channel = self._clean_optional_text(source_channel) or self._source_channel_var.get() or None
        chat_id = self._source_chat_id_var.get()
        request_metadata: dict[str, Any] = {
            "created_via": self._clean_optional_text(created_via) or "agent",
            "source_channel": channel or "agent",
        }

        resolved_message_id = self._clean_optional_text(source_message_id) or self._source_message_id_var.get()
        if resolved_message_id:
            request_metadata["source_message_id"] = resolved_message_id

        resolved_session_id = self._clean_optional_text(source_session_id)
        if resolved_session_id is None and channel and chat_id:
            resolved_session_id = f"{channel}:{chat_id}"
        if resolved_session_id:
            request_metadata["source_session_id"] = resolved_session_id

        resolved_task_id = self._task_id_var.get()
        if resolved_task_id:
            request_metadata["task_id"] = resolved_task_id

        runtime_metadata = deepcopy(self._runtime_metadata_var.get())
        explicit_runtime_metadata = {
            "interaction_surface": interaction_surface,
            "capture_source": capture_source,
            "voice_path": voice_path,
            "planning_surface": planning_surface,
            "owner_kind": owner_kind,
            "delivery_mode": delivery_mode,
            "scene_mode": scene_mode,
            "persona_profile_id": persona_profile_id,
            "persona_voice_style": persona_voice_style,
            "interaction_kind": interaction_kind,
            "interaction_mode": interaction_mode,
            "approval_source": approval_source,
        }
        for key in self._REQUEST_METADATA_KEYS:
            raw_value = explicit_runtime_metadata.get(key)
            if raw_value is None:
                raw_value = runtime_metadata.get(key)
            cleaned = self._clean_optional_text(raw_value)
            if cleaned is not None:
                if key == "planning_surface":
                    cleaned = self._normalize_optional_enum(
                        cleaned,
                        "planning_surface",
                        self._SUPPORTED_PLANNING_SURFACES,
                    )
                elif key == "owner_kind":
                    cleaned = self._normalize_optional_enum(
                        cleaned,
                        "owner_kind",
                        self._SUPPORTED_OWNER_KINDS,
                    )
                elif key == "delivery_mode":
                    cleaned = self._normalize_optional_enum(
                        cleaned,
                        "delivery_mode",
                        self._SUPPORTED_DELIVERY_MODES,
                    )
                request_metadata[key] = cleaned
        return request_metadata

    def _latest_created_resource_ids(self) -> dict[str, str]:
        resource_ids: dict[str, str] = {}
        for payload in reversed(self._turn_results_var.get()):
            current_ids = payload.get("resource_ids", {})
            if not isinstance(current_ids, dict):
                continue
            for key in ("task_id", "event_id", "reminder_id"):
                value = current_ids.get(key)
                if key not in resource_ids and isinstance(value, str) and value.strip():
                    resource_ids[key] = value.strip()
        return resource_ids

    async def _backfill_linked_resources(
        self,
        *,
        task_id: str | None = None,
        event_id: str | None = None,
        reminder_id: str | None = None,
        linked_task_delivery_mode: str | None = None,
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None, dict[str, Any] | None]:
        updated_task: dict[str, Any] | None = None
        updated_event: dict[str, Any] | None = None
        updated_reminder: dict[str, Any] | None = None
        if task_id and event_id:
            updated_task = await self._backend.update_task(task_id, {"linked_event_id": event_id})
            updated_event = await self._backend.update_event(event_id, {"linked_task_id": task_id})
        if task_id and reminder_id:
            task_patch: dict[str, Any] = {"linked_reminder_id": reminder_id}
            if linked_task_delivery_mode is not None:
                task_patch["delivery_mode"] = linked_task_delivery_mode
            updated_task = await self._backend.update_task(task_id, task_patch)
            updated_reminder = await self._backend.update_reminder(reminder_id, {"linked_task_id": task_id})
        if event_id and reminder_id:
            updated_event = await self._backend.update_event(event_id, {"linked_reminder_id": reminder_id})
            updated_reminder = await self._backend.update_reminder(reminder_id, {"linked_event_id": event_id})
        return updated_task, updated_event, updated_reminder

    @staticmethod
    def _default_delivery_mode_for_resource(
        *,
        resource_type: str,
        request_metadata: dict[str, Any],
    ) -> str | None:
        if request_metadata.get("delivery_mode") is not None:
            return request_metadata["delivery_mode"]
        if (
            resource_type == "reminder"
            and request_metadata.get("planning_surface") == "hidden"
            and request_metadata.get("owner_kind") == "assistant"
        ):
            return "device_voice_and_notification"
        return None

    def _sync_turn_result_resource(
        self,
        *,
        action: str,
        resource_key: str,
        resource_id: str,
        resource_type: str,
        resource: dict[str, Any],
        request_metadata_patch: dict[str, Any] | None = None,
    ) -> None:
        updated_results: list[dict[str, Any]] = []
        for payload in self._turn_results_var.get():
            current = deepcopy(payload)
            current_ids = current.get("resource_ids")
            if (
                current.get("action") == action
                and isinstance(current_ids, dict)
                and current_ids.get(resource_key) == resource_id
            ):
                result_payload = current.setdefault("result", {})
                if isinstance(result_payload, dict):
                    result_payload[resource_type] = deepcopy(resource)
                if request_metadata_patch:
                    metadata = current.setdefault("request_metadata", {})
                    if isinstance(metadata, dict):
                        for key, value in request_metadata_patch.items():
                            if value is not None:
                                metadata[key] = value
            updated_results.append(current)
        self._turn_results_var.set(updated_results)

    @staticmethod
    def _result_payload(
        *,
        bundle_id: str,
        action: str,
        resource_ids: dict[str, Any],
        normalized_times: dict[str, Any],
        result: dict[str, Any],
        message: str,
        conflicts: list[dict[str, Any]] | None = None,
        confirmation_needed: bool = False,
        request_metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return {
            "ok": True,
            "bundle_id": bundle_id,
            "action": action,
            "resource_ids": resource_ids,
            "normalized_times": normalized_times,
            "conflicts": conflicts or [],
            "confirmation_needed": confirmation_needed,
            "result": result,
            "message": message,
            "request_metadata": deepcopy(request_metadata or {}),
        }

    @staticmethod
    def _require_text(value: Any, field: str) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field} is required")
        return value.strip()

    @staticmethod
    def _clean_optional_text(value: Any) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise ValueError("text fields must be strings")
        cleaned = value.strip()
        return cleaned or None

    def _normalize_priority(self, value: Any) -> str:
        if value is None:
            return "medium"
        clean = self._require_text(value, "priority").lower()
        if clean not in self._SUPPORTED_PRIORITIES:
            raise ValueError("priority must be one of: high, medium, low")
        return clean

    def _normalize_repeat(self, value: Any) -> str:
        if value is None:
            return "daily"
        clean = self._require_text(value, "repeat").lower()
        if clean not in self._SUPPORTED_REPEATS:
            raise ValueError("repeat must be one of: daily, once, weekdays, weekends")
        return clean

    def _resolve_reminder_repeat(self, value: Any, normalized_time: str) -> str:
        if value is not None:
            return self._normalize_repeat(value)
        if "T" in normalized_time:
            return "once"
        return "daily"

    @staticmethod
    def _normalize_optional_enum(
        value: str,
        field: str,
        supported: set[str],
    ) -> str:
        clean = value.strip().lower()
        if clean not in supported:
            allowed = ", ".join(sorted(supported))
            raise ValueError(f"{field} must be one of: {allowed}")
        return clean

    @staticmethod
    def _normalize_datetime(value: Any, field: str) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field} is required")
        return PlanningTool._parse_iso_datetime(value.strip(), field).isoformat()

    @staticmethod
    def _normalize_reminder_time(value: Any) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ValueError("time is required")
        clean = value.strip()
        if "T" in clean:
            return PlanningTool._parse_iso_datetime(clean, "time").isoformat()
        return PlanningTool._normalize_clock_time(clean)

    @staticmethod
    def _normalize_clock_time(value: str) -> str:
        parts = value.split(":")
        if len(parts) not in (2, 3):
            raise ValueError("time must be ISO datetime or HH:MM[:SS]")
        try:
            hour = int(parts[0])
            minute = int(parts[1])
            second = int(parts[2]) if len(parts) == 3 else 0
        except ValueError as exc:
            raise ValueError("time must be ISO datetime or HH:MM[:SS]") from exc
        if not (0 <= hour <= 23 and 0 <= minute <= 59 and 0 <= second <= 59):
            raise ValueError("time must be ISO datetime or HH:MM[:SS]")
        return f"{hour:02d}:{minute:02d}:{second:02d}"

    @staticmethod
    def _parse_iso_datetime(value: Any, field: str) -> datetime:
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field} is required")
        clean = value.strip()
        if clean.endswith("Z"):
            clean = clean[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(clean)
        except ValueError as exc:
            raise ValueError(f"{field} must be a valid ISO datetime") from exc

    @staticmethod
    def _normalize_date(value: str | None) -> date:
        if value is None:
            return datetime.now().astimezone().date()
        clean = value.strip().lower()
        if clean == "today":
            return datetime.now().astimezone().date()
        if clean == "tomorrow":
            return datetime.now().astimezone().date() + timedelta(days=1)
        try:
            return date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("date must be YYYY-MM-DD, today, or tomorrow") from exc

    @staticmethod
    def _matches_day(value: Any, target_day: date) -> bool:
        if not isinstance(value, str) or not value.strip():
            return False
        if "T" not in value:
            return False
        try:
            return PlanningTool._parse_iso_datetime(value, "date").date() == target_day
        except ValueError:
            return False

    @staticmethod
    def _event_matches_day(event: dict[str, Any], target_day: date) -> bool:
        try:
            start_dt = PlanningTool._parse_iso_datetime(event.get("start_at"), "start_at")
            end_dt = PlanningTool._parse_iso_datetime(event.get("end_at"), "end_at")
        except ValueError:
            return False
        return start_dt.date() <= target_day <= end_dt.date()

    @staticmethod
    def _reminder_matches_day(reminder: dict[str, Any], target_day: date) -> bool:
        if not bool(reminder.get("enabled", True)):
            return False

        next_trigger_at = reminder.get("next_trigger_at")
        if isinstance(next_trigger_at, str) and "T" in next_trigger_at:
            try:
                return PlanningTool._parse_iso_datetime(next_trigger_at, "next_trigger_at").date() == target_day
            except ValueError:
                return False

        raw_time = reminder.get("time")
        if isinstance(raw_time, str) and "T" in raw_time:
            try:
                return PlanningTool._parse_iso_datetime(raw_time, "time").date() == target_day
            except ValueError:
                return False

        repeat = str(reminder.get("repeat") or "daily").strip().lower()
        if repeat == "weekdays":
            return target_day.weekday() < 5
        if repeat == "weekends":
            return target_day.weekday() >= 5
        return True

    @staticmethod
    def _planning_surface_matches(
        item: dict[str, Any],
        *,
        resource_type: str,
        allowed_surfaces: set[str],
    ) -> bool:
        explicit = str(item.get("planning_surface") or "").strip().lower()
        if explicit:
            return explicit in allowed_surfaces
        fallback = {
            "event": "agenda",
            "task": "tasks",
            "reminder": "agenda",
        }.get(resource_type, "agenda")
        return fallback in allowed_surfaces
