from __future__ import annotations

import asyncio
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.session.manager import SessionManager
from services.computer_control import ComputerControlService
from services.app_runtime import AppRuntimeService


class DummyDeviceChannel:
    def __init__(self) -> None:
        self.connected = False
        self.asr = object()
        self.tts = object()
        self.physical_interaction_handler = None
        self._snapshot = {
            "connected": False,
            "state": "IDLE",
            "battery": -1,
            "wifi_rssi": 0,
            "charging": False,
            "reconnect_count": 0,
            "controls": {
                "volume": 70,
                "muted": False,
                "sleeping": False,
                "led_enabled": True,
                "led_brightness": 50,
                "led_color": "#2563eb",
            },
            "status_bar": {
                "time": "09:41",
                "weather": "26°C",
                "weather_status": "ready",
                "updated_at": "2026-04-10T09:41:00+08:00",
            },
            "last_command": {
                "command_id": None,
                "client_command_id": None,
                "command": None,
                "status": "idle",
                "ok": None,
                "error": None,
                "updated_at": None,
            },
        }
        self.last_outbound: OutboundMessage | None = None
        self.last_command: dict[str, Any] | None = None
        self.command_history: list[dict[str, Any]] = []
        self.weather_config: dict[str, Any] | None = None
        self.active_app_session_resolver = None
        self.delivered_voice_texts: list[str] = []

    def get_snapshot(self) -> dict[str, Any]:
        return dict(self._snapshot)

    def set_weather_config(self, config: dict[str, Any]) -> None:
        self.weather_config = dict(config)

    def set_active_app_session_resolver(self, resolver) -> None:
        self.active_app_session_resolver = resolver

    def set_physical_interaction_handler(self, handler) -> None:
        self.physical_interaction_handler = handler

    async def send_outbound(self, out_msg: OutboundMessage) -> None:
        self.last_outbound = out_msg

    async def deliver_external_text_response(self, text: str) -> None:
        self.delivered_voice_texts.append(text)

    async def execute_app_command(
        self,
        command: str,
        params: dict[str, Any],
        *,
        client_command_id: str | None = None,
    ) -> dict[str, Any]:
        self.last_command = {
            "command": command,
            "params": params,
            "client_command_id": client_command_id,
        }
        self.command_history.append(dict(self.last_command))
        self._snapshot["last_command"] = {
            "command_id": "cmd_srv_001",
            "client_command_id": client_command_id,
            "command": command,
            "status": "pending",
            "ok": None,
            "error": None,
            "updated_at": "2026-04-10T09:42:00+08:00",
        }
        return {
            "accepted": True,
            "command_id": "cmd_srv_001",
            "client_command_id": client_command_id,
            "command": command,
            "status": "pending",
            "device": self.get_snapshot(),
        }


class FakeComputerAdapter:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []

    async def open_app(self, *, app: str) -> dict[str, Any]:
        self.calls.append(("open_app", {"app": app}))
        return {"opened": app}

    async def open_path(self, *, path: str) -> dict[str, Any]:
        self.calls.append(("open_path", {"path": path}))
        return {"opened_path": path}

    async def open_url(self, *, url: str) -> dict[str, Any]:
        self.calls.append(("open_url", {"url": url}))
        return {"opened_url": url}

    async def run_script(
        self,
        *,
        script_id: str,
        command: list[str],
        cwd: str | None = None,
    ) -> dict[str, Any]:
        self.calls.append((
            "run_script",
            {
                "script_id": script_id,
                "command": list(command),
                "cwd": cwd,
            },
        ))
        return {"script_id": script_id, "stdout": "ok"}


class FakeRequest:
    def __init__(
        self,
        *,
        headers: dict[str, str] | None = None,
        query: dict[str, str] | None = None,
        match_info: dict[str, str] | None = None,
        json_body: dict[str, Any] | None = None,
    ) -> None:
        self.headers = headers or {}
        self.query = query or {}
        self.match_info = match_info or {}
        self._json_body = json_body
        self.content_length = 0 if json_body is None else 1

    async def json(self) -> dict[str, Any]:
        if self._json_body is None:
            raise json.JSONDecodeError("empty", "", 0)
        return self._json_body


class FakeWebSocket:
    def __init__(self) -> None:
        self.sent: list[dict[str, Any]] = []
        self.closed = False

    async def send_json(self, payload: dict[str, Any]) -> None:
        self.sent.append(payload)


class AppRuntimeApiTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        workspace = Path(self.tmpdir.name)
        self.bus = MessageBus()
        self.sessions = SessionManager(workspace)
        self.device = DummyDeviceChannel()
        self.computer_adapter = FakeComputerAdapter()
        self.computer_control = ComputerControlService(
            {
                "computer_control": {
                    "enabled": True,
                    "allowed_apps": ["Safari", "WeChat"],
                    "allowed_scripts": {
                        "project-healthcheck": {
                            "command": ["/bin/echo", "ok"],
                        }
                    },
                    "allowed_path_roots": [self.tmpdir.name],
                    "confirm_medium_risk": True,
                }
            },
            runtime_dir=workspace / "runtime",
            adapter=self.computer_adapter,
        )
        self.service = AppRuntimeService(
            {
                "app": {
                    "auth_token": "app-local-123",
                    "default_session_id": "app:main",
                },
                "computer_control": {
                    "enabled": True,
                    "allowed_apps": ["Safari", "WeChat"],
                },
                "whatsapp": {"enabled": True},
            },
            bus=self.bus,
            sessions=self.sessions,
            device_channel=self.device,
            computer_control_service=self.computer_control,
            version="0.6.0",
            start_time=0,
        )
        self.bus.add_observer(self.service)
        self.headers = {"Authorization": "Bearer app-local-123"}

    async def asyncTearDown(self) -> None:
        self.tmpdir.cleanup()

    async def test_bootstrap_requires_auth_and_creates_default_session(self) -> None:
        unauthorized = await self.service.handle_bootstrap(FakeRequest())
        self.assertEqual(unauthorized.status, 401)

        response = await self.service.handle_bootstrap(FakeRequest(headers=self.headers))
        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)

        self.assertEqual(payload["data"]["event_stream"]["path"], "/ws/app/v1/events")
        self.assertEqual(payload["data"]["sessions"][0]["session_id"], "app:main")
        self.assertTrue(payload["data"]["capabilities"]["app_events"])
        self.assertTrue(payload["data"]["capabilities"]["todo_summary"])
        self.assertTrue(payload["data"]["capabilities"]["calendar_summary"])
        self.assertTrue(payload["data"]["capabilities"]["settings"])
        self.assertTrue(payload["data"]["capabilities"]["tasks"])
        self.assertTrue(payload["data"]["capabilities"]["notifications"])
        self.assertTrue(payload["data"]["capabilities"]["planning"])
        self.assertTrue(payload["data"]["capabilities"]["planning_overview"])
        self.assertTrue(payload["data"]["capabilities"]["computer_control"])
        self.assertIn("open_app", payload["data"]["capabilities"]["computer_actions"])
        self.assertEqual(
            payload["data"]["planning"]["overview_path"],
            "/api/app/v1/planning/overview",
        )
        self.assertTrue(payload["data"]["runtime"]["planning"]["available"])
        self.assertTrue(payload["data"]["runtime"]["computer_control"]["available"])
        self.assertTrue(payload["data"]["capabilities"]["experience"])
        self.assertIn("experience", payload["data"]["runtime"])
        self.assertEqual(
            payload["data"]["runtime"]["experience"]["active_scene_mode"],
            "focus",
        )

    async def test_post_message_enqueues_app_task(self) -> None:
        response = await self.service.handle_post_message(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
            json_body={"content": "你好", "client_message_id": "flutter_local_001"},
        ))
        self.assertEqual(response.status, 202)
        payload = json.loads(response.text)
        task_id = payload["data"]["task_id"]

        msg = await self.bus.consume_inbound()
        self.assertEqual(msg.channel, "app")
        self.assertEqual(msg.chat_id, "main")
        self.assertEqual(msg.metadata["task_id"], task_id)
        self.assertEqual(msg.metadata["client_message_id"], "flutter_local_001")

        runtime = await self.service.get_runtime_state()
        for _ in range(10):
            if len(runtime["task_queue"]) == 1:
                break
            await asyncio.sleep(0)
            runtime = await self.service.get_runtime_state()

        self.assertIsNone(runtime["current_task"])
        self.assertEqual(len(runtime["task_queue"]), 1)
        self.assertEqual(runtime["task_queue"][0]["task_id"], task_id)

    async def test_post_message_returns_accepted_payload_without_observer_race(self) -> None:
        with patch.object(self.bus, "_schedule_notify", return_value=None):
            response = await self.service.handle_post_message(FakeRequest(
                headers=self.headers,
                match_info={"session_id": "app:main"},
                json_body={"content": "打开微信"},
            ))

        self.assertEqual(response.status, 202)
        payload = json.loads(response.text)
        accepted = payload["data"]["accepted_message"]
        self.assertTrue(accepted["message_id"].startswith("msg_"))
        self.assertTrue(payload["data"]["task_id"].startswith("task_"))
        self.assertEqual(accepted["metadata"]["task_id"], payload["data"]["task_id"])

        msg = await self.bus.consume_inbound()
        self.assertEqual(msg.metadata["message_id"], accepted["message_id"])
        self.assertEqual(msg.metadata["task_id"], payload["data"]["task_id"])

    async def test_post_experience_interaction_reuses_real_runtime_guards(self) -> None:
        response = await self.service.handle_post_experience_interaction(FakeRequest(
            headers=self.headers,
            json_body={
                "kind": "shake",
                "payload": {
                    "app_session_id": "app:main",
                },
            },
        ))
        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)

        self.assertEqual(payload["data"]["result"]["interaction_kind"], "shake")
        self.assertEqual(payload["data"]["result"]["mode"], "blocked")
        self.assertEqual(
            payload["data"]["result"]["metadata"]["blocked_reason"],
            "device_offline",
        )
        self.assertEqual(
            payload["data"]["experience"]["last_interaction_result"]["mode"],
            "blocked",
        )

    async def test_interrupt_interaction_does_not_publish_duplicate_stop_when_device_is_processing(self) -> None:
        self.device.state = "PROCESSING"
        self.device.interrupt_current_activity = AsyncMock()
        self.service.get_runtime_state = AsyncMock(return_value={
            "current_task": {"task_id": "task_001"},
            "voice": {"desktop_bridge": {"ready": True, "status": "idle"}},
            "computer_control": {},
            "device": self.device.get_snapshot(),
        })
        self.service.experience_service.handle_interaction = AsyncMock(return_value={
            "interaction_kind": "tap",
            "mode": "interrupt",
            "title": "打断",
            "short_result": "interrupted",
            "display_text": "已请求打断当前流程。",
        })
        self.bus.publish_inbound = AsyncMock()

        await self.service._handle_physical_interaction(
            "tap",
            {"tap_count": 3, "app_session_id": "app:main"},
        )

        self.device.interrupt_current_activity.assert_awaited_once_with(notice="")
        self.bus.publish_inbound.assert_not_awaited()

    async def test_post_message_scene_command_updates_session_without_queueing_task(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        response = await self.service.handle_post_message(
            FakeRequest(
                headers=self.headers,
                match_info={"session_id": "app:main"},
                json_body={
                    "content": "切换到会议模式",
                    "client_message_id": "flutter_local_scene_cmd",
                },
            )
        )

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]
        self.assertFalse(payload["queued"])
        self.assertEqual(payload["accepted_message"]["status"], "completed")
        self.assertEqual(payload["assistant_message"]["role"], "assistant")
        self.assertIn("会议模式", payload["assistant_message"]["content"])
        self.assertEqual(self.bus.inbound_size, 0)

        session = self.sessions.get("app:main")
        assert session is not None
        self.assertEqual(session.metadata["scene_mode"], "meeting")
        self.assertEqual(session.messages[-2]["role"], "user")
        self.assertEqual(session.messages[-1]["role"], "assistant")

        runtime = await self.service.get_runtime_state()
        self.assertEqual(runtime["experience"]["active_scene_mode"], "meeting")

        event_types = [event["event_type"] for event in ws.sent]
        self.assertIn("session.updated", event_types)
        self.assertIn("session.message.created", event_types)
        self.assertIn("session.message.completed", event_types)
        self.assertIn("runtime.experience.updated", event_types)

    async def test_post_message_companion_mode_command_updates_persona_without_queueing_task(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        response = await self.service.handle_post_message(
            FakeRequest(
                headers=self.headers,
                match_info={"session_id": "app:main"},
                json_body={
                    "content": "切换到陪伴模式",
                    "client_message_id": "flutter_local_companion_mode_cmd",
                },
            )
        )

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]
        self.assertFalse(payload["queued"])
        self.assertIn("温暖陪伴", payload["assistant_message"]["content"])
        self.assertEqual(self.bus.inbound_size, 0)

        session = self.sessions.get("app:main")
        assert session is not None
        self.assertEqual(
            session.metadata["persona_profile"]["preset"],
            "companion_warm",
        )

        runtime = await self.service.get_runtime_state()
        self.assertEqual(
            runtime["experience"]["active_persona"]["preset"],
            "companion_warm",
        )

        event_types = [event["event_type"] for event in ws.sent]
        self.assertIn("session.updated", event_types)
        self.assertIn("session.message.created", event_types)
        self.assertIn("session.message.completed", event_types)
        self.assertIn("runtime.experience.updated", event_types)

    def test_experience_command_response_uses_english_when_requested(self) -> None:
        response = AppRuntimeService._build_experience_command_response(
            command={
                "scene": {"id": "meeting", "label": "会议模式"},
                "persona": {"id": "companion_warm", "label": "温暖陪伴"},
            },
            before_snapshot={
                "active_scene_mode": "focus",
                "active_persona": {"preset": "balanced"},
            },
            after_snapshot={
                "active_persona": {"preset": "companion_warm", "label": "Companion Warm"},
            },
            metadata={"reply_language": "English"},
        )

        self.assertEqual(
            response,
            "Switched to Meeting. Switched persona to Companion Warm.",
        )

    async def test_desktop_voice_transcript_persona_command_returns_direct_confirmation(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        result = await self.service.on_desktop_voice_transcript(
            transcript="切换人格为温暖陪伴",
            metadata={
                "source": "voice",
                "source_channel": "desktop_voice",
                "voice_path": "desktop_mic",
                "interaction_surface": "device_press",
                "capture_source": "desktop_mic",
                "app_session_id": "app:main",
            },
            snapshot={"status": "responding"},
        )

        self.assertIsInstance(result, dict)
        self.assertTrue(result["handled"])
        self.assertIn("温暖陪伴", result["response_text"])
        self.assertEqual(result["outbound_metadata"]["persona_profile_id"], "companion_warm")
        self.assertEqual(self.bus.inbound_size, 0)

        session = self.sessions.get("app:main")
        assert session is not None
        self.assertEqual(session.metadata["persona_profile"]["preset"], "companion_warm")

        runtime = await self.service.get_runtime_state()
        self.assertEqual(
            runtime["experience"]["active_persona"]["preset"],
            "companion_warm",
        )

        event_types = [event["event_type"] for event in ws.sent]
        self.assertIn("desktop_voice.transcript", event_types)
        self.assertIn("session.updated", event_types)
        self.assertIn("session.message.created", event_types)
        self.assertIn("session.message.completed", event_types)
        self.assertIn("runtime.experience.updated", event_types)

    async def test_patch_session_rejects_archiving_last_active_conversation(self) -> None:
        self.service._ensure_app_session("app:main", title="主对话")
        response = await self.service.handle_patch_session(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
            json_body={"archived": True},
        ))

        self.assertEqual(response.status, 409)
        payload = json.loads(response.text)
        self.assertEqual(payload["error"]["code"], "INVALID_STATE")
        self.assertEqual(self.service.get_active_app_session_id(), "app:main")

    async def test_patch_session_archives_current_session_and_falls_back_to_other_active_session(self) -> None:
        self.service._ensure_app_session("app:main", title="主对话")
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        created = await self.service.handle_create_session(FakeRequest(
            headers=self.headers,
            json_body={"title": "Second thread"},
        ))
        created_session_id = json.loads(created.text)["data"]["session_id"]

        archived = await self.service.handle_patch_session(FakeRequest(
            headers=self.headers,
            match_info={"session_id": created_session_id},
            json_body={"archived": True},
        ))

        self.assertEqual(archived.status, 200)
        archived_payload = json.loads(archived.text)["data"]
        self.assertTrue(archived_payload["archived"])
        self.assertEqual(self.service.get_active_app_session_id(), "app:main")
        updated_sessions = [
            event["payload"]["session"]["session_id"]
            for event in ws.sent
            if event["event_type"] == "session.updated"
        ]
        self.assertIn(created_session_id, updated_sessions)
        self.assertIn("app:main", updated_sessions)

    async def test_archived_session_cannot_become_active(self) -> None:
        self.service._ensure_app_session("app:main", title="主对话")
        created = await self.service.handle_create_session(FakeRequest(
            headers=self.headers,
            json_body={"title": "Archive me"},
        ))
        session_id = json.loads(created.text)["data"]["session_id"]

        archived = await self.service.handle_patch_session(FakeRequest(
            headers=self.headers,
            match_info={"session_id": session_id},
            json_body={"archived": True},
        ))
        self.assertEqual(archived.status, 200)

        activated = await self.service.handle_set_active_session(FakeRequest(
            headers=self.headers,
            json_body={"session_id": session_id},
        ))
        self.assertEqual(activated.status, 409)
        payload = json.loads(activated.text)
        self.assertEqual(payload["error"]["code"], "INVALID_STATE")

    async def test_runtime_state_exposes_planning_runtime_flags(self) -> None:
        runtime = await self.service.get_runtime_state()
        self.assertIn("planning", runtime)
        self.assertTrue(runtime["planning"]["available"])
        self.assertTrue(runtime["planning"]["overview_ready"])
        self.assertTrue(runtime["planning"]["timeline_ready"])
        self.assertTrue(runtime["planning"]["conflicts_ready"])
        self.assertIn("computer_control", runtime)
        self.assertTrue(runtime["computer_control"]["available"])
        self.assertIn("open_app", runtime["computer_control"]["supported_actions"])
        self.assertIn("experience", runtime)
        self.assertEqual(runtime["experience"]["active_scene_mode"], "focus")
        self.assertIn("physical_interaction", runtime["experience"])

    async def test_patch_session_updates_persisted_experience_overrides(self) -> None:
        bootstrap = await self.service.handle_bootstrap(FakeRequest(headers=self.headers))
        self.assertEqual(bootstrap.status, 200)

        patched = await self.service.handle_patch_session(
            FakeRequest(
                headers=self.headers,
                match_info={"session_id": "app:main"},
                json_body={
                    "scene_mode": "meeting",
                    "persona_profile": {"preset": "meeting_brief"},
                    "persona_fields": {"voice_style": "quiet"},
                },
            )
        )

        self.assertEqual(patched.status, 200)
        payload = json.loads(patched.text)["data"]
        self.assertEqual(payload["scene_mode"], "meeting")
        self.assertEqual(payload["persona_profile"]["preset"], "meeting_brief")
        self.assertEqual(payload["persona_fields"]["voice_style"], "quiet")

        runtime = await self.service.get_runtime_state()
        self.assertEqual(runtime["experience"]["active_scene_mode"], "meeting")
        self.assertEqual(
            runtime["experience"]["active_persona"]["voice_style"],
            "quiet",
        )
        self.assertEqual(runtime["experience"]["override_source"], "session_override")

    async def test_patch_experience_supports_runtime_override_scope(self) -> None:
        updated = await self.service.handle_patch_experience(
            FakeRequest(
                headers=self.headers,
                json_body={
                    "scope": "runtime",
                    "scene_mode": "offwork",
                    "persona_fields": {"voice_style": "bright"},
                },
            )
        )

        self.assertEqual(updated.status, 200)
        payload = json.loads(updated.text)["data"]
        self.assertEqual(payload["experience"]["active_scene_mode"], "offwork")
        self.assertEqual(
            payload["experience"]["active_persona"]["voice_style"],
            "bright",
        )
        self.assertEqual(payload["experience"]["override_source"], "runtime_override")

    async def test_patch_experience_rejects_session_scope_payload(self) -> None:
        rejected = await self.service.handle_patch_experience(
            FakeRequest(
                headers=self.headers,
                json_body={
                    "scope": "session",
                    "session_id": "app:main",
                    "scene_mode": "meeting",
                },
            )
        )

        self.assertEqual(rejected.status, 400)
        payload = json.loads(rejected.text)
        self.assertEqual(payload["error"]["code"], "INVALID_ARGUMENT")

    async def test_computer_state_and_action_routes_emit_runtime_events(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        state_response = await self.service.handle_computer_state(FakeRequest(headers=self.headers))
        self.assertEqual(state_response.status, 200)
        state_payload = json.loads(state_response.text)["data"]
        self.assertTrue(state_payload["available"])
        self.assertIn("run_script", state_payload["supported_actions"])

        created = await self.service.handle_create_computer_action(FakeRequest(
            headers=self.headers,
            json_body={
                "action": "open_app",
                "arguments": {"app": "Safari"},
                "source_session_id": "app:main",
            },
        ))
        self.assertEqual(created.status, 201)
        created_payload = json.loads(created.text)["data"]
        self.assertEqual(created_payload["status"], "completed")
        self.assertEqual(created_payload["result"]["opened"], "Safari")

        event_types = [event["event_type"] for event in ws.sent]
        self.assertIn("computer.action.created", event_types)
        self.assertIn("computer.action.updated", event_types)
        self.assertIn("computer.action.completed", event_types)
        self.assertEqual(self.computer_adapter.calls[0][0], "open_app")

    async def test_computer_action_confirm_and_cancel_routes(self) -> None:
        awaiting = await self.service.handle_create_computer_action(FakeRequest(
            headers=self.headers,
            json_body={
                "action": "run_script",
                "arguments": {"script_id": "project-healthcheck"},
                "source_session_id": "app:main",
            },
        ))
        self.assertEqual(awaiting.status, 201)
        awaiting_payload = json.loads(awaiting.text)["data"]
        self.assertEqual(awaiting_payload["status"], "awaiting_confirmation")

        confirmed = await self.service.handle_confirm_computer_action(FakeRequest(
            headers=self.headers,
            match_info={"action_id": awaiting_payload["action_id"]},
        ))
        self.assertEqual(confirmed.status, 200)
        confirmed_payload = json.loads(confirmed.text)["data"]
        self.assertEqual(confirmed_payload["status"], "completed")

        second = await self.service.handle_create_computer_action(FakeRequest(
            headers=self.headers,
            json_body={
                "action": "run_script",
                "arguments": {"script_id": "project-healthcheck"},
                "source_session_id": "app:main",
            },
        ))
        second_payload = json.loads(second.text)["data"]

        cancelled = await self.service.handle_cancel_computer_action(FakeRequest(
            headers=self.headers,
            match_info={"action_id": second_payload["action_id"]},
        ))
        self.assertEqual(cancelled.status, 200)
        cancelled_payload = json.loads(cancelled.text)["data"]
        self.assertEqual(cancelled_payload["status"], "cancelled")

    async def test_get_messages_supports_before_after_pagination(self) -> None:
        session = self.sessions.get_or_create("app:main")
        session.metadata.update({
            "channel": "app",
            "title": "主对话",
            "pinned": True,
            "archived": False,
        })
        for index in range(1, 6):
            session.add_message(
                "user" if index % 2 else "assistant",
                f"message-{index}",
                message_id=f"msg_{index}",
                task_id=f"task_{index}",
            )
        self.sessions.save(session)

        latest = await self.service.handle_get_messages(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
            query={"limit": "2"},
        ))
        latest_payload = json.loads(latest.text)
        self.assertEqual(
            [item["message_id"] for item in latest_payload["data"]["items"]],
            ["msg_4", "msg_5"],
        )
        self.assertTrue(latest_payload["data"]["page_info"]["has_more_before"])

        older = await self.service.handle_get_messages(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
            query={"limit": "2", "before": "msg_4"},
        ))
        older_payload = json.loads(older.text)
        self.assertEqual(
            [item["message_id"] for item in older_payload["data"]["items"]],
            ["msg_2", "msg_3"],
        )
        self.assertTrue(older_payload["data"]["page_info"]["has_more_before"])
        self.assertFalse(older_payload["data"]["page_info"]["has_more_after"])

        newer = await self.service.handle_get_messages(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
            query={"limit": "2", "after": "msg_2"},
        ))
        newer_payload = json.loads(newer.text)
        self.assertEqual(
            [item["message_id"] for item in newer_payload["data"]["items"]],
            ["msg_3", "msg_4"],
        )
        self.assertTrue(newer_payload["data"]["page_info"]["has_more_after"])

    async def test_event_resume_replays_missed_events_when_cursor_exists(self) -> None:
        first_ws = FakeWebSocket()
        self.service._ws_clients.add(first_ws)
        await self.bus.publish_inbound(
            InboundMessage(channel="app", sender_id="flutter", chat_id="main", content="第一条")
        )
        self.service._ws_clients.clear()

        last_event_id = self.service._event_history[0]["event_id"]
        resumed_ws = FakeWebSocket()
        await self.service._attach_event_client(
            resumed_ws,
            last_event_id=last_event_id,
            replay_limit=10,
        )

        hello = resumed_ws.sent[0]
        self.assertEqual(hello["event_type"], "system.hello")
        self.assertTrue(hello["payload"]["resume"]["accepted"])
        self.assertEqual(hello["payload"]["resume"]["replayed_count"], 1)
        self.assertEqual(resumed_ws.sent[1]["event_type"], "session.message.created")

    async def test_event_resume_requests_refetch_when_cursor_missing(self) -> None:
        ws = FakeWebSocket()
        await self.service._attach_event_client(
            ws,
            last_event_id="evt_missing",
            replay_limit=10,
        )

        hello = ws.sent[0]
        self.assertEqual(hello["event_type"], "system.hello")
        self.assertFalse(hello["payload"]["resume"]["accepted"])
        self.assertTrue(hello["payload"]["resume"]["should_refetch_bootstrap"])
        self.assertEqual(hello["payload"]["resume"]["reason"], "last_event_id_not_found")

    async def test_set_todo_summary_updates_runtime_state_and_persists(self) -> None:
        response = await self.service.handle_set_todo_summary(FakeRequest(
            headers=self.headers,
            json_body={
                "enabled": True,
                "pending_count": 5,
                "overdue_count": 2,
                "next_due_at": "2026-03-26T15:00:00+08:00",
            },
        ))
        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)
        self.assertTrue(payload["data"]["enabled"])
        self.assertEqual(payload["data"]["pending_count"], 5)

        runtime = await self.service.get_runtime_state()
        self.assertEqual(runtime["todo_summary"]["pending_count"], 5)
        self.assertTrue((Path(self.tmpdir.name) / "runtime" / "todo_summary.json").exists())

    async def test_set_calendar_summary_emits_changed_event(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        response = await self.service.handle_set_calendar_summary(FakeRequest(
            headers=self.headers,
            json_body={
                "enabled": True,
                "today_count": 3,
                "next_event_at": "2026-03-26T19:00:00+08:00",
                "next_event_title": "晚间例会",
            },
        ))
        self.assertEqual(response.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "calendar.summary.changed")
        self.assertEqual(ws.sent[-1]["payload"]["next_event_title"], "晚间例会")

    async def test_creating_task_auto_recalculates_todo_summary(self) -> None:
        response = await self.service.handle_create_task(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Review proposal",
                "priority": "high",
                "due_at": "2099-04-09T11:00:00+08:00",
            },
        ))
        self.assertEqual(response.status, 201)

        runtime = await self.service.get_runtime_state()
        self.assertTrue(runtime["todo_summary"]["enabled"])
        self.assertEqual(runtime["todo_summary"]["pending_count"], 1)
        self.assertEqual(runtime["todo_summary"]["overdue_count"], 0)
        self.assertEqual(
            runtime["todo_summary"]["next_due_at"],
            "2099-04-09T11:00:00+08:00",
        )

    async def test_creating_event_auto_recalculates_calendar_summary(self) -> None:
        response = await self.service.handle_create_event(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Team Standup",
                "start_at": "2099-04-09T09:30:00+08:00",
                "end_at": "2099-04-09T10:00:00+08:00",
            },
        ))
        self.assertEqual(response.status, 201)

        runtime = await self.service.get_runtime_state()
        self.assertTrue(runtime["calendar_summary"]["enabled"])
        self.assertEqual(
            runtime["calendar_summary"]["next_event_at"],
            "2099-04-09T09:30:00+08:00",
        )
        self.assertEqual(
            runtime["calendar_summary"]["next_event_title"],
            "Team Standup",
        )

    async def test_event_stream_model_receives_queue_progress_and_completion(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        msg = InboundMessage(channel="app", sender_id="flutter", chat_id="main", content="今天天气如何？")
        await self.bus.publish_inbound(msg)

        self.assertEqual(
            [event["event_type"] for event in ws.sent[:2]],
            ["runtime.task.queue_changed", "session.message.created"],
        )

        before = len(ws.sent)
        await self.service.on_task_started(msg=msg, session_key="app:main")
        self.assertEqual(
            [event["event_type"] for event in ws.sent[before:before + 2]],
            ["runtime.task.current_changed", "runtime.task.queue_changed"],
        )

    async def test_task_finish_marks_pending_user_message_completed(self) -> None:
        msg = InboundMessage(
            channel="desktop_voice",
            sender_id="desktop_mic",
            chat_id="desktop",
            content="W.",
            metadata={
                "app_session_id": "app:main",
                "task_id": "task_voice_001",
                "message_id": "msg_user_voice_001",
                "assistant_message_id": "msg_assistant_voice_001",
                "source_channel": "desktop_voice",
                "interaction_surface": "device_press",
                "capture_source": "desktop_mic",
            },
            session_key_override="app:main",
        )

        await self.service.on_inbound_published(msg)
        await self.service.on_task_started(msg=msg, session_key="app:main")
        await self.service.on_task_finished(
            msg=msg,
            session_key="app:main",
            response=None,
        )

        history = list(self.service.realtime_hub._event_history)
        user_events = [
            event
            for event in history
            if event["event_type"] in {
                "session.message.created",
                "session.message.completed",
            }
            and event["payload"]["message"]["message_id"] == "msg_user_voice_001"
        ]

        self.assertEqual(
            [event["event_type"] for event in user_events],
            ["session.message.created", "session.message.completed"],
        )
        self.assertEqual(user_events[0]["payload"]["message"]["status"], "pending")
        self.assertEqual(user_events[1]["payload"]["message"]["status"], "completed")
        self.assertEqual(user_events[1]["payload"]["message"]["content"], "W.")

    async def test_completed_session_message_event_keeps_source_metadata(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        await self.service.on_outbound_published(
            OutboundMessage(
                channel="device",
                chat_id="esp32",
                content="Done.",
                metadata={
                    "task_id": "task_123",
                    "assistant_message_id": "msg_assistant_123",
                    "app_session_id": "app:main",
                    "source_channel": "device",
                    "interaction_surface": "device_press",
                    "capture_source": "device_mic",
                    "reply_language": "Chinese",
                    "tool_results": {
                        "planning": [{"action": "create_task"}],
                    },
                },
            )
        )

        completed_events = [
            event for event in ws.sent if event["event_type"] == "session.message.completed"
        ]
        self.assertEqual(len(completed_events), 1)
        metadata = completed_events[0]["payload"]["message"]["metadata"]
        self.assertEqual(metadata["source_channel"], "device")
        self.assertEqual(metadata["interaction_surface"], "device_press")
        self.assertEqual(metadata["capture_source"], "device_mic")
        self.assertEqual(metadata["app_session_id"], "app:main")
        self.assertEqual(metadata["reply_language"], "Chinese")
        self.assertIn("tool_results", metadata)

    async def test_get_messages_preserves_persisted_source_metadata(self) -> None:
        session = self.sessions.get_or_create("app:main")
        session.metadata.update({
            "channel": "app",
            "title": "主对话",
            "pinned": True,
            "archived": False,
        })
        session.messages.append(
            {
                "role": "assistant",
                "content": "Handled from device context.",
                "timestamp": "2026-04-10T10:00:00+08:00",
                "message_id": "msg_assistant_1",
                "task_id": "task_1",
                "source_channel": "device",
                "interaction_surface": "device_press",
                "capture_source": "device_mic",
                "app_session_id": "app:main",
                "tool_results": {"planning": [{"action": "create_task"}]},
            }
        )
        self.sessions.save(session)

        response = await self.service.handle_get_messages(FakeRequest(
            headers=self.headers,
            match_info={"session_id": "app:main"},
        ))

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]["items"][0]["metadata"]
        self.assertEqual(payload["source_channel"], "device")
        self.assertEqual(payload["interaction_surface"], "device_press")
        self.assertEqual(payload["capture_source"], "device_mic")
        self.assertEqual(payload["app_session_id"], "app:main")
        self.assertIn("tool_results", payload)

    async def test_settings_get_put_and_test_routes(self) -> None:
        response = await self.service.handle_get_settings(FakeRequest(headers=self.headers))
        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)
        self.assertIn("llm_api_key_configured", payload["data"])
        self.assertNotIn("llm_api_key", payload["data"])
        self.assertIn("default_scene_mode", payload["data"])

        updated = await self.service.handle_put_settings(FakeRequest(
            headers=self.headers,
            json_body={
                "device_volume": 75,
                "led_mode": "breathing",
                "wake_word": "Hey Assistant",
                "default_scene_mode": "meeting",
                "persona_voice_style": "quiet",
                "physical_interaction_enabled": False,
                "llm_api_key": "secret-key",
            },
        ))
        self.assertEqual(updated.status, 200)
        updated_payload = json.loads(updated.text)
        self.assertEqual(updated_payload["data"]["settings"]["device_volume"], 75)
        self.assertTrue(updated_payload["data"]["settings"]["llm_api_key_configured"])
        self.assertEqual(updated_payload["data"]["settings"]["default_scene_mode"], "meeting")
        self.assertEqual(updated_payload["data"]["settings"]["persona_voice_style"], "quiet")
        self.assertFalse(updated_payload["data"]["settings"]["physical_interaction_enabled"])
        self.assertEqual(
            updated_payload["data"]["apply_results"]["device_volume"]["status"],
            "saved_only",
        )
        self.assertEqual(
            updated_payload["data"]["apply_results"]["device_volume"]["reason"],
            "device_offline",
        )
        self.assertEqual(
            updated_payload["data"]["apply_results"]["led_mode"]["status"],
            "saved_only",
        )
        self.assertEqual(
            updated_payload["data"]["apply_results"]["wake_word"]["mode"],
            "config_only",
        )
        self.assertEqual(
            updated_payload["data"]["apply_results"]["default_scene_mode"]["status"],
            "applied",
        )
        self.assertEqual(
            updated_payload["data"]["apply_results"]["physical_interaction_enabled"]["status"],
            "applied",
        )

        with patch.object(
            self.service.settings,
            "test_llm_connection",
            AsyncMock(return_value=(True, {
                "success": True,
                "provider": "openai",
                "model": "gpt-4o",
                "message": "connection ok",
            }, None)),
        ):
            tested = await self.service.handle_test_llm_settings(FakeRequest(
                headers=self.headers,
                json_body={},
            ))
        self.assertEqual(tested.status, 200)
        tested_payload = json.loads(tested.text)
        self.assertTrue(tested_payload["data"]["success"])

    async def test_put_settings_applies_device_volume_to_connected_device(self) -> None:
        self.device.connected = True
        self.device._snapshot["connected"] = True

        updated = await self.service.handle_put_settings(FakeRequest(
            headers=self.headers,
            json_body={
                "device_volume": 42,
                "led_enabled": False,
                "led_brightness": 33,
                "led_color": "#112233",
                "led_mode": "breathing",
                "auto_listen": True,
            },
        ))

        self.assertEqual(updated.status, 200)
        self.assertIsNotNone(self.device.last_command)
        updated_payload = json.loads(updated.text)["data"]
        self.assertEqual(updated_payload["apply_results"]["device_volume"]["status"], "pending")
        self.assertEqual(updated_payload["apply_results"]["led_enabled"]["status"], "pending")
        self.assertEqual(updated_payload["apply_results"]["led_brightness"]["status"], "pending")
        self.assertEqual(updated_payload["apply_results"]["led_color"]["status"], "saved_only")
        self.assertEqual(
            updated_payload["apply_results"]["led_color"]["reason"],
            "config_saved_but_not_runtime_applied",
        )
        self.assertEqual(updated_payload["apply_results"]["led_mode"]["status"], "saved_only")
        self.assertEqual(updated_payload["apply_results"]["auto_listen"]["mode"], "config_only")
        self.assertEqual(
            [item["command"] for item in self.device.command_history],
            ["set_volume", "toggle_led", "set_led_brightness"],
        )
        self.assertEqual(self.device.command_history[0]["params"]["level"], 42)
        self.assertEqual(self.device.command_history[1]["params"]["enabled"], False)
        self.assertEqual(self.device.command_history[2]["params"]["level"], 33)

    async def test_tasks_events_notifications_and_reminders_crud(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)

        created_task = await self.service.handle_create_task(FakeRequest(
            headers=self.headers,
            json_body={"title": "Review proposal", "priority": "high"},
        ))
        self.assertEqual(created_task.status, 201)
        task_payload = json.loads(created_task.text)["data"]
        task_id = task_payload["task_id"]
        self.assertEqual(ws.sent[-1]["event_type"], "task.created")

        filtered_tasks = await self.service.handle_list_tasks(FakeRequest(
            headers=self.headers,
            query={"completed": "false", "priority": "high", "limit": "10"},
        ))
        filtered_tasks_payload = json.loads(filtered_tasks.text)["data"]
        self.assertEqual([item["task_id"] for item in filtered_tasks_payload["items"]], [task_id])

        patched_task = await self.service.handle_patch_task(FakeRequest(
            headers=self.headers,
            match_info={"task_id": task_id},
            json_body={"completed": True},
        ))
        self.assertEqual(patched_task.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "task.updated")

        deleted_task = await self.service.handle_delete_task(FakeRequest(
            headers=self.headers,
            match_info={"task_id": task_id},
        ))
        self.assertEqual(deleted_task.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "task.deleted")

        created_event = await self.service.handle_create_event(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Team Standup",
                "start_at": "2026-04-02T09:00:00+08:00",
                "end_at": "2026-04-02T09:30:00+08:00",
            },
        ))
        self.assertEqual(created_event.status, 201)
        event_id = json.loads(created_event.text)["data"]["event_id"]
        self.assertEqual(ws.sent[-1]["event_type"], "event.created")

        patched_event = await self.service.handle_patch_event(FakeRequest(
            headers=self.headers,
            match_info={"event_id": event_id},
            json_body={"location": "Meeting Room A"},
        ))
        self.assertEqual(patched_event.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "event.updated")

        reminder = await self.service.handle_create_reminder(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Morning Standup",
                "time": "09:00",
                "repeat": "daily",
                "enabled": True,
            },
        ))
        self.assertEqual(reminder.status, 201)
        reminder_id = json.loads(reminder.text)["data"]["reminder_id"]
        self.assertEqual(ws.sent[-1]["event_type"], "reminder.created")

        reminder_list = await self.service.handle_list_reminders(FakeRequest(headers=self.headers))
        self.assertEqual(len(json.loads(reminder_list.text)["data"]["items"]), 1)

        self.service.resources.create_notification({
            "type": "task_due",
            "priority": "high",
            "title": "Task Due Soon",
            "message": "Review project proposal is due in 1 hour",
            "metadata": {"task_id": "task_001"},
        })
        notifications = await self.service.handle_list_notifications(FakeRequest(headers=self.headers))
        self.assertEqual(json.loads(notifications.text)["data"]["unread_count"], 1)

        notification_id = self.service.resources.list_notifications()["items"][0]["notification_id"]
        patched_notification = await self.service.handle_patch_notification(FakeRequest(
            headers=self.headers,
            match_info={"notification_id": notification_id},
            json_body={"read": True},
        ))
        self.assertEqual(patched_notification.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "notification.updated")

        cleared_notifications = await self.service.handle_read_all_notifications(FakeRequest(headers=self.headers))
        self.assertEqual(json.loads(cleared_notifications.text)["data"]["unread_count"], 0)

        deleted_event = await self.service.handle_delete_event(FakeRequest(
            headers=self.headers,
            match_info={"event_id": event_id},
        ))
        self.assertEqual(deleted_event.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "event.deleted")

        deleted_reminder = await self.service.handle_delete_reminder(FakeRequest(
            headers=self.headers,
            match_info={"reminder_id": reminder_id},
        ))
        self.assertEqual(deleted_reminder.status, 200)
        self.assertEqual(ws.sent[-1]["event_type"], "reminder.deleted")

    async def test_patch_reminder_rejects_runtime_action_fields(self) -> None:
        created = await self.service.handle_create_reminder(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Morning Standup",
                "time": "09:00",
                "repeat": "daily",
                "enabled": True,
            },
        ))
        reminder_id = json.loads(created.text)["data"]["reminder_id"]

        patched = await self.service.handle_patch_reminder(FakeRequest(
            headers=self.headers,
            match_info={"reminder_id": reminder_id},
            json_body={"status": "completed"},
        ))

        self.assertEqual(patched.status, 400)
        payload = json.loads(patched.text)
        self.assertEqual(payload["error"]["code"], "INVALID_ARGUMENT")

    async def test_create_reminder_rejects_invalid_repeat_value(self) -> None:
        created = await self.service.handle_create_reminder(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Morning Standup",
                "time": "09:00",
                "repeat": "monthly",
                "enabled": True,
            },
        ))

        self.assertEqual(created.status, 400)
        payload = json.loads(created.text)
        self.assertEqual(payload["error"]["code"], "INVALID_ARGUMENT")

    async def test_reminder_action_route_supports_snooze_and_complete(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)
        now = datetime.now().astimezone().replace(microsecond=0)
        reminder_time = (now + timedelta(hours=1)).isoformat()
        snooze_until = (now + timedelta(hours=1, minutes=30)).isoformat()

        created = await self.service.handle_create_reminder(FakeRequest(
            headers=self.headers,
            json_body={
                "title": "Morning Standup",
                "time": reminder_time,
                "repeat": "once",
                "enabled": True,
            },
        ))
        reminder_id = json.loads(created.text)["data"]["reminder_id"]

        snoozed = await self.service.handle_post_reminder_action(FakeRequest(
            headers=self.headers,
            match_info={"reminder_id": reminder_id},
            json_body={
                "action": "snooze",
                "until": snooze_until,
            },
        ))
        self.assertEqual(snoozed.status, 200)
        snoozed_payload = json.loads(snoozed.text)["data"]
        self.assertEqual(snoozed_payload["status"], "snoozed")
        self.assertEqual(snoozed_payload["snoozed_until"], snooze_until)
        self.assertEqual(ws.sent[-1]["event_type"], "reminder.updated")

        completed = await self.service.handle_post_reminder_action(FakeRequest(
            headers=self.headers,
            match_info={"reminder_id": reminder_id},
            json_body={"action": "complete"},
        ))
        self.assertEqual(completed.status, 200)
        completed_payload = json.loads(completed.text)["data"]
        self.assertEqual(completed_payload["status"], "completed")
        self.assertFalse(completed_payload["enabled"])
        self.assertEqual(ws.sent[-1]["event_type"], "reminder.updated")

    async def test_create_planning_bundle_creates_linked_resources(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)
        now = datetime.now().astimezone().replace(microsecond=0)
        event_start = (now + timedelta(hours=2)).isoformat()
        event_end = (now + timedelta(hours=3)).isoformat()
        reminder_time = (now + timedelta(hours=1, minutes=50)).isoformat()

        created = await self.service.handle_create_planning_bundle(FakeRequest(
            headers=self.headers,
            json_body={
                "created_via": "manual",
                "source_channel": "app",
                "source_message_id": "msg_local_001",
                "source_session_id": "app:main",
                "planning_surface": "tasks",
                "owner_kind": "assistant",
                "delivery_mode": "device_voice_and_notification",
                "tasks": [
                    {
                        "title": "Prepare agenda",
                        "priority": "high",
                    }
                ],
                "events": [
                    {
                        "title": "Planning",
                        "start_at": event_start,
                        "end_at": event_end,
                    }
                ],
                "reminders": [
                    {
                        "title": "Join room",
                        "time": reminder_time,
                        "repeat": "once",
                    }
                ],
            },
        ))

        self.assertEqual(created.status, 201)
        payload = json.loads(created.text)["data"]
        self.assertEqual(payload["counts"], {"tasks": 1, "events": 1, "reminders": 1, "notifications": 0})
        self.assertEqual(payload["tasks"][0]["created_via"], "manual")
        self.assertEqual(payload["tasks"][0]["planning_surface"], "tasks")
        self.assertEqual(payload["tasks"][0]["owner_kind"], "assistant")
        self.assertEqual(payload["tasks"][0]["delivery_mode"], "device_voice_and_notification")
        self.assertEqual(payload["events"][0]["planning_surface"], "tasks")
        self.assertEqual(payload["events"][0]["owner_kind"], "assistant")
        self.assertEqual(payload["events"][0]["delivery_mode"], "device_voice_and_notification")
        self.assertEqual(payload["reminders"][0]["planning_surface"], "tasks")
        self.assertEqual(payload["reminders"][0]["owner_kind"], "assistant")
        self.assertEqual(payload["reminders"][0]["delivery_mode"], "device_voice_and_notification")
        self.assertEqual(payload["events"][0]["linked_task_id"], payload["tasks"][0]["task_id"])
        self.assertEqual(payload["reminders"][0]["linked_event_id"], payload["events"][0]["event_id"])
        self.assertEqual(payload["reminders"][0]["status"], "scheduled")
        self.assertEqual(
            [event["event_type"] for event in ws.sent[-3:]],
            ["task.created", "event.created", "reminder.created"],
        )

    async def test_planning_timeline_supports_date_filter(self) -> None:
        self.service.resources.create_task({
            "title": "Today task",
            "priority": "high",
            "due_at": "2026-04-09T18:00:00+08:00",
        })
        self.service.resources.create_task({
            "title": "Tomorrow task",
            "priority": "medium",
            "due_at": "2026-04-10T10:00:00+08:00",
        })
        self.service.resources.create_event({
            "title": "Overnight shift",
            "start_at": "2026-04-08T23:00:00+08:00",
            "end_at": "2026-04-09T02:00:00+08:00",
        })
        reminder = self.service.resources.create_reminder({
            "title": "Today reminder",
            "time": "2026-04-09T11:00:00+08:00",
            "repeat": "once",
            "enabled": True,
        })
        await self.service.reminder_scheduler.sync_reminder(reminder["reminder_id"])
        await self.service.refresh_planning_state()

        filtered = await self.service.handle_planning_timeline(FakeRequest(
            headers=self.headers,
            query={"date": "2026-04-09"},
        ))

        self.assertEqual(filtered.status, 200)
        items = json.loads(filtered.text)["data"]["items"]
        self.assertEqual(
            [item["title"] for item in items],
            ["Overnight shift", "Today reminder", "Today task"],
        )

    async def test_planning_timeline_invalid_surface_query_falls_back_to_default_visibility(self) -> None:
        self.service.resources.create_task({
            "title": "AI follow-up",
            "priority": "medium",
            "due_at": "2026-04-09T18:00:00+08:00",
            "planning_surface": "tasks",
        })
        reminder = self.service.resources.create_reminder({
            "title": "Hidden delivery",
            "time": "2026-04-09T17:00:00+08:00",
            "repeat": "once",
            "planning_surface": "hidden",
            "enabled": True,
        })
        await self.service.reminder_scheduler.sync_reminder(reminder["reminder_id"])
        await self.service.refresh_planning_state()

        response = await self.service.handle_planning_timeline(FakeRequest(
            headers=self.headers,
            query={"surface": "not-a-surface"},
        ))

        self.assertEqual(response.status, 200)
        items = json.loads(response.text)["data"]["items"]
        self.assertEqual([item["title"] for item in items], ["AI follow-up"])

    async def test_planning_timeline_passes_surface_to_projection_when_supported(self) -> None:
        captured: dict[str, Any] = {}

        def fake_build_timeline(
            *,
            tasks: list[dict[str, Any]],
            events: list[dict[str, Any]],
            reminders: list[dict[str, Any]],
            target_date: str | None = None,
            surface: str | None = None,
        ) -> list[dict[str, Any]]:
            captured["target_date"] = target_date
            captured["surface"] = surface
            return [
                {"title": "Agenda lane", "surface": "agenda"},
                {"title": "Task lane", "surface": "tasks"},
            ] if surface is None else [
                item
                for item in [
                    {"title": "Agenda lane", "surface": "agenda"},
                    {"title": "Task lane", "surface": "tasks"},
                ]
                if item["surface"] == surface
            ]

        self.service.planning_projection_service.build_timeline = fake_build_timeline

        response = await self.service.handle_planning_timeline(FakeRequest(
            headers=self.headers,
            query={"date": "2026-04-09", "surface": "agenda"},
        ))

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]["items"]
        self.assertEqual([item["title"] for item in payload], ["Agenda lane"])
        self.assertEqual(captured, {"target_date": "2026-04-09", "surface": "agenda"})

    async def test_planning_timeline_surface_query_falls_back_for_legacy_projection(self) -> None:
        captured: dict[str, Any] = {}

        def fake_build_timeline(
            *,
            tasks: list[dict[str, Any]],
            events: list[dict[str, Any]],
            reminders: list[dict[str, Any]],
            target_date: str | None = None,
        ) -> list[dict[str, Any]]:
            captured["target_date"] = target_date
            return [{"title": "Legacy timeline"}]

        self.service.planning_projection_service.build_timeline = fake_build_timeline

        response = await self.service.handle_planning_timeline(FakeRequest(
            headers=self.headers,
            query={"date": "2026-04-09", "surface": "agenda"},
        ))

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]["items"]
        self.assertEqual(payload, [{"title": "Legacy timeline"}])
        self.assertEqual(captured, {"target_date": "2026-04-09"})

    async def test_reminder_triggered_delivers_device_voice_when_requested(self) -> None:
        ws = FakeWebSocket()
        await self.service.realtime_hub.attach_client(
            ws,
            last_event_id=None,
            replay_limit=0,
        )
        ws.sent.clear()
        self.device.connected = True
        self.device._snapshot["connected"] = True

        await self.service.on_reminder_triggered(
            reminder={
                "reminder_id": "rem_001",
                "title": "Stand up",
                "message": "",
                "delivery_mode": "device_voice_and_notification",
            },
            notification={
                "notification_id": "notif_001",
                "title": "Stand up",
                "message": "Stand up",
                "metadata": {"reminder_id": "rem_001"},
            },
        )
        await asyncio.sleep(0.05)

        self.assertEqual(self.device.delivered_voice_texts, ["Stand up"])
        self.assertEqual(
            [event["event_type"] for event in ws.sent[:3]],
            ["reminder.updated", "notification.created", "reminder.triggered"],
        )

    async def test_reminder_triggered_skips_device_voice_when_device_offline(self) -> None:
        ws = FakeWebSocket()
        await self.service.realtime_hub.attach_client(
            ws,
            last_event_id=None,
            replay_limit=0,
        )
        ws.sent.clear()

        await self.service.on_reminder_triggered(
            reminder={
                "reminder_id": "rem_002",
                "title": "Drink water",
                "message": "Drink water now",
            },
            notification={
                "notification_id": "notif_002",
                "title": "Drink water",
                "message": "Drink water now",
                "metadata": {
                    "reminder_id": "rem_002",
                    "delivery_mode": "device_voice",
                },
            },
        )
        await asyncio.sleep(0.05)

        self.assertEqual(self.device.delivered_voice_texts, [])
        self.assertEqual(
            [event["event_type"] for event in ws.sent[:3]],
            ["reminder.updated", "notification.created", "reminder.triggered"],
        )

    async def test_reminder_triggered_executes_scheduled_open_app_action(self) -> None:
        await self.service.on_reminder_triggered(
            reminder={
                "reminder_id": "rem_003",
                "title": "打开微信",
                "message": "时间到！帮你打开微信。",
                "scheduled_action_kind": "open_app",
                "scheduled_action_target": "微信",
                "source_channel": "desktop_voice",
                "source_session_id": "desktop_voice:desktop",
                "linked_task_id": "task_open_wechat",
                "bundle_id": "bundle_open_wechat",
            },
            notification={
                "notification_id": "notif_003",
                "title": "打开微信",
                "message": "时间到！帮你打开微信。",
                "metadata": {"reminder_id": "rem_003"},
            },
        )
        await asyncio.sleep(0.05)

        self.assertTrue(self.computer_adapter.calls)
        self.assertEqual(self.computer_adapter.calls[-1][0], "open_app")
        self.assertEqual(
            self.computer_adapter.calls[-1][1],
            {"app": "WeChat"},
        )
        recent_actions = self.computer_control.list_recent_actions()
        self.assertTrue(recent_actions)
        self.assertEqual(recent_actions[0]["kind"], "open_app")
        self.assertEqual(
            recent_actions[0]["metadata"]["linked_reminder_id"],
            "rem_003",
        )

    async def test_reminder_triggered_executes_scheduled_open_url_action(self) -> None:
        await self.service.on_reminder_triggered(
            reminder={
                "reminder_id": "rem_004",
                "title": "打开网页",
                "message": "时间到，打开网页。",
                "scheduled_action_kind": "open_url",
                "scheduled_action_target": "https://example.com",
            },
            notification={
                "notification_id": "notif_004",
                "title": "打开网页",
                "message": "时间到，打开网页。",
                "metadata": {"reminder_id": "rem_004"},
            },
        )
        await asyncio.sleep(0.05)

        self.assertTrue(self.computer_adapter.calls)
        self.assertEqual(self.computer_adapter.calls[-1][0], "open_url")
        self.assertEqual(
            self.computer_adapter.calls[-1][1],
            {"url": "https://example.com"},
        )

    async def test_device_pairing_bundle_requires_auth(self) -> None:
        response = await self.service.handle_device_pairing_bundle(FakeRequest(
            json_body={"host": "192.168.1.23"},
        ))

        self.assertEqual(response.status, 401)
        payload = json.loads(response.text)
        self.assertEqual(payload["error"]["code"], "UNAUTHORIZED")

    async def test_device_pairing_bundle_returns_serial_bundle(self) -> None:
        service = AppRuntimeService(
            {
                "app": {
                    "auth_token": "app-local-123",
                    "default_session_id": "app:main",
                },
                "server": {
                    "port": 8765,
                },
                "device": {
                    "auth_token": "device-local-123",
                },
                "computer_control": {
                    "enabled": True,
                    "allowed_apps": ["Safari"],
                },
            },
            bus=self.bus,
            sessions=self.sessions,
            device_channel=self.device,
            computer_control_service=self.computer_control,
            version="0.6.0",
            start_time=0,
        )

        response = await service.handle_device_pairing_bundle(FakeRequest(
            headers=self.headers,
            json_body={"host": "192.168.1.23"},
        ))

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]
        self.assertEqual(payload["transport"], "serial")
        self.assertEqual(
            payload["bundle"],
            {
                "server": {
                    "host": "192.168.1.23",
                    "port": 8765,
                    "path": "/ws/device",
                    "secure": False,
                },
                "auth": {
                    "device_token": "device-local-123",
                    "required": True,
                },
            },
        )

    async def test_device_pairing_bundle_rejects_unsuitable_hosts(self) -> None:
        for host in ("localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]", "example.com:8765"):
            response = await self.service.handle_device_pairing_bundle(FakeRequest(
                headers=self.headers,
                json_body={"host": host},
            ))

            self.assertEqual(response.status, 400, host)
            payload = json.loads(response.text)
            self.assertEqual(payload["error"]["code"], "INVALID_ARGUMENT")

    async def test_device_pairing_bundle_marks_device_auth_optional_when_token_missing(self) -> None:
        service = AppRuntimeService(
            {
                "app": {
                    "auth_token": "app-local-123",
                    "default_session_id": "app:main",
                },
                "server": {
                    "port": 8765,
                },
                "computer_control": {
                    "enabled": True,
                    "allowed_apps": ["Safari"],
                },
            },
            bus=self.bus,
            sessions=self.sessions,
            device_channel=self.device,
            computer_control_service=self.computer_control,
            version="0.6.0",
            start_time=0,
        )

        response = await service.handle_device_pairing_bundle(FakeRequest(
            headers=self.headers,
            json_body={"host": "192.168.1.23"},
        ))

        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)["data"]
        self.assertEqual(
            payload["bundle"]["auth"],
            {
                "device_token": "",
                "required": False,
            },
        )

    async def test_device_commands_route_handles_offline_and_success(self) -> None:
        offline = await self.service.handle_device_command(FakeRequest(
            headers=self.headers,
            json_body={"command": "set_volume", "params": {"level": 80}},
        ))
        self.assertEqual(offline.status, 409)

        self.device.connected = True
        self.device._snapshot["connected"] = True
        supported = await self.service.handle_device_command(FakeRequest(
            headers=self.headers,
            json_body={
                "client_command_id": "cmd_local_001",
                "command": "set_volume",
                "params": {"level": 80},
            },
        ))
        self.assertEqual(supported.status, 200)
        supported_payload = json.loads(supported.text)["data"]
        self.assertTrue(supported_payload["accepted"])
        self.assertEqual(supported_payload["status"], "pending")
        self.assertEqual(
            supported_payload["device"]["last_command"]["status"],
            "pending",
        )
        self.assertEqual(self.device.last_command["command"], "set_volume")

    async def test_device_command_update_event_exposes_snapshot(self) -> None:
        ws = FakeWebSocket()
        self.service._ws_clients.add(ws)
        self.device._snapshot["controls"]["volume"] = 80
        self.device._snapshot["last_command"] = {
            "command_id": "cmd_srv_001",
            "client_command_id": "cmd_local_001",
            "command": "set_volume",
            "status": "succeeded",
            "ok": True,
            "error": None,
            "updated_at": "2026-04-10T09:43:00+08:00",
        }

        await self.service.on_device_command_updated(
            result={
                "command_id": "cmd_srv_001",
                "client_command_id": "cmd_local_001",
                "command": "set_volume",
                "ok": True,
                "error": None,
                "status": "succeeded",
                "applied_state": {"volume": 80},
            },
            snapshot=self.device.get_snapshot(),
        )

        self.assertEqual(ws.sent[-1]["event_type"], "device.command.updated")
        self.assertEqual(
            ws.sent[-1]["payload"]["device"]["controls"]["volume"],
            80,
        )
