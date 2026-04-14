from __future__ import annotations

import json
import sqlite3
import uuid
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any


PLANNING_METADATA_FIELDS: tuple[str, ...] = (
    "bundle_id",
    "created_via",
    "source_channel",
    "source_message_id",
    "source_session_id",
    "interaction_surface",
    "capture_source",
    "voice_path",
    "linked_task_id",
    "linked_event_id",
    "linked_reminder_id",
)
REMINDER_RUNTIME_FIELDS: tuple[str, ...] = (
    "next_trigger_at",
    "last_triggered_at",
    "last_error",
    "snoozed_until",
    "completed_at",
    "status",
)
_TIMESTAMP_INDEX_FIELDS: dict[str, str] = {
    "next_trigger_at": "next_trigger_epoch",
    "last_triggered_at": "last_triggered_epoch",
    "snoozed_until": "snoozed_until_epoch",
    "completed_at": "completed_epoch",
}
_RESOURCE_CONFIGS: dict[str, dict[str, Any]] = {
    "tasks": {
        "table": "tasks",
        "id_field": "task_id",
        "prefix": "task",
        "fields": (
            "title",
            "description",
            "priority",
            "completed",
            "due_at",
            *PLANNING_METADATA_FIELDS,
            "created_at",
            "updated_at",
        ),
        "bool_fields": {"completed"},
        "json_fields": set(),
    },
    "events": {
        "table": "events",
        "id_field": "event_id",
        "prefix": "event",
        "fields": (
            "title",
            "start_at",
            "end_at",
            "description",
            "location",
            *PLANNING_METADATA_FIELDS,
            "created_at",
            "updated_at",
        ),
        "bool_fields": set(),
        "json_fields": set(),
    },
    "notifications": {
        "table": "notifications",
        "id_field": "notification_id",
        "prefix": "notif",
        "fields": (
            "type",
            "priority",
            "title",
            "message",
            "read",
            "metadata",
            "created_at",
            "updated_at",
        ),
        "bool_fields": {"read"},
        "json_fields": {"metadata"},
    },
    "reminders": {
        "table": "reminders",
        "id_field": "reminder_id",
        "prefix": "rem",
        "fields": (
            "title",
            "time",
            "message",
            "repeat",
            "enabled",
            *PLANNING_METADATA_FIELDS,
            "created_at",
            "updated_at",
        ),
        "bool_fields": {"enabled"},
        "json_fields": set(),
    },
}


def _now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _parse_epoch(value: Any) -> int | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        dt = datetime.fromisoformat(value.strip())
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.astimezone()
    else:
        dt = dt.astimezone()
    return int(dt.timestamp())


def _decode_json_object(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, str) or not raw.strip():
        return {}
    try:
        payload = json.loads(raw)
    except Exception:
        return {}
    if not isinstance(payload, dict):
        return {}
    return deepcopy(payload)


_DOMAIN_DEFAULTS: dict[str, dict[str, Any]] = {
    "tasks": {
        "priority": "medium",
        "completed": False,
        "description": None,
        "due_at": None,
    },
    "notifications": {
        "read": False,
        "metadata": {},
    },
    "reminders": {
        "message": None,
        "repeat": "daily",
        "enabled": True,
    },
}


