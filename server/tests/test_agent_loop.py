from __future__ import annotations

import asyncio
import sys
import time
import unittest
from pathlib import Path
from types import MethodType


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.agent.loop import AgentLoop
from nanobot.bus.events import InboundMessage
from nanobot.bus.queue import MessageBus


class FakeProvider:
    def get_default_model(self) -> str:
        return "fake-model"


class AgentLoopConcurrencyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.agent = AgentLoop(
            bus=MessageBus(),
            provider=FakeProvider(),
            workspace=Path("server/workspace"),
        )

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
