"""Session event recording for Nexus. 🦖"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ALLOWED_REPLAY_SPEEDS = {0.5, 1.0, 2.0, 4.0}


@dataclass(slots=True)
class EventEntry:
    timestamp: str
    type: str
    source: str
    summary: str
    payload: dict[str, Any]

    def as_dict(self) -> dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "type": self.type,
            "source": self.source,
            "summary": self.summary,
            "payload": self.payload,
        }


@dataclass(slots=True)
class RecordingSession:
    session_id: str
    session_name: str
    started_at: str
    stopped_at: str | None = None
    events: list[EventEntry] = field(default_factory=list)
    file_path: Path | None = None
    active: bool = True

    def as_dict(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "session_name": self.session_name,
            "started_at": self.started_at,
            "stopped_at": self.stopped_at,
            "events": [event.as_dict() for event in self.events],
        }


class EventRecorder:
    def __init__(self, log_dir: Path | None = None) -> None:
        self.log_dir = log_dir or (Path.home() / ".nexus" / "logs")
        self.log_dir.mkdir(parents=True, exist_ok=True)

        self.active_sessions: dict[str, RecordingSession] = {}
        self.known_sessions: dict[str, RecordingSession] = {}

    def start_recording(self, session_id: str, session_name: str) -> RecordingSession:
        started = _iso_now_ms()
        date_tag = started[:10].replace("-", "")
        time_tag = started[11:19].replace(":", "")
        file_path = self.log_dir / f"{session_id}_{date_tag}_{time_tag}.json"

        session = RecordingSession(
            session_id=session_id,
            session_name=session_name,
            started_at=started,
            file_path=file_path,
            active=True,
        )
        self.active_sessions[session_id] = session
        self.known_sessions[session_id] = session
        self._persist(session)
        return session

    def stop_recording(self, session_id: str) -> RecordingSession | None:
        session = self.active_sessions.pop(session_id, None)
        if session is None:
            session = self.known_sessions.get(session_id)
            if session is None:
                return None

        session.stopped_at = _iso_now_ms()
        session.active = False
        self.known_sessions[session_id] = session
        self._persist(session)
        return session

    def record_event(self, event_type: str, source: str, summary: str, payload: dict[str, Any] | None = None) -> None:
        if not self.active_sessions:
            return

        entry = EventEntry(
            timestamp=_iso_now_ms(),
            type=event_type,
            source=source,
            summary=summary,
            payload=_json_safe_dict(payload or {}),
        )

        for session in list(self.active_sessions.values()):
            session.events.append(entry)
            self._persist(session)

    def get_session_log(self, session_id: str) -> RecordingSession | None:
        if session_id in self.known_sessions:
            return self.known_sessions[session_id]

        loaded = self._load_latest_from_disk(session_id)
        if loaded is not None:
            self.known_sessions[session_id] = loaded
        return loaded

    def _persist(self, session: RecordingSession) -> None:
        if session.file_path is None:
            return

        session.file_path.parent.mkdir(parents=True, exist_ok=True)
        session.file_path.write_text(json.dumps(session.as_dict(), indent=2), encoding="utf-8")

    def _load_latest_from_disk(self, session_id: str) -> RecordingSession | None:
        candidates = sorted(self.log_dir.glob(f"{session_id}_*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
        if not candidates:
            return None

        latest = candidates[0]
        try:
            parsed = json.loads(latest.read_text(encoding="utf-8"))
        except Exception:
            return None

        events = [
            EventEntry(
                timestamp=str(item.get("timestamp", "")),
                type=str(item.get("type", "")),
                source=str(item.get("source", "")),
                summary=str(item.get("summary", "")),
                payload=_json_safe_dict(item.get("payload", {})),
            )
            for item in parsed.get("events", [])
            if isinstance(item, dict)
        ]

        return RecordingSession(
            session_id=str(parsed.get("session_id", session_id)),
            session_name=str(parsed.get("session_name", "")),
            started_at=str(parsed.get("started_at", "")),
            stopped_at=parsed.get("stopped_at"),
            events=events,
            file_path=latest,
            active=False,
        )


def replay_session(event_log: dict[str, Any], speed: float = 1.0) -> None:
    """Future replay support scaffold.

    TODO:
    - Send replayed messages to currently connected clients.
    - Implement cancellable playback controls.
    """
    replay_speed = _normalize_replay_speed(speed)
    events = event_log.get("events", [])
    if not isinstance(events, list):
        return

    timeline = _build_replay_timeline(events, replay_speed)

    # TODO:
    # - Iterate through timeline and perform async waits.
    # - Replay state updates/intents back through connected clients.
    _ = timeline


def _iso_now_ms() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _json_safe_dict(value: Any) -> dict[str, Any]:
    mapped = _json_safe(value)
    if isinstance(mapped, dict):
        return mapped
    return {"value": mapped}


def _json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {str(key): _json_safe(sub) for key, sub in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_json_safe(item) for item in value]
    return str(value)


def _normalize_replay_speed(speed: float) -> float:
    return speed if speed in ALLOWED_REPLAY_SPEEDS else 1.0


def _build_replay_timeline(events: list[Any], speed: float) -> list[dict[str, Any]]:
    timeline: list[dict[str, Any]] = []
    previous_epoch: float | None = None

    for raw in events:
        if not isinstance(raw, dict):
            continue

        timestamp = str(raw.get("timestamp", ""))
        epoch = _parse_iso_timestamp(timestamp)
        if epoch is None:
            continue

        if previous_epoch is None:
            wait_seconds = 0.0
        else:
            delta = max(0.0, epoch - previous_epoch)
            wait_seconds = delta / speed

        timeline.append(
            {
                "wait_seconds": wait_seconds,
                "event": raw,
            }
        )
        previous_epoch = epoch

    return timeline


def _parse_iso_timestamp(value: str) -> float | None:
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt.timestamp()
