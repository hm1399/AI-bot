from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from .json_store import JsonCollectionStore


class ResourceValidationError(ValueError):
    pass


class ResourceNotFoundError(KeyError):
    pass


class AppResourceService:
    def __init__(self, runtime_dir: Path) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        self.task_store = JsonCollectionStore(runtime_dir / "tasks.json", id_field="task_id", prefix="task")
        self.event_store = JsonCollectionStore(runtime_dir / "events.json", id_field="event_id", prefix="event")
        self.notification_store = JsonCollectionStore(
            runtime_dir / "notifications.json",
            id_field="notification_id",
            prefix="notif",
        )
        self.reminder_store = JsonCollectionStore(
            runtime_dir / "reminders.json",
            id_field="reminder_id",
            prefix="rem",
        )

    def list_tasks(
        self,
        *,
        completed: bool | None = None,
        priority: str | None = None,
        limit: int | None = None,
    ) -> dict[str, Any]:
        if priority is not None and priority not in {"high", "medium", "low"}:
            raise ResourceValidationError("priority must be one of: high, low, medium")
        items = self.task_store.list_items()
        if completed is not None:
            items = [item for item in items if bool(item.get("completed", False)) is completed]
        if priority is not None:
            items = [item for item in items if item.get("priority") == priority]
        items = self._sort_by_updated_at(items)
        if limit:
            items = items[:limit]
        return {"items": items}

    def create_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.task_store.create(self._normalize_task_payload(payload, partial=False))

    def update_task(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_task_payload(payload, partial=True)
        updated = self.task_store.update(task_id, patch)
        if updated is None:
            raise ResourceNotFoundError("TASK_NOT_FOUND")
        return updated

    def delete_task(self, task_id: str) -> dict[str, Any]:
        deleted = self.task_store.delete(task_id)
        if deleted is None:
            raise ResourceNotFoundError("TASK_NOT_FOUND")
        return deleted

    def list_events(self, *, limit: int | None = None) -> dict[str, Any]:
        items = self._sort_by_updated_at(self.event_store.list_items())
        if limit:
            items = items[:limit]
        return {"items": items}

    def create_event(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.event_store.create(self._normalize_event_payload(payload, partial=False))

    def update_event(self, event_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_event_payload(payload, partial=True)
        updated = self.event_store.update(event_id, patch)
        if updated is None:
            raise ResourceNotFoundError("EVENT_NOT_FOUND")
        return updated

    def delete_event(self, event_id: str) -> dict[str, Any]:
        deleted = self.event_store.delete(event_id)
        if deleted is None:
            raise ResourceNotFoundError("EVENT_NOT_FOUND")
        return deleted

    def list_notifications(self) -> dict[str, Any]:
        items = self._sort_by_updated_at(self.notification_store.list_items())
        unread_count = sum(1 for item in items if not item.get("read", False))
        return {"items": items, "unread_count": unread_count}

    def create_notification(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.notification_store.create(self._normalize_notification_payload(payload, partial=False))

    def update_notification(self, notification_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_notification_payload(payload, partial=True)
        updated = self.notification_store.update(notification_id, patch)
        if updated is None:
            raise ResourceNotFoundError("NOTIFICATION_NOT_FOUND")
        return updated

    def mark_all_notifications_read(self) -> dict[str, Any]:
        items = self.notification_store.list_items()
        changed_items: list[dict[str, Any]] = []
        for item in items:
            if not item.get("read", False):
                updated = self.notification_store.update(
                    item["notification_id"],
                    {"read": True},
                )
                if updated is not None:
                    changed_items.append(updated)
        summary = self.list_notifications()
        summary["changed_items"] = changed_items
        return summary

    def delete_notification(self, notification_id: str) -> dict[str, Any]:
        deleted = self.notification_store.delete(notification_id)
        if deleted is None:
            raise ResourceNotFoundError("NOTIFICATION_NOT_FOUND")
        return deleted

    def clear_notifications(self) -> dict[str, Any]:
        deleted_items = self.notification_store.list_items()
        self.notification_store.clear()
        return {"deleted_count": len(deleted_items), "deleted_items": deleted_items}

    def list_reminders(self, *, limit: int | None = None) -> dict[str, Any]:
        items = self._sort_by_updated_at(self.reminder_store.list_items())
        if limit:
            items = items[:limit]
        return {"items": items}

    def create_reminder(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.reminder_store.create(self._normalize_reminder_payload(payload, partial=False))

    def update_reminder(self, reminder_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_reminder_payload(payload, partial=True)
        updated = self.reminder_store.update(reminder_id, patch)
        if updated is None:
            raise ResourceNotFoundError("REMINDER_NOT_FOUND")
        return updated

    def delete_reminder(self, reminder_id: str) -> dict[str, Any]:
        deleted = self.reminder_store.delete(reminder_id)
        if deleted is None:
            raise ResourceNotFoundError("REMINDER_NOT_FOUND")
        return deleted

    def _normalize_task_payload(self, payload: dict[str, Any], *, partial: bool) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        if not partial or "title" in payload:
            normalized["title"] = self._require_string(payload.get("title"), "title")
        if "description" in payload:
            normalized["description"] = self._optional_string(payload.get("description"), "description")
        elif not partial:
            normalized["description"] = None
        if "priority" in payload:
            normalized["priority"] = self._enum_string(payload.get("priority"), "priority", {"high", "medium", "low"})
        elif not partial:
            normalized["priority"] = "medium"
        if "completed" in payload:
            normalized["completed"] = self._require_bool(payload.get("completed"), "completed")
        elif not partial:
            normalized["completed"] = False
        if "due_at" in payload:
            normalized["due_at"] = self._optional_string(payload.get("due_at"), "due_at")
        elif not partial:
            normalized["due_at"] = None
        return normalized

    def _normalize_event_payload(self, payload: dict[str, Any], *, partial: bool) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        if not partial or "title" in payload:
            normalized["title"] = self._require_string(payload.get("title"), "title")
        if not partial or "start_at" in payload:
            normalized["start_at"] = self._require_string(payload.get("start_at"), "start_at")
        if not partial or "end_at" in payload:
            normalized["end_at"] = self._require_string(payload.get("end_at"), "end_at")
        if "description" in payload:
            normalized["description"] = self._optional_string(payload.get("description"), "description")
        elif not partial:
            normalized["description"] = None
        if "location" in payload:
            normalized["location"] = self._optional_string(payload.get("location"), "location")
        elif not partial:
            normalized["location"] = None
        return normalized

    def _normalize_notification_payload(self, payload: dict[str, Any], *, partial: bool) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        if partial:
            if "read" not in payload:
                raise ResourceValidationError("read is required")
            normalized["read"] = self._require_bool(payload.get("read"), "read")
            return normalized

        normalized["type"] = self._require_string(payload.get("type"), "type")
        normalized["priority"] = self._enum_string(payload.get("priority"), "priority", {"high", "medium", "low"})
        normalized["title"] = self._require_string(payload.get("title"), "title")
        normalized["message"] = self._require_string(payload.get("message"), "message")
        normalized["read"] = bool(payload.get("read", False))
        metadata = payload.get("metadata", {})
        if not isinstance(metadata, dict):
            raise ResourceValidationError("metadata must be an object")
        normalized["metadata"] = deepcopy(metadata)
        return normalized

    def _normalize_reminder_payload(self, payload: dict[str, Any], *, partial: bool) -> dict[str, Any]:
        normalized: dict[str, Any] = {}
        if not partial or "title" in payload:
            normalized["title"] = self._require_string(payload.get("title"), "title")
        if not partial or "time" in payload:
            normalized["time"] = self._require_string(payload.get("time"), "time")
        if "message" in payload:
            normalized["message"] = self._optional_string(payload.get("message"), "message")
        elif not partial:
            normalized["message"] = None
        if "repeat" in payload:
            normalized["repeat"] = self._require_string(payload.get("repeat"), "repeat")
        elif not partial:
            normalized["repeat"] = "daily"
        if "enabled" in payload:
            normalized["enabled"] = self._require_bool(payload.get("enabled"), "enabled")
        elif not partial:
            normalized["enabled"] = True
        return normalized

    @staticmethod
    def _sort_by_updated_at(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return sorted(items, key=lambda item: item.get("updated_at", ""), reverse=True)

    @staticmethod
    def _require_string(value: Any, field: str) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ResourceValidationError(f"{field} is required")
        return value.strip()

    @staticmethod
    def _optional_string(value: Any, field: str) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise ResourceValidationError(f"{field} must be a string or null")
        cleaned = value.strip()
        return cleaned or None

    @staticmethod
    def _require_bool(value: Any, field: str) -> bool:
        if not isinstance(value, bool):
            raise ResourceValidationError(f"{field} must be a boolean")
        return value

    @staticmethod
    def _enum_string(value: Any, field: str, allowed: set[str]) -> str:
        cleaned = AppResourceService._require_string(value, field)
        if cleaned not in allowed:
            raise ResourceValidationError(f"{field} must be one of: {', '.join(sorted(allowed))}")
        return cleaned
