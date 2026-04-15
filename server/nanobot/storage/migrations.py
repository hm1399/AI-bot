"""Schema migration runner for the workspace SQLite database."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from nanobot.storage.sqlite_db import (
    SQLiteConnectionFactory,
    create_connection_factory,
    get_user_version,
    set_user_version,
)


LATEST_USER_VERSION = 2


MIGRATIONS: dict[int, str] = {
    1: """
    CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY,
        channel TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        title TEXT NOT NULL,
        title_source TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        message_count INTEGER NOT NULL DEFAULT 0,
        last_message_at TEXT,
        summary_preview TEXT,
        last_consolidated_seq INTEGER NOT NULL DEFAULT 0,
        metadata_json TEXT NOT NULL
    ) STRICT;

    CREATE INDEX IF NOT EXISTS idx_sessions_channel_updated
        ON sessions(channel, updated_at DESC);

    CREATE INDEX IF NOT EXISTS idx_sessions_channel_archived_pinned
        ON sessions(channel, archived, pinned DESC, updated_at DESC);

    CREATE TABLE IF NOT EXISTS session_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
        message_seq INTEGER NOT NULL CHECK (message_seq >= 1),
        message_id TEXT,
        role TEXT NOT NULL,
        created_at TEXT NOT NULL,
        visible INTEGER NOT NULL CHECK (visible IN (0, 1)),
        content_text TEXT,
        task_id TEXT,
        client_message_id TEXT,
        source_channel TEXT,
        interaction_surface TEXT,
        capture_source TEXT,
        app_session_id TEXT,
        raw_json TEXT NOT NULL,
        UNIQUE(session_id, message_seq)
    ) STRICT;

    CREATE INDEX IF NOT EXISTS idx_session_messages_session_created
        ON session_messages(session_id, created_at DESC);

    CREATE INDEX IF NOT EXISTS idx_session_messages_session_message_id
        ON session_messages(session_id, message_id);

    CREATE INDEX IF NOT EXISTS idx_session_messages_session_visible_seq
        ON session_messages(session_id, visible, message_seq);

    CREATE TABLE IF NOT EXISTS import_manifest (
        manifest_key TEXT PRIMARY KEY,
        domain TEXT NOT NULL,
        source_path TEXT NOT NULL,
        source_mtime_ns INTEGER NOT NULL,
        source_size INTEGER NOT NULL,
        imported_at TEXT NOT NULL,
        checksum_sha256 TEXT,
        details_json TEXT NOT NULL
    ) STRICT;

    CREATE INDEX IF NOT EXISTS idx_import_manifest_domain
        ON import_manifest(domain, imported_at DESC);
    """,
    2: """
    -- Reserved shared-schema marker for workspace state.sqlite3.
    """,
}


def _coerce_factory(
    target: SQLiteConnectionFactory | Path | str,
) -> SQLiteConnectionFactory:
    if isinstance(target, SQLiteConnectionFactory):
        return target
    return create_connection_factory(Path(target))


def run_migrations(target: SQLiteConnectionFactory | Path | str) -> int:
    factory = _coerce_factory(target)
    with factory.session() as connection:
        current_version = get_user_version(connection)
        if current_version > LATEST_USER_VERSION:
            raise RuntimeError(
                f"SQLite schema version {current_version} is newer than supported {LATEST_USER_VERSION}"
            )

        _ensure_foundational_schema(connection)

        while current_version < LATEST_USER_VERSION:
            next_version = current_version + 1
            script = MIGRATIONS.get(next_version)
            if not script:
                raise RuntimeError(f"Missing migration for SQLite user_version {next_version}")
            _apply_migration(connection, script=script, version=next_version)
            current_version = next_version

        return current_version


def _ensure_foundational_schema(connection: sqlite3.Connection) -> None:
    """Ensure session tables exist even when another subsystem already bumped user_version."""
    connection.executescript(MIGRATIONS[1])


def _apply_migration(
    connection: sqlite3.Connection,
    *,
    script: str,
    version: int,
) -> None:
    connection.execute("BEGIN;")
    try:
        connection.executescript(script)
        set_user_version(connection, version)
        connection.commit()
    except Exception:
        connection.rollback()
        raise
