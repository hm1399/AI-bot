from __future__ import annotations

"""Async message queue for decoupled channel-agent communication."""

import asyncio
from collections import deque
from dataclasses import asdict, dataclass
from typing import Any, Generic, TypeVar

from loguru import logger

from nanobot.bus.events import InboundMessage, OutboundMessage

T = TypeVar("T", InboundMessage, OutboundMessage)

_CONTROL_COMMANDS = {"/stop", "/cancel", "/abort"}
_PRIORITY_MARKERS = {"control", "critical", "high", "priority", "reserved"}


@dataclass(frozen=True)
class QueueDepthSnapshot:
    maxsize: int
    reserved_slots: int
    depth: int
    normal_depth: int
    reserved_depth: int
    published_total: int
    priority_published_total: int
    consumed_total: int
    rejected_total: int


class MessageBusQueueFullError(asyncio.QueueFull):
    """Raised when a bounded message bus queue is saturated."""

    def __init__(
        self,
        direction: str,
        *,
        priority: bool,
        snapshot: QueueDepthSnapshot,
    ) -> None:
        self.direction = direction
        self.priority = priority
        self.snapshot = snapshot
        lane = "reserved" if priority else "normal"
        super().__init__(
            f"MessageBus {direction} queue is full for {lane} traffic "
            f"(depth={snapshot.depth}/{snapshot.maxsize})"
        )


class _ReservedAsyncQueue(Generic[T]):
    def __init__(self, name: str, *, maxsize: int, reserved_slots: int) -> None:
        if maxsize <= 0:
            raise ValueError(f"{name} maxsize must be > 0")

        if maxsize == 1:
            normalized_reserved = 1
        else:
            normalized_reserved = max(1, min(reserved_slots, maxsize - 1))
        self.name = name
        self.maxsize = maxsize
        self.reserved_slots = normalized_reserved
        self.normal_capacity = max(0, maxsize - normalized_reserved)
        self._reserved: deque[T] = deque()
        self._normal: deque[T] = deque()
        self._condition = asyncio.Condition()
        self._published_total = 0
        self._priority_published_total = 0
        self._consumed_total = 0
        self._rejected_total = 0

    async def publish(self, item: T, *, priority: bool) -> None:
        async with self._condition:
            accepted = False
            if priority:
                if len(self._reserved) < self.reserved_slots:
                    self._reserved.append(item)
                    accepted = True
                elif len(self._normal) < self.normal_capacity:
                    self._normal.append(item)
                    accepted = True
            elif len(self._normal) < self.normal_capacity:
                self._normal.append(item)
                accepted = True

            if not accepted:
                self._rejected_total += 1
                raise MessageBusQueueFullError(
                    self.name,
                    priority=priority,
                    snapshot=self.snapshot(),
                )

            self._published_total += 1
            if priority:
                self._priority_published_total += 1
            self._condition.notify(1)

    async def consume(self) -> T:
        async with self._condition:
            while not self._reserved and not self._normal:
                await self._condition.wait()

            if self._reserved:
                item = self._reserved.popleft()
            else:
                item = self._normal.popleft()

            self._consumed_total += 1
            return item

    def qsize(self) -> int:
        return len(self._reserved) + len(self._normal)

    def snapshot(self) -> QueueDepthSnapshot:
        return QueueDepthSnapshot(
            maxsize=self.maxsize,
            reserved_slots=self.reserved_slots,
            depth=self.qsize(),
            normal_depth=len(self._normal),
            reserved_depth=len(self._reserved),
            published_total=self._published_total,
            priority_published_total=self._priority_published_total,
            consumed_total=self._consumed_total,
            rejected_total=self._rejected_total,
        )


@dataclass
class _ObserverState:
    queue: asyncio.Queue[tuple[str, InboundMessage | OutboundMessage]]
    task: asyncio.Task[None] | None = None
    enqueued_total: int = 0
    delivered_total: int = 0
    failed_total: int = 0


