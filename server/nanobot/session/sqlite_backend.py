"""SQLite-backed session storage."""

from __future__ import annotations

import json
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from nanobot.session.manager import Session
from nanobot.storage.migrations import run_migrations
from nanobot.storage.sqlite_db import SQLiteConnectionFactory, create_connection_factory


APP_CHANNEL = "app"
DEFAULT_APP_SESSION_ID = "app:main"


@dataclass(frozen=True)
class ImportManifestEntry:
    manifest_key: str
    domain: str
    source_path: str
    source_mtime_ns: int
    source_size: int
    imported_at: str
    checksum_sha256: str | None
    details: dict[str, Any]


class SQLiteSessionBackend:
    """Persists sessions and session messages into SQLite."""

    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.factory: SQLiteConnectionFactory = create_connection_factory(self.db_path)
        run_migrations(self.factory)

    def get(self, key: str) -> Session | None:
        with self.factory.session() as connection:
            row = connection.execute(
                "SELECT * FROM sessions WHERE session_id = ?",
                (key,),
            ).fetchone()
            if row is None:
                return None

            message_rows = connection.execute(
                """
                SELECT raw_json
                FROM session_messages
                WHERE session_id = ?
                ORDER BY message_seq ASC
                """,
                (key,),
            ).fetchall()

        metadata = self._load_metadata(row["metadata_json"])
        messages = [json.loads(message_row["raw_json"]) for message_row in message_rows]
        created_at = self._parse_datetime(row["created_at"])
        updated_at = self._parse_datetime(row["updated_at"])
        return Session(
            key=key,
            messages=messages,
            created_at=created_at,
            updated_at=updated_at,
            metadata=metadata,
            last_consolidated=int(row["last_consolidated_seq"] or 0),
        )

    def load_session(self, key: str) -> Session | None:
        """Compatibility wrapper for SessionManager."""
        return self.get(key)

    def exists(self, key: str) -> bool:
        with self.factory.session() as connection:
            row = connection.execute(
                "SELECT 1 FROM sessions WHERE session_id = ?",
                (key,),
            ).fetchone()
        return row is not None

    def save(self, session: Session) -> None:
        session_row, message_rows = self._build_rows(session)
        with self.factory.session() as connection:
            connection.execute("BEGIN;")
            try:
                self._upsert_session_row(connection, session_row)
                self._replace_messages(connection, session.key, message_rows)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

    def save_session(self, session: Session) -> None:
        """Compatibility wrapper for SessionManager."""
        self.save(session)

    def save_incremental(
        self,
        session: Session,
        *,
        previous_message_count: int,
    ) -> None:
        session_row, message_rows = self._build_rows(session)
        replace_existing = previous_message_count < 0 or len(message_rows) < previous_message_count
        with self.factory.session() as connection:
            connection.execute("BEGIN;")
            try:
                self._upsert_session_row(connection, session_row)
                existing_count = self._message_count(connection, session.key)
                if existing_count != previous_message_count:
                    replace_existing = True
                if replace_existing:
                    self._replace_messages(connection, session.key, message_rows)
                else:
                    new_rows = message_rows[previous_message_count:]
                    if new_rows:
                        self._insert_message_rows(connection, new_rows)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

    def list_sessions(self) -> list[dict[str, Any]]:
        with self.factory.session() as connection:
            rows = connection.execute(
                """
                SELECT session_id, created_at, updated_at
                FROM sessions
                ORDER BY updated_at DESC
                """
            ).fetchall()
        return [
            {
                "key": row["session_id"],
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
                "path": str(self.db_path),
            }
            for row in rows
        ]

    def list_app_sessions(
        self,
        *,
        limit: int,
        archived: bool | None = None,
        pinned_first: bool = True,
        active_session_id: str | None = None,
    ) -> list[dict[str, Any]]:
        filters = ["channel = ?"]
        params: list[Any] = [APP_CHANNEL]
        if archived is not None:
            filters.append("archived = ?")
            params.append(1 if archived else 0)
        query = f"""
            SELECT *
            FROM sessions
            WHERE {' AND '.join(filters)}
            ORDER BY updated_at DESC
        """
        with self.factory.session() as connection:
            rows = connection.execute(query, params).fetchall()

        payload = [
            self._session_row_to_summary(row, active_session_id=active_session_id)
            for row in rows
        ]
        payload.sort(key=lambda item: item["last_message_at"] or "", reverse=True)
        if pinned_first:
            payload.sort(key=lambda item: not item["pinned"])
        if limit:
            payload = payload[:limit]
        return payload

    def get_session_summary(
        self,
        key: str,
        *,
        active_session_id: str | None = None,
    ) -> dict[str, Any] | None:
        with self.factory.session() as connection:
            row = connection.execute(
                "SELECT * FROM sessions WHERE session_id = ?",
                (key,),
            ).fetchone()
        if row is None:
            return None
        return self._session_row_to_summary(row, active_session_id=active_session_id)

    def get_messages_page(
        self,
        session_id: str,
        *,
        before: str | None = None,
        after: str | None = None,
        limit: int = 50,
    ) -> dict[str, Any]:
        with self.factory.session() as connection:
            session_exists = connection.execute(
                "SELECT 1 FROM sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            if session_exists is None:
                raise KeyError(session_id)

            visible_rows = connection.execute(
                """
                SELECT message_seq, message_id
                FROM session_messages
                WHERE session_id = ? AND visible = 1
                ORDER BY message_seq ASC
                """,
                (session_id,),
            ).fetchall()

            id_to_index = {
                str(row["message_id"]): index
                for index, row in enumerate(visible_rows)
                if row["message_id"]
            }
            if before and before not in id_to_index:
                raise ValueError("before cursor not found")
            if after and after not in id_to_index:
                raise ValueError("after cursor not found")

            slice_start = id_to_index[after] + 1 if after else 0
            slice_end = id_to_index[before] if before else len(visible_rows)
            if slice_end < slice_start:
                slice_end = slice_start

            anchor_on_before = before is not None or after is None
            if limit and (slice_end - slice_start) > limit:
                if anchor_on_before:
                    result_start = max(slice_start, slice_end - limit)
                    result_end = slice_end
                else:
                    result_start = slice_start
                    result_end = min(slice_end, slice_start + limit)
            else:
                result_start = slice_start
                result_end = slice_end

            selected = visible_rows[result_start:result_end]
            if selected:
                seqs = [int(row["message_seq"]) for row in selected]
                placeholders = ",".join("?" for _ in seqs)
                page_rows = connection.execute(
                    f"""
                    SELECT *
                    FROM session_messages
                    WHERE session_id = ? AND message_seq IN ({placeholders})
                    ORDER BY message_seq ASC
                    """,
                    [session_id, *seqs],
                ).fetchall()
            else:
                page_rows = []

        items = [self._message_row_to_payload(session_id, row) for row in page_rows]
        return {
            "session_id": session_id,
            "items": items,
            "page_info": {
                "limit": limit,
                "before": before,
                "after": after,
                "returned": len(items),
                "has_more_before": result_start > slice_start,
                "has_more_after": result_end < slice_end,
                "next_before": items[0]["message_id"] if items and result_start > slice_start else None,
                "next_after": items[-1]["message_id"] if items and result_end < slice_end else None,
            },
        }

    def get_import_manifest(self, manifest_key: str) -> ImportManifestEntry | None:
        with self.factory.session() as connection:
            row = connection.execute(
                "SELECT * FROM import_manifest WHERE manifest_key = ?",
                (manifest_key,),
            ).fetchone()
        if row is None:
            return None
        return ImportManifestEntry(
            manifest_key=str(row["manifest_key"]),
            domain=str(row["domain"]),
            source_path=str(row["source_path"]),
            source_mtime_ns=int(row["source_mtime_ns"]),
            source_size=int(row["source_size"]),
            imported_at=str(row["imported_at"]),
            checksum_sha256=str(row["checksum_sha256"]) if row["checksum_sha256"] else None,
            details=self._load_metadata(row["details_json"]),
        )

    def schema_version(self) -> int:
        with self.factory.session() as connection:
            row = connection.execute("PRAGMA user_version").fetchone()
        return int(row[0] or 0) if row is not None else 0

    def latest_imported_at(self) -> str | None:
        with self.factory.session() as connection:
            row = connection.execute(
                """
                SELECT imported_at
                FROM import_manifest
                ORDER BY imported_at DESC
                LIMIT 1
                """
            ).fetchone()
        if row is None:
            return None
        return str(row["imported_at"] or "") or None

    def storage_stats(self) -> dict[str, int]:
        with self.factory.session() as connection:
            session_row = connection.execute(
                "SELECT COUNT(*) AS count FROM sessions"
            ).fetchone()
            message_row = connection.execute(
                "SELECT COUNT(*) AS count FROM session_messages"
            ).fetchone()
            app_session_row = connection.execute(
                "SELECT COUNT(*) AS count FROM sessions WHERE channel = ?",
                (APP_CHANNEL,),
            ).fetchone()
            archived_row = connection.execute(
                "SELECT COUNT(*) AS count FROM sessions WHERE archived = 1"
            ).fetchone()
            manifest_row = connection.execute(
                "SELECT COUNT(*) AS count FROM import_manifest"
            ).fetchone()
            imported_session_row = connection.execute(
                """
                SELECT COUNT(*) AS count
                FROM import_manifest
                WHERE domain = 'session'
                """
            ).fetchone()
        return {
            "sessions": int(session_row["count"]) if session_row is not None else 0,
            "messages": int(message_row["count"]) if message_row is not None else 0,
            "app_sessions": int(app_session_row["count"]) if app_session_row is not None else 0,
            "archived_sessions": int(archived_row["count"]) if archived_row is not None else 0,
            "import_manifest_entries": int(manifest_row["count"]) if manifest_row is not None else 0,
            "imported_sessions": int(imported_session_row["count"]) if imported_session_row is not None else 0,
        }

    def read_import_manifest(self, manifest_key: str) -> dict[str, Any] | None:
        entry = self.get_import_manifest(manifest_key)
        if entry is None:
            return None
        return {
            "manifest_key": entry.manifest_key,
            "domain": entry.domain,
            "source_path": entry.source_path,
            "source_mtime_ns": entry.source_mtime_ns,
            "source_size": entry.source_size,
            "imported_at": entry.imported_at,
            "checksum_sha256": entry.checksum_sha256,
            "details": deepcopy(entry.details),
            "status": "imported",
        }

    def upsert_import_manifest(
        self,
        *,
        manifest_key: str,
        domain: str,
        source_path: Path,
        source_mtime_ns: int,
        source_size: int,
        imported_at: str,
        checksum_sha256: str | None,
        details: dict[str, Any],
    ) -> None:
        with self.factory.session() as connection:
            connection.execute(
                """
                INSERT INTO import_manifest (
                    manifest_key,
                    domain,
                    source_path,
                    source_mtime_ns,
                    source_size,
                    imported_at,
                    checksum_sha256,
                    details_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(manifest_key) DO UPDATE SET
                    domain = excluded.domain,
                    source_path = excluded.source_path,
                    source_mtime_ns = excluded.source_mtime_ns,
                    source_size = excluded.source_size,
                    imported_at = excluded.imported_at,
                    checksum_sha256 = excluded.checksum_sha256,
                    details_json = excluded.details_json
                """,
                (
                    manifest_key,
                    domain,
                    str(source_path),
                    int(source_mtime_ns),
                    int(source_size),
                    imported_at,
                    checksum_sha256,
                    json.dumps(details, ensure_ascii=False),
                ),
            )
            connection.commit()

    def _build_rows(self, session: Session) -> tuple[tuple[Any, ...], list[tuple[Any, ...]]]:
        metadata = deepcopy(session.metadata)
        created_at = session.created_at.isoformat()
        updated_at = session.updated_at.isoformat()
        channel = str(
            metadata.get("channel")
            or (session.key.split(":", 1)[0] if ":" in session.key else "unknown")
        )
        title = str(metadata.get("title") or self._placeholder_title_for(session.key))
        title_source = self._coerce_title_source(
            metadata.get("title_source"),
            session_id=session.key,
            title=title,
        )
        pinned = 1 if bool(metadata.get("pinned", session.key == DEFAULT_APP_SESSION_ID)) else 0
        archived = 1 if bool(metadata.get("archived", False)) else 0

        message_rows: list[tuple[Any, ...]] = []
        summary_preview = ""
        last_message_at = updated_at
        visible_index = 0
        visible_count = 0
        for index, entry in enumerate(session.messages, start=1):
            raw_json = json.dumps(entry, ensure_ascii=False)
            role = str(entry.get("role") or "system")
            created = str(entry.get("timestamp") or updated_at)
            content_text = self._content_to_text(entry.get("content"))
            visible = role in {"user", "assistant", "system"} and bool(content_text)
            message_id = entry.get("message_id")
            if visible:
                visible_index += 1
                visible_count += 1
                if not message_id:
                    message_id = f"msg_{session.key.replace(':', '_')}_{visible_index}"
                summary_preview = content_text[:80]
                last_message_at = created

            message_rows.append(
                (
                    session.key,
                    index,
                    self._coerce_optional_text(message_id),
                    role,
                    created,
                    1 if visible else 0,
                    content_text or None,
                    self._coerce_optional_text(entry.get("task_id")),
                    self._coerce_optional_text(entry.get("client_message_id")),
                    self._coerce_optional_text(entry.get("source_channel")),
                    self._coerce_optional_text(entry.get("interaction_surface")),
                    self._coerce_optional_text(entry.get("capture_source")),
                    self._coerce_optional_text(entry.get("app_session_id")),
                    raw_json,
                )
            )

        session_row = (
            session.key,
            channel,
            created_at,
            updated_at,
            title,
            title_source,
            pinned,
            archived,
            visible_count,
            last_message_at,
            summary_preview,
            int(session.last_consolidated),
            json.dumps(metadata, ensure_ascii=False),
        )
        return session_row, message_rows

    @staticmethod
    def _upsert_session_row(connection: Any, session_row: tuple[Any, ...]) -> None:
        connection.execute(
            """
            INSERT INTO sessions (
                session_id,
                channel,
                created_at,
                updated_at,
                title,
                title_source,
                pinned,
                archived,
                message_count,
                last_message_at,
                summary_preview,
                last_consolidated_seq,
                metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                channel = excluded.channel,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                title = excluded.title,
                title_source = excluded.title_source,
                pinned = excluded.pinned,
                archived = excluded.archived,
                message_count = excluded.message_count,
                last_message_at = excluded.last_message_at,
                summary_preview = excluded.summary_preview,
                last_consolidated_seq = excluded.last_consolidated_seq,
                metadata_json = excluded.metadata_json
            """,
            session_row,
        )

    def _replace_messages(
        self,
        connection: Any,
        session_id: str,
        message_rows: list[tuple[Any, ...]],
    ) -> None:
        connection.execute(
            "DELETE FROM session_messages WHERE session_id = ?",
            (session_id,),
        )
        if message_rows:
            self._insert_message_rows(connection, message_rows)

    @staticmethod
    def _insert_message_rows(
        connection: Any,
        message_rows: list[tuple[Any, ...]],
    ) -> None:
        connection.executemany(
            """
            INSERT INTO session_messages (
                session_id,
                message_seq,
                message_id,
                role,
                created_at,
                visible,
                content_text,
                task_id,
                client_message_id,
                source_channel,
                interaction_surface,
                capture_source,
                app_session_id,
                raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            message_rows,
        )

    @staticmethod
    def _message_count(connection: Any, session_id: str) -> int:
        row = connection.execute(
            """
            SELECT COUNT(*) AS total
            FROM session_messages
            WHERE session_id = ?
            """,
            (session_id,),
        ).fetchone()
        return int(row["total"] or 0) if row is not None else 0

    def _message_row_to_payload(
        self,
        session_id: str,
        row: Any,
    ) -> dict[str, Any]:
        entry = json.loads(row["raw_json"])
        entry_message_id = entry.get("message_id")
        return {
            "message_id": row["message_id"]
            or (str(entry_message_id) if entry_message_id is not None else None)
            or f"msg_{session_id.replace(':', '_')}_{row['message_seq']}",
            "session_id": session_id,
            "role": str(row["role"]),
            "content": str(row["content_text"] or ""),
            "content_type": "text",
            "status": "completed",
            "created_at": str(row["created_at"]),
            "metadata": self._extract_message_metadata(entry),
        }

    def _session_row_to_summary(
        self,
        row: Any,
        *,
        active_session_id: str | None,
    ) -> dict[str, Any]:
        session_id = str(row["session_id"])
        metadata = self._load_metadata(row["metadata_json"])
        persona_profile = deepcopy(metadata.get("persona_profile"))
        return {
            "session_id": session_id,
            "channel": str(metadata.get("channel") or row["channel"] or APP_CHANNEL),
            "title": str(metadata.get("title") or row["title"] or self._placeholder_title_for(session_id)),
            "summary": str(row["summary_preview"] or ""),
            "last_message_at": str(row["last_message_at"] or row["updated_at"]),
            "message_count": int(row["message_count"] or 0),
            "pinned": bool(row["pinned"]),
            "archived": bool(row["archived"]),
            "active": session_id == active_session_id,
            "scene_mode": metadata.get("scene_mode"),
            "persona_profile": persona_profile,
            "persona_profile_id": (
                persona_profile.get("preset")
                if isinstance(persona_profile, dict)
                else None
            ),
            "persona_fields": deepcopy(metadata.get("persona_fields") or {}),
        }

    @staticmethod
    def _load_metadata(raw: str) -> dict[str, Any]:
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return payload if isinstance(payload, dict) else {}

    @staticmethod
    def _parse_datetime(raw: str | None) -> datetime:
        if raw:
            try:
                return datetime.fromisoformat(raw)
            except ValueError:
                pass
        return datetime.now()

    @staticmethod
    def _content_to_text(content: Any) -> str:
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "text" and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif item.get("type") == "image_url":
                    parts.append("[image]")
            return "\n".join(part for part in parts if part).strip()
        return ""

    @staticmethod
    def _extract_message_metadata(entry: dict[str, Any]) -> dict[str, Any]:
        metadata: dict[str, Any] = {}
        for key in (
            "task_id",
            "client_message_id",
            "source",
            "interaction_surface",
            "capture_source",
            "voice_path",
            "source_channel",
            "reply_language",
            "emotion",
            "app_session_id",
        ):
            if entry.get(key) is not None:
                metadata[key] = entry[key]
        if entry.get("tool_results") is not None:
            metadata["tool_results"] = entry["tool_results"]
        return metadata

    @staticmethod
    def _placeholder_title_for(session_id: str) -> str:
        if session_id == DEFAULT_APP_SESSION_ID:
            return "主对话"
        return "新对话"

    @classmethod
    def _is_defaultish_title(cls, session_id: str, title: Any) -> bool:
        if not isinstance(title, str):
            return True
        cleaned = title.strip()
        if not cleaned:
            return True
        session_suffix = session_id.split(":", 1)[1].strip() if ":" in session_id else session_id.strip()
        return cleaned in {
            session_suffix,
            cls._placeholder_title_for(session_id),
            "New conversation",
            "Conversation",
            "Untitled session",
        }

    @classmethod
    def _coerce_title_source(
        cls,
        raw: Any,
        *,
        session_id: str,
        title: Any,
    ) -> str:
        if raw in {"user", "default", "generated"}:
            return str(raw)
        return "default" if cls._is_defaultish_title(session_id, title) else "user"

    @staticmethod
    def _coerce_optional_text(value: Any) -> str | None:
        if value is None:
            return None
        return str(value)
