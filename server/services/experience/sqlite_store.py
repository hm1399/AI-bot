from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from nanobot.storage.sqlite_documents import RuntimeDocumentStore


class SQLiteExperienceStateStore:
    def __init__(self, runtime_dir: Path, *, defaults: dict[str, Any]) -> None:
        self._documents = RuntimeDocumentStore(
            runtime_dir / "experience_state.json",
            namespace="experience_state",
            defaults=defaults,
        )

    @property
    def db_path(self) -> Path:
        return self._documents.db_path

    def exists(self) -> bool:
        return self._documents.exists()

    def load(self) -> dict[str, Any]:
        return self._documents.load()

    def save(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._documents.save(payload)

    def bootstrap(self, payload: dict[str, Any]) -> bool:
        return self._documents.bootstrap(deepcopy(payload))
