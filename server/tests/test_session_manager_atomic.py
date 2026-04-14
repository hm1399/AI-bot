from __future__ import annotations

import importlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.session.manager import SessionManager


class AtomicWriteTextTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmpdir.name)

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def _load_atomic_write_text(self):
        spec = importlib.util.find_spec("nanobot.utils.atomic_write")
        if spec is None:
            self.fail("nanobot.utils.atomic_write module is missing")

        module = importlib.import_module("nanobot.utils.atomic_write")
        atomic_write_text = getattr(module, "atomic_write_text", None)
        self.assertIsNotNone(atomic_write_text, "atomic_write_text is missing")
        return atomic_write_text

    def _temp_files(self, path: Path) -> list[Path]:
        return list(path.parent.glob(f".{path.name}.*.tmp"))

    def test_atomic_write_text_replaces_target_after_successful_write(self) -> None:
        atomic_write_text = self._load_atomic_write_text()
        path = self.workspace / "sample.txt"
        path.write_text("old-content", encoding="utf-8")

        atomic_write_text(path, lambda handle: handle.write("new-content"), encoding="utf-8")

        self.assertEqual(path.read_text(encoding="utf-8"), "new-content")
        self.assertEqual(self._temp_files(path), [])

    def test_atomic_write_text_preserves_old_content_when_writer_fails(self) -> None:
        atomic_write_text = self._load_atomic_write_text()
        path = self.workspace / "sample.txt"
        path.write_text("stable-content", encoding="utf-8")

        def flaky_writer(handle) -> None:
            handle.write("partial-content")
            raise RuntimeError("boom")

        with self.assertRaisesRegex(RuntimeError, "boom"):
            atomic_write_text(path, flaky_writer, encoding="utf-8")

        self.assertEqual(path.read_text(encoding="utf-8"), "stable-content")
        self.assertEqual(self._temp_files(path), [])


class SessionManagerPersistenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmpdir.name)
        self.manager = SessionManager(self.workspace)

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_save_persists_session_that_can_be_reloaded(self) -> None:
        session = self.manager.get_or_create("app:main")
        session.metadata["title"] = "Main Session"
        session.add_message("user", "first", message_id="m1")
        session.add_message("assistant", "reply", message_id="m2")
        session.last_consolidated = 1

        self.manager.save(session)

        reloaded = SessionManager(self.workspace).get("app:main")
        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(reloaded.metadata["title"], "Main Session")
        self.assertEqual(reloaded.last_consolidated, 1)
        self.assertEqual(
            [message["message_id"] for message in reloaded.messages],
            ["m1", "m2"],
        )

    def test_save_preserves_existing_file_when_serialization_fails(self) -> None:
        session = self.manager.get_or_create("app:main")
        session.add_message("user", "first", message_id="m1")
        self.manager.save(session)

        path = self.manager._get_session_path(session.key)
        original_content = path.read_text(encoding="utf-8")
        session.add_message("assistant", "second", message_id="m2")

        real_dumps = json.dumps
        call_count = 0

        def flaky_dumps(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise RuntimeError("boom")
            return real_dumps(*args, **kwargs)

        with patch("nanobot.session.manager.json.dumps", side_effect=flaky_dumps):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                self.manager.save(session)

        self.assertEqual(path.read_text(encoding="utf-8"), original_content)
        self.assertEqual(list(path.parent.glob(f".{path.name}.*.tmp")), [])

    def test_save_rolls_back_cached_session_when_serialization_fails(self) -> None:
        session = self.manager.get_or_create("app:main")
        session.add_message("user", "first", message_id="m1")
        self.manager.save(session)
        self.assertIs(self.manager.get("app:main"), session)

        session.add_message("assistant", "second", message_id="m2")

        real_dumps = json.dumps
        call_count = 0

        def flaky_dumps(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise RuntimeError("boom")
            return real_dumps(*args, **kwargs)

        with patch("nanobot.session.manager.json.dumps", side_effect=flaky_dumps):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                self.manager.save(session)

        cached = self.manager.get("app:main")
        self.assertIs(cached, session)
        self.assertEqual([message["message_id"] for message in session.messages], ["m1"])

    def test_list_sessions_skips_invalid_jsonl_files(self) -> None:
        session = self.manager.get_or_create("app:main")
        session.add_message("user", "hello", message_id="m1")
        self.manager.save(session)

        broken = self.manager.sessions_dir / "broken.jsonl"
        broken.write_text("{broken json}\n", encoding="utf-8")

        sessions = self.manager.list_sessions()

        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["key"], "app:main")


class SessionManagerSQLiteModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmpdir.name)

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_sqlite_mode_imports_legacy_session_when_database_is_empty(self) -> None:
        legacy_dir = self.workspace / "legacy_sessions"
        legacy_dir.mkdir(parents=True, exist_ok=True)
        legacy_path = legacy_dir / "app_main.jsonl"
        legacy_path.write_text(
            "\n".join(
                [
                    json.dumps(
                        {
                            "_type": "metadata",
                            "key": "app:main",
                            "created_at": "2026-04-14T09:00:00+08:00",
                            "updated_at": "2026-04-14T09:01:00+08:00",
                            "metadata": {"channel": "app", "title": "主对话"},
                            "last_consolidated": 0,
                        },
                        ensure_ascii=False,
                    ),
                    json.dumps(
                        {
                            "role": "assistant",
                            "content": "from legacy",
                            "timestamp": "2026-04-14T09:01:00+08:00",
                            "message_id": "msg_1",
                        },
                        ensure_ascii=False,
                    ),
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        manager = SessionManager(self.workspace, storage_mode="sqlite")
        manager.legacy_sessions_dir = legacy_dir
        assert manager._jsonl_importer is not None
        manager._jsonl_importer.legacy_sessions_dir = legacy_dir

        session = manager.get("app:main")

        self.assertIsNotNone(session)
        assert session is not None
        self.assertEqual(session.messages[0]["content"], "from legacy")
        assert manager._sqlite_backend is not None
        self.assertTrue(manager._sqlite_backend.exists("app:main"))

    def test_sqlite_mode_rolls_back_cached_session_when_backend_save_fails(self) -> None:
        manager = SessionManager(self.workspace, storage_mode="sqlite")
        session = manager.get_or_create("app:main")
        session.add_message("user", "first", message_id="m1")
        manager.save(session)
        self.assertIs(manager.get("app:main"), session)

        session.add_message("assistant", "second", message_id="m2")
        assert manager._sqlite_backend is not None
        with patch.object(manager._sqlite_backend, "save_incremental", side_effect=RuntimeError("boom")):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                manager.save(session)

        self.assertEqual([message["message_id"] for message in session.messages], ["m1"])

    def test_sqlite_mode_uses_incremental_save_for_appended_messages(self) -> None:
        manager = SessionManager(self.workspace, storage_mode="sqlite")
        session = manager.get_or_create("app:main")
        session.add_message("user", "first", message_id="m1")
        manager.save(session)

        assert manager._sqlite_backend is not None
        real_save_incremental = manager._sqlite_backend.save_incremental
        observed_previous_counts: list[int] = []

        def recording_save_incremental(current_session, *, previous_message_count: int) -> None:
            observed_previous_counts.append(previous_message_count)
            real_save_incremental(
                current_session,
                previous_message_count=previous_message_count,
            )

        with patch.object(manager._sqlite_backend, "save_incremental", side_effect=recording_save_incremental):
            session.add_message("assistant", "second", message_id="m2")
            manager.save(session)

        self.assertEqual(observed_previous_counts, [1])

    def test_dual_mode_keeps_json_primary_when_sqlite_shadow_save_fails(self) -> None:
        manager = SessionManager(self.workspace, storage_mode="dual")
        session = manager.get_or_create("app:main")
        session.add_message("user", "first", message_id="m1")

        assert manager._sqlite_backend is not None
        with patch.object(manager._sqlite_backend, "save", side_effect=RuntimeError("boom")):
            manager.save(session)

        path = manager._get_session_path("app:main")
        self.assertTrue(path.exists())
        self.assertIn('"message_id": "m1"', path.read_text(encoding="utf-8"))
