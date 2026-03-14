"""Central log bus for Nexus. 🦖"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


@dataclass(slots=True)
class LogEvent:
    timestamp: str
    level: str
    message: str


class LogBus:
    def __init__(self) -> None:
        self.events: list[LogEvent] = []

    def log(self, level: str, message: str, **fields: Any) -> None:
        stamp = datetime.now(timezone.utc).isoformat()
        field_blob = " ".join(f"{k}={v}" for k, v in fields.items())
        line = f"[{stamp}] [{level.upper()}] {message}"
        if field_blob:
            line = f"{line} | {field_blob}"
        print(line)
        self.events.append(LogEvent(timestamp=stamp, level=level.upper(), message=line))
