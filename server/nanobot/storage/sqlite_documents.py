from __future__ import annotations

import json
import sqlite3
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def resolve_state_db_path(anchor: Path) -> Path:
    base_dir = anchor if anchor.suffix == "" else anchor.parent
    if base_dir.name == "runtime":
        return base_dir.parent / "state.sqlite3"
    return base_dir / "state.sqlite3"


class RuntimeDocumentStore:
    def __init__(
        self,
        anchor: Path,
        *,
        namespace: str,
        defaults: dict[str, Any] | None = None,
    ) -> None:
        normalized_namespace = str(namespace or "").strip()
        if not normalized_namespace:
            raise ValueError("runtime document namespace is required")
        self.namespace = normalized_namespace
        self.defaults = deepcopy(defaults or {})
        self.db_path = resolve_state_db_path(anchor)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def load(self) -> dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT payload_json
                FROM runtime_documents
                WHERE namespace = ?
                """,
                (self.namespace,),
            ).fetchone()
        if row is None:
            return deepcopy(self.defaults)
        try:
            payload = json.loads(row["payload_json"])
            if not isinstance(payload, dict):
                raise ValueError("runtime document payload must be an object")
        except Exception:
            return deepcopy(self.defaults)
        merged = deepcopy(self.defaults)
        merged.update(payload)
        return merged

    def save(self, payload: dict[str, Any]) -> dict[str, Any]:
        data = deepcopy(payload)
        serialized = json.dumps(data, ensure_ascii=False)
        timestamp = now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO runtime_documents (
                    namespace,
                    payload_json,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?)
                ON CONFLICT(namespace) DO UPDATE SET
                    payload_json = excluded.payload_json,
                    updated_at = excluded.updated_at
                """,
                (self.namespace, serialized, timestamp, timestamp),
            )
            conn.commit()
        return data

    def exists(self) -> bool:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT 1
                FROM runtime_documents
                WHERE namespace = ?
                LIMIT 1
                """,
                (self.namespace,),
            ).fetchone()
        return row is not None

    def bootstrap(self, payload: dict[str, Any]) -> bool:
        data = deepcopy(payload)
        serialized = json.dumps(data, ensure_ascii=False)
        timestamp = now_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                INSERT OR IGNORE INTO runtime_documents (
                    namespace,
                    payload_json,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?)
                """,
                (self.namespace, serialized, timestamp, timestamp),
            )
            conn.commit()
        return cursor.rowcount > 0

    def _initialize(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_documents (
                    namespace TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_runtime_documents_updated_at
                ON runtime_documents(updated_at DESC)
                """
            )
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA foreign_keys=ON;")
        conn.execute("PRAGMA busy_timeout=5000;")
        conn.execute("PRAGMA synchronous=NORMAL;")
        conn.execute("PRAGMA temp_store=MEMORY;")
        return conn
