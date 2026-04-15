from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Awaitable, Callable

from loguru import logger

from services.outbound_lanes import LaneFullError, SerialDispatchLane

_DEFAULT_DROPPABLE_EVENT_TYPES = {
    "runtime.task.current_changed",
    "runtime.task.queue_changed",
    "device.state.changed",
    "desktop_voice.state.changed",
}


def app_event_is_droppable(
    event: dict[str, Any],
    *,
    droppable_event_types: set[str] | None = None,
) -> bool:
    if event.get("_fanout_drop_ok") is True:
        return True

    event_type = str(event.get("event_type") or "").strip()
    if not event_type:
        return False
    allowed = droppable_event_types or _DEFAULT_DROPPABLE_EVENT_TYPES
    return event_type in allowed


@dataclass(frozen=True)
class FanoutResult:
    client_count: int
    accepted: int
    dropped: int
    rejected: int


@dataclass
class _FanoutClient:
    sender: Callable[[dict[str, Any]], Awaitable[None]]
    lane: SerialDispatchLane[dict[str, Any]]


class AppEventFanout:
    """Generic per-client queue + writer helper for App websocket fanout."""

    def __init__(
        self,
        *,
        per_client_maxsize: int = 64,
        droppable_event_types: set[str] | None = None,
    ) -> None:
        self._per_client_maxsize = per_client_maxsize
        self._droppable_event_types = (
            set(droppable_event_types)
            if droppable_event_types is not None
            else set(_DEFAULT_DROPPABLE_EVENT_TYPES)
        )
        self._clients: dict[Any, _FanoutClient] = {}
        self._fanout_calls = 0
        self._accepted_total = 0
        self._dropped_total = 0
        self._rejected_total = 0

    def register_client(
        self,
        client: Any,
        *,
        sender: Callable[[dict[str, Any]], Awaitable[None]] | None = None,
    ) -> None:
        if client in self._clients:
            return

        resolved_sender = sender
        if resolved_sender is None:
            send_json = getattr(client, "send_json", None)
            if send_json is None:
                raise ValueError("client must provide send_json() or an explicit sender")
            resolved_sender = send_json

        lane = SerialDispatchLane[dict[str, Any]](
            f"app-event-client:{id(client)}",
            resolved_sender,
            maxsize=self._per_client_maxsize,
            drop_predicate=lambda event: app_event_is_droppable(
                event,
                droppable_event_types=self._droppable_event_types,
            ),
        )
        lane.start()
        self._clients[client] = _FanoutClient(sender=resolved_sender, lane=lane)

    async def unregister_client(self, client: Any, *, drain: bool = False) -> None:
        registration = self._clients.pop(client, None)
        if registration is None:
            return
        await registration.lane.close(drain=drain)

    async def close(self, *, drain: bool = False) -> None:
        for client in list(self._clients):
            await self.unregister_client(client, drain=drain)

    async def fanout(self, event: dict[str, Any]) -> FanoutResult:
        self._fanout_calls += 1
        accepted = 0
        dropped = 0
        rejected = 0
        stale_clients: list[Any] = []

        for client, registration in tuple(self._clients.items()):
            if bool(getattr(client, "closed", False)):
                stale_clients.append(client)
                continue

            try:
                queued = await registration.lane.submit(dict(event))
            except LaneFullError:
                rejected += 1
                logger.warning("App event client lane {} is full", id(client))
            except Exception:
                rejected += 1
                logger.exception("App event fanout enqueue failed for client {}", id(client))
            else:
                if queued:
                    accepted += 1
                else:
                    dropped += 1

        for client in stale_clients:
            await self.unregister_client(client)

        self._accepted_total += accepted
        self._dropped_total += dropped
        self._rejected_total += rejected
        return FanoutResult(
            client_count=len(self._clients),
            accepted=accepted,
            dropped=dropped,
            rejected=rejected,
        )

    def snapshot(self) -> dict[str, Any]:
        return {
            "client_count": len(self._clients),
            "fanout_calls": self._fanout_calls,
            "accepted_total": self._accepted_total,
            "dropped_total": self._dropped_total,
            "rejected_total": self._rejected_total,
            "clients": {
                str(id(client)): asdict(registration.lane.snapshot())
                for client, registration in self._clients.items()
            },
        }
