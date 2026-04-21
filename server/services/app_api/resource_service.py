from __future__ import annotations

from collections.abc import Mapping
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from .json_importer import import_runtime_json_collections
from .json_store import JsonCollectionStore
from .sqlite_store import (
    SQLiteCollectionAdapter,
    SQLitePlanningStore,
    SQLiteReminderStoreAdapter,
)


PLANNING_METADATA_FIELDS = (
    "bundle_id",
    "created_via",
    "source_channel",
    "source_message_id",
    "source_session_id",
    "interaction_surface",
    "planning_surface",
    "owner_kind",
    "delivery_mode",
    "capture_source",
    "voice_path",
    "linked_task_id",
    "linked_event_id",
    "linked_reminder_id",
    "scheduled_action_kind",
    "scheduled_action_target",
)
REMINDER_RUNTIME_FIELDS = (
    "next_trigger_at",
    "last_triggered_at",
    "last_error",
    "snoozed_until",
    "completed_at",
    "status",
)
REMINDER_REPEAT_FIELDS = {
    "daily",
    "once",
    "weekdays",
    "weekends",
}
REMINDER_STATUS_FIELDS = {
    "completed",
    "overdue",
    "scheduled",
    "snoozed",
}
CANONICAL_PLANNING_SURFACES = {
    "agenda",
    "tasks",
    "hidden",
}
CANONICAL_OWNER_KINDS = {
    "user",
    "assistant",
}
CANONICAL_DELIVERY_MODES = {
    "none",
    "device_voice",
    "device_voice_and_notification",
}
DEFAULT_PLANNING_SURFACES = {
    "tasks": "tasks",
    "events": "agenda",
    "reminders": "agenda",
}
NOTIFICATION_ORIGIN_ALIASES = {
    "linked_task_id": "task_id",
    "linked_event_id": "event_id",
    "linked_reminder_id": "reminder_id",
}
_PLANNING_DOMAINS = ("tasks", "events", "notifications", "reminders")


class ResourceValidationError(ValueError):
    pass


class ResourceNotFoundError(KeyError):
    pass


