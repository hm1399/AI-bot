from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any

from services.app_api.json_store import JsonCollectionStore

from .models import ComputerActionRecord
from .policies import PENDING_STATUSES
from .sqlite_store import SQLiteComputerActionStore


class ComputerActionStore:
    def __init__(
        self,
        path: Path,
        *,
        max_items: int = 200,
        storage_config: Mapping[str, Any] | None = None,
    ) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.collection = JsonCollectionStore(path, id_field="action_id", prefix="cc")
        self.max_items = max_items
        self._storage_mode = self._resolve_storage_mode(storage_config)
        self._sqlite_store: SQLiteComputerActionStore | None = None
        if self._storage_mode in {"sqlite", "dual"}:
            self._sqlite_store = SQLiteComputerActionStore(path, max_items=max_items)
        if self._sqlite_store is not None and self._sqlite_store.count() <= 0:
            self._sqlite_store.bootstrap(self.collection.list_items())

    def save(self, action: ComputerActionRecord) -> dict[str, Any]:
        payload = action.to_dict()
        if self._storage_mode in {"json", "dual"}:
            items = self.collection.list_items()
            replaced = False
            for index, item in enumerate(items):
                if item.get("action_id") != action.action_id:
                    continue
                items[index] = payload
                replaced = True
                break
            if not replaced:
                items.append(payload)
            self.collection.replace_all(self._trim(items))
        if self._sqlite_store is not None:
            return self._sqlite_store.save(action)
        return payload

    def get(self, action_id: str) -> dict[str, Any] | None:
        if self._sqlite_store is not None:
            return self._sqlite_store.get(action_id)
        return self.collection.get(action_id)

    def list_recent(self, *, limit: int = 20) -> list[dict[str, Any]]:
        if self._sqlite_store is not None:
            return self._sqlite_store.list_recent(limit=limit)
        items = sorted(
            self.collection.list_items(),
            key=lambda item: (item.get("updated_at") or "", item.get("created_at") or ""),
            reverse=True,
        )
        if limit > 0:
            items = items[:limit]
        return items

    def list_pending(self, *, limit: int = 20) -> list[dict[str, Any]]:
        if self._sqlite_store is not None:
            return self._sqlite_store.list_pending(limit=limit)
        items = [
            item for item in self.list_recent(limit=0)
            if str(item.get("status") or "") in PENDING_STATUSES
        ]
        if limit > 0:
            items = items[:limit]
        return items

    def _trim(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if len(items) <= self.max_items:
            return items
        pending_ids = {
            str(item.get("action_id") or "")
            for item in items
            if str(item.get("status") or "") in PENDING_STATUSES
        }
        ordered = sorted(
            items,
            key=lambda item: (item.get("updated_at") or "", item.get("created_at") or ""),
            reverse=True,
        )
        kept: list[dict[str, Any]] = []
        for item in ordered:
            action_id = str(item.get("action_id") or "")
            if len(kept) < self.max_items or action_id in pending_ids:
                kept.append(item)
        return list(reversed(kept))

    @staticmethod
    def _resolve_storage_mode(storage_config: Mapping[str, Any] | None) -> str:
        raw = ""
        if storage_config is not None:
            raw = str(storage_config.get("computer_action_storage_mode") or "").strip().lower()
        if raw in {"json", "dual", "sqlite"}:
            return raw
        return "sqlite"
