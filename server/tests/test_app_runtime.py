from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.session.manager import SessionManager
from services.app_runtime import AppRuntimeService


class DummyDeviceChannel:
    def __init__(self) -> None:
        self.connected = False
        self.asr = object()
        self.tts = object()
        self._snapshot = {
            "connected": False,
            "state": "IDLE",
            "battery": -1,
            "wifi_rssi": 0,
            "charging": False,
            "reconnect_count": 0,
        }
        self.last_outbound: OutboundMessage | None = None
        self.last_command: dict[str, Any] | None = None

    def get_snapshot(self) -> dict[str, Any]:
        return dict(self._snapshot)

    async def send_outbound(self, out_msg: OutboundMessage) -> None:
        self.last_outbound = out_msg

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
        return {
            "accepted": True,
            "command_id": "cmd_srv_001",
            "command": command,
            "device": self.get_snapshot(),
        }


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
        self.service = AppRuntimeService(
            {
                "app": {
                    "auth_token": "app-local-123",
                    "default_session_id": "app:main",
                },
                "whatsapp": {"enabled": True},
            },
            bus=self.bus,
            sessions=self.sessions,
            device_channel=self.device,
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
        self.assertEqual(
            payload["data"]["planning"]["overview_path"],
            "/api/app/v1/planning/overview",
        )
        self.assertTrue(payload["data"]["runtime"]["planning"]["available"])

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
        self.assertIsNone(runtime["current_task"])
        self.assertEqual(len(runtime["task_queue"]), 1)
        self.assertEqual(runtime["task_queue"][0]["task_id"], task_id)

    async def test_runtime_state_exposes_planning_runtime_flags(self) -> None:
        runtime = await self.service.get_runtime_state()
        self.assertIn("planning", runtime)
        self.assertTrue(runtime["planning"]["available"])
        self.assertTrue(runtime["planning"]["overview_ready"])
        self.assertTrue(runtime["planning"]["timeline_ready"])
        self.assertTrue(runtime["planning"]["conflicts_ready"])

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

    async def test_settings_get_put_and_test_routes(self) -> None:
        response = await self.service.handle_get_settings(FakeRequest(headers=self.headers))
        self.assertEqual(response.status, 200)
        payload = json.loads(response.text)
        self.assertIn("llm_api_key_configured", payload["data"])
        self.assertNotIn("llm_api_key", payload["data"])

        updated = await self.service.handle_put_settings(FakeRequest(
            headers=self.headers,
            json_body={
                "device_volume": 75,
                "wake_word": "Hey Assistant",
                "llm_api_key": "secret-key",
            },
        ))
        self.assertEqual(updated.status, 200)
        updated_payload = json.loads(updated.text)
        self.assertEqual(updated_payload["data"]["device_volume"], 75)
        self.assertTrue(updated_payload["data"]["llm_api_key_configured"])

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
        self.assertEqual(self.device.last_command["command"], "set_volume")
