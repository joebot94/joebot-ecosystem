"""Client registry for Nexus. 🦖"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from websockets.server import WebSocketServerProtocol


@dataclass(slots=True)
class ClientRecord:
    client_id: str
    client_type: str
    websocket: WebSocketServerProtocol | None = None
    online: bool = False
    last_seen_at: datetime | None = None
    registered_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    capabilities: dict[str, Any] = field(default_factory=dict)

    @property
    def last_seen_iso(self) -> str | None:
        if self.last_seen_at is None:
            return None
        return self.last_seen_at.isoformat()


class ClientRegistry:
    def __init__(self) -> None:
        self._clients: dict[str, ClientRecord] = {}

    def register(
        self,
        client_id: str,
        client_type: str,
        websocket: WebSocketServerProtocol,
        capabilities: dict[str, Any] | None = None,
    ) -> ClientRecord:
        record = self._clients.get(client_id)
        if record is None:
            record = ClientRecord(client_id=client_id, client_type=client_type)
            self._clients[client_id] = record

        record.client_type = client_type
        record.websocket = websocket
        record.online = True
        record.last_seen_at = datetime.now(timezone.utc)
        if capabilities is not None:
            record.capabilities = capabilities
        return record

    def touch(self, client_id: str) -> ClientRecord | None:
        record = self._clients.get(client_id)
        if record is None:
            return None
        record.last_seen_at = datetime.now(timezone.utc)
        return record

    def set_online(self, client_id: str, websocket: WebSocketServerProtocol | None = None) -> bool:
        record = self._clients.get(client_id)
        if record is None:
            return False
        changed = not record.online
        record.online = True
        if websocket is not None:
            record.websocket = websocket
        record.last_seen_at = datetime.now(timezone.utc)
        return changed

    def set_offline(self, client_id: str) -> bool:
        record = self._clients.get(client_id)
        if record is None:
            return False
        changed = record.online
        record.online = False
        record.websocket = None
        return changed

    def set_capabilities(self, client_id: str, capabilities: dict[str, Any]) -> None:
        record = self._clients.get(client_id)
        if record is not None:
            record.capabilities = capabilities

    def get(self, client_id: str) -> ClientRecord | None:
        return self._clients.get(client_id)

    def all_records(self) -> list[ClientRecord]:
        return list(self._clients.values())

    def online_records(self) -> list[ClientRecord]:
        return [record for record in self._clients.values() if record.online]

    def online_client_ids(self) -> list[str]:
        return [record.client_id for record in self.online_records()]

    def stale_online_clients(self, threshold_seconds: int) -> list[ClientRecord]:
        now = datetime.now(timezone.utc)
        stale: list[ClientRecord] = []
        for record in self._clients.values():
            if not record.online or record.last_seen_at is None:
                continue
            age = (now - record.last_seen_at).total_seconds()
            if age > threshold_seconds:
                stale.append(record)
        return stale

    def snapshot(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for record in sorted(self._clients.values(), key=lambda item: item.client_id):
            rows.append(
                {
                    "client_id": record.client_id,
                    "client_type": record.client_type,
                    "online": record.online,
                    "last_seen": record.last_seen_iso,
                    "capabilities": record.capabilities,
                }
            )
        return rows
