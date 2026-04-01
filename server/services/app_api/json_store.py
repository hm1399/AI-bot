from __future__ import annotations

import json
import uuid
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any

from nanobot.utils.atomic_write import atomic_write_text


def _now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


class JsonObjectStore:
    """Persist a single JSON object atomically."""

    def __init__(self, path: Path, *, defaults: dict[str, Any] | None = None) -> None:
        self.path = path
        self.defaults = defaults or {}

    def load(self) -> dict[str, Any]:
        if not self.path.exists():
            return deepcopy(self.defaults)
        try:
            with open(self.path, encoding="utf-8") as handle:
                payload = json.load(handle)
            if not isinstance(payload, dict):
                raise ValueError("json object store payload must be an object")
        except Exception:
            return deepcopy(self.defaults)
        merged = deepcopy(self.defaults)
        merged.update(payload)
        return merged

    def save(self, payload: dict[str, Any]) -> dict[str, Any]:
        data = deepcopy(payload)

        def _write(handle) -> None:
            json.dump(data, handle, ensure_ascii=False, indent=2)

        atomic_write_text(self.path, _write, encoding="utf-8")
        return data


class JsonCollectionStore:
    """Persist a collection of JSON items atomically."""

    def __init__(self, path: Path, *, id_field: str, prefix: str) -> None:
        self.path = path
        self.id_field = id_field
        self.prefix = prefix

    def list_items(self) -> list[dict[str, Any]]:
        return deepcopy(self._load_items())

    def get(self, item_id: str) -> dict[str, Any] | None:
        for item in self._load_items():
            if item.get(self.id_field) == item_id:
                return deepcopy(item)
        return None

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        now = _now_iso()
        items = self._load_items()
        item = deepcopy(payload)
        item.setdefault(self.id_field, f"{self.prefix}_{uuid.uuid4().hex[:8]}")
        item.setdefault("created_at", now)
        item["updated_at"] = now
        items.append(item)
        self._save_items(items)
        return deepcopy(item)

    def update(self, item_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        items = self._load_items()
        now = _now_iso()
        for item in items:
            if item.get(self.id_field) != item_id:
                continue
            created_at = item.get("created_at", now)
            item.update(deepcopy(patch))
            item[self.id_field] = item_id
            item["created_at"] = created_at
            item["updated_at"] = now
            self._save_items(items)
            return deepcopy(item)
        return None

    def delete(self, item_id: str) -> dict[str, Any] | None:
        items = self._load_items()
        for index, item in enumerate(items):
            if item.get(self.id_field) != item_id:
                continue
            deleted = items.pop(index)
            self._save_items(items)
            return deepcopy(deleted)
        return None

    def replace_all(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        self._save_items(items)
        return self.list_items()

    def clear(self) -> None:
        self._save_items([])

    def _load_items(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        try:
            with open(self.path, encoding="utf-8") as handle:
                payload = json.load(handle)
            if isinstance(payload, dict):
                items = payload.get("items", [])
            else:
                items = payload
            if not isinstance(items, list):
                raise ValueError("json collection store payload must contain a list")
        except Exception:
            return []
        return [deepcopy(item) for item in items if isinstance(item, dict)]

    def _save_items(self, items: list[dict[str, Any]]) -> None:
        payload = {"items": deepcopy(items)}

        def _write(handle) -> None:
            json.dump(payload, handle, ensure_ascii=False, indent=2)

        atomic_write_text(self.path, _write, encoding="utf-8")
