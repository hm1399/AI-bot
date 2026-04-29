from __future__ import annotations

import asyncio
import sys
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

    async def test_toggle_led_accepts_explicit_enabled_flag(self) -> None:
        sent: list[dict] = []

        async def capture(msg: dict) -> None:
            sent.append(msg)

        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel.send_json = capture

        result = await channel.execute_app_command(
            "toggle_led",
            {"enabled": True},
            client_command_id="cmd_light_on_001",
        )

        self.assertTrue(result["accepted"])
        self.assertEqual(result["command"], "toggle_led")
        self.assertEqual(sent[-1]["type"], "device_command")
        self.assertEqual(sent[-1]["data"]["params"]["enabled"], True)

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

    async def test_device_status_merges_touch_diagnostics(self) -> None:
        channel = DeviceChannel(MessageBus())

        await channel._on_device_status({
            "wifi_rssi": -51,
            "playback_active": True,
            "voice_touch_active": False,
            "touch": {
                "raw": 31234,
                "baseline": 24800,
                "baseline_ready": True,
                "press_threshold": 31800,
                "release_threshold": 29300,
                "pressed": False,
                "raw_pressed": False,
                "can_voice": True,
                "can_tap": False,
            },
        })

        diagnostics = channel.get_snapshot()["diagnostics"]["device"]
        self.assertEqual(diagnostics["touch_raw_value"], 31234)
        self.assertEqual(diagnostics["touch_baseline"], 24800)
        self.assertEqual(diagnostics["touch_press_threshold"], 31800)
        self.assertEqual(diagnostics["touch_release_threshold"], 29300)
        self.assertTrue(diagnostics["touch_baseline_ready"])
        self.assertTrue(diagnostics["touch_can_voice"])
        self.assertFalse(diagnostics["touch_can_tap"])
        self.assertTrue(diagnostics["playback_active"])

    async def test_long_press_without_desktop_bridge_does_not_fall_back_to_device_mic(self) -> None:
        shown: list[str] = []

        async def capture_display(text: str, truncate: bool = True) -> None:
            shown.append(text)

        channel = DeviceChannel(MessageBus())
        channel._send_display_update = capture_display

        await channel._on_touch_event({"action": "long_press"})

        self.assertEqual(channel.state, DeviceState.IDLE)
        self.assertIn("桌面麦克风未连接", shown[-1])

    async def test_device_mic_asr_marks_reply_language_as_english(self) -> None:
        bus = MessageBus()
        asr = SimpleNamespace(
            transcribe=AsyncMock(return_value="打开微信。"),
            last_emotion=None,
        )
        channel = DeviceChannel(bus, asr=asr)

        await channel._run_asr_and_publish(b"\x00" * 16000, 16000)

        inbound = await asyncio.wait_for(bus.consume_inbound(), timeout=0.2)
        self.assertEqual(inbound.metadata["reply_language"], "English")
        self.assertEqual(inbound.metadata["interaction_surface"], "device_press")

    async def test_single_tap_routes_to_structured_confirmation_handler(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        class Observer:
            async def on_device_interaction(
                self,
                *,
                kind: str,
                data: dict[str, object],
            ) -> None:
                routed.append((kind, dict(data)))

        channel = DeviceChannel(MessageBus())
        channel.set_event_observer(Observer())

        await channel._on_touch_event({"tap_count": 1})

        self.assertEqual(channel.state, DeviceState.IDLE)
        self.assertEqual(routed[0][0], "tap")
        self.assertEqual(routed[0][1]["tap_count"], 1)
        self.assertEqual(routed[0][1]["reply_language"], "English")

    async def test_shake_event_uses_structured_handler_instead_of_prompt_inbound(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        class Observer:
            async def on_device_interaction(
                self,
                *,
                kind: str,
                data: dict[str, object],
            ) -> None:
                routed.append((kind, dict(data)))

        channel = DeviceChannel(MessageBus())
        channel.set_event_observer(Observer())

        await channel._on_shake_event({"source": "shake"})

        self.assertEqual(routed[0][0], "shake")
        self.assertEqual(routed[0][1]["source"], "shake")
        self.assertEqual(routed[0][1]["reply_language"], "English")

    async def test_shake_disabled_record_only_feedback_does_not_call_send_voice_reply(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        async def handle(kind: str, data: dict[str, object]) -> dict[str, object]:
            routed.append((kind, dict(data)))
            return {
                "interaction_kind": "shake",
                "mode": "blocked",
                "short_result": "blocked",
                "display_text": "Shake is disabled.",
                "feedback_mode": "record_only",
                "metadata": {"blocked_reason": "shake_disabled"},
            }

        channel = DeviceChannel(MessageBus())
        channel.set_physical_interaction_handler(handle)
        channel._send_voice_reply = AsyncMock()
        channel._send_display_update = AsyncMock()
        channel.send_json = AsyncMock()

        await channel._on_shake_event({"source": "shake"})

        self.assertEqual(routed[0][0], "shake")
        self.assertEqual(routed[0][1]["source"], "shake")
        channel._send_voice_reply.assert_not_awaited()
        channel._send_display_update.assert_not_awaited()
        channel.send_json.assert_not_awaited()

    async def test_long_press_routes_hold_through_structured_handler_in_record_only_mode(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        class Bridge:
            def is_ready(self) -> bool:
                return True

            async def start_device_push_to_talk(self) -> bool:
                return True

        async def handle(kind: str, data: dict[str, object]) -> dict[str, object]:
            routed.append((kind, dict(data)))
            return {
                "feedback_mode": "record_only",
                "display_text": "屏幕提示",
                "voice_text": "语音提示",
                "animation_hint": "celebrate",
                "led_hint": "green",
            }

        channel = DeviceChannel(MessageBus())
        channel.set_desktop_voice_bridge(Bridge())
        channel.set_physical_interaction_handler(handle)
        channel._send_voice_reply = AsyncMock()
        channel.send_json = AsyncMock()

        await channel._on_touch_event({"action": "long_press"})

        self.assertEqual(channel.state, DeviceState.LISTENING)
        self.assertEqual(routed[0][0], "hold")
        self.assertEqual(routed[0][1]["action"], "long_press")
        self.assertEqual(routed[0][1]["source"], "hold")
        self.assertEqual(routed[0][1]["feedback_mode"], "record_only")
        self.assertEqual(routed[0][1]["reply_language"], "English")
        channel._send_voice_reply.assert_not_awaited()
        self.assertGreaterEqual(channel.send_json.await_count, 2)

    async def test_long_press_while_processing_barges_in_and_starts_hold(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        class Bridge:
            def __init__(self) -> None:
                self.start_device_push_to_talk = AsyncMock(return_value=True)
                self.cancel_device_push_to_talk = AsyncMock()

            def is_ready(self) -> bool:
                return True

        async def handle(kind: str, data: dict[str, object]) -> dict[str, object]:
            routed.append((kind, dict(data)))
            return {"feedback_mode": "record_only"}

        bus = MessageBus()
        channel = DeviceChannel(bus)
        channel.state = DeviceState.PROCESSING
        channel.send_json = AsyncMock()
        bridge = Bridge()
        channel.set_desktop_voice_bridge(bridge)
        channel.set_physical_interaction_handler(handle)

        await channel._on_touch_event({"action": "long_press"})

        stop_msg = await asyncio.wait_for(bus.consume_inbound(), timeout=0.2)
        self.assertEqual(stop_msg.content, "/stop")
        self.assertEqual(channel.state, DeviceState.LISTENING)
        self.assertEqual(routed[0][0], "hold")
        self.assertEqual(routed[0][1]["action"], "long_press")
        self.assertEqual(routed[0][1]["operation_status"], "accepted")
        bridge.cancel_device_push_to_talk.assert_awaited_once_with(reason="barge_in")
        bridge.start_device_push_to_talk.assert_awaited_once()

    async def test_long_press_while_desktop_voice_transcribing_does_not_publish_stop(self) -> None:
        class Bridge:
            def __init__(self) -> None:
                self.start_device_push_to_talk = AsyncMock(return_value=True)
                self.cancel_device_push_to_talk = AsyncMock()

            def is_ready(self) -> bool:
                return True

            def get_snapshot(self) -> dict[str, object]:
                return {"status": "transcribing"}

        bus = MessageBus()
        channel = DeviceChannel(bus)
        channel.state = DeviceState.PROCESSING
        channel.send_json = AsyncMock()
        channel._send_display_update = AsyncMock()
        bridge = Bridge()
        channel.set_desktop_voice_bridge(bridge)
        handler = AsyncMock(return_value={"feedback_mode": "record_only"})
        channel.set_physical_interaction_handler(handler)

        await channel._on_touch_event({"action": "long_press"})

        self.assertEqual(channel.state, DeviceState.PROCESSING)
        self.assertEqual(bus.inbound_size, 0)
        channel._send_display_update.assert_awaited_once_with("正在识别，请稍后再按")
        bridge.cancel_device_push_to_talk.assert_not_awaited()
        bridge.start_device_push_to_talk.assert_not_awaited()
        handler.assert_awaited_once()
        self.assertEqual(handler.await_args.args[1]["operation_status"], "failed")
        self.assertEqual(handler.await_args.args[1]["blocked_reason"], "voice_busy")

    async def test_long_press_while_listening_still_records_device_busy(self) -> None:
        routed: list[tuple[str, dict[str, object]]] = []

        async def handle(kind: str, data: dict[str, object]) -> dict[str, object]:
            routed.append((kind, dict(data)))
            return {"feedback_mode": "record_only"}

        channel = DeviceChannel(MessageBus())
        channel.state = DeviceState.LISTENING
        channel.set_physical_interaction_handler(handle)

        await channel._on_touch_event({"action": "long_press"})

        self.assertEqual(channel.state, DeviceState.LISTENING)
        self.assertEqual(routed[0][0], "hold")
        self.assertEqual(routed[0][1]["operation_status"], "failed")
        self.assertEqual(routed[0][1]["blocked_reason"], "device_busy")

    async def test_physical_feedback_routes_voice_and_led_hints(self) -> None:
        sent: list[dict] = []

        async def capture(msg: dict) -> None:
            sent.append(msg)

        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel.send_json = capture
        channel._send_voice_reply = AsyncMock()

        await channel._apply_physical_interaction_feedback({
            "display_text": "屏幕提示",
            "voice_text": "语音提示",
            "animation_hint": "celebrate",
            "led_hint": "green",
        })

        channel._send_voice_reply.assert_awaited_once_with(
            "语音提示",
            display_text="屏幕提示",
            update_display=True,
        )
        self.assertEqual(sent[0]["type"], "face_update")
        self.assertEqual(sent[1]["type"], "led_control")

    async def test_physical_feedback_skips_device_output_for_record_only_result(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel.send_json = AsyncMock()
        channel._send_voice_reply = AsyncMock()
        channel._send_display_update = AsyncMock()

        await channel._apply_physical_interaction_feedback({
            "feedback_mode": "record_only",
            "display_text": "屏幕提示",
            "voice_text": "语音提示",
            "animation_hint": "celebrate",
            "led_hint": "green",
        })

        channel._send_voice_reply.assert_not_awaited()
        channel._send_display_update.assert_not_awaited()
        channel.send_json.assert_not_awaited()

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
        self.assertEqual(channel._weather_provider, "open-meteo-fallback")
        self.assertEqual(channel._weather_city, "Hong Kong")
        fallback.assert_awaited_once()

    async def test_weather_push_loop_updates_app_snapshot_without_status_bar_capability(
        self,
    ) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel._mark_device_activity()
        channel._status_bar_state["capability"] = False
        channel._status_bar_state["weather_capability"] = False

        with patch.object(
            channel,
            "_fetch_weather",
            AsyncMock(return_value=("26°C", "ready")),
        ) as fetch_weather, patch(
            "channels.device_channel.asyncio.sleep",
            AsyncMock(side_effect=asyncio.CancelledError()),
        ):
            await channel._weather_push_loop()

        snapshot = channel.get_snapshot()
        self.assertEqual(snapshot["status_bar"]["weather"], "26°C")
        self.assertEqual(snapshot["status_bar"]["weather_status"], "ready")
        self.assertTrue(snapshot["status_bar"]["weather_capability"])
        self.assertTrue(snapshot["display_capabilities"]["weather_available"])
        self.assertEqual(snapshot["display_capabilities"]["weather_validity"], "valid")
        fetch_weather.assert_awaited_once()

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

    async def test_send_voice_reply_serializes_overlapping_playback_requests(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel.tts = object()

        order: list[tuple[str, str]] = []
        first_started = asyncio.Event()
        allow_first_finish = asyncio.Event()

        async def fake_stream(
            text: str,
            *,
            display_text: str | None = None,
            update_display: bool = True,
        ) -> None:
            order.append(("start", text))
            if text == "first":
                first_started.set()
                await allow_first_finish.wait()
            order.append(("end", text))

        channel._stream_voice_reply = fake_stream  # type: ignore[method-assign]

        first = asyncio.create_task(channel._send_voice_reply("first"))
        await first_started.wait()
        second = asyncio.create_task(channel._send_voice_reply("second"))

        await asyncio.sleep(0.01)
        self.assertEqual(order, [("start", "first")])

        allow_first_finish.set()
        await first
        await second

        self.assertEqual(
            order,
            [
                ("start", "first"),
                ("end", "first"),
                ("start", "second"),
                ("end", "second"),
            ],
        )

    async def test_get_snapshot_marks_connection_offline_when_activity_is_stale(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel._last_device_activity_monotonic = 1.0
        channel._last_device_activity_at = "2026-04-10T19:20:00+08:00"

        with patch(
            "channels.device_channel.time.monotonic",
            return_value=DEVICE_ACTIVITY_STALE_TIMEOUT + 2,
        ):
            snapshot = channel.get_snapshot()

        self.assertFalse(snapshot["connected"])
        self.assertEqual(snapshot["last_seen_at"], "2026-04-10T19:20:00+08:00")

    async def test_execute_app_command_rejects_stale_connection(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel.connected = True
        channel._last_device_activity_monotonic = 1.0

        with patch(
            "channels.device_channel.time.monotonic",
            return_value=DEVICE_ACTIVITY_STALE_TIMEOUT + 2,
        ):
            with self.assertRaisesRegex(RuntimeError, "DEVICE_OFFLINE"):
                await channel.execute_app_command("set_volume", {"level": 50})

    async def test_get_snapshot_exposes_weather_metadata(self) -> None:
        channel = DeviceChannel(MessageBus())
        channel._status_bar_state["weather"] = "25°C"
        channel._status_bar_state["weather_status"] = "ready"
        channel._status_bar_state["updated_at"] = "2026-04-10T19:36:19+08:00"
        channel._weather_provider = "open-meteo-fallback"
        channel._weather_city = "Hong Kong"
        channel._weather_source = "computer_fetch"
        channel._weather_fetched_at = "2026-04-10T19:30:30+08:00"

        snapshot = channel.get_snapshot()

        self.assertEqual(
            snapshot["status_bar"]["weather_meta"]["provider"],
            "open-meteo-fallback",
        )
        self.assertEqual(
            snapshot["status_bar"]["weather_meta"]["city"],
            "Hong Kong",
        )
        self.assertEqual(
            snapshot["status_bar"]["weather_meta"]["source"],
            "computer_fetch",
        )
        self.assertEqual(
            snapshot["status_bar"]["weather_meta"]["fetched_at"],
            "2026-04-10T19:30:30+08:00",
        )
