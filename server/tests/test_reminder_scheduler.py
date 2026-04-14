from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.app_api.resource_service import AppResourceService
from services.reminder_scheduler import ReminderScheduler


class _Observer:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict, dict]] = []

    async def on_reminder_triggered(
        self,
        *,
        reminder: dict,
        notification: dict,
    ) -> None:
        self.events.append(("on_reminder_triggered", reminder, notification))


class ReminderSchedulerTests(unittest.IsolatedAsyncioTestCase):
    _RESOURCE_MODES = ("json", "dual", "sqlite")

    def _make_scheduler(
        self,
        *,
        storage_mode: str,
        now: datetime,
    ) -> tuple[tempfile.TemporaryDirectory, AppResourceService, _Observer, ReminderScheduler]:
        tmpdir = tempfile.TemporaryDirectory()
        resources = AppResourceService(Path(tmpdir.name), storage_mode=storage_mode)
        observer = _Observer()
        scheduler = ReminderScheduler(
            resources,
            event_observer=observer,
            poll_interval_s=3600,
            now_provider=lambda: now,
        )
        return tmpdir, resources, observer, scheduler

    async def test_sync_reminder_prefers_snoozed_until(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                now = datetime(2026, 4, 9, 9, 0, tzinfo=timezone.utc)
                tmpdir, resources, observer, scheduler = self._make_scheduler(storage_mode=mode, now=now)
                try:
                    reminder = resources.create_reminder(
                        {
                            "title": "Follow up",
                            "time": "08:30",
                            "repeat": "daily",
                            "enabled": True,
                            "snoozed_until": (now + timedelta(minutes=20)).isoformat(),
                        }
                    )

                    synced = await scheduler.sync_reminder(reminder["reminder_id"])

                    assert synced is not None
                    self.assertEqual(synced["status"], "snoozed")
                    self.assertEqual(
                        datetime.fromisoformat(synced["next_trigger_at"]).astimezone(timezone.utc),
                        datetime.fromisoformat(reminder["snoozed_until"]).astimezone(timezone.utc),
                    )
                    self.assertEqual(observer.events, [])
                finally:
                    tmpdir.cleanup()

    async def test_complete_reminder_disables_future_triggers(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                now = datetime(2026, 4, 9, 9, 0, tzinfo=timezone.utc)
                tmpdir, resources, _observer, scheduler = self._make_scheduler(storage_mode=mode, now=now)
                try:
                    reminder = resources.create_reminder(
                        {
                            "title": "Archive inbox",
                            "time": "11:00",
                            "repeat": "daily",
                            "enabled": True,
                        }
                    )

                    completed = await scheduler.complete_reminder(reminder["reminder_id"])

                    assert completed is not None
                    self.assertFalse(completed["enabled"])
                    self.assertEqual(completed["status"], "completed")
                    self.assertIsNone(completed["next_trigger_at"])
                    self.assertIsNotNone(completed["completed_at"])
                finally:
                    tmpdir.cleanup()

    async def test_due_once_reminder_syncs_to_overdue_state(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                now = datetime(2026, 4, 9, 9, 0, tzinfo=timezone.utc)
                tmpdir, resources, _observer, scheduler = self._make_scheduler(storage_mode=mode, now=now)
                try:
                    reminder = resources.create_reminder(
                        {
                            "title": "Pay rent",
                            "time": (now - timedelta(minutes=5)).isoformat(),
                            "repeat": "once",
                            "enabled": True,
                        }
                    )

                    synced = await scheduler.sync_reminder(reminder["reminder_id"])

                    assert synced is not None
                    self.assertTrue(synced["enabled"])
                    self.assertEqual(synced["status"], "overdue")
                    self.assertEqual(
                        datetime.fromisoformat(synced["next_trigger_at"]).astimezone(timezone.utc),
                        datetime.fromisoformat(reminder["time"]).astimezone(timezone.utc),
                    )
                finally:
                    tmpdir.cleanup()

    async def test_due_once_reminder_creates_notification_and_stays_overdue(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                now = datetime(2026, 4, 9, 9, 0, tzinfo=timezone.utc)
                tmpdir, resources, observer, scheduler = self._make_scheduler(storage_mode=mode, now=now)
                try:
                    reminder = resources.create_reminder(
                        {
                            "title": "Pay rent",
                            "time": (now - timedelta(minutes=5)).isoformat(),
                            "repeat": "once",
                            "enabled": True,
                            "bundle_id": "bundle_plan_001",
                        }
                    )

                    await scheduler.sync_all()
                    await scheduler._process_due_reminders()

                    updated = resources.get_reminder(reminder["reminder_id"])
                    notifications = resources.list_notification_items()

                    assert updated is not None
                    self.assertTrue(updated["enabled"])
                    self.assertEqual(updated["status"], "overdue")
                    self.assertEqual(
                        datetime.fromisoformat(updated["next_trigger_at"]).astimezone(timezone.utc),
                        datetime.fromisoformat(reminder["time"]).astimezone(timezone.utc),
                    )
                    self.assertEqual(len(notifications), 1)
                    self.assertEqual(notifications[0]["metadata"]["reminder_id"], reminder["reminder_id"])
                    self.assertEqual(notifications[0]["metadata"]["bundle_id"], "bundle_plan_001")
                    self.assertEqual(len(observer.events), 1)
                finally:
                    tmpdir.cleanup()

    async def test_due_repeating_reminder_reschedules_and_returns_to_scheduled(self) -> None:
        for mode in self._RESOURCE_MODES:
            with self.subTest(storage_mode=mode):
                now = datetime(2026, 4, 9, 9, 0, tzinfo=timezone.utc)
                tmpdir, resources, _observer, scheduler = self._make_scheduler(storage_mode=mode, now=now)
                try:
                    reminder = resources.create_reminder(
                        {
                            "title": "Stand up",
                            "time": "08:55",
                            "repeat": "daily",
                            "enabled": True,
                            "snoozed_until": (now - timedelta(minutes=5)).isoformat(),
                        }
                    )

                    await scheduler.sync_all()
                    await scheduler._process_due_reminders()

                    updated = resources.get_reminder(reminder["reminder_id"])

                    assert updated is not None
                    self.assertTrue(updated["enabled"])
                    self.assertEqual(updated["status"], "scheduled")
                    self.assertEqual(
                        datetime.fromisoformat(updated["next_trigger_at"]).astimezone(timezone.utc),
                        datetime(2026, 4, 10, 8, 55, tzinfo=timezone.utc),
                    )
                    self.assertEqual(
                        datetime.fromisoformat(updated["last_triggered_at"]).astimezone(timezone.utc),
                        now,
                    )
                finally:
                    tmpdir.cleanup()
