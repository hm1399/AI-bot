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
        self.assertEqual(
            [message["message_id"] for message in session.messages],
            ["m1"],
        )

    def test_list_sessions_skips_invalid_jsonl_files(self) -> None:
        session = self.manager.get_or_create("app:main")
        session.add_message("user", "hello", message_id="m1")
        self.manager.save(session)

        broken = self.manager.sessions_dir / "broken.jsonl"
        broken.write_text("{broken json}\n", encoding="utf-8")

        sessions = self.manager.list_sessions()

        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["key"], "app:main")
