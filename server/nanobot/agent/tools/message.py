"""Message tool for sending messages to users."""

from __future__ import annotations

from contextvars import ContextVar
from typing import Any, Awaitable, Callable

from nanobot.agent.tools.base import Tool
from nanobot.bus.events import OutboundMessage


class MessageTool(Tool):
    """Tool to send messages to users on chat channels."""

    def __init__(
        self,
        send_callback: Callable[[OutboundMessage], Awaitable[None]] | None = None,
        default_channel: str = "",
        default_chat_id: str = "",
        default_message_id: str | None = None,
        default_task_id: str | None = None,
    ):
        self._send_callback = send_callback
        self._default_channel_var: ContextVar[str] = ContextVar(
            "message_default_channel", default=default_channel
        )
        self._default_chat_id_var: ContextVar[str] = ContextVar(
            "message_default_chat_id", default=default_chat_id
        )
        self._default_message_id_var: ContextVar[str | None] = ContextVar(
            "message_default_message_id", default=default_message_id
        )
        self._default_task_id_var: ContextVar[str | None] = ContextVar(
            "message_default_task_id", default=default_task_id
        )
        self._sent_in_turn_var: ContextVar[bool] = ContextVar(
            "message_sent_in_turn", default=False
        )

    def set_context(
        self,
        channel: str,
        chat_id: str,
        message_id: str | None = None,
        task_id: str | None = None,
    ) -> None:
        """Set the current message context."""
        self._default_channel_var.set(channel)
        self._default_chat_id_var.set(chat_id)
        self._default_message_id_var.set(message_id)
        self._default_task_id_var.set(task_id)

    def set_send_callback(self, callback: Callable[[OutboundMessage], Awaitable[None]]) -> None:
        """Set the callback for sending messages."""
        self._send_callback = callback

    def start_turn(self) -> None:
        """Reset per-turn send tracking."""
        self._sent_in_turn_var.set(False)

    @property
    def sent_in_turn(self) -> bool:
        """Whether the current task already sent a direct user message."""
        return self._sent_in_turn_var.get()

    @property
    def name(self) -> str:
        return "message"

    @property
    def description(self) -> str:
        return "Send a message to the user. Use this when you want to communicate something."

    @property
    def parameters(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "content": {
                    "type": "string",
                    "description": "The message content to send"
                },
                "channel": {
                    "type": "string",
                    "description": "Optional: target channel (telegram, discord, etc.)"
                },
                "chat_id": {
                    "type": "string",
                    "description": "Optional: target chat/user ID"
                },
                "media": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Optional: list of file paths to attach (images, audio, documents)"
                }
            },
            "required": ["content"]
        }

    async def execute(
        self,
        content: str,
        channel: str | None = None,
        chat_id: str | None = None,
        message_id: str | None = None,
        media: list[str] | None = None,
        **kwargs: Any
    ) -> str:
        default_channel = self._default_channel_var.get()
        default_chat_id = self._default_chat_id_var.get()
        default_message_id = self._default_message_id_var.get()
        default_task_id = self._default_task_id_var.get()

        channel = channel or default_channel
        chat_id = chat_id or default_chat_id
        message_id = message_id or default_message_id
        task_id = kwargs.pop("task_id", None) or default_task_id

        if not channel or not chat_id:
            return "Error: No target channel/chat specified"

        if not self._send_callback:
            return "Error: Message sending not configured"

        msg = OutboundMessage(
            channel=channel,
            chat_id=chat_id,
            content=content,
            media=media or [],
            metadata={
                "message_id": message_id,
                "task_id": task_id,
            }
        )

        try:
            await self._send_callback(msg)
            if channel == default_channel and chat_id == default_chat_id:
                self._sent_in_turn_var.set(True)
            media_info = f" with {len(media)} attachments" if media else ""
            return f"Message sent to {channel}:{chat_id}{media_info}"
        except Exception as e:
            return f"Error sending message: {str(e)}"
