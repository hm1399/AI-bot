from __future__ import annotations

import asyncio
import inspect
import json
from pathlib import Path
from typing import Any

from loguru import logger

from nanobot.utils.atomic_write import atomic_write_text
from services.app_api import AppResourceService
from services.planning import PlanningProjectionService, PlanningSummaryService


class PlanningRuntimeService:
    """Owns planning-derived runtime snapshots and persisted summaries."""

    def __init__(self, runtime_dir: Path, resources: AppResourceService) -> None:
        self.resources = resources
        self.planning_projection_service = PlanningProjectionService()
        self.planning_summary_service = PlanningSummaryService()
        self._todo_summary_path = runtime_dir / "todo_summary.json"
        self._calendar_summary_path = runtime_dir / "calendar_summary.json"
        self._todo_summary = self._load_summary_file(
            self._todo_summary_path,
            self._default_todo_summary(),
        )
        self._calendar_summary = self._load_summary_file(
            self._calendar_summary_path,
            self._default_calendar_summary(),
        )

    def get_todo_summary(self) -> dict[str, Any]:
        return dict(self._todo_summary)

    def get_calendar_summary(self) -> dict[str, Any]:
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

    def planning_runtime_state(self) -> dict[str, Any]:
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

    async def set_todo_summary(
        self,
        payload: dict[str, Any],
        *,
        lock: asyncio.Lock,
    ) -> tuple[dict[str, Any], str | None, bool]:
        async with lock:
            updated, error = self._normalize_todo_summary(self._todo_summary, payload)
            if error:
                return {}, error, False
            changed = updated != self._todo_summary
            self._todo_summary = updated
            if changed:
                self._save_summary_file(self._todo_summary_path, updated)
        return dict(updated), None, changed

    async def set_calendar_summary(
        self,
        payload: dict[str, Any],
        *,
        lock: asyncio.Lock,
    ) -> tuple[dict[str, Any], str | None, bool]:
        async with lock:
            updated, error = self._normalize_calendar_summary(
                self._calendar_summary,
                payload,
            )
            if error:
                return {}, error, False
            changed = updated != self._calendar_summary
            self._calendar_summary = updated
            if changed:
                self._save_summary_file(self._calendar_summary_path, updated)
        return dict(updated), None, changed

    async def refresh_summary_files(
        self,
        *,
        lock: asyncio.Lock,
    ) -> list[tuple[str, dict[str, Any]]]:
        inputs = self._planning_inputs()
        derived = self.planning_summary_service.derive_all(
            tasks=inputs["tasks"],
            events=inputs["events"],
            reminders=inputs["reminders"],
        )

        changed_events: list[tuple[str, dict[str, Any]]] = []
        async with lock:
            todo_summary = derived["todo_summary"]
            if todo_summary != self._todo_summary:
                self._todo_summary = dict(todo_summary)
                self._save_summary_file(self._todo_summary_path, self._todo_summary)
                changed_events.append(
                    ("todo.summary.changed", dict(self._todo_summary))
                )

            calendar_summary = derived["calendar_summary"]
            if calendar_summary != self._calendar_summary:
                self._calendar_summary = dict(calendar_summary)
                self._save_summary_file(
                    self._calendar_summary_path,
                    self._calendar_summary,
                )
                changed_events.append(
                    ("calendar.summary.changed", dict(self._calendar_summary))
                )

        return changed_events

    @staticmethod
    def normalize_planning_surface(value: Any) -> str | None:
        if not isinstance(value, str):
            return None
        cleaned = value.strip().lower()
        if cleaned in {"agenda", "tasks", "hidden"}:
            return cleaned
        return None

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
            if (
                parameter_names is not None
                and "date" in parameter_names
                and "target_date" not in parameter_names
            ):
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

    def _load_summary_file(
        self,
        path: Path,
        default: dict[str, Any],
    ) -> dict[str, Any]:
        if not path.exists():
            return dict(default)
        try:
            with open(path, encoding="utf-8") as handle:
                payload = json.load(handle)
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
    def _normalize_bool_field(
        payload: dict[str, Any],
        *,
        key: str,
        current: bool,
    ) -> bool:
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
