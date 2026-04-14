from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.app_api.resource_service import AppResourceService
from services.planning.planning_bundle_service import PlanningBundleService
from services.planning.planning_projection_service import PlanningProjectionService
from services.planning.planning_summary_service import PlanningSummaryService


class PlanningBundleServiceTests(unittest.TestCase):
    def test_create_bundle_applies_shared_metadata_to_created_resources(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            resources = AppResourceService(Path(tmpdir))
            service = PlanningBundleService(
                resources,
                id_factory=lambda: "bundle_test_001",
            )

            created = service.create_bundle(
                tasks=[
                    {
                        "title": "Prepare kickoff",
                        "priority": "high",
                    }
                ],
                events=[
                    {
                        "title": "Kickoff",
                        "start_at": "2026-04-10T09:00:00+08:00",
                        "end_at": "2026-04-10T10:00:00+08:00",
                    }
                ],
                reminders=[
                    {
                        "title": "Join room",
                        "time": "2026-04-10T08:50:00+08:00",
                        "repeat": "once",
                    }
                ],
                source_metadata={
                    "created_via": "chat",
                    "source_channel": "app",
                    "source_message_id": "msg_100",
                    "source_session_id": "session_100",
                },
            )

            self.assertEqual(created["bundle_id"], "bundle_test_001")
            self.assertEqual(created["counts"], {"tasks": 1, "events": 1, "reminders": 1, "notifications": 0})
            self.assertEqual(created["tasks"][0]["bundle_id"], "bundle_test_001")
            self.assertEqual(created["events"][0]["source_message_id"], "msg_100")
            self.assertEqual(created["reminders"][0]["source_session_id"], "session_100")
            self.assertEqual(created["tasks"][0]["linked_event_id"], created["events"][0]["event_id"])
            self.assertEqual(created["tasks"][0]["linked_reminder_id"], created["reminders"][0]["reminder_id"])
            self.assertEqual(created["events"][0]["linked_task_id"], created["tasks"][0]["task_id"])
            self.assertEqual(created["events"][0]["linked_reminder_id"], created["reminders"][0]["reminder_id"])
            self.assertEqual(created["reminders"][0]["linked_task_id"], created["tasks"][0]["task_id"])
            self.assertEqual(created["reminders"][0]["linked_event_id"], created["events"][0]["event_id"])


class PlanningProjectionServiceTests(unittest.TestCase):
    def test_project_returns_overview_timeline_and_conflicts_from_raw_resources(self) -> None:
        service = PlanningProjectionService()
        now = datetime.fromisoformat("2026-04-09T08:00:00+08:00")

        projection = service.project(
            tasks=[
                {
                    "task_id": "task_001",
                    "title": "Send recap",
                    "priority": "medium",
                    "completed": False,
                    "due_at": "2026-04-09T11:00:00+08:00",
                    "bundle_id": "bundle_plan_001",
                },
                {
                    "task_id": "task_002",
                    "title": "Backlog grooming",
                    "priority": "low",
                    "completed": False,
                    "due_at": "2026-04-10T09:00:00+08:00",
                },
            ],
            events=[
                {
                    "event_id": "event_001",
                    "title": "Standup",
                    "start_at": "2026-04-09T09:00:00+08:00",
                    "end_at": "2026-04-09T09:30:00+08:00",
                },
                {
                    "event_id": "event_002",
                    "title": "Planning",
                    "start_at": "2026-04-09T09:15:00+08:00",
                    "end_at": "2026-04-09T10:00:00+08:00",
                },
            ],
            reminders=[
                {
                    "reminder_id": "rem_001",
                    "title": "Join war room",
                    "time": "2026-04-09T09:40:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-09T09:40:00+08:00",
                },
                {
                    "reminder_id": "rem_002",
                    "title": "Escalate blocker",
                    "time": "2026-04-09T11:00:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-09T11:00:00+08:00",
                    "priority": "high",
                },
            ],
            now=now,
        )

        self.assertEqual(
            [item["resource_id"] for item in projection["timeline"]],
            ["event_001", "event_002", "rem_001", "rem_002", "task_001", "task_002"],
        )
        self.assertEqual(
            projection["overview"]["counts"],
            {"tasks": 2, "events": 2, "reminders": 2, "timeline_items": 6, "conflicts": 3},
        )
        self.assertEqual(projection["overview"]["next_item_at"], "2026-04-09T09:00:00+08:00")
        self.assertEqual(
            {conflict["kind"] for conflict in projection["conflicts"]},
            {"event_overlap", "reminder_during_event", "task_due_conflict"},
        )

    def test_filter_timeline_for_date_returns_only_matching_items(self) -> None:
        service = PlanningProjectionService()
        timeline = service.build_timeline(
            tasks=[
                {
                    "task_id": "task_today",
                    "title": "Due today",
                    "completed": False,
                    "due_at": "2026-04-09T18:00:00+08:00",
                },
                {
                    "task_id": "task_other",
                    "title": "Due tomorrow",
                    "completed": False,
                    "due_at": "2026-04-10T09:00:00+08:00",
                },
            ],
            events=[
                {
                    "event_id": "event_span",
                    "title": "Overnight shift",
                    "start_at": "2026-04-08T23:00:00+08:00",
                    "end_at": "2026-04-09T02:00:00+08:00",
                }
            ],
            reminders=[
                {
                    "reminder_id": "rem_today",
                    "title": "Drink water",
                    "time": "2026-04-09T10:00:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-09T10:00:00+08:00",
                    "status": "scheduled",
                },
                {
                    "reminder_id": "rem_other",
                    "title": "Call mom",
                    "time": "2026-04-10T10:00:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-10T10:00:00+08:00",
                    "status": "scheduled",
                },
            ],
        )

        filtered = service.filter_timeline_for_date(
            timeline,
            "2026-04-09",
        )

        self.assertEqual(
            [item["resource_id"] for item in filtered],
            ["event_span", "rem_today", "task_today"],
        )

    def test_build_timeline_supports_surface_filter_and_metadata_passthrough(self) -> None:
        service = PlanningProjectionService()

        timeline = service.build_timeline(
            tasks=[
                {
                    "task_id": "task_assistant",
                    "title": "AI follow-up",
                    "completed": False,
                    "due_at": "2026-04-09T18:00:00+08:00",
                    "planning_surface": "tasks",
                    "owner_kind": "assistant",
                    "delivery_mode": "none",
                }
            ],
            events=[
                {
                    "event_id": "event_agenda",
                    "title": "Dentist",
                    "start_at": "2026-04-09T15:00:00+08:00",
                    "end_at": "2026-04-09T16:00:00+08:00",
                    "planning_surface": "agenda",
                    "owner_kind": "user",
                    "delivery_mode": "none",
                }
            ],
            reminders=[
                {
                    "reminder_id": "rem_hidden",
                    "title": "Meeting prompt",
                    "time": "2026-04-09T17:00:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "next_trigger_at": "2026-04-09T17:00:00+08:00",
                    "planning_surface": "hidden",
                    "owner_kind": "assistant",
                    "delivery_mode": "device_voice_and_notification",
                }
            ],
            surface="agenda",
        )

        self.assertEqual([item["resource_id"] for item in timeline], ["event_agenda"])
        self.assertEqual(timeline[0]["planning_surface"], "agenda")
        self.assertEqual(timeline[0]["owner_kind"], "user")
        self.assertEqual(timeline[0]["delivery_mode"], "none")

        task_timeline = service.build_timeline(
            tasks=[
                {
                    "task_id": "task_assistant",
                    "title": "AI follow-up",
                    "completed": False,
                    "due_at": "2026-04-09T18:00:00+08:00",
                    "planning_surface": "tasks",
                    "owner_kind": "assistant",
                    "delivery_mode": "none",
                }
            ],
            events=[],
            reminders=[],
            surface="tasks",
        )

        self.assertEqual([item["resource_id"] for item in task_timeline], ["task_assistant"])
        self.assertEqual(task_timeline[0]["planning_surface"], "tasks")
        self.assertEqual(task_timeline[0]["owner_kind"], "assistant")

    def test_build_timeline_ignores_invalid_surface_filter_values(self) -> None:
        service = PlanningProjectionService()

        timeline = service.build_timeline(
            tasks=[
                {
                    "task_id": "task_assistant",
                    "title": "AI follow-up",
                    "completed": False,
                    "due_at": "2026-04-09T18:00:00+08:00",
                    "planning_surface": "tasks",
                }
            ],
            events=[],
            reminders=[
                {
                    "reminder_id": "rem_hidden",
                    "title": "Delivery",
                    "time": "2026-04-09T17:00:00+08:00",
                    "repeat": "once",
                    "enabled": True,
                    "planning_surface": "hidden",
                }
            ],
            surface="not-a-surface",
        )

        self.assertEqual([item["resource_id"] for item in timeline], ["task_assistant"])

    def test_summary_service_supports_raw_inputs_and_projection_results(self) -> None:
        projection_service = PlanningProjectionService()
        summary_service = PlanningSummaryService(projection_service=projection_service)
        now = datetime.fromisoformat("2026-04-09T08:00:00+08:00")

        tasks = [
            {
                "task_id": "task_001",
                "title": "Review draft",
                "priority": "high",
                "completed": False,
                "due_at": "2026-04-09T07:30:00+08:00",
            },
            {
                "task_id": "task_002",
                "title": "Archive notes",
                "priority": "low",
                "completed": True,
                "due_at": "2026-04-09T09:00:00+08:00",
            },
        ]
        events = [
            {
                "event_id": "event_001",
                "title": "Design review",
                "start_at": "2026-04-09T09:00:00+08:00",
                "end_at": "2026-04-09T10:00:00+08:00",
            }
        ]
        reminders = [
            {
                "reminder_id": "rem_001",
                "title": "Check links",
                "time": "2026-04-09T08:45:00+08:00",
                "repeat": "once",
                "enabled": True,
                "next_trigger_at": "2026-04-09T08:45:00+08:00",
                "status": "scheduled",
            }
        ]

        projection = projection_service.project(
            tasks=tasks,
            events=events,
            reminders=reminders,
            now=now,
        )

        from_raw = summary_service.summarize(
            tasks=tasks,
            events=events,
            reminders=reminders,
            now=now,
        )
        from_projection = summary_service.summarize(
            projection=projection,
            now=now,
        )

        self.assertEqual(from_raw, from_projection)
        self.assertEqual(
            from_raw["todo_summary"],
            {
                "enabled": True,
                "pending_count": 1,
                "overdue_count": 1,
                "next_due_at": "2026-04-09T07:30:00+08:00",
            },
        )
        self.assertEqual(
            from_raw["calendar_summary"],
            {
                "enabled": True,
                "today_count": 2,
                "next_event_at": "2026-04-09T08:45:00+08:00",
                "next_event_title": "Check links",
            },
        )