class SQLitePlanningStore:
    """SQLite-backed planning resource store for tasks/events/notifications/reminders."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._ensure_schema()

    def domain_count(self, domain: str) -> int:
        table = self._config(domain)["table"]
        with self._connect() as conn:
            row = conn.execute(f"SELECT COUNT(*) AS count FROM {table}").fetchone()
        return int(row["count"]) if row is not None else 0

    def schema_version(self) -> int:
        with self._connect() as conn:
            row = conn.execute("PRAGMA user_version").fetchone()
        return int(row[0] or 0) if row is not None else 0

    def list_items(self, domain: str) -> list[dict[str, Any]]:
        with self._connect() as conn:
            if domain == "reminders":
                rows = conn.execute(
                    """
                    SELECT
                      reminders.reminder_id,
                      reminders.title,
                      reminders.time,
                      reminders.message,
                      reminders.repeat,
                      reminders.enabled,
                      reminders.bundle_id,
                      reminders.created_via,
                      reminders.source_channel,
                      reminders.source_message_id,
                      reminders.source_session_id,
                      reminders.interaction_surface,
                      reminders.capture_source,
                      reminders.voice_path,
                      reminders.linked_task_id,
                      reminders.linked_event_id,
                      reminders.linked_reminder_id,
                      reminders.created_at,
                      reminders.updated_at,
                      reminder_runtime.next_trigger_at,
                      reminder_runtime.last_triggered_at,
                      reminder_runtime.last_error,
                      reminder_runtime.snoozed_until,
                      reminder_runtime.completed_at,
                      reminder_runtime.status
                    FROM reminders
                    LEFT JOIN reminder_runtime
                      ON reminder_runtime.reminder_id = reminders.reminder_id
                    ORDER BY reminders.created_at ASC, reminders.rowid ASC
                    """
                ).fetchall()
                return [self._row_to_reminder_item(row) for row in rows]

            config = self._config(domain)
            fields_sql = self._select_fields_sql(domain)
            rows = conn.execute(
                f"SELECT {fields_sql} FROM {config['table']} ORDER BY created_at ASC, rowid ASC"
            ).fetchall()
            return [self._row_to_item(domain, row) for row in rows]

    def get(self, domain: str, item_id: str) -> dict[str, Any] | None:
        with self._connect() as conn:
            if domain == "reminders":
                row = conn.execute(
                    """
                    SELECT
                      reminders.reminder_id,
                      reminders.title,
                      reminders.time,
                      reminders.message,
                      reminders.repeat,
                      reminders.enabled,
                      reminders.bundle_id,
                      reminders.created_via,
                      reminders.source_channel,
                      reminders.source_message_id,
                      reminders.source_session_id,
                      reminders.interaction_surface,
                      reminders.capture_source,
                      reminders.voice_path,
                      reminders.linked_task_id,
                      reminders.linked_event_id,
                      reminders.linked_reminder_id,
                      reminders.created_at,
                      reminders.updated_at,
                      reminder_runtime.next_trigger_at,
                      reminder_runtime.last_triggered_at,
                      reminder_runtime.last_error,
                      reminder_runtime.snoozed_until,
                      reminder_runtime.completed_at,
                      reminder_runtime.status
                    FROM reminders
                    LEFT JOIN reminder_runtime
                      ON reminder_runtime.reminder_id = reminders.reminder_id
                    WHERE reminders.reminder_id = ?
                    """,
                    (item_id,),
                ).fetchone()
                return self._row_to_reminder_item(row) if row is not None else None

            config = self._config(domain)
            fields_sql = self._select_fields_sql(domain)
            row = conn.execute(
                f"SELECT {fields_sql} FROM {config['table']} WHERE {config['id_field']} = ?",
                (item_id,),
            ).fetchone()
            return self._row_to_item(domain, row) if row is not None else None

    def create(self, domain: str, payload: dict[str, Any]) -> dict[str, Any]:
        now = _now_iso()
        if domain == "reminders":
            item = self._prepare_reminder_item(payload, now=now)
            with self._connect() as conn:
                with conn:
                    self._write_reminder_item(conn, item)
            return item

        item = self._prepare_item(domain, payload, now=now)
        with self._connect() as conn:
            with conn:
                self._write_item(conn, domain, item)
        return item

    def update(self, domain: str, item_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        with self._connect() as conn:
            existing = self.get(domain, item_id)
            if existing is None:
                return None

            now = _now_iso()
            merged = deepcopy(existing)
            merged.update(deepcopy(patch))
            merged[self._config(domain)["id_field"]] = item_id
            merged["created_at"] = existing.get("created_at", now)
            merged["updated_at"] = now

            with conn:
                if domain == "reminders":
                    self._write_reminder_item(conn, merged)
                else:
                    self._write_item(conn, domain, merged)
        return merged

    def delete(self, domain: str, item_id: str) -> dict[str, Any] | None:
        deleted = self.get(domain, item_id)
        if deleted is None:
            return None

        with self._connect() as conn:
            with conn:
                config = self._config(domain)
                conn.execute(
                    f"DELETE FROM {config['table']} WHERE {config['id_field']} = ?",
                    (item_id,),
                )
        return deleted

    def replace_all(self, domain: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        now = _now_iso()
        prepared = [
            self._prepare_reminder_item(item, now=now)
            if domain == "reminders"
            else self._prepare_item(domain, item, now=now)
            for item in items
        ]
        with self._connect() as conn:
            with conn:
                self._clear_with_connection(conn, domain)
                for item in prepared:
                    if domain == "reminders":
                        self._write_reminder_item(conn, item)
                    else:
                        self._write_item(conn, domain, item)
        return self.list_items(domain)

    def clear(self, domain: str) -> None:
        with self._connect() as conn:
            with conn:
                self._clear_with_connection(conn, domain)

    def list_due_reminders(
        self,
        *,
        due_before: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        due_epoch = _parse_epoch(due_before or _now_iso())
        if due_epoch is None:
            return []

        sql = """
            SELECT
              reminders.reminder_id,
              reminders.title,
              reminders.time,
              reminders.message,
              reminders.repeat,
              reminders.enabled,
              reminders.bundle_id,
              reminders.created_via,
              reminders.source_channel,
              reminders.source_message_id,
              reminders.source_session_id,
              reminders.interaction_surface,
              reminders.capture_source,
              reminders.voice_path,
              reminders.linked_task_id,
              reminders.linked_event_id,
              reminders.linked_reminder_id,
              reminders.created_at,
              reminders.updated_at,
              reminder_runtime.next_trigger_at,
              reminder_runtime.last_triggered_at,
              reminder_runtime.last_error,
              reminder_runtime.snoozed_until,
              reminder_runtime.completed_at,
              reminder_runtime.status
            FROM reminder_runtime
            INNER JOIN reminders
              ON reminders.reminder_id = reminder_runtime.reminder_id
            WHERE reminders.enabled = 1
              AND reminder_runtime.next_trigger_epoch IS NOT NULL
              AND reminder_runtime.next_trigger_epoch <= ?
            ORDER BY reminder_runtime.next_trigger_epoch ASC, reminders.created_at ASC
        """
        params: list[Any] = [due_epoch]
        if isinstance(limit, int) and limit > 0:
            sql += " LIMIT ?"
            params.append(limit)

        with self._connect() as conn:
            rows = conn.execute(sql, tuple(params)).fetchall()
        return [self._row_to_reminder_item(row) for row in rows]

    def create_notification_and_update_reminder(
        self,
        *,
        reminder_id: str,
        notification_payload: dict[str, Any],
        reminder_patch: dict[str, Any],
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        with self._connect() as conn:
            reminder = self._get_reminder_with_connection(conn, reminder_id)
            if reminder is None:
                return None, None

            now = _now_iso()
            notification = self._prepare_item("notifications", notification_payload, now=now)
            updated_reminder = deepcopy(reminder)
            updated_reminder.update(deepcopy(reminder_patch))
            updated_reminder["updated_at"] = now

            with conn:
                self._write_item(conn, "notifications", notification)
                self._write_reminder_item(conn, updated_reminder)
        return notification, updated_reminder

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=5.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA foreign_keys=ON;")
        conn.execute("PRAGMA busy_timeout=5000;")
        conn.execute("PRAGMA synchronous=NORMAL;")
        conn.execute("PRAGMA temp_store=MEMORY;")
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            with conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS tasks (
                      task_id TEXT PRIMARY KEY,
                      title TEXT NOT NULL,
                      description TEXT,
                      priority TEXT NOT NULL,
                      completed INTEGER NOT NULL,
                      due_at TEXT,
                      bundle_id TEXT,
                      created_via TEXT,
                      source_channel TEXT,
                      source_message_id TEXT,
                      source_session_id TEXT,
                      interaction_surface TEXT,
                      capture_source TEXT,
                      voice_path TEXT,
                      linked_task_id TEXT,
                      linked_event_id TEXT,
                      linked_reminder_id TEXT,
                      created_at TEXT NOT NULL,
                      updated_at TEXT NOT NULL
                    ) STRICT
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS events (
                      event_id TEXT PRIMARY KEY,
                      title TEXT NOT NULL,
                      start_at TEXT NOT NULL,
                      end_at TEXT NOT NULL,
                      description TEXT,
                      location TEXT,
                      bundle_id TEXT,
                      created_via TEXT,
                      source_channel TEXT,
                      source_message_id TEXT,
                      source_session_id TEXT,
                      interaction_surface TEXT,
                      capture_source TEXT,
                      voice_path TEXT,
                      linked_task_id TEXT,
                      linked_event_id TEXT,
                      linked_reminder_id TEXT,
                      created_at TEXT NOT NULL,
                      updated_at TEXT NOT NULL
                    ) STRICT
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS notifications (
                      notification_id TEXT PRIMARY KEY,
                      type TEXT NOT NULL,
                      priority TEXT NOT NULL,
                      title TEXT NOT NULL,
                      message TEXT NOT NULL,
                      read INTEGER NOT NULL,
                      metadata_json TEXT NOT NULL,
                      created_at TEXT NOT NULL,
                      updated_at TEXT NOT NULL
                    ) STRICT
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS reminders (
                      reminder_id TEXT PRIMARY KEY,
                      title TEXT NOT NULL,
                      time TEXT NOT NULL,
                      message TEXT,
                      repeat TEXT NOT NULL,
                      enabled INTEGER NOT NULL,
                      bundle_id TEXT,
                      created_via TEXT,
                      source_channel TEXT,
                      source_message_id TEXT,
                      source_session_id TEXT,
                      interaction_surface TEXT,
                      capture_source TEXT,
                      voice_path TEXT,
                      linked_task_id TEXT,
                      linked_event_id TEXT,
                      linked_reminder_id TEXT,
                      created_at TEXT NOT NULL,
                      updated_at TEXT NOT NULL
                    ) STRICT
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS reminder_runtime (
                      reminder_id TEXT PRIMARY KEY REFERENCES reminders(reminder_id) ON DELETE CASCADE,
                      next_trigger_at TEXT,
                      next_trigger_epoch INTEGER,
                      last_triggered_at TEXT,
                      last_triggered_epoch INTEGER,
                      last_error TEXT,
                      snoozed_until TEXT,
                      snoozed_until_epoch INTEGER,
                      completed_at TEXT,
                      completed_epoch INTEGER,
                      status TEXT
                    ) STRICT
                    """
                )
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at DESC)")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_events_updated_at ON events(updated_at DESC)")
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_notifications_read_updated_at ON notifications(read, updated_at DESC)"
                )
                conn.execute("CREATE INDEX IF NOT EXISTS idx_reminders_updated_at ON reminders(updated_at DESC)")
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_reminder_runtime_next_trigger_epoch ON reminder_runtime(next_trigger_epoch)"
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_reminder_runtime_status_next_trigger_epoch ON reminder_runtime(status, next_trigger_epoch)"
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_reminder_runtime_snoozed_until_epoch ON reminder_runtime(snoozed_until_epoch)"
                )
                conn.execute("PRAGMA user_version=1;")

    def _config(self, domain: str) -> dict[str, Any]:
        try:
            return _RESOURCE_CONFIGS[domain]
        except KeyError as exc:
            raise ValueError(f"unsupported planning domain: {domain}") from exc

    def _prepare_item(self, domain: str, payload: dict[str, Any], *, now: str) -> dict[str, Any]:
        config = self._config(domain)
        item = deepcopy(payload)
        for field, default in _DOMAIN_DEFAULTS.get(domain, {}).items():
            item.setdefault(field, deepcopy(default))
        item.setdefault(config["id_field"], f"{config['prefix']}_{uuid.uuid4().hex[:8]}")
        item.setdefault("created_at", now)
        item.setdefault("updated_at", item.get("created_at") or now)
        if domain == "notifications":
            metadata = item.get("metadata")
            item["metadata"] = deepcopy(metadata) if isinstance(metadata, dict) else {}
        return item

    def _prepare_reminder_item(self, payload: dict[str, Any], *, now: str) -> dict[str, Any]:
        item = deepcopy(payload)
        for field, default in _DOMAIN_DEFAULTS["reminders"].items():
            item.setdefault(field, deepcopy(default))
        item.setdefault("reminder_id", f"rem_{uuid.uuid4().hex[:8]}")
        item.setdefault("created_at", now)
        item.setdefault("updated_at", item.get("created_at") or now)
        return item

    def _clear_with_connection(self, conn: sqlite3.Connection, domain: str) -> None:
        config = self._config(domain)
        conn.execute(f"DELETE FROM {config['table']}")

    def _write_item(self, conn: sqlite3.Connection, domain: str, item: dict[str, Any]) -> None:
        config = self._config(domain)
        id_field = config["id_field"]
        fields = (id_field, *config["fields"])
        db_fields = [self._db_field_name(domain, field) for field in fields]
        placeholders = ", ".join("?" for _ in fields)
        assignments = ", ".join(
            f"{self._db_field_name(domain, field)}=excluded.{self._db_field_name(domain, field)}"
            for field in config["fields"]
        )
        values = [self._serialize_field(domain, field, item.get(field)) for field in fields]
        conn.execute(
            f"""
            INSERT INTO {config['table']} ({", ".join(db_fields)})
            VALUES ({placeholders})
            ON CONFLICT({id_field}) DO UPDATE SET {assignments}
            """,
            values,
        )

    def _write_reminder_item(self, conn: sqlite3.Connection, item: dict[str, Any]) -> None:
        reminder_fields = ("reminder_id", *self._config("reminders")["fields"])
        reminder_values = [self._serialize_field("reminders", field, item.get(field)) for field in reminder_fields]
        conn.execute(
            f"""
            INSERT INTO reminders ({", ".join(reminder_fields)})
            VALUES ({", ".join("?" for _ in reminder_fields)})
            ON CONFLICT(reminder_id) DO UPDATE SET
              title=excluded.title,
              time=excluded.time,
              message=excluded.message,
              repeat=excluded.repeat,
              enabled=excluded.enabled,
              bundle_id=excluded.bundle_id,
              created_via=excluded.created_via,
              source_channel=excluded.source_channel,
              source_message_id=excluded.source_message_id,
              source_session_id=excluded.source_session_id,
              interaction_surface=excluded.interaction_surface,
              capture_source=excluded.capture_source,
              voice_path=excluded.voice_path,
              linked_task_id=excluded.linked_task_id,
              linked_event_id=excluded.linked_event_id,
              linked_reminder_id=excluded.linked_reminder_id,
              created_at=excluded.created_at,
              updated_at=excluded.updated_at
            """,
            reminder_values,
        )

        runtime_payload = {
            field: item.get(field)
            for field in REMINDER_RUNTIME_FIELDS
        }
        runtime_payload["reminder_id"] = item["reminder_id"]
        for field, epoch_field in _TIMESTAMP_INDEX_FIELDS.items():
            runtime_payload[epoch_field] = _parse_epoch(runtime_payload.get(field))

        runtime_fields = (
            "reminder_id",
            "next_trigger_at",
            "next_trigger_epoch",
            "last_triggered_at",
            "last_triggered_epoch",
            "last_error",
            "snoozed_until",
            "snoozed_until_epoch",
            "completed_at",
            "completed_epoch",
            "status",
        )
        conn.execute(
            f"""
            INSERT INTO reminder_runtime ({", ".join(runtime_fields)})
            VALUES ({", ".join("?" for _ in runtime_fields)})
            ON CONFLICT(reminder_id) DO UPDATE SET
              next_trigger_at=excluded.next_trigger_at,
              next_trigger_epoch=excluded.next_trigger_epoch,
              last_triggered_at=excluded.last_triggered_at,
              last_triggered_epoch=excluded.last_triggered_epoch,
              last_error=excluded.last_error,
              snoozed_until=excluded.snoozed_until,
              snoozed_until_epoch=excluded.snoozed_until_epoch,
              completed_at=excluded.completed_at,
              completed_epoch=excluded.completed_epoch,
              status=excluded.status
            """,
            [runtime_payload.get(field) for field in runtime_fields],
        )

    def _row_to_item(self, domain: str, row: sqlite3.Row | None) -> dict[str, Any] | None:
        if row is None:
            return None
        config = self._config(domain)
        item: dict[str, Any] = {config["id_field"]: row[config["id_field"]]}
        for field in config["fields"]:
            item[field] = self._deserialize_field(domain, field, row[field])
        return item

    def _select_fields_sql(self, domain: str) -> str:
        config = self._config(domain)
        fields: list[str] = [config["id_field"]]
        for field in config["fields"]:
            db_field = self._db_field_name(domain, field)
            if db_field == field:
                fields.append(field)
            else:
                fields.append(f"{db_field} AS {field}")
        return ", ".join(fields)

    @staticmethod
    def _db_field_name(domain: str, field: str) -> str:
        if domain == "notifications" and field == "metadata":
            return "metadata_json"
        return field

    def _row_to_reminder_item(self, row: sqlite3.Row | None) -> dict[str, Any] | None:
        if row is None:
            return None
        item: dict[str, Any] = {
            "reminder_id": row["reminder_id"],
            "title": row["title"],
            "time": row["time"],
            "message": row["message"],
            "repeat": row["repeat"],
            "enabled": bool(row["enabled"]),
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }
        for field in PLANNING_METADATA_FIELDS:
            item[field] = row[field]
        for field in REMINDER_RUNTIME_FIELDS:
            item[field] = row[field]
        return item

    def _get_reminder_with_connection(self, conn: sqlite3.Connection, reminder_id: str) -> dict[str, Any] | None:
        row = conn.execute(
            """
            SELECT
              reminders.reminder_id,
              reminders.title,
              reminders.time,
              reminders.message,
              reminders.repeat,
              reminders.enabled,
              reminders.bundle_id,
              reminders.created_via,
              reminders.source_channel,
              reminders.source_message_id,
              reminders.source_session_id,
              reminders.interaction_surface,
              reminders.capture_source,
              reminders.voice_path,
              reminders.linked_task_id,
              reminders.linked_event_id,
              reminders.linked_reminder_id,
              reminders.created_at,
              reminders.updated_at,
              reminder_runtime.next_trigger_at,
              reminder_runtime.last_triggered_at,
              reminder_runtime.last_error,
              reminder_runtime.snoozed_until,
              reminder_runtime.completed_at,
              reminder_runtime.status
            FROM reminders
            LEFT JOIN reminder_runtime
              ON reminder_runtime.reminder_id = reminders.reminder_id
            WHERE reminders.reminder_id = ?
            """,
            (reminder_id,),
        ).fetchone()
        return self._row_to_reminder_item(row)

    def _serialize_field(self, domain: str, field: str, value: Any) -> Any:
        config = self._config(domain)
        if field in config["bool_fields"]:
            return int(bool(value))
        if field in config["json_fields"]:
            payload = value if isinstance(value, dict) else {}
            return json.dumps(payload, ensure_ascii=False, sort_keys=True)
        return value

    def _deserialize_field(self, domain: str, field: str, value: Any) -> Any:
        config = self._config(domain)
        if field in config["bool_fields"]:
            return bool(value)
        if field in config["json_fields"]:
            return _decode_json_object(value)
        return value


class SQLiteCollectionAdapter:
    def __init__(self, store: SQLitePlanningStore, domain: str) -> None:
        self._store = store
        self._domain = domain

    def list_items(self) -> list[dict[str, Any]]:
        return self._store.list_items(self._domain)

    def get(self, item_id: str) -> dict[str, Any] | None:
        return self._store.get(self._domain, item_id)

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._store.create(self._domain, payload)

    def update(self, item_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        return self._store.update(self._domain, item_id, patch)

    def delete(self, item_id: str) -> dict[str, Any] | None:
        return self._store.delete(self._domain, item_id)

    def replace_all(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self._store.replace_all(self._domain, items)

    def clear(self) -> None:
        self._store.clear(self._domain)


class SQLiteReminderStoreAdapter(SQLiteCollectionAdapter):
    def __init__(self, store: SQLitePlanningStore) -> None:
        super().__init__(store, "reminders")

    def list_due_items(
        self,
        *,
        due_before: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        return self._store.list_due_reminders(due_before=due_before, limit=limit)
