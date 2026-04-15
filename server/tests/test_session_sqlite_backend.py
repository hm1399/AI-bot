from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.session.jsonl_importer import JSONLSessionImporter
from nanobot.session.manager import Session
from nanobot.session.sqlite_backend import SQLiteSessionBackend
from nanobot.storage.sqlite_db import get_user_version
from services.app_api.sqlite_store import SQLitePlanningStore


class SQLiteSessionBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmpdir.name)
        self.db_path = self.workspace / "state.sqlite3"
        self.backend = SQLiteSessionBackend(self.db_path)

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def _build_session(self, key: str = "app:main") -> Session:
        session = Session(key=key)
        session.metadata.update(
            {
                "channel": "app",
                "title": "主对话",
                "pinned": True,
                "archived": False,
                "scene_mode": "meeting",
                "persona_profile": {"preset": "planner"},
                "persona_fields": {"tone": "calm"},
            }
        )
        session.add_message(
            "user",
            "提醒我五点开会",
            message_id="msg_user_1",
            task_id="task_1",
            client_message_id="client_1",
            app_session_id=key,
        )
        session.add_message(
            "assistant",
            "已为你记录",
            message_id="msg_assistant_1",
            task_id="task_1",
            source_channel="device",
            interaction_surface="voice",
            capture_source="mic",
            app_session_id=key,
            tool_results={"planning": [{"action": "create_reminder"}]},
        )
        session.last_consolidated = 1
        return session

    def test_backend_bootstraps_schema_with_generic_import_manifest_columns(self) -> None:
        with self.backend.factory.session() as connection:
            user_version = get_user_version(connection)
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(import_manifest);").fetchall()
            }

        self.assertEqual(user_version, 2)
        self.assertIn("manifest_key", columns)
        self.assertIn("domain", columns)
        self.assertIn("details_json", columns)
        self.assertNotIn("source_key", columns)
        self.assertNotIn("record_count", columns)
        self.assertNotIn("message_count", columns)

    def test_backend_accepts_shared_database_already_marked_at_schema_v2(self) -> None:
        sqlite_store = SQLitePlanningStore(self.db_path)
        self.assertEqual(sqlite_store.schema_version(), 2)

        backend = SQLiteSessionBackend(self.db_path)
        session = self._build_session("app:shared")
        backend.save(session)

        reloaded = backend.get("app:shared")
        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(reloaded.messages[0]["message_id"], "msg_user_1")

    def test_save_round_trip_preserves_raw_messages_summary_and_page_queries(self) -> None:
        session = self._build_session()
        self.backend.save(session)

        reloaded = self.backend.get("app:main")
        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(reloaded.last_consolidated, 1)
        self.assertEqual(
            reloaded.messages[1]["tool_results"]["planning"][0]["action"],
            "create_reminder",
        )

        summary = self.backend.get_session_summary("app:main", active_session_id="app:main")
        self.assertIsNotNone(summary)
        assert summary is not None
        self.assertEqual(summary["summary"], "已为你记录")
        self.assertEqual(summary["message_count"], 2)
        self.assertTrue(summary["active"])
        self.assertEqual(summary["persona_profile_id"], "planner")

        page = self.backend.get_messages_page("app:main", limit=1)
        self.assertEqual(len(page["items"]), 1)
        self.assertEqual(page["items"][0]["message_id"], "msg_assistant_1")
        self.assertEqual(page["items"][0]["metadata"]["source_channel"], "device")
        self.assertTrue(page["page_info"]["has_more_before"])

    def test_save_preserves_existing_rows_when_serialization_fails(self) -> None:
        session = self._build_session()
        self.backend.save(session)

        session.add_message("assistant", "新的回复", message_id="msg_assistant_2")
        real_dumps = json.dumps
        call_count = 0

        def flaky_dumps(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise RuntimeError("boom")
            return real_dumps(*args, **kwargs)

        with patch("nanobot.session.sqlite_backend.json.dumps", side_effect=flaky_dumps):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                self.backend.save(session)

        reloaded = self.backend.get("app:main")
        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(
            [message["message_id"] for message in reloaded.messages],
            ["msg_user_1", "msg_assistant_1"],
        )

    def test_save_incremental_appends_new_messages_and_updates_summary(self) -> None:
        session = self._build_session()
        self.backend.save(session)

        session.add_message("assistant", "第二次回复", message_id="msg_assistant_2")
        self.backend.save_incremental(session, previous_message_count=2)

        reloaded = self.backend.get("app:main")
        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(
            [message["message_id"] for message in reloaded.messages],
            ["msg_user_1", "msg_assistant_1", "msg_assistant_2"],
        )

        summary = self.backend.get_session_summary("app:main", active_session_id="app:main")
        self.assertIsNotNone(summary)
        assert summary is not None
        self.assertEqual(summary["summary"], "第二次回复")
        self.assertEqual(summary["message_count"], 3)


class JSONLSessionImporterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmpdir.name)
        self.db_path = self.workspace / "state.sqlite3"
        self.backend = SQLiteSessionBackend(self.db_path)
        self.workspace_sessions_dir = self.workspace / "sessions"
        self.workspace_sessions_dir.mkdir(parents=True, exist_ok=True)
        self.legacy_sessions_dir = self.workspace / "legacy_sessions"
        self.legacy_sessions_dir.mkdir(parents=True, exist_ok=True)
        self.importer = JSONLSessionImporter(
            backend=self.backend,
            workspace_sessions_dir=self.workspace_sessions_dir,
            legacy_sessions_dir=self.legacy_sessions_dir,
        )

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def _write_jsonl(self, directory: Path, key: str, title: str, body: str) -> Path:
        path = directory / f"{key.replace(':', '_')}.jsonl"
        lines = [
            {
                "_type": "metadata",
                "key": key,
                "created_at": "2026-04-14T09:00:00+08:00",
                "updated_at": "2026-04-14T09:05:00+08:00",
                "metadata": {
                    "channel": "app",
                    "title": title,
                    "pinned": key == "app:main",
                    "archived": False,
                },
                "last_consolidated": 0,
            },
            {
                "role": "assistant",
                "content": body,
                "timestamp": "2026-04-14T09:05:00+08:00",
                "message_id": f"{key.replace(':', '_')}_msg_1",
            },
        ]
        path.write_text(
            "\n".join(json.dumps(line, ensure_ascii=False) for line in lines) + "\n",
            encoding="utf-8",
        )
        return path

    def test_importer_records_generic_manifest_details_and_is_idempotent(self) -> None:
        self._write_jsonl(self.workspace_sessions_dir, "app:main", "主对话", "workspace body")

        imported_first = self.importer.import_all_available()
        imported_second = self.importer.import_all_available()

        self.assertEqual(imported_first, 1)
        self.assertEqual(imported_second, 0)
        manifest = self.backend.get_import_manifest("session:app:main")
        self.assertIsNotNone(manifest)
        assert manifest is not None
        self.assertEqual(manifest.domain, "session")
        self.assertEqual(manifest.details["session_id"], "app:main")
        self.assertEqual(manifest.details["message_count"], 1)

    def test_importer_prefers_workspace_copy_over_legacy_duplicate(self) -> None:
        self._write_jsonl(self.workspace_sessions_dir, "app:main", "主对话", "workspace body")
        self._write_jsonl(self.legacy_sessions_dir, "app:main", "旧主对话", "legacy body")

        imported = self.importer.import_all_available()

        self.assertEqual(imported, 1)
        session = self.backend.get("app:main")
        self.assertIsNotNone(session)
        assert session is not None
        self.assertEqual(session.metadata["title"], "主对话")
        self.assertEqual(session.messages[0]["content"], "workspace body")
