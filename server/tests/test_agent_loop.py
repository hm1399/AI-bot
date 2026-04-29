from __future__ import annotations

import asyncio
import importlib
import json
import sys
import tempfile
import time
import types
import unittest
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import MethodType
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.agent.loop import AgentLoop
from nanobot.bus.events import InboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.providers.base import LLMResponse, ToolCallRequest


class FakeProvider:
    def get_default_model(self) -> str:
        return "fake-model"


class SequencedProvider(FakeProvider):
    def __init__(self, responses: list[LLMResponse]) -> None:
        self._responses = list(responses)

    async def chat(self, **kwargs):
        if not self._responses:
            raise AssertionError("No more fake responses queued")
        return self._responses.pop(0)


class CapturingProvider(SequencedProvider):
    def __init__(self, responses: list[LLMResponse]) -> None:
        super().__init__(responses)
        self.calls: list[dict[str, object]] = []

    async def chat(self, **kwargs):
        self.calls.append(dict(kwargs))
        return await super().chat(**kwargs)


class FakePlanningBackend:
    def __init__(self) -> None:
        self.create_task_payloads: list[dict[str, object]] = []
        self.create_event_payloads: list[dict[str, object]] = []
        self.create_reminder_payloads: list[dict[str, object]] = []
        self.tasks = [
            {
                "task_id": "task_today",
                "title": "Pay rent",
                "completed": False,
                "priority": "high",
                "due_at": "2026-04-09T18:00:00+08:00",
                "updated_at": "2026-04-09T08:00:00+08:00",
            },
            {
                "task_id": "task_done",
                "title": "Archive mail",
                "completed": True,
                "priority": "low",
                "due_at": "2026-04-09T12:00:00+08:00",
                "updated_at": "2026-04-09T07:00:00+08:00",
            },
            {
                "task_id": "task_other_day",
                "title": "Buy tea",
                "completed": False,
                "priority": "medium",
                "due_at": "2026-04-10T09:00:00+08:00",
                "updated_at": "2026-04-08T23:00:00+08:00",
            },
        ]
        self.events = [
            {
                "event_id": "event_existing",
                "title": "Standup",
                "start_at": "2026-04-09T09:00:00+08:00",
                "end_at": "2026-04-09T10:00:00+08:00",
                "updated_at": "2026-04-09T08:30:00+08:00",
            },
            {
                "event_id": "event_other_day",
                "title": "Dinner",
                "start_at": "2026-04-10T19:00:00+08:00",
                "end_at": "2026-04-10T20:00:00+08:00",
                "updated_at": "2026-04-08T20:00:00+08:00",
            },
        ]
        self.reminders = [
            {
                "reminder_id": "rem_today",
                "title": "Stretch",
                "time": "2026-04-09T14:00:00+08:00",
                "repeat": "once",
                "enabled": True,
                "next_trigger_at": "2026-04-09T14:00:00+08:00",
                "updated_at": "2026-04-09T08:05:00+08:00",
            },
            {
                "reminder_id": "rem_other_day",
                "title": "Call mom",
                "time": "2026-04-10T10:00:00+08:00",
                "repeat": "once",
                "enabled": True,
                "next_trigger_at": "2026-04-10T10:00:00+08:00",
                "updated_at": "2026-04-08T08:05:00+08:00",
            },
        ]

    async def list_tasks(
        self,
        *,
        completed: bool | None = None,
        limit: int | None = None,
    ) -> dict[str, object]:
        items = list(self.tasks)
        if completed is not None:
            items = [item for item in items if bool(item.get("completed")) is completed]
        if limit is not None:
            items = items[:limit]
        return {"items": items}

    async def create_task(self, payload: dict[str, object]) -> dict[str, object]:
        self.create_task_payloads.append(deepcopy(payload))
        task = {
            "task_id": "task_created",
            "title": payload["title"],
            "description": payload.get("description"),
            "priority": payload.get("priority", "medium"),
            "completed": False,
            "due_at": payload.get("due_at"),
            "bundle_id": payload.get("bundle_id"),
            "created_via": payload.get("created_via"),
            "source_channel": payload.get("source_channel"),
            "source_message_id": payload.get("source_message_id"),
            "source_session_id": payload.get("source_session_id"),
            "interaction_surface": payload.get("interaction_surface"),
            "capture_source": payload.get("capture_source"),
            "voice_path": payload.get("voice_path"),
            "planning_surface": payload.get("planning_surface"),
            "owner_kind": payload.get("owner_kind"),
            "delivery_mode": payload.get("delivery_mode"),
            "linked_task_id": payload.get("linked_task_id"),
            "linked_event_id": payload.get("linked_event_id"),
            "linked_reminder_id": payload.get("linked_reminder_id"),
            "updated_at": "2026-04-09T08:10:00+08:00",
        }
        self.tasks.append(task)
        return task

    async def update_task(self, task_id: str, payload: dict[str, object]) -> dict[str, object]:
        for task in self.tasks:
            if task["task_id"] == task_id:
                task.update(payload)
                task["updated_at"] = "2026-04-09T08:11:00+08:00"
                return task
        raise KeyError(task_id)

    async def update_event(self, event_id: str, payload: dict[str, object]) -> dict[str, object]:
        for event in self.events:
            if event["event_id"] == event_id:
                event.update(payload)
                event["updated_at"] = "2026-04-09T08:11:30+08:00"
                return event
        raise KeyError(event_id)

    async def delete_event(self, event_id: str) -> dict[str, object]:
        for index, event in enumerate(self.events):
            if event["event_id"] == event_id:
                return self.events.pop(index)
        raise KeyError(event_id)

    async def list_events(self, *, limit: int | None = None) -> dict[str, object]:
        items = list(self.events)
        if limit is not None:
            items = items[:limit]
        return {"items": items}

    async def create_event(self, payload: dict[str, object]) -> dict[str, object]:
        self.create_event_payloads.append(deepcopy(payload))
        event = {
            "event_id": "event_created",
            "title": payload["title"],
            "start_at": payload["start_at"],
            "end_at": payload["end_at"],
            "description": payload.get("description"),
            "location": payload.get("location"),
            "bundle_id": payload.get("bundle_id"),
            "created_via": payload.get("created_via"),
            "source_channel": payload.get("source_channel"),
            "source_message_id": payload.get("source_message_id"),
            "source_session_id": payload.get("source_session_id"),
            "interaction_surface": payload.get("interaction_surface"),
            "capture_source": payload.get("capture_source"),
            "voice_path": payload.get("voice_path"),
            "planning_surface": payload.get("planning_surface"),
            "owner_kind": payload.get("owner_kind"),
            "delivery_mode": payload.get("delivery_mode"),
            "linked_task_id": payload.get("linked_task_id"),
            "linked_event_id": payload.get("linked_event_id"),
            "linked_reminder_id": payload.get("linked_reminder_id"),
            "updated_at": "2026-04-09T08:12:00+08:00",
        }
        self.events.append(event)
        return event

    async def create_reminder(self, payload: dict[str, object]) -> dict[str, object]:
        self.create_reminder_payloads.append(deepcopy(payload))
        reminder = {
            "reminder_id": "rem_created",
            "title": payload["title"],
            "time": payload["time"],
            "message": payload.get("message"),
            "repeat": payload.get("repeat", "daily"),
            "enabled": payload.get("enabled", True),
            "next_trigger_at": payload["time"],
            "bundle_id": payload.get("bundle_id"),
            "created_via": payload.get("created_via"),
            "source_channel": payload.get("source_channel"),
            "source_message_id": payload.get("source_message_id"),
            "source_session_id": payload.get("source_session_id"),
            "interaction_surface": payload.get("interaction_surface"),
            "capture_source": payload.get("capture_source"),
            "voice_path": payload.get("voice_path"),
            "planning_surface": payload.get("planning_surface"),
            "owner_kind": payload.get("owner_kind"),
            "delivery_mode": payload.get("delivery_mode"),
            "linked_task_id": payload.get("linked_task_id"),
            "linked_event_id": payload.get("linked_event_id"),
            "linked_reminder_id": payload.get("linked_reminder_id"),
            "scheduled_action_kind": payload.get("scheduled_action_kind"),
            "scheduled_action_target": payload.get("scheduled_action_target"),
            "updated_at": "2026-04-09T08:13:00+08:00",
        }
        self.reminders.append(reminder)
        return reminder

    async def update_reminder(self, reminder_id: str, payload: dict[str, object]) -> dict[str, object]:
        for reminder in self.reminders:
            if reminder["reminder_id"] == reminder_id:
                reminder.update(payload)
                reminder["updated_at"] = "2026-04-09T08:14:00+08:00"
                return reminder
        raise KeyError(reminder_id)

    async def delete_reminder(self, reminder_id: str) -> dict[str, object]:
        for index, reminder in enumerate(self.reminders):
            if reminder["reminder_id"] == reminder_id:
                return self.reminders.pop(index)
        raise KeyError(reminder_id)

    async def snooze_reminder(
        self,
        reminder_id: str,
        *,
        snoozed_until: str | None = None,
        delay_minutes: int = 10,
    ) -> dict[str, object]:
        del delay_minutes
        for reminder in self.reminders:
            if reminder["reminder_id"] == reminder_id:
                reminder["enabled"] = True
                reminder["status"] = "snoozed"
                reminder["snoozed_until"] = snoozed_until
                reminder["next_trigger_at"] = snoozed_until
                reminder["updated_at"] = "2026-04-09T08:14:30+08:00"
                return reminder
        raise KeyError(reminder_id)

    async def complete_reminder(self, reminder_id: str) -> dict[str, object]:
        for reminder in self.reminders:
            if reminder["reminder_id"] == reminder_id:
                reminder["enabled"] = False
                reminder["status"] = "completed"
                reminder["completed_at"] = "2026-04-09T08:15:00+08:00"
                reminder["next_trigger_at"] = None
                reminder["updated_at"] = "2026-04-09T08:15:00+08:00"
                return reminder
        raise KeyError(reminder_id)

    async def list_reminders(self, *, limit: int | None = None) -> dict[str, object]:
        items = list(self.reminders)
        if limit is not None:
            items = items[:limit]
        return {"items": items}


