#!/usr/bin/env python3
"""Read-only local SQLite table viewer for AI-Bot workspace data."""

from __future__ import annotations

import argparse
import html
import json
import sqlite3
import threading
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse


def _quote_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def _connect_read_only(db_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(
        f"file:{db_path.as_posix()}?mode=ro",
        uri=True,
    )
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only=ON;")
    connection.execute("PRAGMA busy_timeout=3000;")
    return connection


def _list_tables(db_path: Path) -> list[str]:
    with _connect_read_only(db_path) as connection:
        rows = connection.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name ASC
            """
        ).fetchall()
    return [str(row["name"]) for row in rows]


def _table_columns(db_path: Path, table_name: str) -> list[dict[str, Any]]:
    with _connect_read_only(db_path) as connection:
        rows = connection.execute(
            f"PRAGMA table_info({_quote_identifier(table_name)})"
        ).fetchall()
    return [
        {
            "name": str(row["name"]),
            "type": str(row["type"] or ""),
            "notnull": bool(row["notnull"]),
            "pk": int(row["pk"] or 0),
        }
        for row in rows
    ]


def _row_count(db_path: Path, table_name: str) -> int:
    with _connect_read_only(db_path) as connection:
        row = connection.execute(
            f"SELECT COUNT(*) AS total FROM {_quote_identifier(table_name)}"
        ).fetchone()
    return int(row["total"] or 0) if row is not None else 0


def _order_clause(columns: list[dict[str, Any]]) -> str:
    names = {str(column["name"]) for column in columns}
    if "updated_at" in names:
        return ' ORDER BY "updated_at" DESC'
    if "created_at" in names:
        return ' ORDER BY "created_at" DESC'
    pk_columns = [column for column in columns if int(column["pk"]) > 0]
    if pk_columns:
        ordered = sorted(pk_columns, key=lambda column: int(column["pk"]))
        return " ORDER BY " + ", ".join(
            f'{_quote_identifier(str(column["name"]))} DESC' for column in ordered
        )
    return " ORDER BY rowid DESC"


def _fetch_rows(
    db_path: Path,
    table_name: str,
    *,
    limit: int,
    offset: int,
) -> list[sqlite3.Row]:
    columns = _table_columns(db_path, table_name)
    order_clause = _order_clause(columns)
    with _connect_read_only(db_path) as connection:
        rows = connection.execute(
            (
                f"SELECT * FROM {_quote_identifier(table_name)}"
                f"{order_clause} LIMIT ? OFFSET ?"
            ),
            (limit, offset),
        ).fetchall()
    return rows


def _render_cell(value: Any) -> str:
    if value is None:
        return '<span class="muted">NULL</span>'

    if isinstance(value, bytes):
        return f"<code>{html.escape(value.hex())}</code>"

    text = str(value)
    compact_preview = text if len(text) <= 140 else text[:137] + "..."
    escaped_preview = html.escape(compact_preview)

    if text.startswith("{") or text.startswith("["):
        try:
            payload = json.loads(text)
        except Exception:
            payload = None
        if payload is not None:
            pretty = json.dumps(payload, ensure_ascii=False, indent=2)
            return (
                "<details>"
                f"<summary>{escaped_preview}</summary>"
                f"<pre>{html.escape(pretty)}</pre>"
                "</details>"
            )

    if len(text) > 140 or "\n" in text:
        return (
            "<details>"
            f"<summary>{escaped_preview}</summary>"
            f"<pre>{html.escape(text)}</pre>"
            "</details>"
        )

    return html.escape(text)


def _page_url(table_name: str, page: int, limit: int) -> str:
    return "/table?" + urlencode(
        {
            "name": table_name,
            "page": page,
            "limit": limit,
        }
    )


class _SQLiteTableViewerHandler(BaseHTTPRequestHandler):
    db_path: Path
    table_names: list[str]

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._respond_html(self._render_home())
            return
        if parsed.path == "/table":
            query = parse_qs(parsed.query)
            table_name = str((query.get("name") or [""])[0])
            if table_name not in self.table_names:
                self._respond_html(
                    self._render_page(
                        "Table Not Found",
                        "<p>Unknown table.</p><p><a href='/'>Back to tables</a></p>",
                    ),
                    status=HTTPStatus.NOT_FOUND,
                )
                return
            self._respond_html(self._render_table(table_name, query))
            return

        self._respond_html(
            self._render_page(
                "Not Found",
                "<p>Unknown page.</p><p><a href='/'>Back to tables</a></p>",
            ),
            status=HTTPStatus.NOT_FOUND,
        )

    def log_message(self, format: str, *args: Any) -> None:
        _ = format
        _ = args

    def _respond_html(self, payload: str, *, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = payload.encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _render_home(self) -> str:
        items: list[str] = []
        for table_name in self.table_names:
            columns = _table_columns(self.db_path, table_name)
            count = _row_count(self.db_path, table_name)
            preview_columns = ", ".join(column["name"] for column in columns[:6])
            if len(columns) > 6:
                preview_columns += ", ..."
            items.append(
                "<tr>"
                f"<td><a href='{html.escape(_page_url(table_name, 1, 50))}'>{html.escape(table_name)}</a></td>"
                f"<td>{count}</td>"
                f"<td>{html.escape(preview_columns)}</td>"
                "</tr>"
            )

        body = (
            f"<p><strong>Database:</strong> {html.escape(str(self.db_path))}</p>"
            f"<p><strong>Tables:</strong> {len(self.table_names)}</p>"
            "<table>"
            "<thead><tr><th>Table</th><th>Rows</th><th>Columns</th></tr></thead>"
            f"<tbody>{''.join(items)}</tbody>"
            "</table>"
        )
        return self._render_page("SQLite Table Viewer", body)

    def _render_table(self, table_name: str, query: dict[str, list[str]]) -> str:
        try:
            page = max(1, int((query.get("page") or ["1"])[0]))
        except ValueError:
            page = 1
        try:
            limit = int((query.get("limit") or ["50"])[0])
        except ValueError:
            limit = 50
        limit = max(1, min(limit, 500))
        offset = (page - 1) * limit

        columns = _table_columns(self.db_path, table_name)
        rows = _fetch_rows(self.db_path, table_name, limit=limit, offset=offset)
        total_rows = _row_count(self.db_path, table_name)
        total_pages = max(1, (total_rows + limit - 1) // limit)

        schema_row_items: list[str] = []
        for column in columns:
            column_type = html.escape(str(column["type"]))
            if not column_type:
                column_type = '<span class="muted">TEXT</span>'
            schema_row_items.append(
                "<tr>"
                f"<td>{html.escape(str(column['name']))}</td>"
                f"<td>{column_type}</td>"
                f"<td>{'yes' if column['pk'] else ''}</td>"
                f"<td>{'yes' if column['notnull'] else ''}</td>"
                "</tr>"
            )
        schema_rows = "".join(
            schema_row_items
        )
        header_html = "".join(
            f"<th>{html.escape(str(column['name']))}</th>" for column in columns
        )
        row_html = "".join(
            "<tr>"
            + "".join(
                f"<td>{_render_cell(row[str(column['name'])])}</td>" for column in columns
            )
            + "</tr>"
            for row in rows
        )
        if not row_html:
            row_html = (
                f"<tr><td colspan='{max(1, len(columns))}' class='muted'>No rows.</td></tr>"
            )

        nav_links: list[str] = []
        if page > 1:
            nav_links.append(
                f"<a href='{html.escape(_page_url(table_name, page - 1, limit))}'>Previous</a>"
            )
        if page < total_pages:
            nav_links.append(
                f"<a href='{html.escape(_page_url(table_name, page + 1, limit))}'>Next</a>"
            )

        page_sizes = " ".join(
            (
                f"<a href='{html.escape(_page_url(table_name, 1, size))}'"
                + (" class='active-link'" if size == limit else "")
                + f">{size}</a>"
            )
            for size in (25, 50, 100, 250)
        )
        nav_html = " | ".join(nav_links) if nav_links else '<span class="muted">No other pages.</span>'

        body = (
            "<p><a href='/'>Back to tables</a></p>"
            f"<h2>{html.escape(table_name)}</h2>"
            f"<p><strong>Rows:</strong> {total_rows} | "
            f"<strong>Page:</strong> {page}/{total_pages} | "
            f"<strong>Page size:</strong> {page_sizes}</p>"
            f"<p>{nav_html}</p>"
            "<h3>Schema</h3>"
            "<table>"
            "<thead><tr><th>Name</th><th>Type</th><th>PK</th><th>Not Null</th></tr></thead>"
            f"<tbody>{schema_rows}</tbody>"
            "</table>"
            "<h3>Data</h3>"
            "<div class='table-wrap'>"
            "<table>"
            f"<thead><tr>{header_html}</tr></thead>"
            f"<tbody>{row_html}</tbody>"
            "</table>"
            "</div>"
        )
        return self._render_page(f"Table: {table_name}", body)

    @staticmethod
    def _render_page(title: str, body: str) -> str:
        return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #0f172a;
      --panel: #111827;
      --panel-alt: #0b1220;
      --text: #e5e7eb;
      --muted: #94a3b8;
      --line: #334155;
      --link: #38bdf8;
    }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(180deg, #020617, #0f172a 30%, #111827 100%);
      color: var(--text);
    }}
    main {{
      max-width: 1400px;
      margin: 0 auto;
      padding: 24px;
    }}
    h1, h2, h3 {{
      margin: 0 0 12px;
    }}
    p {{
      margin: 0 0 16px;
      color: var(--text);
    }}
    a {{
      color: var(--link);
      text-decoration: none;
    }}
    a:hover {{
      text-decoration: underline;
    }}
    .active-link {{
      font-weight: 700;
      text-decoration: underline;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: rgba(15, 23, 42, 0.82);
      border: 1px solid var(--line);
      margin-bottom: 20px;
    }}
    th, td {{
      text-align: left;
      vertical-align: top;
      padding: 10px 12px;
      border-bottom: 1px solid rgba(51, 65, 85, 0.55);
      border-right: 1px solid rgba(51, 65, 85, 0.28);
      font-size: 13px;
    }}
    th {{
      position: sticky;
      top: 0;
      background: rgba(2, 6, 23, 0.96);
      z-index: 1;
    }}
    .muted {{
      color: var(--muted);
    }}
    .table-wrap {{
      overflow: auto;
      max-height: calc(100vh - 260px);
      border: 1px solid var(--line);
    }}
    code, pre {{
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px;
    }}
    pre {{
      white-space: pre-wrap;
      word-break: break-word;
      margin: 8px 0 0;
      color: #dbeafe;
    }}
    details summary {{
      cursor: pointer;
      color: var(--text);
    }}
  </style>
</head>
<body>
  <main>
    <h1>{html.escape(title)}</h1>
    {body}
  </main>
</body>
</html>
"""


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read-only SQLite table viewer")
    parser.add_argument("--db", required=True, help="Path to SQLite database")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind")
    parser.add_argument("--port", type=int, default=8787, help="Port to bind")
    parser.add_argument(
        "--open-browser",
        action="store_true",
        help="Open the viewer in the default web browser",
    )
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    db_path = Path(args.db).expanduser().resolve()
    if not db_path.is_file():
        raise SystemExit(f"Database file not found: {db_path}")

    handler = type(
        "SQLiteTableViewerHandler",
        (_SQLiteTableViewerHandler,),
        {
            "db_path": db_path,
            "table_names": _list_tables(db_path),
        },
    )
    server = ThreadingHTTPServer((args.host, args.port), handler)
    url = f"http://{args.host}:{args.port}/"
    print(f"SQLite viewer running at {url}")
    print(f"Database: {db_path}")
    print("Press Ctrl+C to stop.")

    if args.open_browser:
        threading.Timer(0.35, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping SQLite viewer...")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