class _DualCollectionStore:
    """JSON primary store with SQLite shadow mirror."""

    def __init__(
        self,
        primary: JsonCollectionStore,
        shadow: SQLiteCollectionAdapter,
        *,
        sync_shadow: Callable[[], None],
    ) -> None:
        self._primary = primary
        self._shadow = shadow
        self._sync_shadow = sync_shadow

    def list_items(self) -> list[dict[str, Any]]:
        return self._primary.list_items()

    def get(self, item_id: str) -> dict[str, Any] | None:
        return self._primary.get(item_id)

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        item = self._primary.create(payload)
        self._sync_shadow()
        return item

    def update(self, item_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        updated = self._primary.update(item_id, patch)
        if updated is not None:
            self._sync_shadow()
        return updated

    def delete(self, item_id: str) -> dict[str, Any] | None:
        deleted = self._primary.delete(item_id)
        if deleted is not None:
            self._sync_shadow()
        return deleted

    def replace_all(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        replaced = self._primary.replace_all(items)
        self._sync_shadow()
        return replaced

    def clear(self) -> None:
        self._primary.clear()
        self._sync_shadow()


class AppResourceService:
    def __init__(
        self,
        runtime_dir: Path,
        *,
        storage_mode: str = "json",
        sqlite_path: Path | None = None,
        storage_config: Mapping[str, Any] | None = None,
    ) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        resolved_storage_mode, resolved_sqlite_path = self._resolve_storage_config(
            runtime_dir,
            storage_mode=storage_mode,
            sqlite_path=sqlite_path,
            storage_config=storage_config,
        )
        if resolved_storage_mode not in {"json", "dual", "sqlite"}:
            raise ValueError("storage_mode must be one of: json, dual, sqlite")

        self.runtime_dir = runtime_dir
        self.storage_mode = resolved_storage_mode
        self.sqlite_path = resolved_sqlite_path
        self.last_imported_at: str | None = None
        self.last_import_summary: dict[str, dict[str, Any]] = {}
        self.shadow_failure_count = 0
        self.shadow_mismatch_count = 0
        self.shadow_mismatch_domains: dict[str, int] = {}
        self.shadow_last_synced_at: str | None = None
        self.shadow_last_error: str | None = None
        self.shadow_last_error_at: str | None = None
        self.shadow_last_mismatch_at: str | None = None
        self._shadow_domain_state: dict[str, dict[str, Any]] = {
            domain: {
                "enabled": self.storage_mode == "dual",
                "last_synced_at": None,
                "last_error": None,
                "last_error_at": None,
                "mismatch_count": 0,
                "last_mismatch_at": None,
                "last_match": None,
                "last_primary_count": 0,
                "last_shadow_count": 0,
            }
            for domain in _PLANNING_DOMAINS
        }
        self._reminder_change_listeners: list[Callable[[dict[str, Any]], None]] = []

        json_task_store = JsonCollectionStore(runtime_dir / "tasks.json", id_field="task_id", prefix="task")
        json_event_store = JsonCollectionStore(runtime_dir / "events.json", id_field="event_id", prefix="event")
        json_notification_store = JsonCollectionStore(
            runtime_dir / "notifications.json",
            id_field="notification_id",
            prefix="notif",
        )
        json_reminder_store = JsonCollectionStore(
            runtime_dir / "reminders.json",
            id_field="reminder_id",
            prefix="rem",
        )
        self._json_stores: dict[str, JsonCollectionStore] = {
            "tasks": json_task_store,
            "events": json_event_store,
            "notifications": json_notification_store,
            "reminders": json_reminder_store,
        }

        self._sqlite_store: SQLitePlanningStore | None = None
        self._sqlite_adapters: dict[str, Any] = {}
        if self.storage_mode in {"dual", "sqlite"}:
            self._sqlite_store = SQLitePlanningStore(self.sqlite_path)
            import_summary = import_runtime_json_collections(
                runtime_dir,
                self._sqlite_store,
                overwrite=False,
            )
            self.last_import_summary = {
                domain: deepcopy(summary)
                for domain, summary in import_summary.items()
            }
            if any(bool(item.get("imported")) for item in import_summary.values()):
                self.last_imported_at = self._now_iso()
            self._sqlite_adapters = {
                "tasks": SQLiteCollectionAdapter(self._sqlite_store, "tasks"),
                "events": SQLiteCollectionAdapter(self._sqlite_store, "events"),
                "notifications": SQLiteCollectionAdapter(self._sqlite_store, "notifications"),
                "reminders": SQLiteReminderStoreAdapter(self._sqlite_store),
            }

        if self.storage_mode == "sqlite":
            self.task_store = self._sqlite_adapters["tasks"]
            self.event_store = self._sqlite_adapters["events"]
            self.notification_store = self._sqlite_adapters["notifications"]
            self.reminder_store = self._sqlite_adapters["reminders"]
        elif self.storage_mode == "dual":
            self.task_store = _DualCollectionStore(
                json_task_store,
                self._sqlite_adapters["tasks"],
                sync_shadow=lambda: self._sync_shadow_domain("tasks"),
            )
            self.event_store = _DualCollectionStore(
                json_event_store,
                self._sqlite_adapters["events"],
                sync_shadow=lambda: self._sync_shadow_domain("events"),
            )
            self.notification_store = _DualCollectionStore(
                json_notification_store,
                self._sqlite_adapters["notifications"],
                sync_shadow=lambda: self._sync_shadow_domain("notifications"),
            )
            self.reminder_store = _DualCollectionStore(
                json_reminder_store,
                self._sqlite_adapters["reminders"],
                sync_shadow=lambda: self._sync_shadow_domain("reminders"),
            )
        else:
            self.task_store = json_task_store
            self.event_store = json_event_store
            self.notification_store = json_notification_store
            self.reminder_store = json_reminder_store

    def list_tasks(
        self,
        *,
        completed: bool | None = None,
        priority: str | None = None,
        limit: int | None = None,
    ) -> dict[str, Any]:
        if priority is not None and priority not in {"high", "medium", "low"}:
            raise ResourceValidationError("priority must be one of: high, low, medium")
        items = self.list_task_items()
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
        items = self._sort_by_updated_at(self.list_event_items())
        if limit:
            items = items[:limit]
        return {"items": items}

    def create_event(self, payload: dict[str, Any]) -> dict[str, Any]:
        normalized = self._normalize_event_payload(payload, partial=False)
        self._validate_event_window(
            start_at=normalized.get("start_at"),
            end_at=normalized.get("end_at"),
        )
        return self.event_store.create(normalized)

    def update_event(self, event_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_event_payload(payload, partial=True)
        existing = self.event_store.get(event_id)
        if existing is None:
            raise ResourceNotFoundError("EVENT_NOT_FOUND")
        merged = {**existing, **patch}
        self._validate_event_window(
            start_at=merged.get("start_at"),
            end_at=merged.get("end_at"),
        )
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
        items = self._sort_by_updated_at(self.list_notification_items())
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
        items = self.list_notification_items()
        changed_items: list[dict[str, Any]] = []
        for item in items:
            if not item.get("read", False):
                updated = self.notification_store.update(item["notification_id"], {"read": True})
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
        deleted_items = self.list_notification_items()
        self.notification_store.clear()
        return {"deleted_count": len(deleted_items), "deleted_items": deleted_items}

    def list_reminders(self, *, limit: int | None = None) -> dict[str, Any]:
        items = self._sort_by_updated_at(self.list_reminder_items())
        if limit:
            items = items[:limit]
        return {"items": items}

    def create_reminder(self, payload: dict[str, Any]) -> dict[str, Any]:
        created = self.reminder_store.create(self._normalize_reminder_payload(payload, partial=False))
        self._notify_reminder_change("created", reminder_id=created.get("reminder_id"), reminder=created)
        return created

    def update_reminder(self, reminder_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        patch = self._normalize_reminder_payload(payload, partial=True)
        updated = self.reminder_store.update(reminder_id, patch)
        if updated is None:
            raise ResourceNotFoundError("REMINDER_NOT_FOUND")
        self._notify_reminder_change("updated", reminder_id=reminder_id, reminder=updated)
        return updated

    def delete_reminder(self, reminder_id: str) -> dict[str, Any]:
        deleted = self.reminder_store.delete(reminder_id)
        if deleted is None:
            raise ResourceNotFoundError("REMINDER_NOT_FOUND")
        self._notify_reminder_change("deleted", reminder_id=reminder_id, reminder=deleted)
        return deleted

    def register_reminder_change_listener(
        self,
        listener: Callable[[dict[str, Any]], None],
    ) -> None:
        if listener not in self._reminder_change_listeners:
            self._reminder_change_listeners.append(listener)

    def unregister_reminder_change_listener(
        self,
        listener: Callable[[dict[str, Any]], None],
    ) -> None:
        self._reminder_change_listeners = [
            candidate
            for candidate in self._reminder_change_listeners
            if candidate != listener
        ]

    def list_task_items(self) -> list[dict[str, Any]]:
        return self.task_store.list_items()

    def list_event_items(self) -> list[dict[str, Any]]:
        return self.event_store.list_items()

    def list_notification_items(self) -> list[dict[str, Any]]:
        return self.notification_store.list_items()

    def list_reminder_items(self) -> list[dict[str, Any]]:
        return self.reminder_store.list_items()

    def get_reminder(self, reminder_id: str) -> dict[str, Any] | None:
        return self.reminder_store.get(reminder_id)

    def get_next_reminder_fire(self) -> dict[str, Any] | None:
        if self._should_use_sqlite_reminder_runtime() and self._sqlite_store is not None:
            return self._sqlite_store.get_next_reminder_fire(deliverable_only=True)

        items = [
            item
            for item in self.list_reminder_items()
            if self._reminder_delivery_pending(item)
        ]
        items.sort(
            key=lambda item: (
                self._parse_epoch(item.get("next_trigger_at")) or 0,
                item.get("created_at", ""),
            )
        )
        return deepcopy(items[0]) if items else None

    def get_next_reminder_fire_at(self) -> str | None:
        next_item = self.get_next_reminder_fire()
        if next_item is None:
            return None
        value = next_item.get("next_trigger_at")
        return str(value) if isinstance(value, str) and value.strip() else None

    def planning_inputs(self) -> dict[str, list[dict[str, Any]]]:
        if self._sqlite_store is not None:
            return {
                "tasks": self._sqlite_adapters["tasks"].list_items(),
                "events": self._sqlite_adapters["events"].list_items(),
                "reminders": self._sqlite_adapters["reminders"].list_items(),
                "notifications": self._sqlite_adapters["notifications"].list_items(),
            }
        return {
            "tasks": self.list_task_items(),
            "events": self.list_event_items(),
            "reminders": self.list_reminder_items(),
            "notifications": self.list_notification_items(),
        }

    def planning_store_diagnostics(self) -> dict[str, Any]:
        domain_stats = self._planning_domain_stats()
        schema_version = self._sqlite_store.schema_version() if self._sqlite_store is not None else 0
        sqlite_ready = bool(self._sqlite_store and self.sqlite_path.exists())
        reminder_runtime = (
            self._sqlite_store.reminder_runtime_stats()
            if self._sqlite_store is not None
            else self._json_reminder_runtime_stats()
        )
        next_fire_at = self.get_next_reminder_fire_at()
        shadow_state = {
            "enabled": self.storage_mode == "dual",
            "primary_backend": "json" if self.storage_mode != "sqlite" else "sqlite",
            "shadow_backend": "sqlite" if self.storage_mode == "dual" else None,
            "last_synced_at": self.shadow_last_synced_at,
            "last_error": self.shadow_last_error,
            "last_error_at": self.shadow_last_error_at,
            "last_mismatch_at": self.shadow_last_mismatch_at,
            "failure_count": self.shadow_failure_count,
            "mismatch_count": self.shadow_mismatch_count,
            "mismatch_domains": dict(self.shadow_mismatch_domains),
            "domains": {
                domain: deepcopy(state)
                for domain, state in self._shadow_domain_state.items()
            },
        }
        return {
            "mode": self.storage_mode,
            "primary_backend": "sqlite" if self.storage_mode == "sqlite" else "json",
            "shadow_backend": "sqlite" if self.storage_mode == "dual" else None,
            "sqlite_path": str(self.sqlite_path),
            "sqlite_ready": sqlite_ready,
            "schema_version": schema_version,
            "latest_imported_at": self.last_imported_at,
            "imports": {
                "latest_imported_at": self.last_imported_at,
                "latest_summary": {
                    domain: deepcopy(summary)
                    for domain, summary in self.last_import_summary.items()
                },
            },
            "shadow": shadow_state,
            "domains": domain_stats,
            "reminder_runtime": {
                **reminder_runtime,
                "next_fire_at": next_fire_at,
            },
        }

    def storage_runtime_state(self) -> dict[str, Any]:
        diagnostics = self.planning_store_diagnostics()
        return {
            "mode": diagnostics["mode"],
            "primary_backend": diagnostics["primary_backend"],
            "shadow_backend": diagnostics["shadow_backend"],
            "sqlite_path": diagnostics["sqlite_path"],
            "sqlite_ready": diagnostics["sqlite_ready"],
            "schema_version": diagnostics["schema_version"],
            "latest_imported_at": diagnostics["latest_imported_at"],
            "shadow_failures": self.shadow_failure_count,
            "mismatch_count": self.shadow_mismatch_count,
            "mismatch_domains": dict(self.shadow_mismatch_domains),
            "imports": deepcopy(diagnostics["imports"]),
            "shadow": deepcopy(diagnostics["shadow"]),
            "domains": deepcopy(diagnostics["domains"]),
            "reminder_runtime": deepcopy(diagnostics["reminder_runtime"]),
        }

    def list_due_reminders(
        self,
        *,
        due_before: str | None = None,
        limit: int | None = None,
        deliverable_only: bool = False,
    ) -> list[dict[str, Any]]:
        if self._should_use_sqlite_reminder_runtime() and self._sqlite_store is not None:
            return self._sqlite_store.list_due_reminders(
                due_before=due_before,
                limit=limit,
                deliverable_only=deliverable_only,
            )

        due_epoch = self._parse_epoch(due_before or self._now_iso())
        if due_epoch is None:
            return []

        items = [
            item
            for item in self.list_reminder_items()
            if self._reminder_due(item, due_epoch=due_epoch, deliverable_only=deliverable_only)
        ]
        items.sort(
            key=lambda item: (
                self._parse_epoch(item.get("next_trigger_at")) or 0,
                item.get("created_at", ""),
            )
        )
        if isinstance(limit, int) and limit > 0:
            return items[:limit]
        return items

    def create_notification_and_update_reminder(
        self,
        *,
        reminder_id: str,
        notification_payload: dict[str, Any],
        reminder_patch: dict[str, Any],
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        normalized_notification = self._normalize_notification_payload(notification_payload, partial=False)
        normalized_reminder_patch = self._normalize_reminder_payload(reminder_patch, partial=True)

        if self.storage_mode == "sqlite" and self._sqlite_store is not None:
            notification, updated_reminder = self._sqlite_store.create_notification_and_update_reminder(
                reminder_id=reminder_id,
                notification_payload=normalized_notification,
                reminder_patch=normalized_reminder_patch,
            )
            if updated_reminder is not None:
                self._notify_reminder_change(
                    "notification_update",
                    reminder_id=reminder_id,
                    reminder=updated_reminder,
                )
            return notification, updated_reminder

        if self.get_reminder(reminder_id) is None:
            return None, None
        notification = self.notification_store.create(normalized_notification)
        updated_reminder = self.reminder_store.update(reminder_id, normalized_reminder_patch)
        if updated_reminder is not None:
            self._notify_reminder_change(
                "notification_update",
                reminder_id=reminder_id,
                reminder=updated_reminder,
            )
        return notification, updated_reminder

    def _notify_reminder_change(
        self,
        action: str,
        *,
        reminder_id: Any,
        reminder: dict[str, Any] | None,
    ) -> None:
        if not isinstance(reminder_id, str) or not reminder_id.strip():
            return
        payload = {
            "action": action,
            "reminder_id": reminder_id.strip(),
            "reminder": deepcopy(reminder) if isinstance(reminder, dict) else None,
            "storage_mode": self.storage_mode,
            "changed_at": self._now_iso(),
        }
        for listener in list(self._reminder_change_listeners):
            try:
                listener(deepcopy(payload))
            except Exception:
                continue

    def _planning_domain_stats(self) -> dict[str, dict[str, Any]]:
        now_iso = self._now_iso()
        stats: dict[str, dict[str, Any]] = {}
        reminder_runtime = (
            self._sqlite_store.reminder_runtime_stats(due_before=now_iso)
            if self._sqlite_store is not None
            else self._json_reminder_runtime_stats(due_before=now_iso)
        )
        for domain in _PLANNING_DOMAINS:
            json_count = len(self._json_stores[domain].list_items())
            sqlite_count = (
                self._sqlite_store.domain_count(domain)
                if self._sqlite_store is not None
                else 0
            )
            active_count = sqlite_count if self.storage_mode == "sqlite" else json_count
            stats[domain] = {
                "active_count": active_count,
                "json_count": json_count,
                "sqlite_count": sqlite_count,
                "active_backend": "sqlite" if self.storage_mode == "sqlite" else "json",
                "shadow_backend": "sqlite" if self.storage_mode == "dual" else None,
                "count_delta": sqlite_count - json_count,
            }
        stats["reminders"]["runtime"] = reminder_runtime
        return stats

    def _json_reminder_runtime_stats(self, *, due_before: str | None = None) -> dict[str, Any]:
        items = self.list_reminder_items()
        due_epoch = self._parse_epoch(due_before or self._now_iso())
        status_counts: dict[str, int] = {}
        enabled_count = 0
        with_next_trigger = 0
        deliverable_due = 0
        for item in items:
            if bool(item.get("enabled", True)):
                enabled_count += 1
            if self._parse_epoch(item.get("next_trigger_at")) is not None:
                with_next_trigger += 1
            status = str(item.get("status") or "unknown").strip().lower() or "unknown"
            status_counts[status] = status_counts.get(status, 0) + 1
            if due_epoch is not None and self._reminder_due(item, due_epoch=due_epoch, deliverable_only=True):
                deliverable_due += 1
        return {
            "total": len(items),
            "enabled": enabled_count,
            "with_next_trigger": with_next_trigger,
            "deliverable_due": deliverable_due,
            "status_counts": status_counts,
        }

    def _should_use_sqlite_reminder_runtime(self) -> bool:
        if self._sqlite_store is None:
            return False
        if self.storage_mode == "sqlite":
            return True
        reminder_shadow_state = self._shadow_domain_state.get("reminders", {})
        return (
            reminder_shadow_state.get("last_error") is None
            and reminder_shadow_state.get("last_match", True) is not False
        )

    def _reminder_due(
        self,
        item: dict[str, Any],
        *,
        due_epoch: int,
        deliverable_only: bool,
    ) -> bool:
        next_trigger_epoch = self._parse_epoch(item.get("next_trigger_at"))
        if not bool(item.get("enabled", True)) or next_trigger_epoch is None or next_trigger_epoch > due_epoch:
            return False
        if not deliverable_only:
            return True
        return self._reminder_delivery_pending(item)

    def _reminder_delivery_pending(self, item: dict[str, Any]) -> bool:
        if not bool(item.get("enabled", True)):
            return False
        next_trigger_epoch = self._parse_epoch(item.get("next_trigger_at"))
        if next_trigger_epoch is None:
            return False
        last_triggered_epoch = self._parse_epoch(item.get("last_triggered_at"))
        if last_triggered_epoch is None:
            return True
        return last_triggered_epoch < next_trigger_epoch

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
        normalized.update(self._normalize_optional_fields(payload, PLANNING_METADATA_FIELDS))
        if not partial:
            normalized.setdefault("planning_surface", DEFAULT_PLANNING_SURFACES["tasks"])
            normalized.setdefault("owner_kind", self._default_owner_kind(normalized))
            normalized.setdefault("delivery_mode", "none")
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
        normalized.update(self._normalize_optional_fields(payload, PLANNING_METADATA_FIELDS))
        if not partial:
            normalized.setdefault("planning_surface", DEFAULT_PLANNING_SURFACES["events"])
            normalized.setdefault("owner_kind", self._default_owner_kind(normalized))
            normalized.setdefault("delivery_mode", "none")
        return normalized

    @classmethod
    def _validate_event_window(cls, *, start_at: Any, end_at: Any) -> None:
        start = cls._parse_datetime_for_validation(start_at, field="start_at")
        end = cls._parse_datetime_for_validation(end_at, field="end_at")
        if end <= start:
            raise ResourceValidationError("end_at must be later than start_at")

    @staticmethod
    def _parse_datetime_for_validation(value: Any, *, field: str) -> datetime:
        cleaned = AppResourceService._require_string(value, field)
        try:
            parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ResourceValidationError(
                f"{field} must be a valid ISO 8601 datetime"
            ) from exc
        if parsed.tzinfo is not None:
            return parsed.astimezone(timezone.utc).replace(tzinfo=None)
        return parsed

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
        merged_metadata = deepcopy(metadata)
        merged_metadata.update(self._normalize_optional_fields(payload, PLANNING_METADATA_FIELDS))
        for linked_key, origin_key in NOTIFICATION_ORIGIN_ALIASES.items():
            origin_id = merged_metadata.get(linked_key)
            if origin_id is not None and merged_metadata.get(origin_key) is None:
                merged_metadata[origin_key] = origin_id
        normalized["metadata"] = merged_metadata
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
            normalized["repeat"] = self._enum_string(payload.get("repeat"), "repeat", REMINDER_REPEAT_FIELDS)
        elif not partial:
            normalized["repeat"] = "daily"
        if "enabled" in payload:
            normalized["enabled"] = self._require_bool(payload.get("enabled"), "enabled")
        elif not partial:
            normalized["enabled"] = True
        normalized.update(self._normalize_optional_fields(payload, PLANNING_METADATA_FIELDS))
        if not partial:
            normalized.setdefault("planning_surface", DEFAULT_PLANNING_SURFACES["reminders"])
            normalized.setdefault("owner_kind", self._default_owner_kind(normalized))
            normalized.setdefault("delivery_mode", "none")
        normalized.update(self._normalize_reminder_runtime_fields(payload))
        return normalized

    def _sync_shadow_domain(self, domain: str) -> None:
        if self._sqlite_store is None:
            return
        state = self._shadow_domain_state.setdefault(
            domain,
            {
                "enabled": self.storage_mode == "dual",
                "last_synced_at": None,
                "last_error": None,
                "last_error_at": None,
                "mismatch_count": 0,
                "last_mismatch_at": None,
                "last_match": None,
                "last_primary_count": 0,
                "last_shadow_count": 0,
            },
        )
        try:
            primary_items = self._json_stores[domain].list_items()
            shadow_items = self._sqlite_adapters[domain].replace_all(primary_items)
        except Exception as exc:
            error_at = self._now_iso()
            self.shadow_failure_count += 1
            self.shadow_last_error = str(exc)
            self.shadow_last_error_at = error_at
            state["last_error"] = str(exc)
            state["last_error_at"] = error_at
            return
        synced_at = self._now_iso()
        self.shadow_last_synced_at = synced_at
        self.shadow_last_error = None
        self.shadow_last_error_at = None
        state["last_synced_at"] = synced_at
        state["last_error"] = None
        state["last_error_at"] = None
        state["last_primary_count"] = len(primary_items)
        state["last_shadow_count"] = len(shadow_items)
        id_field = {
            "tasks": "task_id",
            "events": "event_id",
            "notifications": "notification_id",
            "reminders": "reminder_id",
        }[domain]
        matched = self._canonical_items(domain, primary_items, id_field) == self._canonical_items(
            domain,
            shadow_items,
            id_field,
        )
        state["last_match"] = matched
        if not matched:
            mismatch_at = self._now_iso()
            self.shadow_mismatch_count += 1
            self.shadow_mismatch_domains[domain] = self.shadow_mismatch_domains.get(domain, 0) + 1
            self.shadow_last_mismatch_at = mismatch_at
            state["mismatch_count"] = int(state.get("mismatch_count", 0) or 0) + 1
            state["last_mismatch_at"] = mismatch_at

    @staticmethod
    def _canonical_items(domain: str, items: list[dict[str, Any]], id_field: str) -> list[dict[str, Any]]:
        return sorted(
            (AppResourceService._canonical_item(domain, item) for item in items),
            key=lambda item: str(item.get(id_field) or ""),
        )

    @staticmethod
    def _canonical_item(domain: str, item: dict[str, Any]) -> dict[str, Any]:
        normalized = deepcopy(item)
        for field in PLANNING_METADATA_FIELDS:
            normalized.setdefault(field, None)
        if domain == "tasks":
            normalized.setdefault("description", None)
            normalized.setdefault("priority", "medium")
            normalized.setdefault("completed", False)
            normalized.setdefault("due_at", None)
            normalized["planning_surface"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("planning_surface"),
                    CANONICAL_PLANNING_SURFACES,
                )
                or DEFAULT_PLANNING_SURFACES["tasks"]
            )
            normalized["owner_kind"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("owner_kind"),
                    CANONICAL_OWNER_KINDS,
                )
                or AppResourceService._default_owner_kind(normalized)
            )
            normalized["delivery_mode"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("delivery_mode"),
                    CANONICAL_DELIVERY_MODES,
                )
                or "none"
            )
        elif domain == "events":
            normalized["planning_surface"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("planning_surface"),
                    CANONICAL_PLANNING_SURFACES,
                )
                or DEFAULT_PLANNING_SURFACES["events"]
            )
            normalized["owner_kind"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("owner_kind"),
                    CANONICAL_OWNER_KINDS,
                )
                or AppResourceService._default_owner_kind(normalized)
            )
            normalized["delivery_mode"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("delivery_mode"),
                    CANONICAL_DELIVERY_MODES,
                )
                or "none"
            )
        elif domain == "notifications":
            metadata = normalized.get("metadata")
            normalized["metadata"] = deepcopy(metadata) if isinstance(metadata, dict) else {}
            normalized.setdefault("read", False)
        elif domain == "reminders":
            normalized.setdefault("message", None)
            normalized.setdefault("repeat", "daily")
            normalized.setdefault("enabled", True)
            for field in REMINDER_RUNTIME_FIELDS:
                normalized.setdefault(field, None)
            normalized["planning_surface"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("planning_surface"),
                    CANONICAL_PLANNING_SURFACES,
                )
                or DEFAULT_PLANNING_SURFACES["reminders"]
            )
            normalized["owner_kind"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("owner_kind"),
                    CANONICAL_OWNER_KINDS,
                )
                or AppResourceService._default_owner_kind(normalized)
            )
            normalized["delivery_mode"] = (
                AppResourceService._coerce_optional_enum(
                    normalized.get("delivery_mode"),
                    CANONICAL_DELIVERY_MODES,
                )
                or "none"
            )
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

    @classmethod
    def _normalize_optional_fields(
        cls,
        payload: dict[str, Any],
        fields: tuple[str, ...],
    ) -> dict[str, str | None]:
        normalized: dict[str, str | None] = {}
        for field in fields:
            if field in payload:
                if field == "planning_surface":
                    normalized[field] = cls._optional_enum_string(
                        payload.get(field),
                        field,
                        CANONICAL_PLANNING_SURFACES,
                    )
                elif field == "owner_kind":
                    normalized[field] = cls._optional_enum_string(
                        payload.get(field),
                        field,
                        CANONICAL_OWNER_KINDS,
                    )
                elif field == "delivery_mode":
                    normalized[field] = cls._optional_enum_string(
                        payload.get(field),
                        field,
                        CANONICAL_DELIVERY_MODES,
                    )
                else:
                    normalized[field] = cls._optional_string(payload.get(field), field)
        return normalized

    @classmethod
    def _normalize_reminder_runtime_fields(cls, payload: dict[str, Any]) -> dict[str, str | None]:
        normalized = cls._normalize_optional_fields(payload, REMINDER_RUNTIME_FIELDS)
        if "status" in payload:
            status = payload.get("status")
            if status is None:
                normalized["status"] = None
            else:
                normalized["status"] = cls._enum_string(status, "status", REMINDER_STATUS_FIELDS)
        return normalized

    @staticmethod
    def _enum_string(value: Any, field: str, allowed: set[str]) -> str:
        cleaned = AppResourceService._require_string(value, field)
        normalized = cleaned.lower()
        if normalized not in allowed:
            raise ResourceValidationError(f"{field} must be one of: {', '.join(sorted(allowed))}")
        return normalized

    @classmethod
    def _optional_enum_string(
        cls,
        value: Any,
        field: str,
        allowed: set[str],
    ) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise ResourceValidationError(f"{field} must be a string or null")
        cleaned = value.strip()
        if not cleaned:
            return None
        normalized = cleaned.lower()
        if normalized not in allowed:
            raise ResourceValidationError(f"{field} must be one of: {', '.join(sorted(allowed))}")
        return normalized

    @staticmethod
    def _coerce_optional_text(value: Any) -> str | None:
        if not isinstance(value, str):
            return None
        cleaned = value.strip()
        return cleaned or None

    @classmethod
    def _coerce_optional_enum(
        cls,
        value: Any,
        allowed: set[str],
    ) -> str | None:
        cleaned = cls._coerce_optional_text(value)
        if cleaned is None:
            return None
        normalized = cleaned.lower()
        if normalized not in allowed:
            return None
        return normalized

    @classmethod
    def _default_owner_kind(cls, payload: dict[str, Any]) -> str:
        explicit = cls._coerce_optional_enum(
            payload.get("owner_kind"),
            CANONICAL_OWNER_KINDS,
        )
        if explicit is not None:
            return explicit

        for field in ("created_via", "source_channel"):
            cleaned = cls._coerce_optional_text(payload.get(field))
            if cleaned is None:
                continue
            normalized = cleaned.lower()
            if normalized in {"agent", "assistant", "ai"}:
                return "assistant"
            if "agent" in normalized or "assistant" in normalized:
                return "assistant"
        return "user"

    @staticmethod
    def _default_sqlite_path(runtime_dir: Path) -> Path:
        if runtime_dir.name == "runtime":
            return runtime_dir.parent / "state.sqlite3"
        return runtime_dir / "state.sqlite3"

    @classmethod
    def _resolve_storage_config(
        cls,
        runtime_dir: Path,
        *,
        storage_mode: str,
        sqlite_path: Path | None,
        storage_config: Mapping[str, Any] | None,
    ) -> tuple[str, Path]:
        resolved_mode = str(storage_mode or "").strip().lower() or "json"
        resolved_sqlite_path = sqlite_path or cls._default_sqlite_path(runtime_dir)
        if storage_config is not None:
            configured_mode = str(
                storage_config.get("planning_storage_mode") or ""
            ).strip().lower()
            if configured_mode:
                resolved_mode = configured_mode
            configured_path = storage_config.get("sqlite_path")
            if isinstance(configured_path, str) and configured_path.strip():
                resolved_sqlite_path = Path(configured_path.strip())
        return resolved_mode, resolved_sqlite_path

    @staticmethod
    def _now_iso() -> str:
        return datetime.now().astimezone().isoformat(timespec="seconds")

    @staticmethod
    def _parse_epoch(value: Any) -> int | None:
        if not isinstance(value, str) or not value.strip():
            return None
        try:
            dt = datetime.fromisoformat(value.strip())
        except ValueError:
            return None
        if dt.tzinfo is None:
            dt = dt.astimezone()
        else:
            dt = dt.astimezone()
        return int(dt.timestamp())