class FakeComputerControlBackend:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []
        self.policy = self.FakePolicy()

    class FakePolicy:
        @staticmethod
        def infer_allowed_app(text: object) -> str | None:
            normalized = str(text or "").casefold()
            if "whatsapp" in normalized or "whats app" in normalized:
                return "WhatsApp"
            if "safari" in normalized:
                return "Safari"
            return None

        @staticmethod
        def resolve_allowed_app(value: object) -> str | None:
            normalized = str(value or "").strip().casefold()
            if normalized in {"whatsapp", "whats app"}:
                return "WhatsApp"
            if normalized == "safari":
                return "Safari"
            return None

    async def request_action(self, payload: dict[str, object]) -> dict[str, object]:
        self.calls.append(dict(payload))
        action = str(payload.get("action") or "")
        if action == "wechat_send_prepared_message":
            return {
                "action_id": "cc_action_confirm",
                "action": action,
                "status": "awaiting_confirmation",
                "confirmation_needed": True,
                "risk_level": "high",
                "metadata": deepcopy(payload.get("metadata") or {}),
                "message": "Waiting for user confirmation.",
                "result": {
                    "target": payload.get("target"),
                },
            }

        return {
            "action_id": "cc_action_done",
            "action": action,
            "status": "completed",
            "confirmation_needed": False,
            "risk_level": "low",
            "metadata": deepcopy(payload.get("metadata") or {}),
            "message": "Action completed.",
            "result": {
                "target": payload.get("target"),
            },
        }


