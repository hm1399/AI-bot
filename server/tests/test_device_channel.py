from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from channels.device_channel import DeviceChannel
from models.device_state import DeviceState
from nanobot.bus.queue import MessageBus


class DeviceChannelTests(unittest.IsolatedAsyncioTestCase):
    async def test_processing_interrupt_publishes_stop(self) -> None:
        async def noop(*args, **kwargs):
            return None

        bus = MessageBus()
        channel = DeviceChannel(bus)
        channel.send_json = noop
        channel._send_display_update = noop
        channel.state = DeviceState.PROCESSING

        await channel.interrupt_current_activity(notice="")

        stop_msg = await asyncio.wait_for(bus.consume_inbound(), timeout=0.2)
        self.assertEqual(stop_msg.content, "/stop")
        self.assertEqual(stop_msg.channel, "device")
        self.assertEqual(channel.state, DeviceState.IDLE)

    async def test_authorization_accepts_matching_bearer_token(self) -> None:
        channel = DeviceChannel(MessageBus(), auth_token="local-secret-123")
        request = SimpleNamespace(
            headers={"Authorization": "Bearer local-secret-123"},
            query={},
            remote="127.0.0.1",
        )
        self.assertTrue(channel._is_authorized(request))

    async def test_authorization_rejects_missing_token(self) -> None:
        channel = DeviceChannel(MessageBus(), auth_token="local-secret-123")
        request = SimpleNamespace(headers={}, query={}, remote="127.0.0.1")
        self.assertFalse(channel._is_authorized(request))

    async def test_execute_app_command_sends_device_command_payload(self) -> None:
        sent: list[dict] = []

        async def capture(msg: dict) -> None:
            sent.append(msg)

        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel.send_json = capture

        result = await channel.execute_app_command(
            "set_volume",
            {"level": 80},
            client_command_id="cmd_local_001",
        )

        self.assertTrue(result["accepted"])
        self.assertEqual(result["command"], "set_volume")
        self.assertEqual(sent[-1]["type"], "device_command")
        self.assertEqual(sent[-1]["data"]["params"]["level"], 80)
