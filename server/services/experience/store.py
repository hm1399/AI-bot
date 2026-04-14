from __future__ import annotations

import time
from collections.abc import Mapping
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from services.app_api.json_store import JsonObjectStore

from .sqlite_store import SQLiteExperienceStateStore


DEFAULT_EXPERIENCE_STATE = {
    "runtime_override": {},
    "last_interaction_result": None,
    "interaction_history": [],
    "interaction_throttle": {},
    "daily_shake_state": {
        "date": "",
        "valid_shake_count": 0,
        "first_result_mode": None,
        "first_valid_shake_at": None,
        "last_valid_shake_at": None,
        "last_mode": None,
    },
}


class _ExperienceStateBackend:
    def __init__(
        self,
        runtime_dir: Path,
        *,
        storage_config: Mapping[str, Any] | None = None,
    ) -> None:
        self._defaults = deepcopy(DEFAULT_EXPERIENCE_STATE)
        self._storage_mode = self._resolve_storage_mode(storage_config)
        self._json_path = runtime_dir / "experience_state.json"
        self._json_store = JsonObjectStore(self._json_path, defaults=self._defaults)
        self._sqlite_store: SQLiteExperienceStateStore | None = None
        if self._storage_mode in {"sqlite", "dual"}:
            self._sqlite_store = SQLiteExperienceStateStore(runtime_dir, defaults=self._defaults)
        if self._sqlite_store is not None and not self._sqlite_store.exists():
            self._sqlite_store.bootstrap(self._json_store.load())

    def load(self) -> dict[str, Any]:
        if self._storage_mode == "json":
            return self._json_store.load()
        if self._sqlite_store is None:
            return self._json_store.load()
        return self._sqlite_store.load()

    def save(self, payload: dict[str, Any]) -> dict[str, Any]:
        data = deepcopy(payload)
        if self._storage_mode in {"json", "dual"}:
            self._json_store.save(data)
        if self._sqlite_store is not None:
            self._sqlite_store.save(data)
        return deepcopy(data)

    @staticmethod
    def _resolve_storage_mode(storage_config: Mapping[str, Any] | None) -> str:
        raw = ""
        if storage_config is not None:
            raw = str(storage_config.get("experience_storage_mode") or "").strip().lower()
        if raw in {"json", "dual", "sqlite"}:
            return raw
        return "sqlite"