def _load_bootstrap_module():
    sys.modules.pop("bootstrap", None)
    fake_app_runtime = types.ModuleType("services.app_runtime")

    class FakeAppRuntimeService:
        pass

    fake_app_runtime.AppRuntimeService = FakeAppRuntimeService

    with patch.dict(sys.modules, {"services.app_runtime": fake_app_runtime}):
        return importlib.import_module("bootstrap")


class AgentLoopConcurrencyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmpdir.name)
        self.agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
        )

    async def asyncTearDown(self) -> None:
        self._tmpdir.cleanup()

    async def test_same_session_serializes_but_other_session_can_run(self) -> None:
        marks: list[tuple[str, str, str, float]] = []

        async def fake_process(self, msg, session_key=None, on_progress=None):
            marks.append(("start", session_key, msg.content, time.monotonic()))
            await asyncio.sleep(0.2)
            marks.append(("end", session_key, msg.content, time.monotonic()))
            return None

        self.agent._process_message = MethodType(fake_process, self.agent)

        msg_a1 = InboundMessage(channel="cli", sender_id="u", chat_id="same", content="a1")
        msg_a2 = InboundMessage(channel="cli", sender_id="u", chat_id="same", content="a2")
        msg_b1 = InboundMessage(channel="cli", sender_id="u", chat_id="other", content="b1")

        await asyncio.gather(
            asyncio.create_task(self.agent._dispatch(msg_a1, session_key=self.agent._resolve_session_key(msg_a1))),
            asyncio.create_task(self.agent._dispatch(msg_a2, session_key=self.agent._resolve_session_key(msg_a2))),
            asyncio.create_task(self.agent._dispatch(msg_b1, session_key=self.agent._resolve_session_key(msg_b1))),
        )

        starts = {(key, content): ts for kind, key, content, ts in marks if kind == "start"}
        ends = {(key, content): ts for kind, key, content, ts in marks if kind == "end"}

        self.assertGreaterEqual(starts[("cli:same", "a2")], ends[("cli:same", "a1")] - 0.01)
        self.assertLess(starts[("cli:other", "b1")], ends[("cli:same", "a1")])

    async def test_handle_stop_cancels_active_session_tasks(self) -> None:
        cancelled = asyncio.Event()

        async def slow_task():
            try:
                await asyncio.sleep(60)
            except asyncio.CancelledError:
                cancelled.set()
                raise

        task = asyncio.create_task(slow_task())
        await asyncio.sleep(0)
        self.agent._active_tasks["cli:test"] = {task}

        msg = InboundMessage(channel="cli", sender_id="u", chat_id="test", content="/stop")
        await self.agent._handle_stop(msg, session_key="cli:test")

        self.assertTrue(cancelled.is_set())
        out = await asyncio.wait_for(self.agent.bus.consume_outbound(), timeout=1.0)
        self.assertIn("stopped", out.content.lower())


class AgentLoopPlanningToolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmpdir.name)
        self.backend = FakePlanningBackend()
        self.agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
            planning_backend=self.backend,
        )

    async def asyncTearDown(self) -> None:
        self._tmpdir.cleanup()

    async def test_planning_tool_is_optional(self) -> None:
        agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
        )

        self.assertFalse(agent.tools.has("planning"))
        self.assertTrue(self.agent.tools.has("planning"))

    async def test_planning_tool_create_task_returns_structured_metadata(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_task",
                "title": "Renew passport",
                "priority": "high",
                "due_at": "2026-04-09T17:00:00+08:00",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "create_task")
        self.assertFalse(payload["confirmation_needed"])
        self.assertEqual(payload["resource_ids"]["task_id"], "task_created")
        self.assertEqual(
            payload["normalized_times"]["due_at"],
            "2026-04-09T17:00:00+08:00",
        )
        self.assertEqual(payload["result"]["task"]["created_via"], "agent")
        self.assertEqual(payload["result"]["task"]["source_channel"], "agent")
        self.assertTrue(payload["result"]["task"]["bundle_id"].startswith("planning_"))

    async def test_planning_tool_create_event_reports_conflicts(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_event",
                "title": "Design review",
                "start_at": "2026-04-09T09:30:00+08:00",
                "end_at": "2026-04-09T10:30:00+08:00",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "create_event")
        self.assertTrue(payload["confirmation_needed"])
        self.assertEqual(payload["resource_ids"]["event_id"], "event_created")
        self.assertEqual(payload["conflicts"][0]["event_id"], "event_existing")

    async def test_planning_tool_create_event_passes_extended_metadata(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_event",
                "title": "Airport transfer",
                "start_at": "2026-04-10T07:30:00+08:00",
                "end_at": "2026-04-10T08:30:00+08:00",
                "source_channel": "app",
                "source_message_id": "msg_trip",
                "source_session_id": "app:main",
                "planning_surface": "agenda",
                "owner_kind": "user",
                "delivery_mode": "none",
            },
        )

        payload = json.loads(result)
        event = payload["result"]["event"]
        self.assertEqual(payload["request_metadata"]["source_message_id"], "msg_trip")
        self.assertEqual(payload["request_metadata"]["planning_surface"], "agenda")
        self.assertEqual(payload["request_metadata"]["owner_kind"], "user")
        self.assertEqual(payload["request_metadata"]["delivery_mode"], "none")
        self.assertEqual(event["source_session_id"], "app:main")
        self.assertEqual(event["planning_surface"], "agenda")
        self.assertEqual(event["owner_kind"], "user")
        self.assertEqual(event["delivery_mode"], "none")
        self.assertEqual(
            self.backend.create_event_payloads[-1]["source_message_id"],
            "msg_trip",
        )

    async def test_planning_tool_create_reminder_returns_normalized_time(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "Water plants",
                "time": "2026-04-09T20:15:00+08:00",
                "repeat": "once",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "create_reminder")
        self.assertEqual(payload["resource_ids"]["reminder_id"], "rem_created")
        self.assertEqual(
            payload["normalized_times"]["time"],
            "2026-04-09T20:15:00+08:00",
        )
        self.assertEqual(payload["result"]["reminder"]["bundle_id"], payload["bundle_id"])
        self.assertEqual(payload["result"]["reminder"]["created_via"], "agent")

    async def test_planning_tool_create_reminder_passes_scheduled_open_app_metadata(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "打开微信",
                "time": "2026-04-09T20:15:00+08:00",
                "repeat": "once",
                "scheduled_action_kind": "open_app",
                "scheduled_action_target": "WeChat",
            },
        )

        payload = json.loads(result)
        reminder = payload["result"]["reminder"]
        self.assertEqual(reminder["scheduled_action_kind"], "open_app")
        self.assertEqual(reminder["scheduled_action_target"], "WeChat")
        self.assertEqual(
            self.backend.create_reminder_payloads[-1]["scheduled_action_kind"],
            "open_app",
        )
        self.assertEqual(
            self.backend.create_reminder_payloads[-1]["scheduled_action_target"],
            "WeChat",
        )

    async def test_planning_tool_create_reminder_defaults_once_for_absolute_datetime(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "Dentist reminder",
                "time": "2026-04-16T17:00:00+08:00",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["result"]["reminder"]["repeat"], "once")
        self.assertEqual(self.backend.create_reminder_payloads[-1]["repeat"], "once")

    async def test_planning_tool_reminder_style_task_and_hidden_reminder_pass_metadata(self) -> None:
        planning_tool = self.agent.tools.get("planning")
        assert planning_tool is not None
        planning_tool.start_turn()

        task_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_task",
                "title": "Remind me to stretch",
                "source_channel": "app",
                "source_message_id": "msg_reminder",
                "source_session_id": "app:main",
                "planning_surface": "tasks",
                "owner_kind": "assistant",
                "delivery_mode": "none",
            },
        ))
        reminder_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "Stretch prompt",
                "time": "2026-04-09T14:00:00+08:00",
                "repeat": "once",
                "source_channel": "app",
                "source_message_id": "msg_reminder",
                "source_session_id": "app:main",
                "planning_surface": "hidden",
                "owner_kind": "assistant",
                "delivery_mode": "device_voice_and_notification",
            },
        ))

        task = task_payload["result"]["task"]
        reminder = reminder_payload["result"]["reminder"]
        self.assertEqual(task["bundle_id"], reminder["bundle_id"])
        self.assertEqual(task_payload["request_metadata"]["owner_kind"], "assistant")
        self.assertEqual(task["planning_surface"], "tasks")
        self.assertEqual(task["delivery_mode"], "none")
        self.assertEqual(reminder_payload["request_metadata"]["planning_surface"], "hidden")
        self.assertEqual(
            reminder_payload["request_metadata"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(reminder["owner_kind"], "assistant")
        self.assertEqual(reminder["planning_surface"], "hidden")
        self.assertEqual(
            reminder["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(reminder["linked_task_id"], task["task_id"])
        self.assertEqual(self.backend.tasks[-1]["linked_reminder_id"], reminder["reminder_id"])
        self.assertEqual(
            self.backend.create_reminder_payloads[-1]["source_session_id"],
            "app:main",
        )

    async def test_planning_tool_hidden_assistant_reminder_defaults_delivery_and_syncs_linked_task(self) -> None:
        planning_tool = self.agent.tools.get("planning")
        assert planning_tool is not None
        planning_tool.start_turn()

        await self.agent.tools.execute(
            "planning",
            {
                "action": "create_task",
                "title": "Prepare weekly review",
                "due_at": "2026-04-16T17:00:00+08:00",
                "source_channel": "app",
                "source_message_id": "msg_followup",
                "source_session_id": "app:main",
                "planning_surface": "tasks",
                "owner_kind": "assistant",
            },
        )
        reminder_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "Weekly review reminder",
                "time": "2026-04-16T17:00:00+08:00",
                "source_channel": "app",
                "source_message_id": "msg_followup",
                "source_session_id": "app:main",
                "planning_surface": "hidden",
                "owner_kind": "assistant",
            },
        ))

        turn_results = planning_tool.consume_turn_results()
        task_result = next(item for item in turn_results if item["action"] == "create_task")
        reminder_result = next(item for item in turn_results if item["action"] == "create_reminder")

        self.assertEqual(
            reminder_payload["request_metadata"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            reminder_payload["result"]["reminder"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            reminder_result["request_metadata"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            reminder_result["result"]["reminder"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            task_result["request_metadata"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            task_result["result"]["task"]["delivery_mode"],
            "device_voice_and_notification",
        )
        self.assertEqual(
            self.backend.tasks[-1]["delivery_mode"],
            "device_voice_and_notification",
        )

    async def test_planning_tool_complete_task_returns_updated_task_id(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "complete_task",
                "task_id": "task_today",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "complete_task")
        self.assertEqual(payload["resource_ids"]["task_id"], "task_today")
        self.assertFalse(payload["confirmation_needed"])
        self.assertTrue(payload["result"]["task"]["completed"])

    async def test_planning_tool_delete_event_returns_deleted_event_id(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "delete_event",
                "event_id": "event_existing",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "delete_event")
        self.assertEqual(payload["resource_ids"]["event_id"], "event_existing")
        self.assertEqual(payload["result"]["event"]["event_id"], "event_existing")
        self.assertFalse(
            any(
                event["event_id"] == "event_existing"
                for event in self.backend.events
            )
        )

    async def test_planning_tool_delete_reminder_returns_deleted_reminder_id(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "delete_reminder",
                "reminder_id": "rem_today",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "delete_reminder")
        self.assertEqual(payload["resource_ids"]["reminder_id"], "rem_today")
        self.assertEqual(
            payload["result"]["reminder"]["reminder_id"],
            "rem_today",
        )
        self.assertFalse(
            any(
                reminder["reminder_id"] == "rem_today"
                for reminder in self.backend.reminders
            )
        )

    async def test_planning_tool_snooze_reminder_returns_updated_time(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "snooze_reminder",
                "reminder_id": "rem_today",
                "until": "2026-04-09T15:30:00+08:00",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "snooze_reminder")
        self.assertEqual(payload["resource_ids"]["reminder_id"], "rem_today")
        self.assertEqual(
            payload["normalized_times"]["snoozed_until"],
            "2026-04-09T15:30:00+08:00",
        )
        self.assertEqual(payload["result"]["reminder"]["status"], "snoozed")

    async def test_planning_tool_persists_bundle_metadata_and_links_across_creates(self) -> None:
        planning_tool = self.agent.tools.get("planning")
        assert planning_tool is not None
        planning_tool.start_turn()

        task_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_task",
                "title": "Renew passport",
            },
        ))
        event_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_event",
                "title": "Passport office visit",
                "start_at": "2026-04-09T09:30:00+08:00",
                "end_at": "2026-04-09T10:30:00+08:00",
            },
        ))
        reminder_payload = json.loads(await self.agent.tools.execute(
            "planning",
            {
                "action": "create_reminder",
                "title": "Bring documents",
                "time": "2026-04-09T09:00:00+08:00",
                "repeat": "once",
            },
        ))

        task = task_payload["result"]["task"]
        event = event_payload["result"]["event"]
        reminder = reminder_payload["result"]["reminder"]

        self.assertEqual(task["bundle_id"], event["bundle_id"])
        self.assertEqual(event["bundle_id"], reminder["bundle_id"])
        self.assertEqual(task["created_via"], "agent")
        self.assertEqual(event["linked_task_id"], task["task_id"])
        self.assertEqual(reminder["linked_task_id"], task["task_id"])
        self.assertEqual(reminder["linked_event_id"], event["event_id"])
        self.assertEqual(
            self.backend.tasks[-1]["linked_event_id"],
            event["event_id"],
        )
        self.assertEqual(
            self.backend.events[-1]["linked_reminder_id"],
            reminder["reminder_id"],
        )

    async def test_planning_tool_list_today_returns_filtered_resources(self) -> None:
        result = await self.agent.tools.execute(
            "planning",
            {
                "action": "list_today",
                "date": "2026-04-09",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "list_today")
        self.assertEqual(payload["resource_ids"]["task_ids"], ["task_today"])
        self.assertEqual(payload["resource_ids"]["event_ids"], ["event_existing"])
        self.assertEqual(payload["resource_ids"]["reminder_ids"], ["rem_today"])

    async def test_planning_tool_list_today_supports_tomorrow_keyword(self) -> None:
        class FrozenDateTime(datetime):
            @classmethod
            def now(cls, tz=None):
                current = cls(2026, 4, 9, 8, 0, 0, tzinfo=timezone(timedelta(hours=8)))
                return current if tz is None else current.astimezone(tz)

        with patch("nanobot.agent.tools.planning.datetime", FrozenDateTime):
            result = await self.agent.tools.execute(
                "planning",
                {
                    "action": "list_today",
                    "date": "tomorrow",
                },
            )

        payload = json.loads(result)
        self.assertEqual(payload["normalized_times"]["date"], "2026-04-10")
        self.assertEqual(payload["resource_ids"]["task_ids"], ["task_other_day"])
        self.assertEqual(payload["resource_ids"]["event_ids"], ["event_other_day"])
        self.assertEqual(payload["resource_ids"]["reminder_ids"], ["rem_other_day"])

    async def test_planning_tool_result_is_preserved_in_response_metadata_and_session(self) -> None:
        provider = SequencedProvider(
            [
                LLMResponse(
                    content=None,
                    tool_calls=[
                        ToolCallRequest(
                            id="call_1",
                            name="planning",
                            arguments={
                                "action": "create_task",
                                "title": "Renew passport",
                                "due_at": "2026-04-09T17:00:00+08:00",
                                "planning_surface": "tasks",
                                "owner_kind": "assistant",
                                "delivery_mode": "device_voice_and_notification",
                            },
                        )
                    ],
                ),
                LLMResponse(content="Created the task."),
            ]
        )
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            planning_backend=FakePlanningBackend(),
        )
        msg = InboundMessage(
            channel="app",
            sender_id="u",
            chat_id="main",
            content="Remember to renew my passport today",
            metadata={
                "task_id": "runtime_task",
                "source": "device",
                "interaction_surface": "device_shake",
                "capture_source": "imu_sensor",
                "voice_path": "desktop_mic",
                "scene_mode": "companion",
                "persona_profile": {
                    "id": "planner_companion",
                    "voice_style": "warm_concise",
                },
                "interaction_kind": "shake_event",
                "interaction_mode": "physical",
                "approval_source": "device_tap",
                "assistant_message_id": "msg_assistant",
            },
        )

        response = await agent._process_message(msg)

        self.assertIsNotNone(response)
        planning_results = response.metadata["tool_results"]["planning"]
        self.assertEqual(planning_results[0]["action"], "create_task")
        self.assertEqual(planning_results[0]["resource_ids"]["task_id"], "task_created")
        self.assertEqual(planning_results[0]["request_metadata"]["scene_mode"], "companion")
        self.assertEqual(planning_results[0]["request_metadata"]["persona_profile_id"], "planner_companion")
        self.assertEqual(planning_results[0]["request_metadata"]["persona_voice_style"], "warm_concise")
        self.assertEqual(planning_results[0]["request_metadata"]["interaction_kind"], "shake_event")
        self.assertEqual(planning_results[0]["request_metadata"]["interaction_mode"], "physical")
        self.assertEqual(planning_results[0]["request_metadata"]["approval_source"], "device_tap")
        self.assertEqual(planning_results[0]["request_metadata"]["planning_surface"], "tasks")
        self.assertEqual(planning_results[0]["request_metadata"]["owner_kind"], "assistant")
        self.assertEqual(planning_results[0]["request_metadata"]["delivery_mode"], "device_voice_and_notification")
        self.assertEqual(planning_results[0]["result"]["task"]["interaction_surface"], "device_shake")
        self.assertEqual(planning_results[0]["result"]["task"]["capture_source"], "imu_sensor")
        self.assertEqual(planning_results[0]["result"]["task"]["voice_path"], "desktop_mic")
        self.assertEqual(planning_results[0]["result"]["task"]["planning_surface"], "tasks")
        self.assertEqual(planning_results[0]["result"]["task"]["owner_kind"], "assistant")
        self.assertEqual(planning_results[0]["result"]["task"]["delivery_mode"], "device_voice_and_notification")

        session = agent.sessions.get_or_create("app:main")
        persisted = [
            entry for entry in session.messages
            if entry.get("role") == "assistant" and entry.get("content") == "Created the task."
        ]
        self.assertEqual(len(persisted), 1)
        self.assertEqual(
            persisted[0]["tool_results"]["planning"][0]["resource_ids"]["task_id"],
            "task_created",
        )

    async def test_turn_persists_source_metadata_for_user_and_assistant_messages(self) -> None:
        provider = SequencedProvider([LLMResponse(content="Sure, continuing this thread.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            planning_backend=FakePlanningBackend(),
        )
        msg = InboundMessage(
            channel="device",
            sender_id="esp32",
            chat_id="esp32",
            content="继续刚才那个提醒",
            metadata={
                "task_id": "runtime_task",
                "message_id": "msg_user",
                "assistant_message_id": "msg_assistant",
                "client_message_id": "client_user",
                "source": "voice",
                "source_channel": "device",
                "interaction_surface": "device_press",
                "capture_source": "device_mic",
                "voice_path": "device_mic",
                "reply_language": "Chinese",
                "emotion": "calm",
                "app_session_id": "app:main",
                "scene_mode": "focus",
                "persona_profile": {
                    "id": "coach",
                    "voice_style": "calm_direct",
                },
                "interaction_kind": "press_hold",
                "interaction_mode": "hands_free",
                "approval_source": "device_double_tap",
            },
        )

        response = await agent._process_message(msg, session_key="app:main")

        self.assertIsNotNone(response)
        session = agent.sessions.get_or_create("app:main")
        user_entry = next(
            entry for entry in session.messages if entry.get("role") == "user"
        )
        assistant_entry = next(
            entry
            for entry in session.messages
            if entry.get("role") == "assistant"
            and entry.get("content") == "Sure, continuing this thread."
        )
        for entry in (user_entry, assistant_entry):
            self.assertEqual(entry["task_id"], "runtime_task")
            self.assertEqual(entry["source_channel"], "device")
            self.assertEqual(entry["interaction_surface"], "device_press")
            self.assertEqual(entry["capture_source"], "device_mic")
            self.assertEqual(entry["voice_path"], "device_mic")
            self.assertEqual(entry["reply_language"], "Chinese")
            self.assertEqual(entry["emotion"], "calm")
            self.assertEqual(entry["app_session_id"], "app:main")
            self.assertEqual(entry["scene_mode"], "focus")
            self.assertEqual(entry["persona_profile_id"], "coach")
            self.assertEqual(entry["persona_voice_style"], "calm_direct")
            self.assertEqual(entry["interaction_kind"], "press_hold")
            self.assertEqual(entry["interaction_mode"], "hands_free")
            self.assertEqual(entry["approval_source"], "device_double_tap")
        self.assertEqual(user_entry["message_id"], "msg_user")
        self.assertEqual(user_entry["client_message_id"], "client_user")
        self.assertEqual(assistant_entry["message_id"], "msg_assistant")
        self.assertEqual(response.metadata["scene_mode"], "focus")
        self.assertEqual(response.metadata["persona_profile_id"], "coach")
        self.assertEqual(response.metadata["persona_voice_style"], "calm_direct")

    async def test_agent_loop_injects_trusted_runtime_metadata_into_system_prompt(self) -> None:
        provider = CapturingProvider([LLMResponse(content="Ready.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
        )
        msg = InboundMessage(
            channel="device",
            sender_id="esp32",
            chat_id="living-room",
            content="现在状态怎么样",
            metadata={
                "scene_mode": "meeting",
                "interaction_kind": "wake_word",
                "interaction_mode": "ambient",
                "persona_profile": {
                    "id": "briefing",
                    "tone_style": "warm",
                    "reply_length": "expanded",
                    "proactivity": "high",
                    "voice_style": "short_formal",
                },
            },
        )

        response = await agent._process_message(msg)

        self.assertIsNotNone(response)
        system_prompt = provider.calls[0]["messages"][0]["content"]
        self.assertIn("Trusted Runtime Metadata", system_prompt)
        self.assertIn("Scene Mode: meeting", system_prompt)
        self.assertIn("Interaction Kind: wake_word", system_prompt)
        self.assertIn("Interaction Mode: ambient", system_prompt)
        self.assertIn("Persona Profile: briefing", system_prompt)
        self.assertIn("Persona Tone Style: warm", system_prompt)
        self.assertIn("Persona Reply Length: expanded", system_prompt)
        self.assertIn("Persona Proactivity: high", system_prompt)
        self.assertIn("Persona Voice Style: short_formal", system_prompt)
        self.assertIn("Everyday Conversation Style", system_prompt)
        self.assertIn("Natural Chinese examples", system_prompt)


class AgentLoopComputerControlToolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmpdir.name)
        self.backend = FakeComputerControlBackend()

    async def asyncTearDown(self) -> None:
        self._tmpdir.cleanup()

    async def test_computer_control_tool_is_optional(self) -> None:
        agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
        )
        controlled_agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )

        self.assertFalse(agent.tools.has("computer_control"))
        self.assertTrue(controlled_agent.tools.has("computer_control"))

    async def test_computer_control_tool_calls_structured_backend(self) -> None:
        agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        tool = agent.tools.get("computer_control")
        assert tool is not None
        tool.set_context(
            "app",
            "main",
            "msg_user",
            "runtime_task",
            metadata={
                "source": "voice",
                "scene_mode": "focus",
                "persona_profile_id": "operator",
                "persona_voice_style": "calm_direct",
                "interaction_kind": "button_press",
                "interaction_mode": "hands_free",
                "approval_source": "device_tap",
                "interaction_surface": "device_button",
                "capture_source": "desktop_mic",
                "voice_path": "desktop_mic",
            },
        )
        tool.start_turn()

        result = await agent.tools.execute(
            "computer_control",
            {
                "action": "open_app",
                "target": {"app": "Safari"},
                "reason": "Open the browser for the user",
            },
        )

        payload = json.loads(result)
        self.assertEqual(payload["action"], "open_app")
        self.assertEqual(payload["status"], "completed")
        self.assertEqual(self.backend.calls[0]["target"], {"app": "Safari"})
        self.assertEqual(self.backend.calls[0]["reason"], "Open the browser for the user")
        self.assertEqual(self.backend.calls[0]["source_channel"], "app")
        self.assertEqual(self.backend.calls[0]["source_session_id"], "app:main")
        self.assertEqual(self.backend.calls[0]["source_message_id"], "msg_user")
        self.assertEqual(self.backend.calls[0]["task_id"], "runtime_task")
        self.assertEqual(self.backend.calls[0]["metadata"]["scene_mode"], "focus")
        self.assertEqual(self.backend.calls[0]["metadata"]["persona_profile_id"], "operator")
        self.assertEqual(self.backend.calls[0]["metadata"]["persona_voice_style"], "calm_direct")
        self.assertEqual(self.backend.calls[0]["metadata"]["interaction_kind"], "button_press")
        self.assertEqual(self.backend.calls[0]["metadata"]["interaction_mode"], "hands_free")
        self.assertEqual(self.backend.calls[0]["metadata"]["approval_source"], "device_tap")
        self.assertEqual(self.backend.calls[0]["metadata"]["interaction_surface"], "device_button")
        self.assertEqual(self.backend.calls[0]["metadata"]["capture_source"], "desktop_mic")
        self.assertEqual(self.backend.calls[0]["metadata"]["voice_path"], "desktop_mic")

        turn_results = tool.consume_turn_results()
        self.assertEqual(turn_results[0]["action_id"], "cc_action_done")
        self.assertEqual(turn_results[0]["metadata"]["scene_mode"], "focus")

    async def test_computer_control_tool_result_is_preserved_in_response_metadata_and_session(self) -> None:
        provider = SequencedProvider(
            [
                LLMResponse(
                    content=None,
                    tool_calls=[
                        ToolCallRequest(
                            id="call_1",
                            name="computer_control",
                            arguments={
                                "action": "wechat_send_prepared_message",
                                "target": {"contact": "Alice", "draft": "hi"},
                                "reason": "Send the prepared outbound message after confirmation",
                            },
                        )
                    ],
                ),
                LLMResponse(content="已为你准备好，等你确认再发送。"),
            ]
        )
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="app",
            sender_id="u",
            chat_id="main",
            content="给 Alice 发一条 hi",
            metadata={
                "task_id": "runtime_task",
                "message_id": "msg_user",
                "assistant_message_id": "msg_assistant",
                "scene_mode": "focus",
                "persona_profile": {
                    "id": "assistant_operator",
                    "voice_style": "precise",
                },
                "interaction_kind": "voice_command",
                "interaction_mode": "direct",
                "approval_source": "app_confirm_button",
            },
        )

        response = await agent._process_message(msg)

        self.assertIsNotNone(response)
        control_results = response.metadata["tool_results"]["computer_control"]
        self.assertEqual(control_results[0]["action_id"], "cc_action_confirm")
        self.assertTrue(control_results[0]["confirmation_needed"])
        self.assertEqual(self.backend.calls[0]["source_channel"], "app")
        self.assertEqual(self.backend.calls[0]["source_session_id"], "app:main")
        self.assertEqual(self.backend.calls[0]["source_message_id"], "msg_user")
        self.assertEqual(control_results[0]["metadata"]["scene_mode"], "focus")
        self.assertEqual(control_results[0]["metadata"]["persona_profile_id"], "assistant_operator")
        self.assertEqual(control_results[0]["metadata"]["persona_voice_style"], "precise")
        self.assertEqual(control_results[0]["metadata"]["interaction_kind"], "voice_command")
        self.assertEqual(control_results[0]["metadata"]["interaction_mode"], "direct")
        self.assertEqual(control_results[0]["metadata"]["approval_source"], "app_confirm_button")

        session = agent.sessions.get_or_create("app:main")
        persisted = [
            entry for entry in session.messages
            if entry.get("role") == "assistant"
            and entry.get("content") == "已为你准备好，等你确认再发送。"
        ]
        self.assertEqual(len(persisted), 1)
        self.assertEqual(
            persisted[0]["tool_results"]["computer_control"][0]["action_id"],
            "cc_action_confirm",
        )

    async def test_direct_open_app_command_bypasses_model_timeout_path(self) -> None:
        provider = CapturingProvider([LLMResponse(content="This should not be called.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="desktop_voice",
            sender_id="desktop_mic",
            chat_id="desktop",
            content="Help me open Whatsapp.",
            metadata={
                "task_id": "runtime_task",
                "message_id": "msg_user",
                "assistant_message_id": "msg_assistant",
                "source": "voice",
                "source_channel": "desktop_voice",
                "interaction_surface": "device_press",
                "capture_source": "desktop_mic",
                "voice_path": "desktop_mic",
                "reply_language": "English",
                "app_session_id": "app:main",
            },
            session_key_override="app:main",
        )

        response = await agent._process_message(msg, session_key="app:main")

        self.assertEqual(provider.calls, [])
        self.assertIsNotNone(response)
        self.assertEqual(response.content, "Opened WhatsApp.")
        self.assertEqual(self.backend.calls[0]["action"], "open_app")
        self.assertEqual(self.backend.calls[0]["target"], {"app": "WhatsApp"})
        self.assertEqual(self.backend.calls[0]["source_session_id"], "app:main")
        self.assertEqual(
            self.backend.calls[0]["metadata"]["direct_intent_source"],
            "agent_pre_llm",
        )
        control_results = response.metadata["tool_results"]["computer_control"]
        self.assertEqual(control_results[0]["action_id"], "cc_action_done")

        session = agent.sessions.get_or_create("app:main")
        assistant_entry = next(
            entry
            for entry in session.messages
            if entry.get("role") == "assistant"
            and entry.get("content") == "Opened WhatsApp."
        )
        self.assertEqual(assistant_entry["message_id"], "msg_assistant")
        self.assertEqual(
            assistant_entry["tool_results"]["computer_control"][0]["action_id"],
            "cc_action_done",
        )

    async def test_direct_google_search_command_bypasses_model_timeout_path(self) -> None:
        provider = CapturingProvider([LLMResponse(content="This should not be called.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="desktop_voice",
            sender_id="desktop_mic",
            chat_id="desktop",
            content="Open Google Com and helpmi search Ctuk.",
            metadata={
                "task_id": "runtime_task",
                "message_id": "msg_user",
                "assistant_message_id": "msg_assistant",
                "source": "voice",
                "source_channel": "desktop_voice",
                "interaction_surface": "device_press",
                "capture_source": "desktop_mic",
                "voice_path": "desktop_mic",
                "reply_language": "English",
                "app_session_id": "app:main",
            },
            session_key_override="app:main",
        )

        response = await agent._process_message(msg, session_key="app:main")

        self.assertEqual(provider.calls, [])
        self.assertIsNotNone(response)
        self.assertEqual(response.content, "Opened Google search for Ctuk.")
        self.assertEqual(self.backend.calls[0]["action"], "open_url")
        self.assertEqual(
            self.backend.calls[0]["target"],
            {"url": "https://www.google.com/search?q=Ctuk"},
        )
        self.assertEqual(self.backend.calls[0]["metadata"]["search_query"], "Ctuk")
        control_results = response.metadata["tool_results"]["computer_control"]
        self.assertEqual(control_results[0]["action"], "open_url")

    async def test_direct_search_command_tolerates_missing_google_target(self) -> None:
        provider = CapturingProvider([LLMResponse(content="This should not be called.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="desktop_voice",
            sender_id="desktop_mic",
            chat_id="desktop",
            content="Help me open and.Search city, City University.",
            metadata={"reply_language": "English"},
            session_key_override="app:main",
        )

        response = await agent._process_message(msg, session_key="app:main")

        self.assertEqual(provider.calls, [])
        self.assertIsNotNone(response)
        self.assertEqual(
            response.content,
            "Opened Google search for city, City University.",
        )
        self.assertEqual(self.backend.calls[0]["action"], "open_url")
        self.assertEqual(
            self.backend.calls[0]["target"],
            {"url": "https://www.google.com/search?q=city%2C+City+University"},
        )

    async def test_direct_google_search_tolerates_gocom_without_search_word(self) -> None:
        provider = CapturingProvider([LLMResponse(content="This should not be called.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="desktop_voice",
            sender_id="desktop_mic",
            chat_id="desktop",
            content="Open Gocom and city University, Hong Kong.",
            metadata={"reply_language": "English"},
            session_key_override="app:main",
        )

        response = await agent._process_message(msg, session_key="app:main")

        self.assertEqual(provider.calls, [])
        self.assertIsNotNone(response)
        self.assertEqual(
            response.content,
            "Opened Google search for city University, Hong Kong.",
        )
        self.assertEqual(self.backend.calls[0]["action"], "open_url")
        self.assertEqual(
            self.backend.calls[0]["target"],
            {"url": "https://www.google.com/search?q=city+University%2C+Hong+Kong"},
        )

    async def test_scheduled_open_app_request_still_uses_model(self) -> None:
        provider = CapturingProvider([LLMResponse(content="I can help schedule that.")])
        agent = AgentLoop(
            bus=MessageBus(),
            provider=provider,
            workspace=self.workspace,
            computer_control_backend=self.backend,
        )
        msg = InboundMessage(
            channel="app",
            sender_id="flutter",
            chat_id="main",
            content="Remind me to open WhatsApp tomorrow.",
            metadata={
                "task_id": "runtime_task",
                "message_id": "msg_user",
                "assistant_message_id": "msg_assistant",
                "reply_language": "English",
            },
        )

        response = await agent._process_message(msg)

        self.assertIsNotNone(response)
        self.assertEqual(response.content, "I can help schedule that.")
        self.assertEqual(len(provider.calls), 1)
        self.assertEqual(self.backend.calls, [])


class BootstrapPlanningInjectionTests(unittest.TestCase):
    def test_create_agent_passes_planning_backend_to_agent_loop(self) -> None:
        bootstrap = _load_bootstrap_module()
        planning_backend = object()
        bus = object()
        provider = object()
        session_manager = object()
        agent = object()
        cfg = {
            "nanobot": {
                "api_key": "test-key",
                "model": "openai/gpt-4o-mini",
                "provider": "openai",
            }
        }

        with patch.object(bootstrap, "MessageBus", return_value=bus), patch.object(
            bootstrap,
            "LiteLLMProvider",
            return_value=provider,
        ), patch.object(
            bootstrap,
            "SessionManager",
            return_value=session_manager,
        ), patch.object(
            bootstrap,
            "AgentLoop",
            return_value=agent,
        ) as agent_loop_cls:
            result_bus, result_agent = bootstrap.create_agent(
                cfg,
                planning_backend=planning_backend,
            )

        self.assertIs(result_bus, bus)
        self.assertIs(result_agent, agent)
        self.assertIs(
            agent_loop_cls.call_args.kwargs["planning_backend"],
            planning_backend,
        )
