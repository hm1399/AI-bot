"""Helpers for atomic text-file writes."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Callable, TextIO


def atomic_write_text(
    path: Path,
    write_fn: Callable[[TextIO], None],
    *,
    encoding: str = "utf-8",
) -> None:
    """
    Write text to a temporary file and atomically replace the target.

    If writing fails, the original file is left untouched and the temp file is
    cleaned up on a best-effort basis.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temp_path = Path(temp_name)

    try:
        with os.fdopen(fd, "w", encoding=encoding) as handle:
            write_fn(handle)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temp_path, path)
        _fsync_dir(path.parent)
    except Exception:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass
        except OSError:
            pass
        raise


def _fsync_dir(path: Path) -> None:
    try:
        dir_fd = os.open(path, os.O_RDONLY)
    except OSError:
        return

    try:
        os.fsync(dir_fd)
    except OSError:
        pass
    finally:
        os.close(dir_fd)
