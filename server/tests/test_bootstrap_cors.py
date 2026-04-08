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


class DummyBus:
    def add_observer(self, observer) -> None:
        self.observer = observer


class DummyAgent:
    def __init__(self) -> None:
        self.sessions = object()
        self.task_observer = None


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
