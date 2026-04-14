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
from services.experience.store import ExperienceStore


class ExperienceStoreSQLiteTests(unittest.TestCase):
    def test_sqlite_mode_bootstraps_legacy_json_and_persists_daily_shake_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "runtime"
            runtime_dir.mkdir(parents=True, exist_ok=True)
            legacy_path = runtime_dir / "experience_state.json"
            legacy_path.write_text(
                json.dumps(
                    {
                        "runtime_override": {"scene_mode": "focus"},
                        "interaction_history": [{"mode": "legacy"}],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            store = ExperienceStore(
                runtime_dir,
                storage_config={"experience_storage_mode": "sqlite"},
            )

            loaded = store.load()
            self.assertEqual(loaded["runtime_override"]["scene_mode"], "focus")
            self.assertEqual(len(loaded["interaction_history"]), 1)

            store.record_valid_shake("fortune")
            reloaded = ExperienceStore(
                runtime_dir,
                storage_config={"experience_storage_mode": "sqlite"},
            )
            shake_state = reloaded.get_daily_shake_state()

            self.assertEqual(shake_state["valid_shake_count"], 1)
            self.assertTrue(resolve_state_db_path(runtime_dir).exists())

    def test_history_limit_and_throttle_are_written_through_sqlite_document_store(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "runtime"
            store = ExperienceStore(runtime_dir)

            for index in range(5):
                store.record_interaction_result(
                    {"mode": f"mode-{index}"},
                    limit=3,
                )
            touched_at = store.touch_interaction("shake")
            reloaded = ExperienceStore(runtime_dir)

            history = reloaded.list_history(limit=0)
            self.assertEqual(len(history), 3)
            self.assertEqual(history[0]["mode"], "mode-2")
            self.assertEqual(history[-1]["mode"], "mode-4")
            self.assertTrue(reloaded.is_throttled("shake", ttl_s=60))
            self.assertGreater(touched_at, 0)
