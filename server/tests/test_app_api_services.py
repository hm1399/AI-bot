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
    def test_tasks_filter_and_notification_unread_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            service = AppResourceService(Path(tmpdir))
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
