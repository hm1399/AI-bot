from __future__ import annotations

import time
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from services.app_api.json_store import JsonObjectStore


class ExperienceStore:
    def __init__(self, runtime_dir: Path) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        self._store = JsonObjectStore(
            runtime_dir / "experience_state.json",
            defaults={
                "runtime_override": {},
                "last_interaction_result": None,
                "interaction_history": [],
                "interaction_throttle": {},
            },
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
