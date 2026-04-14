from __future__ import annotations

import uuid
from copy import deepcopy
from typing import Any, Callable, Mapping

from services.app_api.resource_service import AppResourceService


class PlanningBundleService:
    """Normalizes cross-resource planning metadata around a shared bundle_id."""

    _RESOURCE_FIELDS = (
        "bundle_id",
        "created_via",
        "source_channel",
        "source_message_id",
        "source_session_id",
        "interaction_surface",
        "capture_source",
        "voice_path",
        "linked_task_id",
        "linked_event_id",
        "linked_reminder_id",
    )
    _SOURCE_FIELDS = _RESOURCE_FIELDS + (
        "scene_mode",
        "persona_profile_id",
        "persona_voice_style",
        "interaction_kind",
        "interaction_mode",
        "approval_source",
    )

    def __init__(
        self,
        resources: AppResourceService | None = None,
        *,
        id_factory: Callable[[], str] | None = None,
    ) -> None:
        self.resources = resources
        self._id_factory = id_factory or (lambda: f"bundle_{uuid.uuid4().hex[:12]}")

    def ensure_metadata(
        self,
        payload: dict[str, Any],
        *,
        bundle_id: str | None = None,
        defaults: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        result = deepcopy(payload)
        merged_defaults = defaults or {}

        candidate_bundle_id = (
            str(result.get("bundle_id") or "").strip()
            or str(merged_defaults.get("bundle_id") or "").strip()
            or bundle_id
            or self.new_bundle_id()
        )
        result["bundle_id"] = candidate_bundle_id

        for field in self._RESOURCE_FIELDS[1:]:
            if field in result:
                continue
            value = merged_defaults.get(field)
            if value is not None:
                result[field] = value
        return result

    def extract_metadata(
        self,
        payload: dict[str, Any],
        *,
        fields: tuple[str, ...] | None = None,
    ) -> dict[str, Any]:
        metadata: dict[str, Any] = {}
        for field in fields or self._SOURCE_FIELDS:
            value = payload.get(field)
            if value is None:
                continue
            cleaned = str(value).strip() if isinstance(value, str) else value
            if cleaned in {"", None}:
                continue
            metadata[field] = cleaned
        return metadata

    def build_source_metadata(
        self,
        source_metadata: Mapping[str, Any] | None = None,
        *,
        bundle_id: str | None = None,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_message_id: str | None = None,
        source_session_id: str | None = None,
        interaction_surface: str | None = None,
        capture_source: str | None = None,
        voice_path: str | None = None,
        scene_mode: str | None = None,
        persona_profile_id: str | None = None,
        persona_voice_style: str | None = None,
        interaction_kind: str | None = None,
        interaction_mode: str | None = None,
        approval_source: str | None = None,
        linked_task_id: str | None = None,
        linked_event_id: str | None = None,
        linked_reminder_id: str | None = None,
    ) -> dict[str, Any]:
        merged = deepcopy(dict(source_metadata or {}))
        explicit = {
            "bundle_id": bundle_id,
            "created_via": created_via,
            "source_channel": source_channel,
            "source_message_id": source_message_id,
            "source_session_id": source_session_id,
            "interaction_surface": interaction_surface,
            "capture_source": capture_source,
            "voice_path": voice_path,
            "scene_mode": scene_mode,
            "persona_profile_id": persona_profile_id,
            "persona_voice_style": persona_voice_style,
            "interaction_kind": interaction_kind,
            "interaction_mode": interaction_mode,
            "approval_source": approval_source,
            "linked_task_id": linked_task_id,
            "linked_event_id": linked_event_id,
            "linked_reminder_id": linked_reminder_id,
        }
        for key, value in explicit.items():
            if value is not None:
                merged[key] = value
        return self.extract_metadata(merged, fields=self._SOURCE_FIELDS)

    def attach_metadata(
        self,
        payload: Mapping[str, Any],
        *,
        bundle_id: str | None = None,
        source_metadata: Mapping[str, Any] | None = None,
        linked_task_id: str | None = None,
        linked_event_id: str | None = None,
        linked_reminder_id: str | None = None,
    ) -> dict[str, Any]:
        result = self.ensure_metadata(
            dict(payload),
            bundle_id=bundle_id,
            defaults=self.build_source_metadata(source_metadata, bundle_id=bundle_id),
        )
        explicit_links = {
            "linked_task_id": linked_task_id,
            "linked_event_id": linked_event_id,
            "linked_reminder_id": linked_reminder_id,
        }
        for key, value in explicit_links.items():
            if isinstance(value, str) and value.strip():
                result[key] = value.strip()
        return result

    def build_bundle_result(self, *resources: dict[str, Any]) -> dict[str, Any]:
        bundle_id = None
        resource_ids: dict[str, str] = {}
        for item in resources:
            if not isinstance(item, dict):
                continue
            bundle_id = bundle_id or item.get("bundle_id")
            for key in ("task_id", "event_id", "reminder_id", "notification_id"):
                value = item.get(key)
                if isinstance(value, str) and value.strip():
                    resource_ids[key] = value
        return {
            "bundle_id": bundle_id,
            "resource_ids": resource_ids,
        }

    def create_bundle(
        self,
        *,
        tasks: list[dict[str, Any]] | None = None,
        events: list[dict[str, Any]] | None = None,
        reminders: list[dict[str, Any]] | None = None,
        notifications: list[dict[str, Any]] | None = None,
        source_metadata: Mapping[str, Any] | None = None,
        bundle_id: str | None = None,
    ) -> dict[str, Any]:
        if self.resources is None:
            raise ValueError("resources is required to create a bundle")

        resolved_bundle_id = bundle_id or self.new_bundle_id()
        defaults = self.build_source_metadata(source_metadata, bundle_id=resolved_bundle_id)
        created_tasks = [
            self.resources.create_task(
                self.attach_metadata(payload, bundle_id=resolved_bundle_id, source_metadata=defaults)
            )
            for payload in (tasks or [])
        ]
        created_events = [
            self.resources.create_event(
                self.attach_metadata(payload, bundle_id=resolved_bundle_id, source_metadata=defaults)
            )
            for payload in (events or [])
        ]
        created_reminders = [
            self.resources.create_reminder(
                self.attach_metadata(payload, bundle_id=resolved_bundle_id, source_metadata=defaults)
            )
            for payload in (reminders or [])
        ]
        created_notifications = [
            self.resources.create_notification(
                self.attach_metadata(payload, bundle_id=resolved_bundle_id, source_metadata=defaults)
            )
            for payload in (notifications or [])
        ]
        created_tasks, created_events, created_reminders = self._auto_link_created_resources(
            created_tasks=created_tasks,
            created_events=created_events,
            created_reminders=created_reminders,
        )

        return {
            "bundle_id": resolved_bundle_id,
            "source_metadata": defaults,
            "tasks": created_tasks,
            "events": created_events,
            "reminders": created_reminders,
            "notifications": created_notifications,
            "counts": {
                "tasks": len(created_tasks),
                "events": len(created_events),
                "reminders": len(created_reminders),
                "notifications": len(created_notifications),
            },
        }

    def new_bundle_id(self) -> str:
        return self._id_factory()

    def _auto_link_created_resources(
        self,
        *,
        created_tasks: list[dict[str, Any]],
        created_events: list[dict[str, Any]],
        created_reminders: list[dict[str, Any]],
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
        task_id = created_tasks[0]["task_id"] if len(created_tasks) == 1 else None
        event_id = created_events[0]["event_id"] if len(created_events) == 1 else None
        reminder_id = created_reminders[0]["reminder_id"] if len(created_reminders) == 1 else None

        linked_tasks: list[dict[str, Any]] = []
        for item in created_tasks:
            patch: dict[str, Any] = {}
            if event_id and not item.get("linked_event_id"):
                patch["linked_event_id"] = event_id
            if reminder_id and not item.get("linked_reminder_id"):
                patch["linked_reminder_id"] = reminder_id
            linked_tasks.append(self.resources.update_task(item["task_id"], patch) if patch else item)

        linked_events: list[dict[str, Any]] = []
        for item in created_events:
            patch = {}
            if task_id and not item.get("linked_task_id"):
                patch["linked_task_id"] = task_id
            if reminder_id and not item.get("linked_reminder_id"):
                patch["linked_reminder_id"] = reminder_id
            linked_events.append(self.resources.update_event(item["event_id"], patch) if patch else item)

        linked_reminders: list[dict[str, Any]] = []
        for item in created_reminders:
            patch = {}
            if task_id and not item.get("linked_task_id"):
                patch["linked_task_id"] = task_id
            if event_id and not item.get("linked_event_id"):
                patch["linked_event_id"] = event_id
            linked_reminders.append(self.resources.update_reminder(item["reminder_id"], patch) if patch else item)

        return linked_tasks, linked_events, linked_reminders
