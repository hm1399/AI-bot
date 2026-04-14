"""Shared SQLite helpers for local state storage."""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Sequence

from nanobot.utils.helpers import ensure_dir


@dataclass(frozen=True)
class SQLiteConnectionFactory:
    """Build consistently configured SQLite connections for the workspace state DB."""

    db_path: Path
    busy_timeout_ms: int = 5000

    def connect(self) -> sqlite3.Connection:
        ensure_dir(self.db_path.parent)
        connection = sqlite3.connect(
            str(self.db_path),
            timeout=self.busy_timeout_ms / 1000,
            check_same_thread=False,
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL;")
        connection.execute("PRAGMA foreign_keys=ON;")
        connection.execute(f"PRAGMA busy_timeout={self.busy_timeout_ms};")
        connection.execute("PRAGMA synchronous=NORMAL;")
        connection.execute("PRAGMA temp_store=MEMORY;")
        return connection

    @contextmanager
    def session(self) -> Iterator[sqlite3.Connection]:
        connection = self.connect()
        try:
            yield connection
        finally:
            connection.close()


def create_connection_factory(db_path: Path) -> SQLiteConnectionFactory:
    return SQLiteConnectionFactory(db_path=Path(db_path))


def get_user_version(connection: sqlite3.Connection) -> int:
    row = connection.execute("PRAGMA user_version;").fetchone()
    return int(row[0]) if row else 0


def set_user_version(connection: sqlite3.Connection, version: int) -> None:
    connection.execute(f"PRAGMA user_version={int(version)};")


def quick_check(factory: SQLiteConnectionFactory) -> list[str]:
    with factory.session() as connection:
        return [str(row[0]) for row in connection.execute("PRAGMA quick_check;").fetchall()]


def foreign_key_check(factory: SQLiteConnectionFactory) -> list[dict[str, object]]:
    with factory.session() as connection:
        rows = connection.execute("PRAGMA foreign_key_check;").fetchall()
    return [
        {
            "table": row[0],
            "rowid": row[1],
            "parent": row[2],
            "fkid": row[3],
        }
        for row in rows
    ]


def table_row_counts(
    factory: SQLiteConnectionFactory,
    tables: Sequence[str],
) -> dict[str, int]:
    counts: dict[str, int] = {}
    with factory.session() as connection:
        for table in tables:
            row = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
            counts[table] = int(row[0]) if row else 0
    return counts


def backup_database(
    source_factory: SQLiteConnectionFactory,
    destination_path: Path,
) -> Path:
    destination_factory = create_connection_factory(destination_path)
    with source_factory.session() as source, destination_factory.session() as destination:
        source.backup(destination)
    return destination_path
