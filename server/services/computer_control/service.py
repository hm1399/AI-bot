from __future__ import annotations

import inspect
import uuid
from pathlib import Path
from typing import Any, Awaitable, Callable, Optional

from .adapters.macos import MacOSComputerAdapter
from .adapters.wechat import WeChatAdapter
from .models import (
    ComputerActionRecord,
    ComputerActionRequest,
    ComputerControlError,
)
from .policies import ComputerControlPolicy, PENDING_STATUSES
from .store import ComputerActionStore


EventCallback = Callable[..., Optional[Awaitable[None]]]


class ComputerControlService:
    def __init__(
        self,
        cfg: dict[str, Any],
        *,
        runtime_dir: Path,
        adapter: Any | None = None,
        wechat_adapter: Any | None = None,
        store: ComputerActionStore | None = None,
        event_callback: EventCallback | None = None,
    ) -> None:
        self.runtime_dir = runtime_dir
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.policy = ComputerControlPolicy(
            dict(cfg.get("computer_control") or {}),
            runtime_dir=self.runtime_dir,
        )
        self.store = store or ComputerActionStore(
            self.runtime_dir / "computer_control_actions.json"
        )
        self.event_callback = event_callback
        self.adapter_error: ComputerControlError | None = None
        self.adapter = adapter
        self.wechat_adapter = wechat_adapter

        if self.policy.enabled and self.adapter is None:
            try:
                self.adapter = MacOSComputerAdapter()
            except ComputerControlError as exc:
                self.adapter_error = exc
                self.adapter = None

        if self.policy.wechat_enabled and self.wechat_adapter is None and self.adapter is not None:
            self.wechat_adapter = WeChatAdapter(self.adapter)

    def set_event_callback(self, callback: EventCallback | None) -> None:
        self.event_callback = callback

    def is_available(self) -> bool:
        return self.policy.enabled and self.adapter is not None

    def supported_actions(self) -> list[str]:
        return self.policy.supported_actions() if self.policy.enabled else []

    def permission_hints(self) -> list[str]:
        return self.policy.permission_hints()

    def get_state(self) -> dict[str, Any]:
        return {
            "available": self.is_available(),
            "enabled": self.policy.enabled,
            "supported_actions": self.supported_actions(),
            "pending_actions": self.list_pending_actions(),
            "recent_actions": self.list_recent_actions(),
            "permission_hints": self.permission_hints(),
            "adapter_error": self.adapter_error.to_dict() if self.adapter_error else None,
        }

    def list_recent_actions(self, *, limit: int = 20) -> list[dict[str, Any]]:
        return self.store.list_recent(limit=limit)

    def list_pending_actions(self, *, limit: int = 20) -> list[dict[str, Any]]:
        return self.store.list_pending(limit=limit)

    def get_action(self, action_id: str) -> dict[str, Any] | None:
        return self.store.get(action_id)

    async def request_action(
        self,
        payload: dict[str, Any] | None = None,
        /,
        *,
        kind: str | None = None,
        arguments: dict[str, Any] | None = None,
        requested_via: str = "app",
        source_session_id: str | None = None,
        reason: str | None = None,
        requires_confirmation: bool | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if payload is not None:
            if not isinstance(payload, dict):
                raise ComputerControlError(
                    code="invalid_argument",
                    message="computer action payload must be an object",
                    status=400,
                )
            kind = str(payload.get("action") or payload.get("kind") or kind or "").strip() or None
            raw_arguments = payload.get("arguments")
            if raw_arguments is None:
                raw_arguments = payload.get("params")
            if raw_arguments is None:
                raw_arguments = payload.get("target")
            if raw_arguments is not None:
                arguments = raw_arguments
            requested_via = str(
                payload.get("requested_via")
                or payload.get("created_via")
                or requested_via
            ).strip() or requested_via
            source_session_id = str(
                payload.get("source_session_id")
                or payload.get("session_id")
                or source_session_id
                or ""
            ).strip() or None
            reason = str(payload.get("reason") or reason or "").strip() or None
            if "requires_confirmation" in payload:
                requires_confirmation = payload.get("requires_confirmation")
            merged_metadata = dict(metadata or {})
            if isinstance(payload.get("metadata"), dict):
                merged_metadata.update(payload.get("metadata") or {})
            for key in ("created_via", "source_channel", "source_message_id", "task_id"):
                value = payload.get(key)
                if value is None:
                    continue
                cleaned = str(value).strip()
                if cleaned:
                    merged_metadata[key] = cleaned
            metadata = merged_metadata

        if not kind:
            raise ComputerControlError(
                code="invalid_argument",
                message="action kind is required",
                status=400,
            )
        if arguments is not None and not isinstance(arguments, dict):
            raise ComputerControlError(
                code="invalid_argument",
                message="action arguments must be an object",
                status=400,
            )

        request = ComputerActionRequest(
            kind=kind,
            arguments=dict(arguments or {}),
            requested_via=requested_via,
            source_session_id=source_session_id,
            reason=reason,
            requires_confirmation=requires_confirmation,
            metadata=dict(metadata or {}),
        )
        decision = self.policy.evaluate(request)
        action = ComputerActionRecord(
            action_id=f"cc_{uuid.uuid4().hex[:12]}",
            kind=decision.kind,
            status="requested",
            risk_level=decision.risk_level,
            requires_confirmation=decision.requires_confirmation,
            requested_via=request.requested_via,
            source_session_id=request.source_session_id,
            arguments=decision.normalized_arguments,
            reason=request.reason,
            metadata=request.metadata,
        )
        self.store.save(action)
        await self._emit("computer.action.created", action)

        if decision.requires_confirmation:
            action = action.with_status("awaiting_confirmation")
            self.store.save(action)
            await self._emit("computer.action.updated", action)
            await self._emit("computer.action.requires_confirmation", action)
            return action.to_dict()

        return await self._execute(action)

    async def confirm_action(self, action_id: str) -> dict[str, Any]:
        action = self._require_action(action_id)
        if action.status != "awaiting_confirmation":
            raise ComputerControlError(
                code="invalid_state",
                message="action is not awaiting confirmation",
                status=409,
            )
        action = action.with_status("requested", confirmed=True)
        self.store.save(action)
        return await self._execute(action)

    async def cancel_action(self, action_id: str) -> dict[str, Any]:
        action = self._require_action(action_id)
        if action.status not in PENDING_STATUSES:
            raise ComputerControlError(
                code="invalid_state",
                message="action is no longer pending",
                status=409,
            )
        if action.status == "running":
            raise ComputerControlError(
                code="action_not_cancellable",
                message="running actions cannot be cancelled",
                status=409,
            )
        cancelled = action.with_status("cancelled", cancelled=True)
        self.store.save(cancelled)
        await self._emit("computer.action.updated", cancelled)
        await self._emit("computer.action.cancelled", cancelled)
        return cancelled.to_dict()

    async def _execute(self, action: ComputerActionRecord) -> dict[str, Any]:
        running = action.with_status(
            "running",
            confirmed=bool(action.confirmed_at),
        )
        self.store.save(running)
        await self._emit("computer.action.updated", running)

        try:
            result = await self._dispatch(running.kind, running.arguments)
        except ComputerControlError as exc:
            failed = running.with_status("failed", error=exc.to_dict())
            self.store.save(failed)
            await self._emit("computer.action.updated", failed)
            return failed.to_dict()

        completed = running.with_status("completed", result=result)
        self.store.save(completed)
        await self._emit("computer.action.updated", completed)
        await self._emit("computer.action.completed", completed)
        return completed.to_dict()

    async def _dispatch(self, kind: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if self.adapter is None:
            raise self.adapter_error or ComputerControlError(
                code="adapter_unavailable",
                message="computer control adapter is not available",
                status=503,
            )

        if kind == "wechat_prepare_message":
            if self.wechat_adapter is None:
                raise ComputerControlError(
                    code="adapter_unavailable",
                    message="wechat adapter is not available",
                    status=409,
                )
            return await self.wechat_adapter.prepare_message(**arguments)

        if kind == "wechat_send_prepared_message":
            if self.wechat_adapter is None:
                raise ComputerControlError(
                    code="adapter_unavailable",
                    message="wechat adapter is not available",
                    status=409,
                )
            return await self.wechat_adapter.send_prepared_message(**arguments)

        method = getattr(self.adapter, kind, None)
        if method is None:
            raise ComputerControlError(
                code="adapter_unavailable",
                message=f"adapter does not implement action: {kind}",
                status=503,
            )
        return await method(**arguments)

    def _require_action(self, action_id: str) -> ComputerActionRecord:
        payload = self.store.get(action_id)
        if payload is None:
            raise ComputerControlError(
                code="action_not_found",
                message="computer action does not exist",
                status=404,
            )
        return ComputerActionRecord.from_dict(payload)

    async def _emit(self, event_type: str, action: ComputerActionRecord) -> None:
        if self.event_callback is None:
            return
        result = self.event_callback(event_type=event_type, action=action.to_dict())
        if inspect.isawaitable(result):
            await result
