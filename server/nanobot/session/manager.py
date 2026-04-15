"""Session management for conversation history."""

from __future__ import annotations

import json
import os
import shutil
from collections.abc import Mapping
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any

from loguru import logger

from nanobot.utils.atomic_write import atomic_write_text
from nanobot.utils.helpers import ensure_dir, safe_filename

if TYPE_CHECKING:
    from nanobot.session.jsonl_importer import SessionJsonlImporter
    from nanobot.session.sqlite_backend import SQLiteSessionBackend


APP_CHANNEL = "app"
DEFAULT_APP_SESSION_ID = "app:main"


@dataclass
class Session:
    """
    A conversation session.

    Stores messages in JSONL format for easy reading and persistence.

    Important: Messages are append-only for LLM cache efficiency.
    The consolidation process writes summaries to MEMORY.md/HISTORY.md
    but does NOT modify the messages list or get_history() output.
    """

    key: str  # channel:chat_id
    messages: list[dict[str, Any]] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)
    metadata: dict[str, Any] = field(default_factory=dict)
    last_consolidated: int = 0  # Number of messages already consolidated to files

    def add_message(self, role: str, content: str, **kwargs: Any) -> None:
        """Add a message to the session."""
        msg = {
            "role": role,
            "content": content,
            "timestamp": datetime.now().isoformat(),
            **kwargs,
        }
        self.messages.append(msg)
        self.updated_at = datetime.now()

    def get_history(self, max_messages: int = 500) -> list[dict[str, Any]]:
        """Return unconsolidated messages for LLM input, aligned to a user turn."""
        unconsolidated = self.messages[self.last_consolidated:]
        sliced = unconsolidated[-max_messages:]

        # Drop leading non-user messages to avoid orphaned tool_result blocks
        for i, message in enumerate(sliced):
            if message.get("role") == "user":
                sliced = sliced[i:]
                break

        out: list[dict[str, Any]] = []
        for message in sliced:
            entry: dict[str, Any] = {"role": message["role"], "content": message.get("content", "")}
            for key in ("tool_calls", "tool_call_id", "name"):
                if key in message:
                    entry[key] = message[key]
            out.append(entry)
        return out

    def clear(self) -> None:
        """Clear all messages and reset session to initial state."""
        self.messages = []
        self.last_consolidated = 0
        self.updated_at = datetime.now()


