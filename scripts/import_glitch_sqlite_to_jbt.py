#!/usr/bin/env python3
"""Import glitch_catalog SQLite data into per-session .jbt files used by GlitchCatalogSwift."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SESSION_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "joebot/glitch-catalog/session")
GEAR_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "joebot/glitch-catalog/gear")
SESSION_GEAR_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "joebot/glitch-catalog/session-gear")
MEDIA_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "joebot/glitch-catalog/media")


@dataclass(frozen=True)
class ImportStats:
    sessions: int
    tapes: int
    gear_links: int
    media: int


def deterministic_uuid(namespace: uuid.UUID, value: str) -> str:
    return str(uuid.uuid5(namespace, value))


def default_output_dir() -> Path:
    return Path.home() / "Documents" / "Joebot" / "GlitchCatalog" / "sessions"


def fetch_all(conn: sqlite3.Connection, query: str, params: tuple[Any, ...] = ()) -> list[sqlite3.Row]:
    cur = conn.execute(query, params)
    return cur.fetchall()


def build_documents(conn: sqlite3.Connection) -> tuple[list[dict[str, Any]], ImportStats]:
    sessions = fetch_all(conn, "SELECT id, title, date, location, notes FROM session ORDER BY date DESC, id ASC")
    tapes = fetch_all(
        conn,
        "SELECT id, session_id, tape_id, format, label, storage_location, notes FROM tape ORDER BY id ASC",
    )
    gear_rows = fetch_all(conn, "SELECT id, name FROM gear ORDER BY id ASC")
    session_gear = fetch_all(
        conn,
        "SELECT session_id, gear_id, notes, photos FROM session_gear ORDER BY session_id ASC, gear_id ASC",
    )
    media = fetch_all(
        conn,
        "SELECT id, session_id, file_path, kind, checksum, duration, width, height, codec, created_at, notes, thumbnail_path FROM media ORDER BY id ASC",
    )
    tag_rows = fetch_all(conn, "SELECT id, name FROM tag ORDER BY id ASC")
    session_tags = fetch_all(conn, "SELECT session_id, tag_id FROM session_tag ORDER BY session_id ASC, tag_id ASC")

    gear_name_by_id = {row["id"]: (row["name"] or "Unnamed Gear") for row in gear_rows}
    tag_name_by_id = {row["id"]: (row["name"] or "") for row in tag_rows}

    tapes_by_session: dict[int, list[sqlite3.Row]] = {}
    for row in tapes:
        tapes_by_session.setdefault(row["session_id"], []).append(row)

    gear_links_by_session: dict[int, list[sqlite3.Row]] = {}
    for row in session_gear:
        gear_links_by_session.setdefault(row["session_id"], []).append(row)

    media_by_session: dict[int, list[sqlite3.Row]] = {}
    for row in media:
        media_by_session.setdefault(row["session_id"], []).append(row)

    tags_by_session: dict[int, list[str]] = {}
    for row in session_tags:
        tag_name = tag_name_by_id.get(row["tag_id"], "")
        if tag_name:
            tags_by_session.setdefault(row["session_id"], []).append(tag_name)

    documents: list[dict[str, Any]] = []
    tape_count = 0
    link_count = 0
    media_count = 0

    for sess in sessions:
        session_pk = int(sess["id"])
        session_uuid = deterministic_uuid(SESSION_NAMESPACE, f"session:{session_pk}")

        session_tapes: list[dict[str, Any]] = []
        for tape in tapes_by_session.get(session_pk, []):
            tape_count += 1
            session_tapes.append(
                {
                    "sessionID": session_uuid,
                    "tapeID": tape["tape_id"] or f"tape-{tape['id']}",
                    "format": tape["format"] or "",
                    "label": tape["label"] or "",
                    "storageLocation": tape["storage_location"] or "",
                    "notes": tape["notes"] or "",
                }
            )

        links = gear_links_by_session.get(session_pk, [])
        unique_gear_ids = sorted({int(link["gear_id"]) for link in links})

        session_gear_defs: list[dict[str, Any]] = []
        for gear_id in unique_gear_ids:
            session_gear_defs.append(
                {
                    "id": deterministic_uuid(GEAR_NAMESPACE, f"gear:{gear_id}"),
                    "name": gear_name_by_id.get(gear_id, f"Gear {gear_id}"),
                }
            )

        session_gear_links: list[dict[str, Any]] = []
        for link in links:
            link_count += 1
            gear_id = int(link["gear_id"])
            notes = link["notes"] or ""
            photos = link["photos"] or ""
            if photos:
                notes = f"{notes}\nphotos: {photos}".strip()

            session_gear_links.append(
                {
                    "id": deterministic_uuid(
                        SESSION_GEAR_NAMESPACE,
                        f"session:{session_pk}:gear:{gear_id}",
                    ),
                    "sessionID": session_uuid,
                    "gearID": deterministic_uuid(GEAR_NAMESPACE, f"gear:{gear_id}"),
                    "notes": notes,
                }
            )

        session_media: list[dict[str, Any]] = []
        for item in media_by_session.get(session_pk, []):
            media_count += 1
            item_id = int(item["id"])
            session_media.append(
                {
                    "id": deterministic_uuid(MEDIA_NAMESPACE, f"media:{item_id}"),
                    "sessionID": session_uuid,
                    "filePath": item["file_path"] or "",
                    "kind": item["kind"] or "",
                    "checksum": item["checksum"] or "",
                    "duration": float(item["duration"] or 0.0),
                    "width": int(item["width"] or 0),
                    "height": int(item["height"] or 0),
                    "codec": item["codec"] or "",
                    "createdAt": item["created_at"] or "",
                    "notes": item["notes"] or "",
                    "thumbnailPath": item["thumbnail_path"] or "",
                }
            )

        notes = sess["notes"] or ""
        tags = sorted(set(tags_by_session.get(session_pk, [])))
        if tags:
            tags_line = f"tags: {', '.join(tags)}"
            notes = f"{notes}\n{tags_line}".strip()

        document = {
            "session": {
                "id": session_uuid,
                "title": sess["title"] or f"Session {session_pk}",
                "date": sess["date"] or "",
                "location": sess["location"] or "",
                "notes": notes,
            },
            "tapes": session_tapes,
            "gear": session_gear_defs,
            "sessionGear": session_gear_links,
            "media": session_media,
        }
        documents.append(document)

    stats = ImportStats(sessions=len(documents), tapes=tape_count, gear_links=link_count, media=media_count)
    return documents, stats


def write_documents(output_dir: Path, docs: list[dict[str, Any]], replace_existing: bool) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    if replace_existing:
        for path in output_dir.glob("*.jbt"):
            path.unlink()

    for doc in docs:
        session_id = doc["session"]["id"]
        target = output_dir / f"{session_id}.jbt"
        target.write_text(json.dumps(doc, indent=2), encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    db_path = Path(args.db).expanduser().resolve()
    if not db_path.exists():
        print(f"[error] DB not found: {db_path}", file=sys.stderr)
        return 1

    out_dir = Path(args.out).expanduser().resolve() if args.out else default_output_dir()

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        docs, stats = build_documents(conn)
    finally:
        conn.close()

    print(f"[info] source db: {db_path}")
    print(f"[info] output dir: {out_dir}")
    print(
        "[info] rows imported: "
        f"sessions={stats.sessions}, tapes={stats.tapes}, gear_links={stats.gear_links}, media={stats.media}"
    )

    if args.dry_run:
        print("[info] dry-run only. no files written.")
        return 0

    write_documents(out_dir, docs, replace_existing=args.replace_existing)
    print(f"[ok] wrote {len(docs)} session .jbt file(s)")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, help="Path to glitch_catalog.db")
    parser.add_argument("--out", help="Output directory for per-session .jbt files")
    parser.add_argument("--dry-run", action="store_true", help="Parse and map only, do not write files")
    parser.add_argument(
        "--replace-existing",
        action="store_true",
        help="Delete existing .jbt files in output directory before writing",
    )
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run(parse_args()))
