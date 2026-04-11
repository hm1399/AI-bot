"""Structured computer control tool backed by the product service layer."""

from __future__ import annotations

import json
from contextvars import ContextVar
from copy import deepcopy
from typing import Any, Protocol

from nanobot.agent.tools.base import Tool


class ComputerControlBackend(Protocol):
    """Injected backend facade for structured computer actions."""

    async def request_action(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Create and/or execute a structured computer action request."""
        ...


class ComputerControlTool(Tool):
    """Tool that routes product computer actions through the service layer."""

    def __init__(self, backend: ComputerControlBackend):
        self._backend = backend
        self._source_channel_var: ContextVar[str] = ContextVar(
            "computer_control_source_channel",
            default="",
        )
        self._source_chat_id_var: ContextVar[str] = ContextVar(
            "computer_control_source_chat_id",
            default="",
        )
        self._source_message_id_var: ContextVar[str | None] = ContextVar(
            "computer_control_source_message_id",
            default=None,
        )
        self._task_id_var: ContextVar[str | None] = ContextVar(
            "computer_control_task_id",
            default=None,
        )
        self._turn_results_var: ContextVar[list[dict[str, Any]]] = ContextVar(
            "computer_control_turn_results",
            default=[],
        )

    def set_context(
        self,
        channel: str,
        chat_id: str,
        message_id: str | None = None,
        task_id: str | None = None,
    ) -> None:
        """Set source context so backend actions stay attributable."""
        self._source_channel_var.set(channel)
        self._source_chat_id_var.set(chat_id)
        self._source_message_id_var.set(message_id)
        self._task_id_var.set(task_id)

    def start_turn(self) -> None:
        """Reset per-turn structured tool results."""
        self._turn_results_var.set([])

    def consume_turn_results(self) -> list[dict[str, Any]]:
        """Return and clear structured results for the current turn."""
        results = deepcopy(self._turn_results_var.get())
        self._turn_results_var.set([])
        return results

    @property
    def name(self) -> str:
        return "computer_control"

    @property
    def description(self) -> str:
        return (
            "Run structured product computer actions through the backend service layer. "
            "Prefer this over raw exec for actions such as open_app, focus_app_or_window, "
            "open_path, open_url, run_shortcut, run_script, clipboard_get, clipboard_set, "
            "active_window, screenshot, system_info, and approved life-skill adapters."
        )

    @property
    def parameters(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": (
                        "Structured computer action id. Examples: open_app, "
                        "focus_app_or_window, open_path, open_url, run_shortcut, "
                        "run_script, clipboard_get, clipboard_set, active_window, "
                        "screenshot, system_info."
                    ),
                },
                "target": {
                    "type": "object",
                    "description": (
                        "Action-specific structured payload, such as "
                        '{"app":"Safari"} or {"url":"https://example.com"}.'
                    ),
                },
                "requires_confirmation": {
                    "type": "boolean",
                    "description": (
                        "Optional confirmation override. Omit to let backend policy decide."
                    ),
                },
                "reason": {
                    "type": "string",
                    "description": "Short reason for requesting this computer action.",
                },
                "created_via": {
                    "type": "string",
                    "description": "Optional origin label. Defaults to agent.",
                },
                "source_channel": {
                    "type": "string",
                    "description": "Optional explicit source channel override.",
                },
                "source_session_id": {
                    "type": "string",
                    "description": "Optional explicit source session id override.",
                },
                "source_message_id": {
                    "type": "string",
                    "description": "Optional explicit source message id override.",
                },
                "task_id": {
                    "type": "string",
                    "description": "Optional runtime task id for auditing.",
                },
            },
            "required": ["action"],
        }

    async def execute(
        self,
        action: str,
        target: dict[str, Any] | None = None,
        requires_confirmation: bool | None = None,
        reason: str | None = None,
        created_via: str | None = None,
        source_channel: str | None = None,
        source_session_id: str | None = None,
        source_message_id: str | None = None,
        task_id: str | None = None,
        **_: Any,
    ) -> str:
        clean_action = action.strip()
        if not clean_action:
            return "Error: action is required"

        channel = source_channel or self._source_channel_var.get()
        chat_id = self._source_chat_id_var.get()
        session_id = source_session_id or (f"{channel}:{chat_id}" if channel and chat_id else None)
        payload: dict[str, Any] = {
            "action": clean_action,
            "target": deepcopy(target) if isinstance(target, dict) else {},
            "created_via": (created_via or "agent").strip() or "agent",
        }
        if requires_confirmation is not None:
            payload["requires_confirmation"] = requires_confirmation
        if reason and reason.strip():
            payload["reason"] = reason.strip()
        if channel:
            payload["source_channel"] = channel
        if session_id:
            payload["source_session_id"] = session_id
        resolved_message_id = source_message_id or self._source_message_id_var.get()
        if resolved_message_id:
            payload["source_message_id"] = resolved_message_id
        resolved_task_id = task_id or self._task_id_var.get()
        if resolved_task_id:
            payload["task_id"] = resolved_task_id

        try:
            result = await self._request_backend_action(payload)
        except KeyError as exc:
            target_name = str(exc.args[0]) if exc.args else "resource"
            return f"Error: {target_name} not found"
        except ValueError as exc:
            return f"Error: {exc}"

        if not isinstance(result, dict):
            return "Error: computer control backend must return a JSON object"

        turn_results = list(self._turn_results_var.get())
        turn_results.append(deepcopy(result))
        self._turn_results_var.set(turn_results)
        return json.dumps(result, ensure_ascii=False)

    async def _request_backend_action(self, payload: dict[str, Any]) -> dict[str, Any]:
        request_action = getattr(self._backend, "request_action", None)
        if callable(request_action):
            return await request_action(payload)

        execute_action = getattr(self._backend, "execute_action", None)
        if callable(execute_action):
            return await execute_action(
                action=payload["action"],
                target=payload.get("target"),
                requires_confirmation=payload.get("requires_confirmation"),
                reason=payload.get("reason"),
                created_via=payload.get("created_via"),
                source_channel=payload.get("source_channel"),
                source_session_id=payload.get("source_session_id"),
                source_message_id=payload.get("source_message_id"),
                task_id=payload.get("task_id"),
            )

        raise RuntimeError(
            "computer control backend does not implement request_action(payload)"
        )
