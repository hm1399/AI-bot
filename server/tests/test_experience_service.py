from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.storage.sqlite_documents import resolve_state_db_path
from nanobot.session.manager import SessionManager
from services.app_api.settings_service import SettingsService
from services.experience.service import ExperienceService


class StubSettingsService:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = dict(payload)

    def get_public_settings(self) -> dict[str, Any]:
        return dict(self.payload)


class ExperienceServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        workspace = Path(self.tmpdir.name)
        self.sessions = SessionManager(workspace)
        self.device_snapshot = {
            "connected": True,
            "state": "IDLE",
            "last_command": {"status": "idle"},
        }
        self.desktop_snapshot = {
            "ready": True,
            "status": "idle",
            "capture_active": False,
        }
        self.computer_state = {
            "pending_actions": [],
            "recent_actions": [],
        }
        self.notifications: list[dict[str, Any]] = []
        self.confirmed_action_ids: list[str] = []
        self.cancelled_action_ids: list[str] = []
        self.active_session_id = "app:main"
        self.settings = StubSettingsService(
            {
                "default_scene_mode": "focus",
                "persona_tone_style": "clear",
                "persona_reply_length": "medium",
                "persona_proactivity": "balanced",
                "persona_voice_style": "calm",
                "physical_interaction_enabled": True,
                "shake_enabled": True,
                "tap_confirmation_enabled": True,
                "wake_word": "Hey Assistant",
                "auto_listen": True,
            }
        )
        self.service = ExperienceService(
            runtime_dir=workspace / "runtime",
            settings_service=self.settings,
            sessions=self.sessions,
            active_session_id_resolver=lambda: self.active_session_id,
            device_snapshot_provider=lambda: dict(self.device_snapshot),
            desktop_voice_snapshot_provider=lambda: dict(self.desktop_snapshot),
            computer_state_provider=lambda: dict(self.computer_state),
            notifications_provider=lambda: list(self.notifications),
            confirm_computer_action=self._confirm_action,
            cancel_computer_action=self._cancel_action,
        )

    async def asyncTearDown(self) -> None:
        self.tmpdir.cleanup()

    async def _confirm_action(self, action_id: str) -> dict[str, Any]:
        self.confirmed_action_ids.append(action_id)
        return {
            "action_id": action_id,
            "kind": "wechat_prepare_message",
            "status": "completed",
            "result": {
                "delivery_mode": "manual_step_required",
                "prepared": True,
            },
        }

    async def _cancel_action(self, action_id: str) -> dict[str, Any]:
        self.cancelled_action_ids.append(action_id)
        return {
            "action_id": action_id,
            "kind": "wechat_prepare_message",
            "status": "cancelled",
        }

    async def test_runtime_snapshot_prefers_session_override_and_keeps_placeholders_honest(self) -> None:
        session = self.sessions.get_or_create("app:main")
        session.metadata.update(
            {
                "scene_mode": "meeting",
                "persona_fields": {"voice_style": "quiet"},
            }
        )
        self.sessions.save(session)

        snapshot = self.service.get_runtime_snapshot()

        self.assertEqual(snapshot["active_scene_mode"], "meeting")
        self.assertEqual(snapshot["override_source"], "session_override")
        self.assertEqual(snapshot["active_persona"]["voice_style"], "quiet")
        self.assertEqual(snapshot["active_persona"]["reply_length"], "short")
        self.assertTrue(snapshot["physical_interaction"]["enabled"])
        self.assertIn("daily_shake_state", snapshot)
        self.assertIn("scene_modes", snapshot)
        self.assertIn("persona_presets", snapshot)

    async def test_runtime_override_is_supported_but_lower_priority_than_session_override(self) -> None:
        session = self.sessions.get_or_create("app:main")
        session.metadata["scene_mode"] = "meeting"
        self.sessions.save(session)

        updated = self.service.update_runtime_override(
            {
                "scene_mode": "offwork",
                "persona_fields": {"voice_style": "bright"},
            }
        )
        snapshot = self.service.get_runtime_snapshot()

        self.assertEqual(updated["scene_mode"], "offwork")
        self.assertEqual(snapshot["active_scene_mode"], "meeting")
        self.assertEqual(snapshot["override_source"], "session_override")

    async def test_tap_allow_confirms_pending_action_without_claiming_auto_send(self) -> None:
        self.computer_state["pending_actions"] = [
            {
                "action_id": "act_001",
                "kind": "wechat_prepare_message",
                "status": "awaiting_confirmation",
                "title": "Open Safari",
            }
        ]

        result = await self.service.handle_interaction(
            "tap",
            {"tap_count": 1, "app_session_id": "app:main"},
        )

        self.assertEqual(self.confirmed_action_ids, ["act_001"])
        self.assertEqual(result["mode"], "allow")
        self.assertEqual(result["short_result"], "allowed")
        self.assertIn("manual_step_required", str(result.get("metadata")))
        self.assertNotIn("已自动发送", result["display_text"])
        self.assertEqual(
            self.service.get_runtime_snapshot()["last_interaction_result"]["mode"],
            "allow",
        )

    async def test_shake_is_blocked_while_voice_pipeline_is_busy(self) -> None:
        self.desktop_snapshot["status"] = "responding"

        result = await self.service.handle_interaction(
            "shake",
            {"app_session_id": "app:main"},
        )

        self.assertEqual(result["interaction_kind"], "shake")
        self.assertEqual(result["short_result"], "blocked")
        self.assertEqual(result["metadata"]["blocked_reason"], "voice_busy")

    async def test_shake_stays_available_when_desktop_bridge_is_not_ready(self) -> None:
        self.desktop_snapshot["ready"] = False

        snapshot = self.service.get_runtime_snapshot()
        physical = snapshot["physical_interaction"]

        self.assertFalse(physical["hold_available"])
        self.assertEqual(physical["hold_blocked_reason"], "desktop_bridge_unavailable")
        self.assertTrue(physical["shake_available"])
        self.assertIsNone(physical["shake_blocked_reason"])

    async def test_pending_confirmation_shake_routes_to_decision_without_consuming_daily_fortune(self) -> None:
        self.computer_state["pending_actions"] = [
            {
                "action_id": "act_001",
                "kind": "wechat_prepare_message",
                "status": "awaiting_confirmation",
                "title": "Open Safari",
            }
        ]

        before = self.service.get_runtime_snapshot()
        result = await self.service.handle_interaction(
            "shake",
            {"app_session_id": "app:main"},
        )
        after = self.service.get_runtime_snapshot()

        self.assertTrue(before["physical_interaction"]["shake_available"])
        self.assertEqual(before["physical_interaction"]["shake_mode"], "decision")
        self.assertEqual(result["mode"], "decision")
        self.assertIn("Open Safari", result["display_text"])
        self.assertEqual(after["daily_shake_state"]["valid_shake_count"], 0)
        self.assertTrue(after["daily_shake_state"]["fortune_available"])

    async def test_first_valid_shake_today_routes_to_fortune_then_random_and_updates_daily_state(self) -> None:
        first = await self.service.handle_interaction(
            "shake",
            {"app_session_id": "app:main"},
        )
        self.service.store.clear_interaction_throttle("shake")

        second = await self.service.handle_interaction(
            "shake",
            {"app_session_id": "app:main"},
        )
        snapshot = self.service.get_runtime_snapshot()
        daily_state = snapshot["daily_shake_state"]

        self.assertEqual(first["interaction_kind"], "shake")
        self.assertEqual(first["mode"], "fortune")
        self.assertEqual(second["mode"], "random")
        self.assertEqual(snapshot["last_interaction_result"]["mode"], "random")
        self.assertTrue(snapshot["physical_interaction"]["ready"])
        self.assertEqual(snapshot["physical_interaction"]["status"], "ready")
        self.assertEqual(snapshot["physical_interaction"]["shake_mode"], "random")
        self.assertIsNotNone(snapshot["physical_interaction"]["latest_interaction_at"])
        self.assertGreaterEqual(len(snapshot["physical_interaction"]["history"]), 1)
        self.assertEqual(daily_state["valid_shake_count"], 2)
        self.assertFalse(daily_state["fortune_available"])

    async def test_default_service_persists_runtime_state_via_sqlite_store(self) -> None:
        await self.service.handle_interaction(
            "shake",
            {"app_session_id": "app:main"},
        )

        reloaded = ExperienceService(
            runtime_dir=Path(self.tmpdir.name) / "runtime",
            settings_service=self.settings,
            sessions=self.sessions,
            active_session_id_resolver=lambda: self.active_session_id,
            device_snapshot_provider=lambda: dict(self.device_snapshot),
            desktop_voice_snapshot_provider=lambda: dict(self.desktop_snapshot),
            computer_state_provider=lambda: dict(self.computer_state),
            notifications_provider=lambda: list(self.notifications),
            confirm_computer_action=self._confirm_action,
            cancel_computer_action=self._cancel_action,
        )
        snapshot = reloaded.get_runtime_snapshot()

        self.assertEqual(snapshot["daily_shake_state"]["valid_shake_count"], 1)
        self.assertTrue(resolve_state_db_path(Path(self.tmpdir.name) / "runtime").exists())


