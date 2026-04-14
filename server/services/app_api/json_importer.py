from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any

from .sqlite_store import SQLitePlanningStore


_DOMAIN_FILES: dict[str, str] = {
    "tasks": "tasks.json",
    "events": "events.json",
    "notifications": "notifications.json",
    "reminders": "reminders.json",
}


def load_collection_items(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        return []

    items = payload.get("items", []) if isinstance(payload, dict) else payload
    if not isinstance(items, list):
        return []
    return [deepcopy(item) for item in items if isinstance(item, dict)]


def import_runtime_json_collections(
    runtime_dir: Path,
    sqlite_store: SQLitePlanningStore,
    *,
    overwrite: bool = False,
    domains: tuple[str, ...] | None = None,
) -> dict[str, dict[str, int | bool]]:
    summary: dict[str, dict[str, int | bool]] = {}
    for domain in domains or tuple(_DOMAIN_FILES.keys()):
        path = runtime_dir / _DOMAIN_FILES[domain]
        items = load_collection_items(path)
        existing_count = sqlite_store.domain_count(domain)
        should_import = overwrite or existing_count == 0
        if should_import:
            sqlite_store.replace_all(domain, items)
        summary[domain] = {
            "imported": bool(should_import),
            "source_count": len(items),
            "stored_count": sqlite_store.domain_count(domain),
        }
    return summary
