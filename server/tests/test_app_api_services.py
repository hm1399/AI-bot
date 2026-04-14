from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.providers.base import LLMResponse
from services.app_api.json_store import JsonCollectionStore
from services.app_api.resource_service import AppResourceService
from services.app_api.settings_service import SettingsService


class JsonCollectionStoreTests(unittest.TestCase):
    def test_json_store_upsert_and_delete_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JsonCollectionStore(
                Path(tmpdir) / "tasks.json",
                id_field="task_id",
                prefix="task",
            )

            created = store.create({"title": "Review proposal", "priority": "high"})
            self.assertTrue(created["task_id"].startswith("task_"))

            updated = store.update(created["task_id"], {"completed": True})
            self.assertIsNotNone(updated)
            self.assertTrue(updated["completed"])

            deleted = store.delete(created["task_id"])
            self.assertEqual(deleted["task_id"], created["task_id"])
            self.assertEqual(store.list_items(), [])


class ResourceServiceTests(unittest.TestCase):
    _RESOURCE_MODES = ("json", "dual", "sqlite")

    def test_tasks_filter_and_notification_unread_count(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                with tempfile.TemporaryDirectory() as tmpdir:
                    service = AppResourceService(Path(tmpdir), storage_mode=mode)
                    service.create_task({"title": "Review proposal", "priority": "high"})
                    service.create_task({
                        "title": "Archive notes",
                        "priority": "low",
                        "completed": True,
                    })

                    filtered = service.list_tasks(completed=False, priority="high", limit=10)
                    self.assertEqual([item["title"] for item in filtered["items"]], ["Review proposal"])

                    service.create_notification({
                        "type": "task_due",
                        "priority": "high",
                        "title": "Task Due Soon",
                        "message": "Review proposal is due in 1 hour",
                        "metadata": {"task_id": "task_001"},
                    })
                    service.create_notification({
                        "type": "device",
                        "priority": "low",
                        "title": "Device online",
                        "message": "ESP32 reconnected",
                        "metadata": {},
                    })
                    summary = service.list_notifications()
                    self.assertEqual(summary["unread_count"], 2)

    def test_resources_accept_optional_planning_metadata(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                with tempfile.TemporaryDirectory() as tmpdir:
                    service = AppResourceService(Path(tmpdir), storage_mode=mode)

                    task = service.create_task(
                        {
                            "title": "Review proposal",
                            "priority": "high",
                            "bundle_id": "bundle_plan_001",
                            "created_via": "chat",
                            "source_channel": "app",
                            "source_message_id": "msg_001",
                            "source_session_id": "session_001",
                        }
                    )
                    self.assertEqual(task["bundle_id"], "bundle_plan_001")
                    self.assertEqual(task["created_via"], "chat")
                    self.assertEqual(task["source_channel"], "app")
                    self.assertEqual(task["source_message_id"], "msg_001")
                    self.assertEqual(task["source_session_id"], "session_001")

                    event = service.create_event(
                        {
                            "title": "Team review",
                            "start_at": "2026-04-10T09:00:00+08:00",
                            "end_at": "2026-04-10T10:00:00+08:00",
                            "bundle_id": "bundle_plan_001",
                            "created_via": "voice",
                            "linked_task_id": task["task_id"],
                        }
                    )
                    self.assertEqual(event["bundle_id"], "bundle_plan_001")
                    self.assertEqual(event["created_via"], "voice")
                    self.assertEqual(event["linked_task_id"], task["task_id"])

                    reminder = service.create_reminder(
                        {
                            "title": "Join call",
                            "time": "2026-04-10T08:50:00+08:00",
                            "repeat": "once",
                            "bundle_id": "bundle_plan_001",
                            "linked_task_id": task["task_id"],
                            "linked_event_id": event["event_id"],
                            "next_trigger_at": "2026-04-10T08:50:00+08:00",
                            "last_triggered_at": None,
                            "last_error": None,
                            "snoozed_until": "2026-04-10T08:55:00+08:00",
                            "completed_at": None,
                            "status": "scheduled",
                        }
                    )
                    self.assertEqual(reminder["bundle_id"], "bundle_plan_001")
                    self.assertEqual(reminder["linked_task_id"], task["task_id"])
                    self.assertEqual(reminder["linked_event_id"], event["event_id"])
                    self.assertEqual(reminder["next_trigger_at"], "2026-04-10T08:50:00+08:00")
                    self.assertEqual(reminder["snoozed_until"], "2026-04-10T08:55:00+08:00")
                    self.assertEqual(reminder["status"], "scheduled")

                    updated = service.update_reminder(
                        reminder["reminder_id"],
                        {
                            "linked_task_id": None,
                            "snoozed_until": None,
                            "status": "completed",
                            "completed_at": "2026-04-10T09:15:00+08:00",
                        },
                    )
                    self.assertIsNone(updated["linked_task_id"])
                    self.assertIsNone(updated["snoozed_until"])
                    self.assertEqual(updated["status"], "completed")
                    self.assertEqual(updated["completed_at"], "2026-04-10T09:15:00+08:00")

    def test_notification_normalization_preserves_metadata_and_origin_links(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                with tempfile.TemporaryDirectory() as tmpdir:
                    service = AppResourceService(Path(tmpdir), storage_mode=mode)
                    metadata = {
                        "scheduled_for": "2026-04-10T08:50:00+08:00",
                        "custom": {"channel": "desktop"},
                    }

                    notification = service.create_notification(
                        {
                            "type": "reminder_due",
                            "priority": "high",
                            "title": "Join call",
                            "message": "Call starts in 10 minutes",
                            "metadata": metadata,
                            "bundle_id": "bundle_plan_001",
                            "created_via": "scheduler",
                            "source_channel": "app",
                            "source_message_id": "msg_001",
                            "source_session_id": "session_001",
                            "linked_task_id": "task_001",
                            "linked_event_id": "event_001",
                            "linked_reminder_id": "rem_001",
                        }
                    )

                    metadata["custom"]["channel"] = "mutated"
                    self.assertEqual(notification["metadata"]["custom"]["channel"], "desktop")
                    self.assertEqual(notification["metadata"]["bundle_id"], "bundle_plan_001")
                    self.assertEqual(notification["metadata"]["created_via"], "scheduler")
                    self.assertEqual(notification["metadata"]["source_channel"], "app")
                    self.assertEqual(notification["metadata"]["source_message_id"], "msg_001")
                    self.assertEqual(notification["metadata"]["source_session_id"], "session_001")
                    self.assertEqual(notification["metadata"]["linked_task_id"], "task_001")
                    self.assertEqual(notification["metadata"]["linked_event_id"], "event_001")
                    self.assertEqual(notification["metadata"]["linked_reminder_id"], "rem_001")
                    self.assertEqual(notification["metadata"]["task_id"], "task_001")
                    self.assertEqual(notification["metadata"]["event_id"], "event_001")
                    self.assertEqual(notification["metadata"]["reminder_id"], "rem_001")

    def test_planning_inputs_and_reminder_transaction_stay_compatible_across_modes(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                with tempfile.TemporaryDirectory() as tmpdir:
                    service = AppResourceService(Path(tmpdir), storage_mode=mode)
                    task = service.create_task({"title": "Review proposal", "priority": "high"})
                    event = service.create_event(
                        {
                            "title": "Team review",
                            "start_at": "2026-04-10T09:00:00+08:00",
                            "end_at": "2026-04-10T10:00:00+08:00",
                        }
                    )
                    reminder = service.create_reminder(
                        {
                            "title": "Join call",
                            "time": "2026-04-10T08:50:00+08:00",
                            "repeat": "once",
                            "linked_task_id": task["task_id"],
                            "linked_event_id": event["event_id"],
                            "next_trigger_at": "2026-04-10T08:50:00+08:00",
                            "status": "scheduled",
                        }
                    )

                    inputs = service.planning_inputs()
                    self.assertEqual([item["task_id"] for item in inputs["tasks"]], [task["task_id"]])
                    self.assertEqual([item["event_id"] for item in inputs["events"]], [event["event_id"]])
                    self.assertEqual([item["reminder_id"] for item in inputs["reminders"]], [reminder["reminder_id"]])
                    self.assertEqual(inputs["notifications"], [])

                    notification, updated_reminder = service.create_notification_and_update_reminder(
                        reminder_id=reminder["reminder_id"],
                        notification_payload={
                            "type": "reminder_due",
                            "priority": "high",
                            "title": "Join call",
                            "message": "Call starts now",
                            "metadata": {"reminder_id": reminder["reminder_id"]},
                        },
                        reminder_patch={
                            "last_triggered_at": "2026-04-10T08:50:00+08:00",
                            "status": "overdue",
                        },
                    )

                    assert notification is not None
                    assert updated_reminder is not None
                    self.assertEqual(notification["metadata"]["reminder_id"], reminder["reminder_id"])
                    self.assertEqual(updated_reminder["status"], "overdue")
                    self.assertEqual(service.list_notifications()["unread_count"], 1)
                    if mode == "dual":
                        self.assertEqual(service.shadow_mismatch_count, 0)


class SettingsServiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_masks_secret_and_reports_configured_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            runtime_dir = Path(tmpdir)
            service = SettingsService(
                {
                    "server": {"host": "192.168.1.100", "port": 8000},
                    "nanobot": {"provider": "openai", "model": "gpt-4o"},
                    "asr": {"language": "en-US"},
                    "tts": {"voice": "alloy"},
                    "app": {"settings": {"device_volume": 60}},
                },
                runtime_dir,
            )

            updated = service.update_settings({
                "device_volume": 75,
                "llm_api_key": "secret-key",
                "wake_word": "Hey Assistant",
            })
            self.assertEqual(updated["device_volume"], 75)
            self.assertTrue(updated["llm_api_key_configured"])
            self.assertNotIn("llm_api_key", updated)

    async def test_llm_test_maps_timeout_and_auth_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            runtime_dir = Path(tmpdir)
            service = SettingsService(
                {
                    "server": {"host": "192.168.1.100", "port": 8000},
                    "nanobot": {"provider": "openai", "model": "gpt-4o"},
                },
                runtime_dir,
            )
            service.update_settings({"llm_api_key": "secret-key"})

            with patch("services.app_api.settings_service.LiteLLMProvider") as provider_cls:
                provider = provider_cls.return_value
                provider.chat = AsyncMock(return_value=LLMResponse.from_error(
                    "401 unauthorized",
                    kind="provider_error",
                    code="AuthError",
                ))
                ok, payload, error = await service.test_llm_connection()
                self.assertFalse(ok)
                self.assertIsNone(payload)
                self.assertEqual(error["code"], "UPSTREAM_AUTH_FAILED")

                provider.chat = AsyncMock(return_value=LLMResponse.from_error(
                    "timeout",
                    kind="timeout",
                    code="TimeoutError",
                ))
                ok, payload, error = await service.test_llm_connection()
                self.assertFalse(ok)
                self.assertIsNone(payload)
                self.assertEqual(error["code"], "UPSTREAM_TIMEOUT")
