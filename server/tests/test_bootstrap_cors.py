from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

from aiohttp import web


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bootstrap import _CORS_ALLOW_HEADERS, _CORS_ALLOW_METHODS, create_http_app
from nanobot.agent.tools.registry import ToolRegistry


class DummyBus:
    def add_observer(self, observer) -> None:
        self.observer = observer


class DummyAgent:
    def __init__(self) -> None:
        self.sessions = object()
        self.task_observer = None


class DummyAgentWithTools(DummyAgent):
    def __init__(self) -> None:
        super().__init__()
        self.tools = ToolRegistry()
        self.computer_control_backend = None


class FakeComputerControlService:
    def __init__(self) -> None:
        self.event_callback = None

    def set_event_callback(self, callback) -> None:
        self.event_callback = callback

    def supported_actions(self) -> list[str]:
        return ["open_app"]

    def is_available(self) -> bool:
        return True

    def get_state(self) -> dict[str, object]:
        return {
            "available": True,
            "supported_actions": ["open_app"],
            "pending_actions": [],
            "recent_actions": [],
            "permission_hints": [],
        }


class DummyDeviceChannel:
    connected = False

    def __init__(self) -> None:
        self.asr = None
        self.tts = None
        self._observer = None

    def get_snapshot(self) -> dict[str, object]:
        return {
            "connected": False,
            "state": "IDLE",
        }

    def register_routes(self, app: web.Application) -> None:
        app.router.add_get("/ws/device", self._handle_ws)

    def set_event_observer(self, observer) -> None:
        self._observer = observer

    def set_active_app_session_resolver(self, resolver) -> None:
        self._resolver = resolver

    async def _handle_ws(self, request: web.Request) -> web.Response:
        return web.Response(status=200)


class BootstrapCorsTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.app = create_http_app(
            {"app": {}},
            DummyBus(),
            DummyAgent(),
            DummyDeviceChannel(),
            start_time=0,
        )
        self.middleware = self.app.middlewares[0]

    async def test_preflight_requests_return_cors_headers(self) -> None:
        request = SimpleNamespace(method="OPTIONS")

        async def handler(_request) -> web.Response:
            raise AssertionError("OPTIONS should be handled by middleware")

        response = await self.middleware(request, handler)

        self.assertEqual(response.status, 204)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], "*")
        self.assertEqual(
            response.headers["Access-Control-Allow-Headers"],
            _CORS_ALLOW_HEADERS,
        )
        self.assertEqual(
            response.headers["Access-Control-Allow-Methods"],
            _CORS_ALLOW_METHODS,
        )

    async def test_normal_responses_also_include_cors_headers(self) -> None:
        request = SimpleNamespace(method="GET")

        async def handler(_request) -> web.Response:
            return web.json_response({"ok": True})

        response = await self.middleware(request, handler)

        self.assertEqual(response.status, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], "*")

    async def test_create_http_app_registers_computer_control_tool_when_service_is_present(self) -> None:
        agent = DummyAgentWithTools()
        service = FakeComputerControlService()

        app = create_http_app(
            {"app": {}},
            DummyBus(),
            agent,
            DummyDeviceChannel(),
            start_time=0,
            computer_control_service=service,
        )

        self.assertTrue(agent.tools.has("computer_control"))
        self.assertIs(agent.computer_control_backend, service)
        self.assertIs(app["computer_control_service"], service)
