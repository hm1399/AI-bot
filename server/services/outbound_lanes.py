from __future__ import annotations

import asyncio
from collections import deque
from dataclasses import asdict, dataclass
from typing import Any, Awaitable, Callable, Generic, Mapping, TypeVar

from loguru import logger

from nanobot.bus.events import OutboundMessage

ItemT = TypeVar("ItemT")


@dataclass(frozen=True)
class LaneSnapshot:
    name: str
    maxsize: int
    depth: int
    running: bool
    enqueued_total: int
    dispatched_total: int
    dropped_total: int
    rejected_total: int
    failed_total: int


class LaneFullError(asyncio.QueueFull):
    def __init__(self, lane_name: str, *, snapshot: LaneSnapshot) -> None:
        self.lane_name = lane_name
        self.snapshot = snapshot
        super().__init__(
            f"Outbound lane {lane_name} is full "
            f"(depth={snapshot.depth}/{snapshot.maxsize})"
        )


def outbound_message_is_droppable(message: OutboundMessage) -> bool:
    metadata = message.metadata or {}
    if metadata.get("_progress"):
        return True
    return bool(metadata.get("_lane_drop_ok"))


class SerialDispatchLane(Generic[ItemT]):
    def __init__(
        self,
        name: str,
        handler: Callable[[ItemT], Awaitable[None]],
        *,
        maxsize: int = 32,
        drop_predicate: Callable[[ItemT], bool] | None = None,
    ) -> None:
        if maxsize <= 0:
            raise ValueError(f"{name} lane maxsize must be > 0")

        self.name = name
        self.maxsize = maxsize
        self._handler = handler
        self._drop_predicate = drop_predicate or (lambda _item: False)
        self._queue: deque[ItemT] = deque()
        self._condition = asyncio.Condition()
        self._task: asyncio.Task[None] | None = None
        self._closing = False
        self._enqueued_total = 0
        self._dispatched_total = 0
        self._dropped_total = 0
        self._rejected_total = 0
        self._failed_total = 0

    def start(self) -> None:
        if self._task is not None and not self._task.done():
            return
        self._closing = False
        self._task = asyncio.create_task(
            self._run(),
            name=f"serial-dispatch-lane:{self.name}",
        )

    async def submit(self, item: ItemT) -> bool:
        self.start()
        async with self._condition:
            if self._closing:
                raise RuntimeError(f"Outbound lane {self.name} is closing")

            if len(self._queue) >= self.maxsize:
                if self._drop_predicate(item):
                    self._dropped_total += 1
                    return False
                if not self._evict_oldest_droppable_locked():
                    self._rejected_total += 1
                    raise LaneFullError(self.name, snapshot=self.snapshot())

            self._queue.append(item)
            self._enqueued_total += 1
            self._condition.notify(1)
            return True

    async def close(self, *, drain: bool = False) -> None:
        task = self._task
        if task is None:
            return

        async with self._condition:
            self._closing = True
            if not drain and self._queue:
                self._dropped_total += len(self._queue)
                self._queue.clear()
            self._condition.notify_all()

        if drain:
            await task
        else:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._task = None

    async def _run(self) -> None:
        while True:
            async with self._condition:
                while not self._queue and not self._closing:
                    await self._condition.wait()

                if self._closing and not self._queue:
                    return

                item = self._queue.popleft()

            try:
                await self._handler(item)
                self._dispatched_total += 1
            except asyncio.CancelledError:
                raise
            except Exception:
                self._failed_total += 1
                logger.exception("Outbound lane {} dispatch failed", self.name)

    def _evict_oldest_droppable_locked(self) -> bool:
        for queued_item in self._queue:
            if self._drop_predicate(queued_item):
                self._queue.remove(queued_item)
                self._dropped_total += 1
                return True
        return False

    def snapshot(self) -> LaneSnapshot:
        return LaneSnapshot(
            name=self.name,
            maxsize=self.maxsize,
            depth=len(self._queue),
            running=self._task is not None and not self._task.done(),
            enqueued_total=self._enqueued_total,
            dispatched_total=self._dispatched_total,
            dropped_total=self._dropped_total,
            rejected_total=self._rejected_total,
            failed_total=self._failed_total,
        )

    def snapshot_dict(self) -> dict[str, Any]:
        return asdict(self.snapshot())


def lane_snapshot_map(
    lanes: Mapping[str, SerialDispatchLane[Any]],
) -> dict[str, dict[str, Any]]:
    return {
        name: lane.snapshot_dict()
        for name, lane in lanes.items()
    }
