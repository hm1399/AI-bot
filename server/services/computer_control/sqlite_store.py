from __future__ import annotations

import json
import sqlite3
from copy import deepcopy
from pathlib import Path
from typing import Any

from nanobot.storage.sqlite_documents import resolve_state_db_path

from .models import ComputerActionRecord
from .policies import PENDING_STATUSES


class SQLiteComputerActionStore:
    def __init__(self, path: Path, *, max_items: int = 200) -> None:
        self.path = path
        self.max_items = max_items
        self.db_path = resolve_state_db_path(path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def save(self, action: ComputerActionRecord) -> dict[str, Any]:
        payload = ComputerActionRecord.from_dict(action.to_dict()).to_dict()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO computer_actions (
                    action_id,
                    status,
                    created_at,
                    updated_at,
                    payload_json
                )
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(action_id) DO UPDATE SET
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    payload_json = excluded.payload_json
                """,
                (
                    payload["action_id"],
                    str(payload.get("status") or ""),
                    str(payload.get("created_at") or ""),
                    str(payload.get("updated_at") or ""),
                    json.dumps(payload, ensure_ascii=False),
                ),
            )
            self._trim(conn)
            conn.commit()
        return deepcopy(payload)

    def get(self, action_id: str) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT payload_json
                FROM computer_actions
                WHERE action_id = ?
                """,
                (action_id,),
            ).fetchone()
        return self._decode_row(row)

    def list_recent(self, *, limit: int = 20) -> list[dict[str, Any]]:
        query = """
            SELECT payload_json
            FROM computer_actions
            ORDER BY updated_at DESC, created_at DESC
        """
        params: tuple[Any, ...] = ()
        if limit > 0:
            query += " LIMIT ?"
            params = (limit,)
        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()
        return [payload for payload in (self._decode_row(row) for row in rows) if payload is not None]

    def list_pending(self, *, limit: int = 20) -> list[dict[str, Any]]:
        placeholders = ", ".join("?" for _ in PENDING_STATUSES)
        query = f"""
            SELECT payload_json
            FROM computer_actions
            WHERE status IN ({placeholders})
            ORDER BY updated_at DESC, created_at DESC
        """
        params: list[Any] = list(PENDING_STATUSES)
        if limit > 0:
            query += " LIMIT ?"
            params.append(limit)
        with self._connect() as conn:
            rows = conn.execute(query, tuple(params)).fetchall()
        return [payload for payload in (self._decode_row(row) for row in rows) if payload is not None]

    def count(self) -> int:
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) AS total FROM computer_actions").fetchone()
        return int(row["total"] or 0) if row is not None else 0

    def bootstrap(self, items: list[dict[str, Any]]) -> bool:
        normalized_items = [
            ComputerActionRecord.from_dict(item).to_dict()
            for item in items
            if isinstance(item, dict)
        ]
        if not normalized_items:
            return False
        with self._connect() as conn:
            existing = conn.execute(
                "SELECT 1 FROM computer_actions LIMIT 1"
            ).fetchone()
            if existing is not None:
                return False
            conn.executemany(
                """
                INSERT INTO computer_actions (
                    action_id,
                    status,
                    created_at,
                    updated_at,
                    payload_json
                )
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (
                        payload["action_id"],
                        str(payload.get("status") or ""),
                        str(payload.get("created_at") or ""),
                        str(payload.get("updated_at") or ""),
                        json.dumps(payload, ensure_ascii=False),
                    )
                    for payload in normalized_items
                ],
            )
            self._trim(conn)
            conn.commit()
        return True

    def _trim(self, conn: sqlite3.Connection) -> None:
        if self.max_items <= 0:
            return
        rows = conn.execute(
            """
            SELECT action_id, status
            FROM computer_actions
            ORDER BY updated_at DESC, created_at DESC
            """
        ).fetchall()
        if len(rows) <= self.max_items:
            return
        pending_ids = {
            str(row["action_id"] or "")
            for row in rows
            if str(row["status"] or "") in PENDING_STATUSES
        }
        keep_ids: set[str] = set()
        for index, row in enumerate(rows):
            action_id = str(row["action_id"] or "")
            if index < self.max_items or action_id in pending_ids:
                keep_ids.add(action_id)
        remove_ids = [
            str(row["action_id"] or "")
            for row in rows
            if str(row["action_id"] or "") and str(row["action_id"] or "") not in keep_ids
        ]
        if not remove_ids:
            return
        conn.executemany(
            "DELETE FROM computer_actions WHERE action_id = ?",
            [(action_id,) for action_id in remove_ids],
        )

    def _initialize(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS computer_actions (
                    action_id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload_json TEXT NOT NULL
                ) STRICT
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_computer_actions_recent
                ON computer_actions(updated_at DESC, created_at DESC)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_computer_actions_pending
                ON computer_actions(status, updated_at DESC, created_at DESC)
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

    @staticmethod
    def _decode_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
        if row is None:
            return None
        try:
            payload = json.loads(row["payload_json"])
            if not isinstance(payload, dict):
                raise ValueError("computer action payload must be an object")
        except Exception:
            return None
        return deepcopy(payload)
