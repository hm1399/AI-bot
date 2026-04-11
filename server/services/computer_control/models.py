from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


ActionStatus = str
RiskLevel = str


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


@dataclass
class ComputerControlError(Exception):
    code: str
    message: str
    status: int = 400
    details: dict[str, Any] = field(default_factory=dict)

    def __str__(self) -> str:
        return self.message

    def to_dict(self) -> dict[str, Any]:
        payload = {
            "code": self.code,
            "message": self.message,
        }
        if self.details:
            payload["details"] = dict(self.details)
        return payload


@dataclass
class ComputerActionRequest:
    kind: str
    arguments: dict[str, Any]
    requested_via: str = "app"
    source_session_id: str | None = None
    reason: str | None = None
    requires_confirmation: bool | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class PolicyDecision:
    kind: str
    normalized_arguments: dict[str, Any]
    risk_level: RiskLevel
    requires_confirmation: bool


@dataclass
class ComputerActionRecord:
    action_id: str
    kind: str
    status: ActionStatus
    risk_level: RiskLevel
    requires_confirmation: bool
    requested_via: str
    source_session_id: str | None
    arguments: dict[str, Any]
    reason: str | None = None
    result: dict[str, Any] | None = None
    error: dict[str, Any] | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: str = field(default_factory=now_iso)
    updated_at: str = field(default_factory=now_iso)
    confirmed_at: str | None = None
    cancelled_at: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "action_id": self.action_id,
            "kind": self.kind,
            "status": self.status,
            "risk_level": self.risk_level,
            "requires_confirmation": self.requires_confirmation,
            "requested_via": self.requested_via,
            "source_session_id": self.source_session_id,
            "arguments": dict(self.arguments),
            "reason": self.reason,
            "result": dict(self.result) if isinstance(self.result, dict) else self.result,
            "error": dict(self.error) if isinstance(self.error, dict) else self.error,
            "metadata": dict(self.metadata),
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "confirmed_at": self.confirmed_at,
            "cancelled_at": self.cancelled_at,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> ComputerActionRecord:
        return cls(
            action_id=str(payload.get("action_id") or ""),
            kind=str(payload.get("kind") or ""),
            status=str(payload.get("status") or "requested"),
            risk_level=str(payload.get("risk_level") or "low"),
            requires_confirmation=bool(payload.get("requires_confirmation")),
            requested_via=str(payload.get("requested_via") or "app"),
            source_session_id=str(payload.get("source_session_id") or "").strip() or None,
            arguments=dict(payload.get("arguments") or {}),
            reason=str(payload.get("reason") or "").strip() or None,
            result=dict(payload.get("result") or {}) or None,
            error=dict(payload.get("error") or {}) or None,
            metadata=dict(payload.get("metadata") or {}),
            created_at=str(payload.get("created_at") or now_iso()),
            updated_at=str(payload.get("updated_at") or payload.get("created_at") or now_iso()),
            confirmed_at=str(payload.get("confirmed_at") or "").strip() or None,
            cancelled_at=str(payload.get("cancelled_at") or "").strip() or None,
        )

    def with_status(
        self,
        status: ActionStatus,
        *,
        result: dict[str, Any] | None = None,
        error: dict[str, Any] | None = None,
        confirmed: bool = False,
        cancelled: bool = False,
    ) -> ComputerActionRecord:
        updated = ComputerActionRecord.from_dict(self.to_dict())
        updated.status = status
        updated.updated_at = now_iso()
        if result is not None:
            updated.result = dict(result)
            updated.error = None
        if error is not None:
            updated.error = dict(error)
            updated.result = None
        if confirmed:
            updated.confirmed_at = updated.updated_at
        if cancelled:
            updated.cancelled_at = updated.updated_at
        return updated
