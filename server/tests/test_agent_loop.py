from __future__ import annotations

import asyncio
import importlib
import json
import sys
import tempfile
import time
import types
import unittest
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


class FakePlanningBackend:
    def __init__(self) -> None:
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
        task = {
            "task_id": "task_created",
            "title": payload["title"],
            "description": payload.get("description"),
            "priority": payload.get("priority", "medium"),
            "completed": False,
            "due_at": payload.get("due_at"),
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

    async def list_events(self, *, limit: int | None = None) -> dict[str, object]:
        items = list(self.events)
        if limit is not None:
            items = items[:limit]
        return {"items": items}

    async def create_event(self, payload: dict[str, object]) -> dict[str, object]:
        event = {
            "event_id": "event_created",
            "title": payload["title"],
            "start_at": payload["start_at"],
            "end_at": payload["end_at"],
            "description": payload.get("description"),
            "location": payload.get("location"),
            "updated_at": "2026-04-09T08:12:00+08:00",
        }
        self.events.append(event)
        return event

    async def create_reminder(self, payload: dict[str, object]) -> dict[str, object]:
        reminder = {
            "reminder_id": "rem_created",
            "title": payload["title"],
            "time": payload["time"],
            "message": payload.get("message"),
            "repeat": payload.get("repeat", "daily"),
            "enabled": payload.get("enabled", True),
            "next_trigger_at": payload["time"],
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

    async def list_reminders(self, *, limit: int | None = None) -> dict[str, object]:
        items = list(self.reminders)
        if limit is not None:
            items = items[:limit]
        return {"items": items}


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
            payload["normalized_times"]["time"],
            "2026-04-09T15:30:00+08:00",
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
                "assistant_message_id": "msg_assistant",
            },
        )

        response = await agent._process_message(msg)

        self.assertIsNotNone(response)
        planning_results = response.metadata["tool_results"]["planning"]
        self.assertEqual(planning_results[0]["action"], "create_task")
        self.assertEqual(planning_results[0]["resource_ids"]["task_id"], "task_created")

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
