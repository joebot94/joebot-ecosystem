"""WebSocket server implementation for Nexus. 🦖"""

from __future__ import annotations

import asyncio
import json
from typing import Any

from websockets.exceptions import ConnectionClosed
from websockets.server import WebSocketServerProtocol, serve

from api.handlers import NexusHandlers, PendingRequest
from api.models import NexusMessage, make_message, parse_message
from config.settings import HEARTBEAT_CHECK_INTERVAL_SECONDS, HEARTBEAT_TIMEOUT_SECONDS, NEXUS_HOST, NEXUS_PORT
from core.heartbeat import HeartbeatWatcher
from core.log_bus import LogBus
from core.registry import ClientRecord, ClientRegistry
from core.state_store import StateStore


class NexusRuntime:
    def __init__(self) -> None:
        self.log_bus = LogBus()
        self.registry = ClientRegistry()
        self.state_store = StateStore()
        self.websocket_to_client_id: dict[WebSocketServerProtocol, str] = {}
        self.pending_capability_requests: dict[str, PendingRequest] = {}
        self.pending_scene_requests: dict[str, PendingRequest] = {}
        self.heartbeat_timeout_seconds = HEARTBEAT_TIMEOUT_SECONDS

    async def send(self, websocket: WebSocketServerProtocol, message: dict[str, Any]) -> None:
        await websocket.send(json.dumps(message))
        self.log_bus.log(
            "debug",
            "Sent message",
            type=message.get("type"),
            source=message.get("source"),
            target=self.websocket_to_client_id.get(websocket, "unknown"),
        )

    async def broadcast_to_monitors(self, message_type: str, payload: dict[str, Any]) -> None:
        tasks: list[asyncio.Task[None]] = []
        for record in self.registry.online_records():
            if record.client_type != "monitor" or record.websocket is None:
                continue
            tasks.append(asyncio.create_task(self.send(record.websocket, make_message(message_type, "nexus", payload))))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def send_registry_snapshot(self, websocket: WebSocketServerProtocol) -> None:
        rows = []
        for item in self.registry.snapshot():
            item["state_summary"] = self.state_store.summary(item["client_id"])
            rows.append(item)
        await self.send(websocket, make_message("registry.snapshot", source="nexus", payload={"clients": rows}))

    async def broadcast_registry_snapshot(self) -> None:
        rows = []
        for item in self.registry.snapshot():
            item["state_summary"] = self.state_store.summary(item["client_id"])
            rows.append(item)
        await self.broadcast_to_monitors("registry.snapshot", {"clients": rows})

    async def broadcast_status(self, client_id: str) -> None:
        record = self.registry.get(client_id)
        if record is None:
            return
        await self.broadcast_to_monitors(
            "client.status",
            {
                "client_id": record.client_id,
                "client_type": record.client_type,
                "online": record.online,
                "last_seen": record.last_seen_iso,
                "state_summary": self.state_store.summary(client_id),
            },
        )

    async def broadcast_client_state(self, client_id: str) -> None:
        record = self.registry.get(client_id)
        if record is None:
            return

        await self.broadcast_to_monitors(
            "client.state",
            {
                "client_id": record.client_id,
                "client_type": record.client_type,
                "online": record.online,
                "state": self.state_store.get_state(client_id),
                "state_summary": self.state_store.summary(client_id),
                "last_seen": record.last_seen_iso,
            },
        )


class NexusServer:
    def __init__(self) -> None:
        self.runtime = NexusRuntime()
        self.handlers = NexusHandlers(self.runtime)
        self.heartbeat = HeartbeatWatcher(
            registry=self.runtime.registry,
            timeout_seconds=HEARTBEAT_TIMEOUT_SECONDS,
            check_interval_seconds=HEARTBEAT_CHECK_INTERVAL_SECONDS,
            on_timeout=self._handle_heartbeat_timeout,
        )

    async def _handle_heartbeat_timeout(self, record: ClientRecord) -> None:
        changed = self.runtime.registry.set_offline(record.client_id)
        if not changed:
            return
        self.runtime.log_bus.log("warn", "Client timed out", client_id=record.client_id)
        await self.runtime.broadcast_status(record.client_id)
        await self.runtime.broadcast_registry_snapshot()

    async def _handle_disconnect(self, websocket: WebSocketServerProtocol) -> None:
        client_id = self.runtime.websocket_to_client_id.pop(websocket, None)
        if client_id is None:
            return

        changed = self.runtime.registry.set_offline(client_id)
        if changed:
            self.runtime.log_bus.log("info", "Client disconnected", client_id=client_id)
            await self.runtime.broadcast_status(client_id)
            await self.runtime.broadcast_registry_snapshot()

    async def _connection_handler(self, websocket: WebSocketServerProtocol) -> None:
        self.runtime.log_bus.log("info", "WebSocket connected", peer=str(websocket.remote_address))
        try:
            async for raw in websocket:
                try:
                    payload = json.loads(raw)
                    message = parse_message(payload)
                except Exception as exc:
                    self.runtime.log_bus.log("error", "Invalid message", error=str(exc))
                    await self.runtime.send(
                        websocket,
                        make_message("error", source="nexus", payload={"error": "invalid_message", "detail": str(exc)}),
                    )
                    continue

                self.runtime.log_bus.log(
                    "debug",
                    "Received message",
                    type=getattr(message, "type", "unknown"),
                    source=getattr(message, "source", "unknown"),
                )

                if isinstance(message, NexusMessage) and message.type == "heartbeat":
                    pass

                await self.handlers.dispatch(websocket, message)
        except ConnectionClosed:
            pass
        finally:
            await self._handle_disconnect(websocket)

    async def run(self, host: str = NEXUS_HOST, port: int = NEXUS_PORT) -> None:
        self.runtime.log_bus.log("info", f"🦖 Nexus starting on ws://{host}:{port}")
        self.heartbeat.start()
        async with serve(self._connection_handler, host, port, ping_interval=None):
            self.runtime.log_bus.log("info", "Nexus accepting connections")
            await asyncio.Future()


async def run_server() -> None:
    server = NexusServer()
    await server.run()
