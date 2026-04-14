"""JSONL import helpers for SQLite-backed session storage."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from loguru import logger

from nanobot.session.manager import Session
from nanobot.session.sqlite_backend import SQLiteSessionBackend
from nanobot.utils.helpers import safe_filename


@dataclass(frozen=True)
class ImportedSessionSnapshot:
    session: Session
    record_count: int
    message_count: int


class JSONLSessionImporter:
    """Imports workspace and legacy JSONL sessions into SQLite."""

    def __init__(
        self,
        *,
        backend: SQLiteSessionBackend,
        workspace_sessions_dir: Path | None = None,
        sessions_dir: Path | None = None,
        legacy_sessions_dir: Path,
    ):
        self.backend = backend
        root_dir = sessions_dir if sessions_dir is not None else workspace_sessions_dir
        if root_dir is None:
            raise ValueError("workspace_sessions_dir or sessions_dir is required")
        self.workspace_sessions_dir = Path(root_dir)
        self.legacy_sessions_dir = Path(legacy_sessions_dir)

    def import_session(self, key: str) -> bool:
        path = self._find_session_path(key)
        if path is None:
            return False
        return self.import_path(path, preferred_key=key)

    def import_all_available(self) -> int:
        imported = 0
        seen_keys: set[str] = set()

        for base_dir in (self.workspace_sessions_dir, self.legacy_sessions_dir):
            if not base_dir.exists():
                continue
            for path in sorted(base_dir.glob("*.jsonl")):
                try:
                    snapshot = self.load_jsonl_session(path)
                except Exception:
                    logger.exception("Failed to inspect session JSONL {}", path)
                    continue
                if snapshot.session.key in seen_keys:
                    continue
                seen_keys.add(snapshot.session.key)
                imported += 1 if self.import_path(path, snapshot=snapshot) else 0
        return imported

    def import_all(self) -> int:
        return self.import_all_available()

    def import_path(
        self,
        path: Path,
        *,
        preferred_key: str | None = None,
        snapshot: ImportedSessionSnapshot | None = None,
    ) -> bool:
        target_path = Path(path)
        if not target_path.exists():
            return False

        stat = target_path.stat()
        snapshot = snapshot or self.load_jsonl_session(target_path, preferred_key=preferred_key)
        session_key = preferred_key or snapshot.session.key
        manifest_key = f"session:{session_key}"
        manifest = self.backend.get_import_manifest(manifest_key)
        if (
            manifest is not None
            and manifest.source_path == str(target_path)
            and manifest.source_mtime_ns == stat.st_mtime_ns
            and manifest.source_size == stat.st_size
        ):
            return False

        checksum = hashlib.sha256(target_path.read_bytes()).hexdigest()
        self.backend.save(snapshot.session)
        self.backend.upsert_import_manifest(
            manifest_key=manifest_key,
            domain="session",
            source_path=target_path,
            source_mtime_ns=stat.st_mtime_ns,
            source_size=stat.st_size,
            imported_at=datetime.now().isoformat(),
            checksum_sha256=checksum,
            details={
                "session_id": session_key,
                "record_count": snapshot.record_count,
                "message_count": snapshot.message_count,
            },
        )
        return True

    def _find_session_path(self, key: str) -> Path | None:
        safe_key = safe_filename(key.replace(":", "_"))
        workspace_path = self.workspace_sessions_dir / f"{safe_key}.jsonl"
        if workspace_path.exists():
            return workspace_path

        legacy_path = self.legacy_sessions_dir / f"{safe_key}.jsonl"
        if legacy_path.exists():
            return legacy_path

        for base_dir in (self.workspace_sessions_dir, self.legacy_sessions_dir):
            if not base_dir.exists():
                continue
            for path in base_dir.glob("*.jsonl"):
                try:
                    snapshot = self.load_jsonl_session(path)
                except Exception:
                    logger.exception("Failed to inspect session JSONL {}", path)
                    continue
                if snapshot.session.key == key:
                    return path
        return None

    @staticmethod
    def load_jsonl_session(
        path: Path,
        *,
        preferred_key: str | None = None,
    ) -> ImportedSessionSnapshot:
        messages: list[dict[str, Any]] = []
        metadata: dict[str, Any] = {}
        created_at: datetime | None = None
        updated_at: datetime | None = None
        session_key = preferred_key
        last_consolidated = 0
        record_count = 0

        with Path(path).open(encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line:
                    continue
                record_count += 1
                data = json.loads(line)
                if data.get("_type") == "metadata":
                    session_key = session_key or str(data.get("key") or "")
                    metadata = data.get("metadata", {}) or {}
                    if data.get("created_at"):
                        created_at = datetime.fromisoformat(str(data["created_at"]))
                    if data.get("updated_at"):
                        updated_at = datetime.fromisoformat(str(data["updated_at"]))
                    last_consolidated = int(data.get("last_consolidated", 0) or 0)
                else:
                    messages.append(data)

        if not session_key:
            session_key = Path(path).stem.replace("_", ":", 1)

        session = Session(
            key=session_key,
            messages=messages,
            created_at=created_at or datetime.now(),
            updated_at=updated_at or created_at or datetime.now(),
            metadata=metadata,
            last_consolidated=last_consolidated,
        )
        return ImportedSessionSnapshot(
            session=session,
            record_count=record_count,
            message_count=len(messages),
        )


SessionJsonlImporter = JSONLSessionImporter


def load_jsonl_session(path: Path, *, fallback_key: str | None = None) -> Session:
    return JSONLSessionImporter.load_jsonl_session(
        path,
        preferred_key=fallback_key,
    ).session
