from __future__ import annotations

from datetime import date, datetime
from typing import Any, Callable


DEFAULT_PLANNING_SURFACES = {
    "event": "agenda",
    "task": "tasks",
    "reminder": "agenda",
}
HIDDEN_PLANNING_SURFACE = "hidden"
CANONICAL_PLANNING_SURFACES = {
    "agenda",
    "tasks",
    HIDDEN_PLANNING_SURFACE,
}


class PlanningProjectionService:
    """Builds workbench projections from tasks, events, and reminders."""

    def __init__(self, now_provider: Callable[[], datetime] | None = None) -> None:
        self.now_provider = now_provider or (lambda: datetime.now().astimezone())

    def project(
        self,
        *,
        tasks: list[dict[str, Any]] | None = None,
        events: list[dict[str, Any]] | None = None,
        reminders: list[dict[str, Any]] | None = None,
        now: datetime | str | None = None,
    ) -> dict[str, Any]:
        task_items = tasks or []
        event_items = events or []
        reminder_items = reminders or []
        now_dt = self._resolve_now(now)
        timeline = self.build_timeline(
            tasks=task_items,
            events=event_items,
            reminders=reminder_items,
        )
        conflicts = self.build_conflicts(
            tasks=task_items,
            events=event_items,
            reminders=reminder_items,
        )
        return {
            "overview": {
                "counts": {
                    "tasks": len(task_items),
                    "events": len(event_items),
                    "reminders": len(reminder_items),
                    "timeline_items": len(timeline),
                    "conflicts": len(conflicts),
                },
                "next_item_at": self._next_timeline_at(timeline, now=now_dt),
                "generated_at": self._format_dt(now_dt),
            },
            "timeline": timeline,
            "conflicts": conflicts,
        }

    def build_timeline(
        self,
        *,
        tasks: list[dict[str, Any]],
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
        target_date: date | str | None = None,
        surface: str | list[str] | tuple[str, ...] | set[str] | None = None,
        planning_surface: str | list[str] | tuple[str, ...] | set[str] | None = None,
    ) -> list[dict[str, Any]]:
        now = self.now_provider()
        effective_surface = planning_surface if planning_surface is not None else surface
        items = [
            *[self._project_task(item, now=now) for item in tasks],
            *[self._project_event(item) for item in events],
            *[self._project_reminder(item, now=now) for item in reminders],
        ]
        resolved_target_date = self._resolve_target_date(target_date)
        if resolved_target_date is not None:
            items = [
                item
                for item in items
                if self._timeline_matches_date(item, resolved_target_date)
            ]
        items = [
            item
            for item in items
            if self._matches_planning_surface(item, planning_surface=effective_surface)
        ]
        items.sort(key=self._timeline_sort_key)
        return items

    def filter_timeline_for_date(
        self,
        timeline: list[dict[str, Any]],
        target_date: date | str,
        surface: str | list[str] | tuple[str, ...] | set[str] | None = None,
        planning_surface: str | list[str] | tuple[str, ...] | set[str] | None = None,
    ) -> list[dict[str, Any]]:
        resolved_target_date = self._resolve_target_date(target_date)
        effective_surface = planning_surface if planning_surface is not None else surface
        filtered = list(timeline)
        if resolved_target_date is not None:
            filtered = [
                item
                for item in filtered
                if self._timeline_matches_date(item, resolved_target_date)
            ]
        return [
            item
            for item in filtered
            if self._matches_planning_surface(item, planning_surface=effective_surface)
        ]

    def build_conflicts(
        self,
        *,
        tasks: list[dict[str, Any]],
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        conflicts: list[dict[str, Any]] = []

        parsed_events = [
            (
                item,
                self._parse_dt(item.get("start_at")),
                self._parse_dt(item.get("end_at")),
            )
            for item in events
            if self._is_visible_on_default_surface(item, resource_type="event")
        ]
        parsed_reminders = [
            (
                item,
                self._parse_dt(item.get("next_trigger_at") or item.get("snoozed_until") or item.get("time")),
            )
            for item in reminders
            if bool(item.get("enabled", True))
            and item.get("completed_at") is None
            and str(item.get("status") or "").strip().lower() != "completed"
            and self._is_visible_on_default_surface(item, resource_type="reminder")
        ]
        parsed_tasks = [
            (item, self._parse_dt(item.get("due_at")))
            for item in tasks
            if not bool(item.get("completed", False))
            and self._is_visible_on_default_surface(item, resource_type="task")
        ]

        for index, (left, left_start, left_end) in enumerate(parsed_events):
            if left_start is None or left_end is None:
                continue
            for right, right_start, right_end in parsed_events[index + 1:]:
                if right_start is None or right_end is None:
                    continue
                if left_start < right_end and right_start < left_end:
                    conflicts.append(
                        self._build_conflict(
                            "event_overlap",
                            "high",
                            "Events overlap on the planning timeline.",
                            left_start,
                            left,
                            right,
                        )
                    )

        for event, event_start, event_end in parsed_events:
            if event_start is None or event_end is None:
                continue
            for reminder, reminder_at in parsed_reminders:
                if reminder_at is None:
                    continue
                if event_start <= reminder_at < event_end:
                    conflicts.append(
                        self._build_conflict(
                            "reminder_during_event",
                            "medium",
                            "Reminder triggers during an event window.",
                            reminder_at,
                            reminder,
                            event,
                        )
                    )

        for task, due_at in parsed_tasks:
            if due_at is None:
                continue
            for event, event_start, event_end in parsed_events:
                if event_start is None or not self._is_high_priority(event):
                    continue
                if self._same_business_minute(due_at, event_start):
                    conflicts.append(
                        self._build_conflict(
                            "task_due_conflict",
                            "high",
                            "Task due time collides with a high-priority event.",
                            due_at,
                            task,
                            event,
                        )
                    )
            for reminder, reminder_at in parsed_reminders:
                if reminder_at is None or not self._is_high_priority(reminder):
                    continue
                if self._same_business_minute(reminder_at, due_at):
                    conflicts.append(
                        self._build_conflict(
                            "task_due_conflict",
                            "high",
                            "Task due time collides with a high-priority reminder.",
                            due_at,
                            task,
                            reminder,
                        )
                    )

        return conflicts

    def build_overview(
        self,
        *,
        tasks: list[dict[str, Any]],
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
        notifications: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        timeline = self.build_timeline(tasks=tasks, events=events, reminders=reminders)
        conflicts = self.build_conflicts(tasks=tasks, events=events, reminders=reminders)
        now = self.now_provider()

        pending_tasks = [
            item
            for item in tasks
            if not bool(item.get("completed", False))
            and self._is_visible_on_default_surface(item, resource_type="task")
        ]
        overdue_tasks = [
            item
            for item in pending_tasks
            if (due_at := self._parse_dt(item.get("due_at"))) is not None and due_at < now
        ]
        today_events = [
            item
            for item in events
            if (start := self._parse_dt(item.get("start_at"))) is not None
            and start.astimezone(now.tzinfo).date() == now.date()
            and self._is_visible_on_default_surface(item, resource_type="event")
        ]
        active_reminders = [
            item
            for item in reminders
            if bool(item.get("enabled", True)) and item.get("completed_at") is None
            and self._is_visible_on_default_surface(item, resource_type="reminder")
        ]
        unread_notifications = sum(
            1 for item in (notifications or []) if not bool(item.get("read", False))
        )

        next_task_due_at = self._first_sorted(
            self._parse_dt(item.get("due_at")) for item in pending_tasks
        )
        next_event = self._next_event(events, now=now)
        next_reminder = self._next_reminder(reminders, now=now)

        return {
            "generated_at": self._format_dt(now),
            "counts": {
                "task_count": len(tasks),
                "pending_task_count": len(pending_tasks),
                "overdue_task_count": len(overdue_tasks),
                "event_count": len(events),
                "today_event_count": len(today_events),
                "reminder_count": len(reminders),
                "active_reminder_count": len(active_reminders),
                "conflict_count": len(conflicts),
                "unread_notification_count": unread_notifications,
                "timeline_count": len(timeline),
            },
            "highlights": {
                "next_task_due_at": self._format_optional_dt(next_task_due_at),
                "next_event_at": next_event.get("at"),
                "next_event_title": next_event.get("title"),
                "next_reminder_at": next_reminder.get("at"),
                "next_reminder_title": next_reminder.get("title"),
            },
        }

    def _project_task(self, item: dict[str, Any], *, now: datetime) -> dict[str, Any]:
        due_at = self._parse_dt(item.get("due_at"))
        planning_surface = self._resolved_planning_surface(item, resource_type="task")
        is_overdue = (
            due_at is not None
            and due_at < now
            and not bool(item.get("completed", False))
        )
        return {
            "item_type": "task",
            "item_id": item.get("task_id"),
            "resource_type": "task",
            "resource_id": item.get("task_id"),
            "bundle_id": item.get("bundle_id"),
            "title": item.get("title"),
            "description": item.get("description"),
            "sort_at": self._format_optional_dt(due_at),
            "start_at": self._format_optional_dt(due_at),
            "starts_at": self._format_optional_dt(due_at),
            "end_at": None,
            "ends_at": None,
            "due_at": self._format_optional_dt(due_at),
            "business_at": self._format_optional_dt(due_at),
            "business_end_at": None,
            "status": "completed" if bool(item.get("completed", False)) else "pending",
            "completed": bool(item.get("completed", False)),
            "is_overdue": is_overdue,
            "overdue_at": self._format_optional_dt(due_at) if is_overdue else None,
            "enabled": True,
            "priority": item.get("priority"),
            "time_kind": "due" if due_at else "backlog",
            "planning_surface": planning_surface,
            "owner_kind": self._clean_optional_text(item.get("owner_kind")),
            "delivery_mode": self._clean_optional_text(item.get("delivery_mode")),
            "created_via": item.get("created_via"),
            "source_channel": item.get("source_channel"),
            "source_message_id": item.get("source_message_id"),
            "source_session_id": item.get("source_session_id"),
            "linked_task_id": item.get("linked_task_id"),
            "linked_event_id": item.get("linked_event_id"),
            "linked_reminder_id": item.get("linked_reminder_id"),
        }

    def _project_event(self, item: dict[str, Any]) -> dict[str, Any]:
        start_at = self._parse_dt(item.get("start_at"))
        end_at = self._parse_dt(item.get("end_at"))
        planning_surface = self._resolved_planning_surface(item, resource_type="event")
        return {
            "item_type": "event",
            "item_id": item.get("event_id"),
            "resource_type": "event",
            "resource_id": item.get("event_id"),
            "bundle_id": item.get("bundle_id"),
            "title": item.get("title"),
            "description": item.get("description"),
            "sort_at": self._format_optional_dt(start_at),
            "start_at": self._format_optional_dt(start_at),
            "starts_at": self._format_optional_dt(start_at),
            "end_at": self._format_optional_dt(end_at),
            "ends_at": self._format_optional_dt(end_at),
            "due_at": None,
            "business_at": self._format_optional_dt(start_at),
            "business_end_at": self._format_optional_dt(end_at),
            "status": "scheduled",
            "completed": False,
            "is_overdue": False,
            "overdue_at": None,
            "enabled": True,
            "priority": item.get("priority"),
            "time_kind": "window",
            "planning_surface": planning_surface,
            "owner_kind": self._clean_optional_text(item.get("owner_kind")),
            "delivery_mode": self._clean_optional_text(item.get("delivery_mode")),
            "created_via": item.get("created_via"),
            "source_channel": item.get("source_channel"),
            "source_message_id": item.get("source_message_id"),
            "source_session_id": item.get("source_session_id"),
            "location": item.get("location"),
            "linked_task_id": item.get("linked_task_id"),
            "linked_event_id": item.get("linked_event_id"),
            "linked_reminder_id": item.get("linked_reminder_id"),
        }

    def _project_reminder(self, item: dict[str, Any], *, now: datetime) -> dict[str, Any]:
        trigger_at = self._parse_dt(
            item.get("next_trigger_at") or item.get("snoozed_until") or item.get("time")
        )
        planning_surface = self._resolved_planning_surface(item, resource_type="reminder")
        status = item.get("status") or ("scheduled" if bool(item.get("enabled", True)) else "disabled")
        normalized_status = str(status).strip().lower()
        is_overdue = normalized_status == "overdue" or (
            trigger_at is not None
            and trigger_at < now
            and item.get("completed_at") is None
            and normalized_status in {"scheduled", "snoozed"}
        )
        return {
            "item_type": "reminder",
            "item_id": item.get("reminder_id"),
            "resource_type": "reminder",
            "resource_id": item.get("reminder_id"),
            "bundle_id": item.get("bundle_id"),
            "title": item.get("title"),
            "description": item.get("message"),
            "sort_at": self._format_optional_dt(trigger_at),
            "start_at": self._format_optional_dt(trigger_at),
            "starts_at": self._format_optional_dt(trigger_at),
            "end_at": None,
            "ends_at": None,
            "due_at": None,
            "business_at": self._format_optional_dt(trigger_at),
            "business_end_at": None,
            "status": status,
            "completed": item.get("completed_at") is not None or str(item.get("status") or "").strip().lower() == "completed",
            "is_overdue": is_overdue,
            "overdue_at": self._format_optional_dt(trigger_at) if is_overdue else None,
            "enabled": bool(item.get("enabled", True)),
            "priority": item.get("priority"),
            "time_kind": "trigger",
            "planning_surface": planning_surface,
            "owner_kind": self._clean_optional_text(item.get("owner_kind")),
            "delivery_mode": self._clean_optional_text(item.get("delivery_mode")),
            "created_via": item.get("created_via"),
            "source_channel": item.get("source_channel"),
            "source_message_id": item.get("source_message_id"),
            "source_session_id": item.get("source_session_id"),
            "repeat": item.get("repeat"),
            "linked_task_id": item.get("linked_task_id"),
            "linked_event_id": item.get("linked_event_id"),
            "linked_reminder_id": item.get("linked_reminder_id"),
            "next_trigger_at": item.get("next_trigger_at"),
            "snoozed_until": item.get("snoozed_until"),
        }

    def _build_conflict(
        self,
        conflict_type: str,
        severity: str,
        message: str,
        when: datetime,
        *items: dict[str, Any],
    ) -> dict[str, Any]:
        refs = []
        for item in items:
            refs.append(
                {
                    "item_type": self._item_type_for(item),
                    "item_id": self._item_id_for(item),
                    "title": item.get("title"),
                    "bundle_id": item.get("bundle_id"),
                }
            )
        return {
            "conflict_id": f"conflict_{conflict_type}_{abs(hash((conflict_type, tuple(ref['item_id'] for ref in refs))))}",
            "kind": conflict_type,
            "type": conflict_type,
            "severity": severity,
            "message": message,
            "at": self._format_dt(when),
            "items": [
                {
                    "resource_type": ref["item_type"],
                    "resource_id": ref["item_id"],
                    "title": ref["title"],
                }
                for ref in refs
            ],
            "item_refs": refs,
        }

    @staticmethod
    def _item_type_for(item: dict[str, Any]) -> str:
        if "task_id" in item:
            return "task"
        if "event_id" in item:
            return "event"
        if "reminder_id" in item:
            return "reminder"
        return "item"

    @staticmethod
    def _item_id_for(item: dict[str, Any]) -> str | None:
        for key in ("task_id", "event_id", "reminder_id", "notification_id"):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                return value
        return None

    @staticmethod
    def _timeline_sort_key(item: dict[str, Any]) -> tuple[int, datetime, int, str]:
        type_order = {
            "event": 0,
            "reminder": 1,
            "task": 2,
        }
        sort_at = item.get("sort_at")
        parsed = PlanningProjectionService._parse_dt(sort_at)
        return (
            0 if parsed is not None else 1,
            parsed or datetime.max.replace(tzinfo=datetime.now().astimezone().tzinfo),
            type_order.get(item.get("resource_type") or item.get("item_type"), 99),
            item.get("title") or "",
        )

    def _next_event(self, events: list[dict[str, Any]], *, now: datetime) -> dict[str, str | None]:
        upcoming = []
        for item in events:
            if not self._is_visible_on_default_surface(item, resource_type="event"):
                continue
            start = self._parse_dt(item.get("start_at"))
            if start is None or start < now:
                continue
            upcoming.append((start, item))
        if not upcoming:
            return {"at": None, "title": None}
        upcoming.sort(key=lambda entry: entry[0])
        return {
            "at": self._format_dt(upcoming[0][0]),
            "title": str(upcoming[0][1].get("title") or "").strip() or None,
        }

    def _next_reminder(self, reminders: list[dict[str, Any]], *, now: datetime) -> dict[str, str | None]:
        upcoming = []
        for item in reminders:
            if (
                not bool(item.get("enabled", True))
                or item.get("completed_at") is not None
                or not self._is_visible_on_default_surface(item, resource_type="reminder")
            ):
                continue
            trigger_at = self._parse_dt(
                item.get("next_trigger_at") or item.get("snoozed_until") or item.get("time")
            )
            if trigger_at is None or trigger_at < now:
                continue
            upcoming.append((trigger_at, item))
        if not upcoming:
            return {"at": None, "title": None}
        upcoming.sort(key=lambda entry: entry[0])
        return {
            "at": self._format_dt(upcoming[0][0]),
            "title": str(upcoming[0][1].get("title") or "").strip() or None,
        }

    @staticmethod
    def _parse_dt(value: Any) -> datetime | None:
        if not isinstance(value, str) or not value.strip():
            return None
        try:
            parsed = datetime.fromisoformat(value.strip())
        except ValueError:
            return None
        if parsed.tzinfo is None:
            return parsed.astimezone()
        return parsed.astimezone()

    @staticmethod
    def _format_dt(value: datetime) -> str:
        return value.astimezone().isoformat(timespec="seconds")

    def _format_optional_dt(self, value: datetime | None) -> str | None:
        return self._format_dt(value) if value is not None else None

    @staticmethod
    def _first_sorted(values: Any) -> datetime | None:
        filtered = sorted([value for value in values if value is not None])
        return filtered[0] if filtered else None

    def _next_timeline_at(
        self,
        timeline: list[dict[str, Any]],
        *,
        now: datetime,
    ) -> str | None:
        for item in timeline:
            starts_at = self._parse_dt(item.get("starts_at"))
            if starts_at is None:
                continue
            if item.get("resource_type") == "event":
                ends_at = self._parse_dt(item.get("ends_at"))
                if ends_at is not None and ends_at < now:
                    continue
                return self._format_dt(starts_at)
            if item.get("status") in {"completed", "disabled"}:
                continue
            if starts_at >= now:
                return self._format_dt(starts_at)
        return None

    def _resolve_now(self, value: datetime | str | None) -> datetime:
        if isinstance(value, datetime):
            return value.astimezone()
        if isinstance(value, str):
            parsed = self._parse_dt(value)
            if parsed is not None:
                return parsed
        return self.now_provider()

    @staticmethod
    def _resolve_target_date(value: date | str | None) -> date | None:
        if value is None:
            return None
        if isinstance(value, date):
            return value
        if not isinstance(value, str) or not value.strip():
            return None
        try:
            return date.fromisoformat(value.strip())
        except ValueError:
            return None

    @classmethod
    def _timeline_matches_date(cls, item: dict[str, Any], target_date: date) -> bool:
        for key in ("start_at", "due_at", "next_trigger_at", "sort_at"):
            parsed = cls._parse_dt(item.get(key))
            if parsed is not None and parsed.date() == target_date:
                return True

        start_at = cls._parse_dt(item.get("start_at"))
        end_at = cls._parse_dt(item.get("end_at"))
        if start_at is not None and end_at is not None:
            return start_at.date() <= target_date <= end_at.date()
        return False

    @classmethod
    def _matches_planning_surface(
        cls,
        item: dict[str, Any],
        *,
        planning_surface: str | list[str] | tuple[str, ...] | set[str] | None,
    ) -> bool:
        resolved_surface = cls._resolved_planning_surface(item)
        allowed_surfaces = cls._normalize_planning_surface_filter(planning_surface)
        if allowed_surfaces is None:
            return resolved_surface != HIDDEN_PLANNING_SURFACE
        return resolved_surface in allowed_surfaces

    @classmethod
    def _is_visible_on_default_surface(cls, item: dict[str, Any], *, resource_type: str) -> bool:
        return cls._resolved_planning_surface(item, resource_type=resource_type) != HIDDEN_PLANNING_SURFACE

    @classmethod
    def _resolved_planning_surface(
        cls,
        item: dict[str, Any],
        *,
        resource_type: str | None = None,
    ) -> str:
        explicit_surface = cls._clean_optional_text(item.get("planning_surface"))
        if explicit_surface is not None:
            normalized_surface = explicit_surface.lower()
            if normalized_surface in {"agenda", "tasks", HIDDEN_PLANNING_SURFACE}:
                return normalized_surface
        resolved_type = resource_type or cls._planning_resource_type(item)
        return DEFAULT_PLANNING_SURFACES.get(resolved_type, "agenda")

    @classmethod
    def _planning_resource_type(cls, item: dict[str, Any]) -> str:
        resource_type = cls._clean_optional_text(item.get("resource_type") or item.get("item_type"))
        if resource_type is not None:
            return resource_type.lower()
        return cls._item_type_for(item)

    @classmethod
    def _normalize_planning_surface_filter(
        cls,
        planning_surface: str | list[str] | tuple[str, ...] | set[str] | None,
    ) -> set[str] | None:
        if planning_surface is None:
            return None
        raw_values = (
            [planning_surface]
            if isinstance(planning_surface, str)
            else list(planning_surface)
        )
        normalized = {
            value.lower()
            for raw in raw_values
            if (value := cls._clean_optional_text(raw)) is not None
            and value.lower() in CANONICAL_PLANNING_SURFACES
        }
        return normalized or None

    @staticmethod
    def _clean_optional_text(value: Any) -> str | None:
        if not isinstance(value, str):
            return None
        cleaned = value.strip()
        return cleaned or None

    @staticmethod
    def _is_high_priority(item: dict[str, Any]) -> bool:
        priority = str(item.get("priority") or "").strip().lower()
        if priority:
            return priority == "high"
        return True

    @staticmethod
    def _same_business_minute(left: datetime, right: datetime) -> bool:
        return left.replace(second=0, microsecond=0) == right.replace(second=0, microsecond=0)
