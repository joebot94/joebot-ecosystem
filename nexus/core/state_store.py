"""In-memory state store for Nexus clients. 🦖"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


@dataclass(slots=True)
class StateRecord:
    client_id: str
    state: dict[str, Any]
    updated_at: str


class StateStore:
    def __init__(self) -> None:
        self._state: dict[str, StateRecord] = {}

    def set_state(self, client_id: str, state: dict[str, Any]) -> None:
        self._state[client_id] = StateRecord(
            client_id=client_id,
            state=state,
            updated_at=datetime.now(timezone.utc).isoformat(),
        )

    def get_state(self, client_id: str) -> dict[str, Any]:
        record = self._state.get(client_id)
        return record.state if record else {}

    def has_state(self, client_id: str) -> bool:
        return client_id in self._state

    def summary(self, client_id: str) -> str:
        state = self.get_state(client_id)
        if not state:
            return "No state yet"

        if "channels" in state and isinstance(state["channels"], list):
            return f"{len(state['channels'])} channels"

        keys = list(state.keys())
        if len(keys) <= 3:
            return ", ".join(keys)
        return f"{len(keys)} keys"

    def snapshot(self) -> dict[str, dict[str, Any]]:
        return {client_id: record.state for client_id, record in self._state.items()}
