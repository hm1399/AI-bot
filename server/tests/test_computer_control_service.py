from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.storage.sqlite_documents import resolve_state_db_path
from services.computer_control import ComputerControlError, ComputerControlService


class FakeMacOSAdapter:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, object]]] = []

    async def open_app(self, *, app: str) -> dict[str, object]:
        self.calls.append(("open_app", {"app": app}))
        return {"opened": app}

    async def open_path(self, *, path: str) -> dict[str, object]:
        self.calls.append(("open_path", {"path": path}))
        return {"opened_path": path}

    async def run_script(
        self,
        *,
        script_id: str,
        command: list[str],
        cwd: str | None = None,
    ) -> dict[str, object]:
        self.calls.append((
            "run_script",
            {
                "script_id": script_id,
                "command": list(command),
                "cwd": cwd,
            },
        ))
        return {"script_id": script_id, "stdout": "ok"}

    async def system_info(self, *, profile: str) -> dict[str, object]:
        self.calls.append(("system_info", {"profile": profile}))
        return {"profile": profile, "value": "ready"}


class FakeWeChatAdapter:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, object]]] = []

    async def prepare_message(
        self,
        *,
        contact_alias: str,
        message: str,
        experimental_ui: bool = False,
    ) -> dict[str, object]:
        self.calls.append((
            "prepare_message",
            {
                "contact_alias": contact_alias,
                "message": message,
                "experimental_ui": experimental_ui,
            },
        ))
        return {
            "delivery_mode": "manual_step_required",
            "send_available": False,
            "manual_steps": [
                "Open WeChat and locate the contact manually.",
                "Paste the copied draft and confirm before sending.",
            ],
        }

    async def send_prepared_message(
        self,
        *,
        prepared_action_id: str,
    ) -> dict[str, object]:
        self.calls.append((
            "send_prepared_message",
            {"prepared_action_id": prepared_action_id},
        ))
        raise ComputerControlError(
            code="adapter_unavailable",
            message="wechat send automation is not available in this build",
            status=409,
        )


class ComputerControlServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.runtime_dir = Path(self.tmpdir.name)

    async def asyncTearDown(self) -> None:
        self.tmpdir.cleanup()

    def _service(
        self,
        *,
        config: dict | None = None,
        adapter: FakeMacOSAdapter | None = None,
        wechat_adapter: FakeWeChatAdapter | None = None,
    ) -> ComputerControlService:
        default_config = {
            "computer_control": {
                "enabled": True,
                "allowed_apps": ["Safari", "WeChat"],
                "allowed_shortcuts": ["daily-brief"],
                "allowed_scripts": {
                    "project-healthcheck": {
                        "command": ["/bin/echo", "ok"],
                    }
                },
                "allowed_path_roots": [self.tmpdir.name],
                "confirm_medium_risk": False,
                "wechat": {
                    "enabled": True,
                    "experimental_ui": False,
                    "allowed_contacts": ["Alice"],
                },
            }
        }
        if config:
            default_config["computer_control"].update(config.get("computer_control", {}))
        return ComputerControlService(
            default_config,
            runtime_dir=self.runtime_dir,
            adapter=adapter or FakeMacOSAdapter(),
            wechat_adapter=wechat_adapter or FakeWeChatAdapter(),
        )

    async def test_request_action_executes_allowed_app_and_persists_recent_action(self) -> None:
        adapter = FakeMacOSAdapter()
        service = self._service(adapter=adapter)

        action = await service.request_action(
            kind="open_app",
            arguments={"app": "Safari"},
            requested_via="app",
            source_session_id="app:main",
        )

        self.assertEqual(action["kind"], "open_app")
        self.assertEqual(action["status"], "completed")
        self.assertEqual(action["risk_level"], "low")
        self.assertFalse(action["requires_confirmation"])
        self.assertEqual(action["result"]["opened"], "Safari")
        self.assertEqual(adapter.calls[0][0], "open_app")

        state = service.get_state()
        self.assertTrue(state["available"])
        self.assertIn("open_app", state["supported_actions"])
        self.assertEqual(state["pending_actions"], [])
        self.assertEqual(len(state["recent_actions"]), 1)
        self.assertEqual(state["recent_actions"][0]["action_id"], action["action_id"])

    async def test_request_action_requires_confirmation_and_supports_confirm_and_cancel(self) -> None:
        adapter = FakeMacOSAdapter()
        service = self._service(
            config={"computer_control": {"confirm_medium_risk": True}},
            adapter=adapter,
        )

        awaiting = await service.request_action(
            kind="run_script",
            arguments={"script_id": "project-healthcheck"},
            requested_via="app",
            source_session_id="app:main",
        )
        self.assertEqual(awaiting["status"], "awaiting_confirmation")
        self.assertTrue(awaiting["requires_confirmation"])
        self.assertEqual(len(service.list_pending_actions()), 1)

        confirmed = await service.confirm_action(awaiting["action_id"])
        self.assertEqual(confirmed["status"], "completed")
        self.assertEqual(confirmed["result"]["script_id"], "project-healthcheck")
        self.assertEqual(adapter.calls[0][0], "run_script")
        self.assertEqual(service.list_pending_actions(), [])

        other = await service.request_action(
            kind="run_script",
            arguments={"script_id": "project-healthcheck"},
            requested_via="app",
            source_session_id="app:main",
            requires_confirmation=True,
        )
        self.assertEqual(other["status"], "awaiting_confirmation")

        cancelled = await service.cancel_action(other["action_id"])
        self.assertEqual(cancelled["status"], "cancelled")
        self.assertEqual(service.list_pending_actions(), [])

    async def test_policy_rejects_disallowed_targets_and_invalid_profiles(self) -> None:
        service = self._service()
        blocked_path = Path(self.tmpdir.name).parent / "blocked.txt"
        blocked_path.write_text("nope", encoding="utf-8")

        with self.assertRaises(ComputerControlError) as blocked_app:
            await service.request_action(
                kind="open_app",
                arguments={"app": "Terminal"},
                requested_via="app",
            )
        self.assertEqual(blocked_app.exception.code, "target_not_allowed")

        with self.assertRaises(ComputerControlError) as blocked_path_error:
            await service.request_action(
                kind="open_path",
                arguments={"path": str(blocked_path)},
                requested_via="app",
            )
        self.assertEqual(blocked_path_error.exception.code, "target_not_allowed")

        with self.assertRaises(ComputerControlError) as invalid_profile:
            await service.request_action(
                kind="system_info",
                arguments={"profile": "everything"},
                requested_via="app",
            )
        self.assertEqual(invalid_profile.exception.code, "invalid_argument")

    async def test_wechat_prepare_message_uses_manual_step_semantics(self) -> None:
        wechat_adapter = FakeWeChatAdapter()
        service = self._service(wechat_adapter=wechat_adapter)

        action = await service.request_action(
            kind="wechat_prepare_message",
            arguments={
                "contact_alias": "Alice",
                "message": "I will be late tonight.",
            },
            requested_via="app",
            source_session_id="app:main",
        )

        self.assertEqual(action["status"], "completed")
        self.assertEqual(action["result"]["delivery_mode"], "manual_step_required")
        self.assertFalse(action["result"]["send_available"])
        self.assertGreaterEqual(len(action["result"]["manual_steps"]), 1)
        self.assertEqual(wechat_adapter.calls[0][0], "prepare_message")
        self.assertTrue(resolve_state_db_path(self.runtime_dir).exists())
