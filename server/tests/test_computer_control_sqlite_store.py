from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.storage.sqlite_documents import resolve_state_db_path
from services.computer_control.models import ComputerActionRecord
from services.computer_control.store import ComputerActionStore


class ComputerControlSQLiteStoreTests(unittest.TestCase):
    def test_sqlite_store_bootstraps_legacy_json_and_keeps_recent_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "runtime"
            runtime_dir.mkdir(parents=True, exist_ok=True)
            legacy_path = runtime_dir / "computer_control_actions.json"
            legacy_path.write_text(
                json.dumps(
                    {
                        "items": [
                            {
                                "action_id": "cc_old_1",
                                "kind": "open_app",
                                "status": "completed",
                                "risk_level": "low",
                                "requires_confirmation": False,
                                "requested_via": "app",
                                "source_session_id": "app:main",
                                "arguments": {"app": "Safari"},
                                "created_at": "2026-04-14T10:00:00+08:00",
                                "updated_at": "2026-04-14T10:00:00+08:00",
                                "metadata": {},
                            },
                            {
                                "action_id": "cc_old_2",
                                "kind": "open_app",
                                "status": "completed",
                                "risk_level": "low",
                                "requires_confirmation": False,
                                "requested_via": "app",
                                "source_session_id": "app:main",
                                "arguments": {"app": "WeChat"},
                                "created_at": "2026-04-14T11:00:00+08:00",
                                "updated_at": "2026-04-14T11:00:00+08:00",
                                "metadata": {},
                            },
                        ]
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            store = ComputerActionStore(
                legacy_path,
                storage_config={"computer_action_storage_mode": "sqlite"},
            )

            recent = store.list_recent(limit=0)
            self.assertEqual([item["action_id"] for item in recent], ["cc_old_2", "cc_old_1"])
            self.assertTrue(resolve_state_db_path(runtime_dir).exists())

    def test_trim_keeps_pending_actions_even_when_over_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp)
            store = ComputerActionStore(
                runtime_dir / "computer_control_actions.json",
                max_items=2,
            )

            actions = [
                ComputerActionRecord(
                    action_id="cc_one",
                    kind="open_app",
                    status="completed",
                    risk_level="low",
                    requires_confirmation=False,
                    requested_via="app",
                    source_session_id="app:main",
                    arguments={"app": "Safari"},
                    created_at="2026-04-14T10:00:00+08:00",
                    updated_at="2026-04-14T10:00:00+08:00",
                ),
                ComputerActionRecord(
                    action_id="cc_two",
                    kind="open_app",
                    status="completed",
                    risk_level="low",
                    requires_confirmation=False,
                    requested_via="app",
                    source_session_id="app:main",
                    arguments={"app": "Notes"},
                    created_at="2026-04-14T11:00:00+08:00",
                    updated_at="2026-04-14T11:00:00+08:00",
                ),
                ComputerActionRecord(
                    action_id="cc_three",
                    kind="run_script",
                    status="awaiting_confirmation",
                    risk_level="medium",
                    requires_confirmation=True,
                    requested_via="app",
                    source_session_id="app:main",
                    arguments={"script_id": "project-healthcheck"},
                    created_at="2026-04-14T09:00:00+08:00",
                    updated_at="2026-04-14T09:00:00+08:00",
                ),
            ]

            for action in actions:
                store.save(action)

            recent = store.list_recent(limit=0)
            pending = store.list_pending(limit=0)

            self.assertEqual([item["action_id"] for item in recent], ["cc_two", "cc_one", "cc_three"])
            self.assertEqual([item["action_id"] for item in pending], ["cc_three"])
            self.assertIsNotNone(store.get("cc_three"))
