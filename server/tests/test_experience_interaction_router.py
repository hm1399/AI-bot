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

    def test_pick_shake_mode_prioritizes_pending_confirmation_then_daily_state(self) -> None:
        self.assertEqual(
            self.router.pick_shake_mode(
                scene_mode="focus",
                physical_state={"pending_confirmation": True},
                daily_shake_state={"valid_shake_count": 0},
            ),
            "decision",
        )
        self.assertEqual(
            self.router.pick_shake_mode(
                scene_mode="meeting",
                physical_state={"pending_confirmation": False},
                daily_shake_state={"valid_shake_count": 0},
                requested_mode="random",
            ),
            "fortune",
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

    def test_route_shake_rotates_random_content_pool(self) -> None:
        first = self.router.route_shake(
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
        )
        second = self.router.route_shake(
            session_id="app:main",
            scene_mode="focus",
            physical_state={
                "shake_available": True,
                "pending_confirmation": False,
            },
            daily_shake_state={
                "date": "2026-04-14",
                "valid_shake_count": 2,
            },
        )

        self.assertEqual(first["mode"], "random")
        self.assertEqual(second["mode"], "random")
        self.assertNotEqual(first["display_text"], second["display_text"])