class ExperienceStore:
    def __init__(
        self,
        runtime_dir: Path,
        *,
        storage_config: Mapping[str, Any] | None = None,
    ) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        self._store = _ExperienceStateBackend(
            runtime_dir,
            storage_config=storage_config,
        )

    def load(self) -> dict[str, Any]:
        return self._store.load()

    def get_runtime_override(self) -> dict[str, Any]:
        payload = self._store.load().get("runtime_override")
        return deepcopy(payload) if isinstance(payload, dict) else {}

    def set_runtime_override(self, payload: dict[str, Any]) -> dict[str, Any]:
        state = self._store.load()
        current = state.get("runtime_override")
        merged = deepcopy(current) if isinstance(current, dict) else {}
        for key, value in payload.items():
            if value is None:
                merged.pop(key, None)
            else:
                merged[key] = deepcopy(value)
        state["runtime_override"] = merged
        self._store.save(state)
        return deepcopy(merged)

    def save_runtime_override(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.set_runtime_override(payload)

    def clear_runtime_override(self) -> None:
        state = self._store.load()
        state["runtime_override"] = {}
        self._store.save(state)

    def get_last_interaction_result(self) -> dict[str, Any] | None:
        payload = self._store.load().get("last_interaction_result")
        return deepcopy(payload) if isinstance(payload, dict) else None

    def get_interaction_history(self) -> list[dict[str, Any]]:
        payload = self._store.load().get("interaction_history")
        if not isinstance(payload, list):
            return []
        return [deepcopy(item) for item in payload if isinstance(item, dict)]

    def list_history(self, *, limit: int | None = None) -> list[dict[str, Any]]:
        history = self.get_interaction_history()
        if limit is None or limit <= 0:
            return history
        return history[-limit:]

    def record_interaction_result(
        self,
        payload: dict[str, Any],
        *,
        limit: int = 20,
    ) -> dict[str, Any]:
        stamped_payload = deepcopy(payload)
        stamped_payload.setdefault("created_at", datetime.now(timezone.utc).isoformat())
        history_entry = stamped_payload.get("history_entry")
        if isinstance(history_entry, dict):
            next_entry = deepcopy(history_entry)
            next_entry.setdefault("created_at", stamped_payload["created_at"])
            next_entry.setdefault("interaction_kind", stamped_payload.get("interaction_kind"))
            next_entry.setdefault("mode", stamped_payload.get("mode"))
            next_entry.setdefault("title", stamped_payload.get("title"))
            next_entry.setdefault(
                "summary",
                stamped_payload.get("display_text") or stamped_payload.get("short_result"),
            )
            next_entry.setdefault(
                "status",
                stamped_payload.get("short_result") or stamped_payload.get("mode"),
            )
            stamped_payload["history_entry"] = next_entry

        state = self._store.load()
        history = state.get("interaction_history")
        if not isinstance(history, list):
            history = []
        history.append(deepcopy(stamped_payload))
        if limit > 0:
            history = history[-limit:]
        state["interaction_history"] = history
        state["last_interaction_result"] = deepcopy(stamped_payload)
        self._store.save(state)
        return deepcopy(stamped_payload)

    def append_interaction_result(
        self,
        payload: dict[str, Any],
        *,
        limit: int = 20,
    ) -> dict[str, Any]:
        return self.record_interaction_result(payload, limit=limit)

    def is_throttled(self, kind: str, *, ttl_s: float) -> bool:
        if ttl_s <= 0:
            return False
        marks = self._store.load().get("interaction_throttle")
        if not isinstance(marks, dict):
            return False
        try:
            last_seen = float(marks.get(kind) or 0.0)
        except (TypeError, ValueError):
            last_seen = 0.0
        return (time.time() - last_seen) < ttl_s

    def touch_interaction(self, kind: str) -> float:
        state = self._store.load()
        marks = state.get("interaction_throttle")
        if not isinstance(marks, dict):
            marks = {}
        now = time.time()
        marks[kind] = now
        state["interaction_throttle"] = marks
        self._store.save(state)
        return now

    def clear_interaction_throttle(self, kind: str | None = None) -> None:
        state = self._store.load()
        marks = state.get("interaction_throttle")
        if not isinstance(marks, dict):
            marks = {}
        if kind is None:
            marks = {}
        else:
            marks.pop(kind, None)
        state["interaction_throttle"] = marks
        self._store.save(state)

    def get_daily_shake_state(self) -> dict[str, Any]:
        state = self._store.load()
        normalized, changed = self._normalize_daily_shake_state(state)
        if changed:
            state["daily_shake_state"] = dict(normalized)
            self._store.save(state)
        return self._daily_shake_state_view(normalized)

    def record_valid_shake(self, mode: str) -> dict[str, Any]:
        if mode not in {"fortune", "random"}:
            return self.get_daily_shake_state()
        state = self._store.load()
        normalized, _ = self._normalize_daily_shake_state(state)
        timestamp = datetime.now(timezone.utc).isoformat()
        if int(normalized.get("valid_shake_count") or 0) <= 0:
            normalized["first_result_mode"] = mode
        normalized["valid_shake_count"] = int(normalized.get("valid_shake_count") or 0) + 1
        if not normalized.get("first_valid_shake_at"):
            normalized["first_valid_shake_at"] = timestamp
        normalized["last_valid_shake_at"] = timestamp
        normalized["last_mode"] = mode
        state["daily_shake_state"] = dict(normalized)
        self._store.save(state)
        return self._daily_shake_state_view(normalized)

    @staticmethod
    def _daily_shake_state_view(payload: dict[str, Any]) -> dict[str, Any]:
        view = deepcopy(payload)
        view["count"] = int(view.get("valid_shake_count") or 0)
        view["first_shake_used"] = view["count"] > 0
        view["last_interaction_at"] = view.get("last_valid_shake_at")
        view["fortune_available"] = int(view.get("valid_shake_count") or 0) <= 0
        return view

    def _normalize_daily_shake_state(self, state: dict[str, Any]) -> tuple[dict[str, Any], bool]:
        today = datetime.now().astimezone().date().isoformat()
        payload = state.get("daily_shake_state")
        raw = payload if isinstance(payload, dict) else {}
        normalized = {
            "date": str(raw.get("date") or "").strip(),
            "valid_shake_count": self._safe_int(raw.get("valid_shake_count")),
            "first_result_mode": str(raw.get("first_result_mode") or "").strip() or None,
            "first_valid_shake_at": raw.get("first_valid_shake_at"),
            "last_valid_shake_at": raw.get("last_valid_shake_at"),
            "last_mode": str(raw.get("last_mode") or "").strip() or None,
        }
        changed = not isinstance(payload, dict)
        if normalized["date"] != today:
            normalized = {
                "date": today,
                "valid_shake_count": 0,
                "first_result_mode": None,
                "first_valid_shake_at": None,
                "last_valid_shake_at": None,
                "last_mode": None,
            }
            changed = True
        return normalized, changed or raw != normalized

    @staticmethod
    def _safe_int(value: Any) -> int:
        try:
            return max(0, int(value))
        except (TypeError, ValueError):
            return 0