class SessionManager:
    """
    Manages conversation sessions.

    Sessions are stored as JSONL files in the sessions directory by default,
    with optional SQLite shadowing/cutover modes.
    """

    def __init__(
        self,
        workspace: Path,
        *,
        storage_mode: str | None = None,
        sqlite_path: Path | None = None,
        storage_config: Mapping[str, Any] | None = None,
        legacy_sessions_dir: Path | None = None,
    ):
        self.workspace = workspace
        self.sessions_dir = ensure_dir(self.workspace / "sessions")
        self.legacy_sessions_dir = Path(legacy_sessions_dir) if legacy_sessions_dir is not None else Path.home() / ".nanobot" / "sessions"
        self._cache: dict[str, Session] = {}
        self._sqlite_saved_message_counts: dict[str, int] = {}
        self._shadow_failure_count = 0
        self._shadow_last_error: str | None = None
        self._shadow_last_error_at: str | None = None
        self._import_failure_count = 0
        self._import_last_error: str | None = None
        self._import_last_error_at: str | None = None

        configured_mode = (
            (
                str(storage_config.get("session_storage_mode") or "").strip()
                if storage_config is not None
                else ""
            )
            or storage_mode
            or os.getenv("NANOBOT_SESSION_STORAGE_MODE")
            or "json"
        )
        self.storage_mode = str(configured_mode).strip().lower()
        if self.storage_mode not in {"json", "dual", "sqlite"}:
            raise ValueError(f"unsupported session storage mode: {self.storage_mode}")

        configured_sqlite_path = (
            str(storage_config.get("sqlite_path") or "").strip()
            if storage_config is not None
            else ""
        )
        self.sqlite_path = Path(
            configured_sqlite_path
            or sqlite_path
            or os.getenv("NANOBOT_STATE_DB_PATH")
            or (self.workspace / "state.sqlite3")
        )
        self._sqlite_backend: SQLiteSessionBackend | None = None
        self._jsonl_importer: SessionJsonlImporter | None = None
        if self.storage_mode in {"dual", "sqlite"}:
            from nanobot.session.jsonl_importer import SessionJsonlImporter
            from nanobot.session.sqlite_backend import SQLiteSessionBackend

            self._sqlite_backend = SQLiteSessionBackend(self.sqlite_path)
            self._jsonl_importer = SessionJsonlImporter(
                backend=self._sqlite_backend,
                sessions_dir=self.sessions_dir,
                legacy_sessions_dir=self.legacy_sessions_dir,
            )

    def _get_session_path(self, key: str) -> Path:
        """Get the file path for a session."""
        safe_key = safe_filename(key.replace(":", "_"))
        return self.sessions_dir / f"{safe_key}.jsonl"

    def _get_legacy_session_path(self, key: str) -> Path:
        """Legacy global session path (~/.nanobot/sessions/)."""
        safe_key = safe_filename(key.replace(":", "_"))
        return self.legacy_sessions_dir / f"{safe_key}.jsonl"

    def get_or_create(self, key: str) -> Session:
        """
        Get an existing session or create a new one.

        Args:
            key: Session key (usually channel:chat_id).

        Returns:
            The session.
        """
        if key in self._cache:
            return self._cache[key]

        session = self._load(key)
        if session is None:
            session = Session(key=key)

        self._cache[key] = session
        self._remember_sqlite_message_count(session)
        return session

    def _load(self, key: str) -> Session | None:
        """Load a session from the configured backing store."""
        if self.storage_mode == "json":
            return self._load_json(key)

        if self.storage_mode == "dual":
            session = self._load_json(key)
            self._shadow_import_session(key)
            if session is not None:
                return session
            return self._load_sqlite(key)

        session = self._load_sqlite(key)
        if session is not None:
            return session
        if self._import_session_to_sqlite(key):
            return self._load_sqlite(key)
        return None

    def _load_json(self, key: str) -> Session | None:
        path = self._get_session_path(key)
        if not path.exists():
            legacy_path = self._get_legacy_session_path(key)
            if legacy_path.exists():
                try:
                    shutil.move(str(legacy_path), str(path))
                    logger.info("Migrated session {} from legacy path", key)
                except Exception:
                    logger.exception("Failed to migrate session {}", key)

        if not path.exists():
            return None

        try:
            messages = []
            metadata = {}
            created_at = None
            updated_at = None
            last_consolidated = 0

            with open(path, encoding="utf-8") as handle:
                for raw_line in handle:
                    line = raw_line.strip()
                    if not line:
                        continue

                    data = json.loads(line)
                    if data.get("_type") == "metadata":
                        metadata = data.get("metadata", {})
                        created_at = datetime.fromisoformat(data["created_at"]) if data.get("created_at") else None
                        updated_at = datetime.fromisoformat(data["updated_at"]) if data.get("updated_at") else None
                        last_consolidated = data.get("last_consolidated", 0)
                    else:
                        messages.append(data)

            return Session(
                key=key,
                messages=messages,
                created_at=created_at or datetime.now(),
                updated_at=updated_at or created_at or datetime.now(),
                metadata=metadata,
                last_consolidated=last_consolidated,
            )
        except Exception as exc:
            logger.warning("Failed to load session {}: {}", key, exc)
            return None

    def _load_sqlite(self, key: str) -> Session | None:
        if self._sqlite_backend is None:
            return None
        try:
            return self._sqlite_backend.get(key)
        except Exception:
            logger.exception("Failed to load session {} from SQLite", key)
            return None

    def get(self, key: str) -> Session | None:
        """Get an existing session without implicitly creating it."""
        if key in self._cache:
            return self._cache[key]

        session = self._load(key)
        if session is not None:
            self._cache[key] = session
            self._remember_sqlite_message_count(session)
        return session

    def exists(self, key: str) -> bool:
        """Return whether a session exists on disk or in cache."""
        if key in self._cache:
            return True
        if self.storage_mode == "json":
            return self._json_exists(key)
        if self._sqlite_backend and self._sqlite_backend.exists(key):
            return True
        return self._json_exists(key)

    @staticmethod
    def _restore_session(target: Session, source: Session) -> None:
        """Restore a session object from a persisted snapshot."""
        target.messages = deepcopy(source.messages)
        target.created_at = source.created_at
        target.updated_at = source.updated_at
        target.metadata = deepcopy(source.metadata)
        target.last_consolidated = source.last_consolidated

    def save(self, session: Session) -> None:
        """Save a session to disk."""
        if self.storage_mode == "json":
            self._save_json(session)
            return

        if self.storage_mode == "dual":
            self._save_json(session)
            if self._sqlite_backend is not None:
                try:
                    self._save_sqlite(session)
                except Exception as exc:
                    self._shadow_failure_count += 1
                    self._shadow_last_error = str(exc)
                    self._shadow_last_error_at = datetime.now().isoformat()
                    logger.exception("Failed to shadow-save session {} to SQLite", session.key)
            self._cache[session.key] = session
            return

        cached_session = self._cache.get(session.key)
        rollback_session = self._sqlite_backend.get(session.key) if cached_session is session and self._sqlite_backend else None
        try:
            if self._sqlite_backend is None:
                raise RuntimeError("SQLite backend is not configured")
            self._save_sqlite(session)
        except Exception:
            if cached_session is session:
                if rollback_session is None:
                    self._cache.pop(session.key, None)
                else:
                    self._restore_session(session, rollback_session)
                    self._cache[session.key] = session
                    self._remember_sqlite_message_count(session)
            raise
        self._cache[session.key] = session

    def _save_json(self, session: Session) -> None:
        path = self._get_session_path(session.key)
        cached_session = self._cache.get(session.key)
        rollback_session = self._load_json(session.key) if cached_session is session else None

        def write_session(handle) -> None:
            metadata_line = {
                "_type": "metadata",
                "key": session.key,
                "created_at": session.created_at.isoformat(),
                "updated_at": session.updated_at.isoformat(),
                "metadata": session.metadata,
                "last_consolidated": session.last_consolidated,
            }
            handle.write(json.dumps(metadata_line, ensure_ascii=False) + "\n")
            for message in session.messages:
                handle.write(json.dumps(message, ensure_ascii=False) + "\n")

        try:
            atomic_write_text(path, write_session, encoding="utf-8")
        except Exception:
            if cached_session is session:
                if rollback_session is None:
                    self._cache.pop(session.key, None)
                else:
                    self._restore_session(session, rollback_session)
                    self._cache[session.key] = session
            raise
        self._cache[session.key] = session

    def invalidate(self, key: str) -> None:
        """Remove a session from the in-memory cache."""
        self._cache.pop(key, None)
        self._sqlite_saved_message_counts.pop(key, None)

    def list_sessions(self) -> list[dict[str, Any]]:
        """
        List all sessions.

        Returns:
            List of session info dicts.
        """
        if self.storage_mode == "json":
            return self._list_json_sessions()

        if self.storage_mode == "dual":
            self._import_all_to_sqlite()
            sessions = self._list_json_sessions()
            return sessions or (self._sqlite_backend.list_sessions() if self._sqlite_backend else [])

        self._import_all_to_sqlite()
        return self._sqlite_backend.list_sessions() if self._sqlite_backend else []

    def list_app_sessions(
        self,
        *,
        limit: int,
        archived: bool | None = None,
        pinned_first: bool = True,
        active_session_id: str | None = None,
    ) -> list[dict[str, Any]]:
        if self.storage_mode in {"dual", "sqlite"} and self._sqlite_backend is not None:
            if self.storage_mode == "sqlite":
                self._import_all_to_sqlite()
            elif self.storage_mode == "dual":
                self._import_all_to_sqlite()
            try:
                payload = self._sqlite_backend.list_app_sessions(
                    limit=limit,
                    archived=archived,
                    pinned_first=pinned_first,
                    active_session_id=active_session_id,
                )
                if payload:
                    return payload
            except Exception:
                logger.exception("Failed to list app sessions from SQLite")

        sessions: list[dict[str, Any]] = []
        for item in self._list_json_sessions():
            key = item.get("key", "")
            if not key.startswith("app:"):
                continue
            session = self.get(key)
            if session is None:
                continue
            summary = self._build_session_summary(
                session,
                active_session_id=active_session_id,
            )
            if archived is not None and summary["archived"] != archived:
                continue
            sessions.append(summary)

        sessions.sort(key=lambda item: item["last_message_at"] or "", reverse=True)
        if pinned_first:
            sessions.sort(key=lambda item: not item["pinned"])
        if limit:
            sessions = sessions[:limit]
        return sessions

    def get_session_summary(
        self,
        key: str,
        *,
        active_session_id: str | None = None,
    ) -> dict[str, Any] | None:
        if self.storage_mode in {"dual", "sqlite"} and self._sqlite_backend is not None:
            if not self._sqlite_backend.exists(key):
                self._import_session_to_sqlite(key)
            try:
                payload = self._sqlite_backend.get_session_summary(
                    key,
                    active_session_id=active_session_id,
                )
                if isinstance(payload, dict):
                    return payload
            except Exception:
                logger.exception("Failed to get session summary for {} from SQLite", key)

        session = self.get(key)
        if session is None:
            return None
        return self._build_session_summary(session, active_session_id=active_session_id)

    def get_messages_page(
        self,
        session_id: str,
        *,
        before: str | None = None,
        after: str | None = None,
        limit: int = 50,
    ) -> dict[str, Any]:
        if self.storage_mode in {"dual", "sqlite"} and self._sqlite_backend is not None:
            if not self._sqlite_backend.exists(session_id):
                self._import_session_to_sqlite(session_id)
            try:
                return self._sqlite_backend.get_messages_page(
                    session_id,
                    before=before,
                    after=after,
                    limit=limit,
                )
            except Exception:
                if self.storage_mode == "sqlite":
                    raise
                logger.exception("Falling back to JSON message pagination for {}", session_id)

        session = self.get(session_id)
        if session is None:
            raise KeyError(session_id)

        messages = self._serialize_messages(session)
        page, error = self._paginate_messages(
            session_id=session_id,
            messages=messages,
            before=before,
            after=after,
            limit=limit,
        )
        if error:
            raise ValueError(error)
        return page

    def _shadow_import_session(self, key: str) -> None:
        if self.storage_mode != "dual":
            return
        self._import_session_to_sqlite(key)

    def _import_session_to_sqlite(self, key: str) -> bool:
        if self._jsonl_importer is None:
            return False
        try:
            imported = self._jsonl_importer.import_session(key)
            if imported:
                session = self._load_sqlite(key)
                if session is not None:
                    self._remember_sqlite_message_count(session)
            return imported
        except Exception as exc:
            self._import_failure_count += 1
            self._import_last_error = str(exc)
            self._import_last_error_at = datetime.now().isoformat()
            logger.exception("Failed to import session {} into SQLite", key)
            return False

    def _import_all_to_sqlite(self) -> None:
        if self._jsonl_importer is None:
            return
        try:
            self._jsonl_importer.import_all()
        except Exception as exc:
            self._import_failure_count += 1
            self._import_last_error = str(exc)
            self._import_last_error_at = datetime.now().isoformat()
            logger.exception("Failed to import JSONL sessions into SQLite")

    def session_store_diagnostics(self) -> dict[str, Any]:
        schema_version = 0
        latest_imported_at = None
        sqlite_stats = {
            "sessions": 0,
            "messages": 0,
            "app_sessions": 0,
            "archived_sessions": 0,
            "import_manifest_entries": 0,
            "imported_sessions": 0,
        }
        if self._sqlite_backend is not None:
            try:
                schema_version = self._sqlite_backend.schema_version()
                latest_imported_at = self._sqlite_backend.latest_imported_at()
                sqlite_stats = self._sqlite_backend.storage_stats()
            except Exception:
                logger.exception("Failed to read session SQLite runtime state")

        json_session_count = len(self._list_json_sessions())
        return {
            "mode": self.storage_mode,
            "primary_backend": "sqlite" if self.storage_mode == "sqlite" else "jsonl",
            "shadow_backend": "sqlite" if self.storage_mode == "dual" else None,
            "sqlite_path": str(self.sqlite_path),
            "sqlite_ready": bool(self._sqlite_backend and self.sqlite_path.exists()),
            "schema_version": schema_version,
            "latest_imported_at": latest_imported_at,
            "paths": {
                "workspace_sessions_dir": str(self.sessions_dir),
                "legacy_sessions_dir": str(self.legacy_sessions_dir),
            },
            "stats": {
                "cached_sessions": len(self._cache),
                "json_sessions": json_session_count,
                "sqlite_sessions": int(sqlite_stats.get("sessions", 0) or 0),
                "sqlite_messages": int(sqlite_stats.get("messages", 0) or 0),
                "app_sessions": int(sqlite_stats.get("app_sessions", 0) or 0),
                "archived_sessions": int(sqlite_stats.get("archived_sessions", 0) or 0),
                "import_manifest_entries": int(sqlite_stats.get("import_manifest_entries", 0) or 0),
                "imported_sessions": int(sqlite_stats.get("imported_sessions", 0) or 0),
                "sqlite_pending_backfill_estimate": max(
                    0,
                    json_session_count - int(sqlite_stats.get("sessions", 0) or 0),
                ),
            },
            "shadow": {
                "enabled": self.storage_mode == "dual",
                "failure_count": self._shadow_failure_count,
                "last_error": self._shadow_last_error,
                "last_error_at": self._shadow_last_error_at,
            },
            "imports": {
                "enabled": self._jsonl_importer is not None,
                "failure_count": self._import_failure_count,
                "last_error": self._import_last_error,
                "last_error_at": self._import_last_error_at,
                "latest_imported_at": latest_imported_at,
            },
        }

    def storage_runtime_state(self) -> dict[str, Any]:
        diagnostics = self.session_store_diagnostics()
        return {
            "mode": diagnostics["mode"],
            "primary_backend": diagnostics["primary_backend"],
            "shadow_backend": diagnostics["shadow_backend"],
            "sqlite_path": diagnostics["sqlite_path"],
            "sqlite_ready": diagnostics["sqlite_ready"],
            "schema_version": diagnostics["schema_version"],
            "latest_imported_at": diagnostics["latest_imported_at"],
            "shadow_failures": self._shadow_failure_count,
            "imports": deepcopy(diagnostics["imports"]),
            "shadow": deepcopy(diagnostics["shadow"]),
            "stats": deepcopy(diagnostics["stats"]),
            "paths": deepcopy(diagnostics["paths"]),
        }

    def _save_sqlite(self, session: Session) -> None:
        if self._sqlite_backend is None:
            raise RuntimeError("SQLite backend is not configured")
        previous_message_count = self._sqlite_saved_message_counts.get(session.key)
        if previous_message_count is None:
            self._sqlite_backend.save(session)
        else:
            self._sqlite_backend.save_incremental(
                session,
                previous_message_count=previous_message_count,
            )
        self._remember_sqlite_message_count(session)

    def _remember_sqlite_message_count(self, session: Session) -> None:
        if self.storage_mode in {"dual", "sqlite"}:
            self._sqlite_saved_message_counts[session.key] = len(session.messages)

    def _json_exists(self, key: str) -> bool:
        return self._get_session_path(key).exists() or self._get_legacy_session_path(key).exists()

    def _list_json_sessions(self) -> list[dict[str, Any]]:
        sessions = []

        for path in self.sessions_dir.glob("*.jsonl"):
            try:
                with open(path, encoding="utf-8") as handle:
                    first_line = handle.readline().strip()
                if not first_line:
                    continue
                data = json.loads(first_line)
                if data.get("_type") != "metadata":
                    continue
                key = data.get("key") or path.stem.replace("_", ":", 1)
                sessions.append(
                    {
                        "key": key,
                        "created_at": data.get("created_at"),
                        "updated_at": data.get("updated_at"),
                        "path": str(path),
                    }
                )
            except Exception as exc:
                logger.warning("Skipping invalid session file {}: {}", path, exc)
                continue

        return sorted(sessions, key=lambda item: item.get("updated_at", ""), reverse=True)

    def _build_session_summary(
        self,
        session: Session,
        *,
        active_session_id: str | None,
    ) -> dict[str, Any]:
        visible_messages = self._serialize_messages(session)
        last_message = visible_messages[-1] if visible_messages else None
        persona_profile = deepcopy(session.metadata.get("persona_profile"))
        return {
            "session_id": session.key,
            "channel": str(
                session.metadata.get("channel")
                or (APP_CHANNEL if session.key.startswith("app:") else session.key.split(":", 1)[0])
            ),
            "title": str(session.metadata.get("title") or self._placeholder_title_for(session.key)),
            "summary": str((last_message or {}).get("content", ""))[:80],
            "last_message_at": (last_message or {}).get("created_at") or session.updated_at.isoformat(),
            "message_count": len(visible_messages),
            "pinned": bool(session.metadata.get("pinned", session.key == DEFAULT_APP_SESSION_ID)),
            "archived": bool(session.metadata.get("archived", False)),
            "active": session.key == active_session_id,
            "scene_mode": session.metadata.get("scene_mode"),
            "persona_profile": persona_profile,
            "persona_profile_id": (
                persona_profile.get("preset")
                if isinstance(persona_profile, dict)
                else None
            ),
            "persona_fields": deepcopy(session.metadata.get("persona_fields") or {}),
        }

    def _serialize_messages(self, session: Session) -> list[dict[str, Any]]:
        messages: list[dict[str, Any]] = []
        visible_index = 0
        for entry in session.messages:
            role = entry.get("role")
            if role not in {"user", "assistant", "system"}:
                continue
            content = self._content_to_text(entry.get("content"))
            if not content:
                continue
            visible_index += 1
            messages.append(
                {
                    "message_id": entry.get("message_id") or f"msg_{session.key.replace(':', '_')}_{visible_index}",
                    "session_id": session.key,
                    "role": role,
                    "content": content,
                    "content_type": "text",
                    "status": "completed",
                    "created_at": entry.get("timestamp") or session.updated_at.isoformat(),
                    "metadata": self._extract_message_metadata(entry),
                }
            )
        return messages

    @staticmethod
    def _paginate_messages(
        *,
        session_id: str,
        messages: list[dict[str, Any]],
        before: str | None,
        after: str | None,
        limit: int,
    ) -> tuple[dict[str, Any], str | None]:
        id_to_index = {message["message_id"]: index for index, message in enumerate(messages)}

        if before and before not in id_to_index:
            return {}, "before cursor not found"
        if after and after not in id_to_index:
            return {}, "after cursor not found"

        slice_start = id_to_index[after] + 1 if after else 0
        slice_end = id_to_index[before] if before else len(messages)
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

        items = messages[result_start:result_end]
        return (
            {
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
            },
            None,
        )

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
    def _placeholder_title_for(session_id: str) -> str:
        if session_id == DEFAULT_APP_SESSION_ID:
            return "主对话"
        return "新对话"
