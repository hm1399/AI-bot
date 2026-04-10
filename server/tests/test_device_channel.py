from __future__ import annotations

import asyncio
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from channels.device_channel import (
    DEVICE_ACTIVITY_STALE_TIMEOUT,
    DeviceChannel,
)
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

    async def test_execute_app_command_times_out_without_result(self) -> None:
        sent: list[dict] = []
        observed: list[dict[str, object]] = []

        async def capture(msg: dict) -> None:
            sent.append(msg)

        class Observer:
            async def on_device_command_updated(
                self,
                *,
                result: dict[str, object],
                snapshot: dict[str, object],
            ) -> None:
                observed.append({
                    "result": result,
                    "snapshot": snapshot,
                })

        channel = DeviceChannel(MessageBus(), command_result_timeout_s=0.01)
        channel.connected = True
        channel.send_json = capture
        channel.set_event_observer(Observer())

        await channel.execute_app_command(
            "set_volume",
            {"level": 80},
            client_command_id="cmd_local_timeout",
        )
        await asyncio.sleep(0.03)

        self.assertEqual(sent[-1]["type"], "device_command")
        self.assertEqual(channel.get_snapshot()["last_command"]["status"], "failed")
        self.assertEqual(channel.get_snapshot()["last_command"]["error"], "command_timeout")
        self.assertEqual(observed[-1]["result"]["status"], "failed")
        self.assertEqual(observed[-1]["result"]["error"], "command_timeout")

    async def test_fetch_weather_uses_fallback_when_api_key_missing(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.set_weather_config({
            "api_key": "",
            "city": "Hong Kong",
            "units": "metric",
        })

        with patch.object(
            channel,
            "_fetch_weather_fallback",
            AsyncMock(return_value=("26°C", "ready")),
            create=True,
        ) as fallback:
            weather, status = await channel._fetch_weather()

        self.assertEqual(weather, "26°C")
        self.assertEqual(status, "ready")
        fallback.assert_awaited_once()

    async def test_merge_status_bar_state_preserves_weather_when_payload_omits_it(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel._status_bar_state["time"] = "19:05"
        channel._status_bar_state["weather"] = "26°C"
        channel._status_bar_state["weather_status"] = "ready"

        channel._merge_status_bar_state({
            "status_bar": {
                "time": "19:06",
                "weather_status": "ready",
            },
        })

        snapshot = channel.get_snapshot()
        self.assertEqual(snapshot["status_bar"]["time"], "19:06")
        self.assertEqual(snapshot["status_bar"]["weather"], "26°C")
        self.assertEqual(snapshot["status_bar"]["weather_status"], "ready")

    async def test_get_snapshot_marks_connection_offline_when_activity_is_stale(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel._last_device_activity_monotonic = (
            time.monotonic() - DEVICE_ACTIVITY_STALE_TIMEOUT - 1
        )
        channel._last_device_activity_at = "2026-04-10T19:20:00+08:00"

        snapshot = channel.get_snapshot()

        self.assertFalse(snapshot["connected"])
        self.assertEqual(snapshot["last_seen_at"], "2026-04-10T19:20:00+08:00")

    async def test_execute_app_command_rejects_stale_connection(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel._last_device_activity_monotonic = (
            time.monotonic() - DEVICE_ACTIVITY_STALE_TIMEOUT - 1
        )

        with self.assertRaisesRegex(RuntimeError, "DEVICE_OFFLINE"):
            await channel.execute_app_command("set_volume", {"level": 50})
