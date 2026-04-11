from __future__ import annotations

from pathlib import Path
from typing import Any

from services.app_api.json_store import JsonCollectionStore

from .models import ComputerActionRecord
from .policies import PENDING_STATUSES


class ComputerActionStore:
    def __init__(self, path: Path, *, max_items: int = 200) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.collection = JsonCollectionStore(path, id_field="action_id", prefix="cc")
        self.max_items = max_items

    def save(self, action: ComputerActionRecord) -> dict[str, Any]:
        items = self.collection.list_items()
        payload = action.to_dict()
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
        return payload

    def get(self, action_id: str) -> dict[str, Any] | None:
        return self.collection.get(action_id)

    def list_recent(self, *, limit: int = 20) -> list[dict[str, Any]]:
        items = sorted(
            self.collection.list_items(),
            key=lambda item: (item.get("updated_at") or "", item.get("created_at") or ""),
            reverse=True,
        )
        if limit > 0:
            items = items[:limit]
        return items

    def list_pending(self, *, limit: int = 20) -> list[dict[str, Any]]:
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