class MessageBus:
    """
    Async message bus that decouples chat channels from the agent core.

    Channels push messages to the inbound queue, and the agent processes
    them and pushes responses to the outbound queue.
    """

    def __init__(
        self,
        *,
        inbound_maxsize: int = 128,
        outbound_maxsize: int = 128,
        inbound_reserved_slots: int = 8,
        outbound_reserved_slots: int = 8,
    ) -> None:
        self._inbound = _ReservedAsyncQueue[InboundMessage](
            "inbound",
            maxsize=inbound_maxsize,
            reserved_slots=inbound_reserved_slots,
        )
        self._outbound = _ReservedAsyncQueue[OutboundMessage](
            "outbound",
            maxsize=outbound_maxsize,
            reserved_slots=outbound_reserved_slots,
        )
        self._observers: list[Any] = []
        self._observer_states: dict[Any, _ObserverState] = {}

    def add_observer(self, observer: Any) -> None:
        """Register an observer for inbound/outbound publish events."""
        if observer in self._observers:
            return
        self._observers.append(observer)
        self._observer_states[observer] = _ObserverState(queue=asyncio.Queue())

    def _ensure_observer_worker(self, observer: Any, state: _ObserverState) -> None:
        if state.task is not None and not state.task.done():
            return
        state.task = asyncio.create_task(
            self._drain_observer(observer, state),
            name=f"message-bus-observer:{type(observer).__name__}",
        )

    async def _drain_observer(self, observer: Any, state: _ObserverState) -> None:
        while True:
            method_name, msg = await state.queue.get()
            callback = getattr(observer, method_name, None)
            if callback is None:
                continue
            try:
                await callback(msg)
                state.delivered_total += 1
            except asyncio.CancelledError:
                raise
            except Exception:
                state.failed_total += 1
                logger.exception("MessageBus observer {} failed", method_name)

    def _schedule_notify(
        self,
        method_name: str,
        msg: InboundMessage | OutboundMessage,
    ) -> None:
        for observer in tuple(self._observers):
            callback = getattr(observer, method_name, None)
            if callback is None:
                continue
            state = self._observer_states.setdefault(
                observer,
                _ObserverState(queue=asyncio.Queue()),
            )
            state.queue.put_nowait((method_name, msg))
            state.enqueued_total += 1
            self._ensure_observer_worker(observer, state)

    @staticmethod
    def _metadata_requests_reserved_lane(metadata: dict[str, Any]) -> bool:
        if metadata.get("_bus_control") is True:
            return True

        raw_priority = (
            metadata.get("_bus_priority")
            or metadata.get("_queue_priority")
            or metadata.get("_transport_priority")
            or metadata.get("_lane_priority")
        )
        priority = str(raw_priority or "").strip().lower()
        return priority in _PRIORITY_MARKERS

    def _is_reserved_inbound(self, msg: InboundMessage) -> bool:
        if self._metadata_requests_reserved_lane(msg.metadata):
            return True
        content = msg.content.strip().lower()
        return content in _CONTROL_COMMANDS

    def _is_reserved_outbound(self, msg: OutboundMessage) -> bool:
        if self._metadata_requests_reserved_lane(msg.metadata):
            return True

        content = msg.content.strip().lower()
        return content.startswith("⏹ stopped ") or content == "no active task to stop."

    async def publish_inbound(self, msg: InboundMessage) -> None:
        """Publish a message from a channel to the agent."""
        await self._inbound.publish(msg, priority=self._is_reserved_inbound(msg))
        self._schedule_notify("on_inbound_published", msg)

    async def consume_inbound(self) -> InboundMessage:
        """Consume the next inbound message (blocks until available)."""
        return await self._inbound.consume()

    async def publish_outbound(self, msg: OutboundMessage) -> None:
        """Publish a response from the agent to channels."""
        await self._outbound.publish(msg, priority=self._is_reserved_outbound(msg))
        self._schedule_notify("on_outbound_published", msg)

    async def consume_outbound(self) -> OutboundMessage:
        """Consume the next outbound message (blocks until available)."""
        return await self._outbound.consume()

    @property
    def inbound_size(self) -> int:
        """Number of pending inbound messages."""
        return self._inbound.qsize()

    @property
    def outbound_size(self) -> int:
        """Number of pending outbound messages."""
        return self._outbound.qsize()

    def inbound_depth_snapshot(self) -> dict[str, int]:
        return asdict(self._inbound.snapshot())

    def outbound_depth_snapshot(self) -> dict[str, int]:
        return asdict(self._outbound.snapshot())

    def observer_snapshot(self) -> dict[str, int]:
        pending = sum(state.queue.qsize() for state in self._observer_states.values())
        workers = sum(
            1
            for state in self._observer_states.values()
            if state.task is not None and not state.task.done()
        )
        return {
            "observer_count": len(self._observer_states),
            "worker_count": workers,
            "pending_notifications": pending,
            "enqueued_total": sum(state.enqueued_total for state in self._observer_states.values()),
            "delivered_total": sum(state.delivered_total for state in self._observer_states.values()),
            "failed_total": sum(state.failed_total for state in self._observer_states.values()),
        }

    def metrics_snapshot(self) -> dict[str, dict[str, int]]:
        return {
            "inbound": self.inbound_depth_snapshot(),
            "outbound": self.outbound_depth_snapshot(),
            "observers": self.observer_snapshot(),
        }
