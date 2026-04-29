from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.experience.interaction_router import ExperienceInteractionRouter


class ExperienceInteractionRouterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.router = ExperienceInteractionRouter()

    def test_pick_shake_mode_always_uses_context_random_reply(self) -> None:
        self.assertEqual(
            self.router.pick_shake_mode(
                scene_mode="focus",
                physical_state={"pending_confirmation": True},
                daily_shake_state={"valid_shake_count": 0},
            ),
            "random",
        )
        self.assertEqual(
            self.router.pick_shake_mode(
                scene_mode="meeting",
                physical_state={"pending_confirmation": False},
                daily_shake_state={"valid_shake_count": 0},
                requested_mode="random",
            ),
            "random",
        )
        self.assertEqual(
            self.router.pick_shake_mode(
                scene_mode="offwork",
                physical_state={"pending_confirmation": False},
                daily_shake_state={"valid_shake_count": 2},
                requested_mode="fortune",
            ),
            "random",
        )

    def test_route_shake_uses_context_candidate(self) -> None:
        result = self.router.route_shake(
            session_id="app:main",
            scene_mode="focus",
            physical_state={
                "shake_available": True,
                "pending_confirmation": False,
            },
            daily_shake_state={
                "date": "2026-04-14",
                "valid_shake_count": 1,
            },
            reply_language="Chinese",
            context={
                "candidates": [
                    {
                        "kind": "event",
                        "source": "planning_timeline",
                        "title": "下午考试",
                    }
                ]
            },
        )

        self.assertEqual(result["mode"], "random")
        self.assertEqual(result["short_result"], "context_random_ready")
        self.assertIn("下午考试", result["display_text"])
        self.assertEqual(result["metadata"]["context_kind"], "event")

    def test_route_shake_has_expanded_everyday_fallback_pool(self) -> None:
        result = self.router.route_shake(
            session_id="app:main",
            scene_mode="offwork",
            physical_state={
                "shake_available": True,
                "pending_confirmation": False,
            },
            reply_language="Chinese",
            context={"candidates": []},
        )

        self.assertEqual(result["mode"], "random")
        self.assertEqual(result["metadata"]["context_kind"], "fallback")
        self.assertGreaterEqual(result["metadata"]["context_candidate_count"], 8)
        self.assertTrue(result["display_text"].strip())
