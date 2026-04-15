from __future__ import annotations

from collections import deque
from typing import Any, Callable

from aiohttp import web

from services.app_event_fanout import AppEventFanout


class AppRealtimeHub:
    """Owns app event history, replay, and websocket fanout isolation."""

    def __init__(
        self,
        *,
        version: str,
        buffer_size: int,
        per_client_maxsize: int,
        now_iso: Callable[[], str],
        new_id: Callable[[str], str],
    ) -> None:
        self.version = version
        self._now_iso = now_iso
        self._new_id = new_id
        self._event_history: deque[dict[str, Any]] = deque(maxlen=buffer_size)
        self._ws_clients: set[web.WebSocketResponse] = set()
        self._event_fanout = AppEventFanout(
            per_client_maxsize=per_client_maxsize,
        )
        self._slow_client_drops = 0

    async def close(self) -> None:
        await self._event_fanout.close()

    async def attach_client(
        self,
        ws: web.WebSocketResponse,
        *,
        last_event_id: str | None,
        replay_limit: int,
    ) -> None:
        hello_payload, replay_events = self.build_replay_payload(
            last_event_id=last_event_id,
            replay_limit=replay_limit,
        )
        await self.broadcast_direct(
            ws,
            "system.hello",
            payload=hello_payload,
            scope="global",
        )
        for event in replay_events:
            await ws.send_json(event)
        self._ws_clients.add(ws)
        self._event_fanout.register_client(ws)

    async def detach_client(self, ws: web.WebSocketResponse) -> None:
        self._ws_clients.discard(ws)
        await self._event_fanout.unregister_client(ws)

    async def broadcast(
        self,
        event_type: str,
        *,
        payload: dict[str, Any],
        scope: str,
        session_id: str | None = None,
        task_id: str | None = None,
    ) -> None:
        event = self.make_event(
            event_type=event_type,
            payload=payload,
            scope=scope,
            session_id=session_id,
            task_id=task_id,
        )
        self._event_history.append(event)

        if not self._ws_clients:
            return

        result = await self._event_fanout.fanout(event)
        self._slow_client_drops = result.dropped + result.rejected

    async def broadcast_direct(
        self,
        ws: web.WebSocketResponse,
        event_type: str,
        *,
        payload: dict[str, Any],
        scope: str,
    ) -> None:
        await ws.send_json(
            {
                "event_id": self._new_id("evt"),
                "event_type": event_type,
                "scope": scope,
                "occurred_at": self._now_iso(),
                "session_id": None,
                "task_id": None,
                "payload": payload,
            }
        )

    def build_replay_payload(
        self,
        *,
        last_event_id: str | None,
        replay_limit: int,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        history = list(self._event_history)
        latest_event_id = history[-1]["event_id"] if history else None
        resume = {
            "requested": bool(last_event_id),
            "accepted": False,
            "replayed_count": 0,
            "replay_limit": replay_limit,
            "latest_event_id": latest_event_id,
            "history_size": len(history),
            "should_refetch_bootstrap": False,
            "reason": None,
        }

        replay_events: list[dict[str, Any]] = []
        if last_event_id:
            matched_index = next(
                (
                    index
                    for index, event in enumerate(history)
                    if event["event_id"] == last_event_id
                ),
                None,
            )
            if matched_index is None:
                resume["should_refetch_bootstrap"] = True
                resume["reason"] = "last_event_id_not_found"
            else:
                missed_events = history[matched_index + 1 :]
                if len(missed_events) > replay_limit:
                    resume["should_refetch_bootstrap"] = True
                    resume["reason"] = "replay_limit_exceeded"
                else:
                    replay_events = missed_events
                    resume["accepted"] = True
                    resume["replayed_count"] = len(replay_events)

        hello_payload = {
            "server_version": self.version,
            "protocol_version": "app-v1",
            "ts": self._now_iso(),
            "resume": resume,
        }
        return hello_payload, replay_events

    def make_event(
        self,
        *,
        event_type: str,
        payload: dict[str, Any],
        scope: str,
        session_id: str | None = None,
        task_id: str | None = None,
    ) -> dict[str, Any]:
        return {
            "event_id": self._new_id("evt"),
            "event_type": event_type,
            "scope": scope,
            "occurred_at": self._now_iso(),
            "session_id": session_id,
            "task_id": task_id,
            "payload": payload,
        }

    def latest_event_id(self) -> str | None:
        return self._event_history[-1]["event_id"] if self._event_history else None

    def snapshot(self) -> dict[str, Any]:
        fanout_snapshot = self._event_fanout.snapshot()
        return {
            "app_event_fanout": fanout_snapshot,
            "ws_client_count": int(
                fanout_snapshot.get("client_count", len(self._ws_clients)) or 0
            ),
            "slow_client_drops": self._slow_client_drops,
            "history_size": len(self._event_history),
        }
