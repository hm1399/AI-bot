from __future__ import annotations

"""Async message queue for decoupled channel-agent communication."""

import asyncio
from typing import Any

from loguru import logger

from nanobot.bus.events import InboundMessage, OutboundMessage


class MessageBus:
    """
    Async message bus that decouples chat channels from the agent core.

    Channels push messages to the inbound queue, and the agent processes
    them and pushes responses to the outbound queue.
    """

    def __init__(self):
        self.inbound: asyncio.Queue[InboundMessage] = asyncio.Queue()
        self.outbound: asyncio.Queue[OutboundMessage] = asyncio.Queue()
        self._observers: list[Any] = []

    def add_observer(self, observer: Any) -> None:
        """Register an observer for inbound/outbound publish events."""
        if observer not in self._observers:
            self._observers.append(observer)

    async def _notify(self, method_name: str, msg: InboundMessage | OutboundMessage) -> None:
        for observer in tuple(self._observers):
            callback = getattr(observer, method_name, None)
            if callback is None:
                continue
            try:
                await callback(msg)
            except Exception:
                logger.exception("MessageBus observer {} failed", method_name)

    async def publish_inbound(self, msg: InboundMessage) -> None:
        """Publish a message from a channel to the agent."""
        await self._notify("on_inbound_published", msg)
        await self.inbound.put(msg)

    async def consume_inbound(self) -> InboundMessage:
        """Consume the next inbound message (blocks until available)."""
        return await self.inbound.get()

    async def publish_outbound(self, msg: OutboundMessage) -> None:
        """Publish a response from the agent to channels."""
        await self._notify("on_outbound_published", msg)
        await self.outbound.put(msg)

    async def consume_outbound(self) -> OutboundMessage:
        """Consume the next outbound message (blocks until available)."""
        return await self.outbound.get()

    @property
    def inbound_size(self) -> int:
        """Number of pending inbound messages."""
        return self.inbound.qsize()

    @property
    def outbound_size(self) -> int:
        """Number of pending outbound messages."""
        return self.outbound.qsize()