class SettingsServiceExperienceFieldsTests(unittest.TestCase):
    def test_settings_service_exposes_and_updates_experience_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp)
            service = SettingsService(
                {
                    "app": {
                        "settings": {
                            "default_scene_mode": "focus",
                            "persona_tone_style": "clear",
                            "persona_reply_length": "medium",
                            "persona_proactivity": "balanced",
                            "persona_voice_style": "calm",
                            "physical_interaction_enabled": True,
                            "shake_enabled": True,
                            "tap_confirmation_enabled": True,
                        }
                    }
                },
                runtime_dir,
            )

            current = service.get_public_settings()
            self.assertEqual(current["default_scene_mode"], "focus")
            self.assertTrue(current["physical_interaction_enabled"])

            updated = service.update_settings(
                {
                    "default_scene_mode": "meeting",
                    "persona_tone_style": "warm",
                    "persona_reply_length": "short",
                    "persona_proactivity": "low",
                    "persona_voice_style": "quiet",
                    "physical_interaction_enabled": False,
                    "shake_enabled": False,
                    "tap_confirmation_enabled": True,
                }
            )

            self.assertEqual(updated["default_scene_mode"], "meeting")
            self.assertEqual(updated["persona_voice_style"], "quiet")
            self.assertFalse(updated["physical_interaction_enabled"])
            self.assertFalse(updated["shake_enabled"])
