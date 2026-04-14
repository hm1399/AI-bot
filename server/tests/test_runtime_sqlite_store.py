from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.app_api.json_importer import import_runtime_json_collections, load_collection_items
from services.app_api.sqlite_store import SQLitePlanningStore


class RuntimeSQLiteStoreTests(unittest.TestCase):
    def test_json_importer_accepts_items_wrapper_and_bare_array(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            runtime_dir = Path(tmpdir)
            sqlite_store = SQLitePlanningStore(runtime_dir / "state.sqlite3")

            (runtime_dir / "tasks.json").write_text(
                json.dumps(
                    {
                        "items": [
                            {
                                "task_id": "task_001",
                                "title": "Review proposal",
                                "priority": "high",
                                "completed": False,
                                "created_at": "2026-04-10T08:00:00+08:00",
                                "updated_at": "2026-04-10T08:00:00+08:00",
                            }
                        ]
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            (runtime_dir / "events.json").write_text(
                json.dumps(
                    [
                        {
                            "event_id": "event_001",
                            "title": "Team review",
                            "start_at": "2026-04-10T09:00:00+08:00",
                            "end_at": "2026-04-10T10:00:00+08:00",
                            "created_at": "2026-04-10T08:00:00+08:00",
                            "updated_at": "2026-04-10T08:00:00+08:00",
                        }
                    ],
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(load_collection_items(runtime_dir / "tasks.json")[0]["task_id"], "task_001")
            summary = import_runtime_json_collections(runtime_dir, sqlite_store, overwrite=True)

            self.assertTrue(summary["tasks"]["imported"])
            self.assertTrue(summary["events"]["imported"])
            self.assertEqual(sqlite_store.domain_count("tasks"), 1)
            self.assertEqual(sqlite_store.domain_count("events"), 1)
            self.assertEqual(sqlite_store.list_items("tasks")[0]["task_id"], "task_001")
            self.assertEqual(sqlite_store.list_items("events")[0]["event_id"], "event_001")

    def test_reminder_runtime_is_split_into_indexed_runtime_table(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "state.sqlite3"
            sqlite_store = SQLitePlanningStore(db_path)
            sqlite_store.create(
                "reminders",
                {
                    "reminder_id": "rem_001",
                    "title": "Join call",
                    "time": "2026-04-10T08:50:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-10T08:50:00+08:00",
                    "status": "scheduled",
                    "created_at": "2026-04-10T08:00:00+08:00",
                    "updated_at": "2026-04-10T08:00:00+08:00",
                },
            )
            sqlite_store.create(
                "reminders",
                {
                    "reminder_id": "rem_002",
                    "title": "Tomorrow",
                    "time": "2026-04-11T08:50:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-11T08:50:00+08:00",
                    "status": "scheduled",
                    "created_at": "2026-04-10T08:01:00+08:00",
                    "updated_at": "2026-04-10T08:01:00+08:00",
                },
            )

            due_items = sqlite_store.list_due_reminders(due_before="2026-04-10T09:00:00+08:00")
            self.assertEqual([item["reminder_id"] for item in due_items], ["rem_001"])

            with sqlite3.connect(db_path) as conn:
                reminder_count = conn.execute("SELECT COUNT(*) FROM reminders").fetchone()[0]
                runtime_count = conn.execute("SELECT COUNT(*) FROM reminder_runtime").fetchone()[0]
                next_trigger_epoch = conn.execute(
                    "SELECT next_trigger_epoch FROM reminder_runtime WHERE reminder_id = ?",
                    ("rem_001",),
                ).fetchone()[0]

            self.assertEqual(reminder_count, 2)
            self.assertEqual(runtime_count, 2)
            self.assertIsInstance(next_trigger_epoch, int)

    def test_notification_and_reminder_update_share_one_sqlite_call_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sqlite_store = SQLitePlanningStore(Path(tmpdir) / "state.sqlite3")
            sqlite_store.create(
                "reminders",
                {
                    "reminder_id": "rem_001",
                    "title": "Join call",
                    "time": "2026-04-10T08:50:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-10T08:50:00+08:00",
                    "status": "scheduled",
                    "created_at": "2026-04-10T08:00:00+08:00",
                    "updated_at": "2026-04-10T08:00:00+08:00",
                },
            )

            notification, reminder = sqlite_store.create_notification_and_update_reminder(
                reminder_id="rem_001",
                notification_payload={
                    "notification_id": "notif_001",
                    "type": "reminder_due",
                    "priority": "high",
                    "title": "Join call",
                    "message": "Call starts now",
                    "metadata": {"reminder_id": "rem_001"},
                    "read": False,
                    "created_at": "2026-04-10T08:50:00+08:00",
                    "updated_at": "2026-04-10T08:50:00+08:00",
                },
                reminder_patch={
                    "last_triggered_at": "2026-04-10T08:50:00+08:00",
                    "status": "overdue",
                },
            )

            assert notification is not None
            assert reminder is not None
            self.assertEqual(notification["notification_id"], "notif_001")
            self.assertEqual(reminder["status"], "overdue")
            self.assertEqual(sqlite_store.domain_count("notifications"), 1)
            self.assertEqual(sqlite_store.get("reminders", "rem_001")["status"], "overdue")
