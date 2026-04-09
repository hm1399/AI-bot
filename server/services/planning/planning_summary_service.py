from __future__ import annotations

from datetime import datetime
from typing import Any, Callable

from .planning_projection_service import PlanningProjectionService


class PlanningSummaryService:
    """Derives runtime-compatible todo and calendar summaries from planning data."""

    def __init__(
        self,
        *,
        now_provider: Callable[[], datetime] | None = None,
        projection_service: PlanningProjectionService | None = None,
    ) -> None:
        self.now_provider = now_provider or (lambda: datetime.now().astimezone())
        self.projection_service = projection_service or PlanningProjectionService(now_provider=self.now_provider)

    def summarize(
        self,
        *,
        tasks: list[dict[str, Any]] | None = None,
        events: list[dict[str, Any]] | None = None,
        reminders: list[dict[str, Any]] | None = None,
        projection: dict[str, Any] | None = None,
        now: datetime | str | None = None,
    ) -> dict[str, dict[str, Any]]:
        if projection is None:
            projection = self.projection_service.project(
                tasks=tasks,
                events=events,
                reminders=reminders,
                now=now,
            )
        timeline = list(projection.get("timeline", []))
        now_dt = self._resolve_now(now)
        return {
            "todo_summary": self._todo_from_timeline(timeline, now=now_dt),
            "calendar_summary": self._calendar_from_timeline(timeline, now=now_dt),
        }

    def derive_todo_summary(
        self,
        *,
        tasks: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
    ) -> dict[str, Any]:
        return self.summarize(tasks=tasks, reminders=reminders)["todo_summary"]

    def derive_calendar_summary(
        self,
        *,
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
    ) -> dict[str, Any]:
        return self.summarize(events=events, reminders=reminders)["calendar_summary"]

    def derive_all(
        self,
        *,
        tasks: list[dict[str, Any]],
        events: list[dict[str, Any]],
        reminders: list[dict[str, Any]],
    ) -> dict[str, dict[str, Any]]:
        return self.summarize(tasks=tasks, events=events, reminders=reminders)

    def _todo_from_timeline(
        self,
        timeline: list[dict[str, Any]],
        *,
        now: datetime,
    ) -> dict[str, Any]:
        pending_tasks = [
            item
            for item in timeline
            if item.get("resource_type") == "task" and not bool(item.get("completed", False))
        ]
        active_reminders = [
            item
            for item in timeline
            if item.get("resource_type") == "reminder"
            and item.get("status") not in {"completed", "disabled"}
        ]
        next_due_at = self._min_business_time([*pending_tasks, *active_reminders])
        overdue_count = sum(
            1
            for item in [*pending_tasks, *active_reminders]
            if (at := self._parse_dt(item.get("business_at") or item.get("starts_at"))) is not None and at < now
        )
        return {
            "enabled": bool(pending_tasks or active_reminders),
            "pending_count": len(pending_tasks),
            "overdue_count": overdue_count,
            "next_due_at": self._format_optional_dt(next_due_at),
        }

    def _calendar_from_timeline(
        self,
        timeline: list[dict[str, Any]],
        *,
        now: datetime,
    ) -> dict[str, Any]:
        calendar_items = [
            item
            for item in timeline
            if item.get("resource_type") in {"event", "reminder"}
            and item.get("status") not in {"completed", "disabled"}
        ]
        next_item = None
        for item in calendar_items:
            start_at = self._parse_dt(item.get("business_at") or item.get("starts_at"))
            if start_at is None:
                continue
            if item.get("resource_type") == "event":
                end_at = self._parse_dt(item.get("business_end_at") or item.get("ends_at"))
                if end_at is not None and end_at < now:
                    continue
                next_item = item
                break
            if start_at >= now:
                next_item = item
                break

        today_count = sum(
            1
            for item in calendar_items
            if (at := self._parse_dt(item.get("business_at") or item.get("starts_at"))) is not None
            and at.astimezone(now.tzinfo).date() == now.date()
        )
        next_at = None
        next_title = None
        if next_item is not None:
            next_at = self._parse_dt(next_item.get("business_at") or next_item.get("starts_at"))
            next_title = str(next_item.get("title") or "").strip() or None
        return {
            "enabled": bool(calendar_items),
            "today_count": today_count,
            "next_event_at": self._format_optional_dt(next_at),
            "next_event_title": next_title,
        }

    def _min_business_time(self, items: list[dict[str, Any]]) -> datetime | None:
        candidates = [
            self._parse_dt(item.get("business_at") or item.get("starts_at"))
            for item in items
        ]
        candidates = [item for item in candidates if item is not None]
        return min(candidates) if candidates else None

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
    def _format_optional_dt(value: datetime | None) -> str | None:
        return value.astimezone().isoformat(timespec="seconds") if value is not None else None

    def _resolve_now(self, value: datetime | str | None) -> datetime:
        if isinstance(value, datetime):
            return value.astimezone()
        if isinstance(value, str):
            parsed = self._parse_dt(value)
            if parsed is not None:
                return parsed
        return self.now_provider()
