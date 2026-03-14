"""Message handlers for Nexus websocket API. 🦖"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any
from uuid import uuid4

from websockets.server import WebSocketServerProtocol

from api.models import (
    CapabilitiesQueryMessage,
    CapabilitiesResultMessage,
    HeartbeatMessage,
    IntentMessage,
    NexusMessage,
    QueryMessage,
    RegisterMessage,
    SceneRecallMessage,
    SceneSaveMessage,
    SceneStateMessage,
    StateUpdateMessage,
    make_message,
)


@dataclass(slots=True)
class PendingRequest:
    future: asyncio.Future[dict[str, Any]]
    requester_source: str
    target: str


class NexusHandlers:
    def __init__(self, runtime: "NexusRuntime") -> None:
        self.runtime = runtime

    async def dispatch(self, websocket: WebSocketServerProtocol, message: NexusMessage | Any) -> None:
        msg_type = message.type

        if msg_type == "register" and isinstance(message, RegisterMessage):
            await self._handle_register(websocket, message)
            return
        if msg_type == "heartbeat" and isinstance(message, HeartbeatMessage):
            await self._handle_heartbeat(websocket, message)
            return
        if msg_type == "state_update" and isinstance(message, StateUpdateMessage):
            await self._handle_state_update(message)
            return
        if msg_type == "query" and isinstance(message, QueryMessage):
            await self._handle_query(websocket, message)
            return
        if msg_type == "intent" and isinstance(message, IntentMessage):
            await self._handle_intent(websocket, message)
            return
        if msg_type == "capabilities.query" and isinstance(message, CapabilitiesQueryMessage):
            await self._handle_capabilities_query(websocket, message)
            return
        if msg_type == "capabilities.result" and isinstance(message, CapabilitiesResultMessage):
            await self._handle_capabilities_result(message)
            return
        if msg_type == "scene_save" and isinstance(message, SceneSaveMessage):
            await self._handle_scene_save(websocket, message)
            return
        if msg_type == "scene_recall" and isinstance(message, SceneRecallMessage):
            await self._handle_scene_recall(websocket, message)
            return
        if msg_type == "scene.state" and isinstance(message, SceneStateMessage):
            await self._handle_scene_state(message)
            return

        self.runtime.log_bus.log("warn", "Unhandled message type", type=msg_type, source=message.source)

    async def _handle_register(self, websocket: WebSocketServerProtocol, message: RegisterMessage) -> None:
        client_id = message.payload.client_id or message.source
        client_type = message.payload.client_type

        record = self.runtime.registry.register(
            client_id=client_id,
            client_type=client_type,
            websocket=websocket,
            capabilities=message.payload.capabilities,
        )
        self.runtime.websocket_to_client_id[websocket] = client_id

        await self.runtime.send(
            websocket,
            make_message(
                "registered",
                source="nexus",
                payload={
                    "client_id": record.client_id,
                    "client_type": record.client_type,
                    "heartbeat_interval": 5,
                    "heartbeat_timeout": self.runtime.heartbeat_timeout_seconds,
                    "online_clients": self.runtime.registry.online_client_ids(),
                },
            ),
        )

        self.runtime.log_bus.log("info", "Client registered", client_id=client_id, client_type=client_type)
        await self.runtime.broadcast_status(client_id)

        if client_type == "monitor":
            await self.runtime.send_registry_snapshot(websocket)
        else:
            await self.runtime.broadcast_registry_snapshot()

    async def _handle_heartbeat(self, websocket: WebSocketServerProtocol, message: HeartbeatMessage) -> None:
        client_id = self.runtime.websocket_to_client_id.get(websocket, message.source)
        record = self.runtime.registry.touch(client_id)
        if record is None:
            return

        if not record.online:
            self.runtime.registry.set_online(client_id, websocket)
            await self.runtime.broadcast_status(client_id)

    async def _handle_state_update(self, message: StateUpdateMessage) -> None:
        client_id = message.source
        self.runtime.state_store.set_state(client_id, message.payload.state)
        await self.runtime.broadcast_client_state(client_id)

    async def _handle_query(self, websocket: WebSocketServerProtocol, message: QueryMessage) -> None:
        target = message.payload.target
        record = self.runtime.registry.get(target)

        await self.runtime.send(
            websocket,
            make_message(
                "query_result",
                source="nexus",
                payload={
                    "target": target,
                    "online": record.online if record else False,
                    "last_seen": record.last_seen_iso if record else None,
                    "state": self.runtime.state_store.get_state(target),
                    "state_summary": self.runtime.state_store.summary(target),
                },
            ),
        )

    async def _handle_intent(self, websocket: WebSocketServerProtocol, message: IntentMessage) -> None:
        delivered: list[str] = []
        missing: list[str] = []

        for target in message.payload.targets:
            record = self.runtime.registry.get(target)
            if record and record.online and record.websocket is not None:
                delivered.append(target)
                await self.runtime.send(
                    record.websocket,
                    make_message(
                        "intent",
                        source=message.source,
                        payload={
                            "action": message.payload.action,
                            "params": message.payload.params,
                            "request_id": message.id,
                        },
                    ),
                )
            else:
                missing.append(target)

        await self.runtime.send(
            websocket,
            make_message(
                "intent_result",
                source="nexus",
                payload={"request_id": message.id, "delivered": delivered, "missing": missing},
            ),
        )

    async def _handle_capabilities_query(
        self,
        websocket: WebSocketServerProtocol,
        message: CapabilitiesQueryMessage,
    ) -> None:
        target = message.payload.target
        record = self.runtime.registry.get(target)

        if record is None:
            await self.runtime.send(
                websocket,
                make_message(
                    "capabilities.result",
                    source="nexus",
                    payload={"target": target, "capabilities": {}, "from_cache": False, "error": "unknown_target"},
                ),
            )
            return

        if not record.online or record.websocket is None:
            await self.runtime.send(
                websocket,
                make_message(
                    "capabilities.result",
                    source="nexus",
                    payload={"target": target, "capabilities": record.capabilities, "from_cache": True},
                ),
            )
            return

        request_id = f"cap_{uuid4().hex[:12]}"
        future: asyncio.Future[dict[str, Any]] = asyncio.get_running_loop().create_future()
        self.runtime.pending_capability_requests[request_id] = PendingRequest(
            future=future,
            requester_source=message.source,
            target=target,
        )

        await self.runtime.send(
            record.websocket,
            make_message(
                "capabilities.query",
                source="nexus",
                payload={"request_id": request_id, "requester": message.source},
            ),
        )

        try:
            result_payload = await asyncio.wait_for(future, timeout=5)
            capabilities = result_payload.get("capabilities", {})
            self.runtime.registry.set_capabilities(target, capabilities)
            await self.runtime.send(
                websocket,
                make_message(
                    "capabilities.result",
                    source="nexus",
                    payload={"target": target, "capabilities": capabilities, "from_cache": False},
                ),
            )
        except asyncio.TimeoutError:
            await self.runtime.send(
                websocket,
                make_message(
                    "capabilities.result",
                    source="nexus",
                    payload={"target": target, "capabilities": record.capabilities, "from_cache": True, "timeout": True},
                ),
            )
        finally:
            self.runtime.pending_capability_requests.pop(request_id, None)

    async def _handle_capabilities_result(self, message: CapabilitiesResultMessage) -> None:
        pending = self.runtime.pending_capability_requests.get(message.payload.request_id)
        if pending is None or pending.future.done():
            return
        pending.future.set_result(message.payload.model_dump())

    async def _handle_scene_save(self, websocket: WebSocketServerProtocol, message: SceneSaveMessage) -> None:
        request_id = f"scene_{uuid4().hex[:12]}"

        targets = [
            record
            for record in self.runtime.registry.online_records()
            if record.websocket is not None and record.client_type != "monitor"
        ]

        futures: dict[str, asyncio.Future[dict[str, Any]]] = {}
        for target_record in targets:
            per_client_id = f"{request_id}:{target_record.client_id}"
            future: asyncio.Future[dict[str, Any]] = asyncio.get_running_loop().create_future()
            self.runtime.pending_scene_requests[per_client_id] = PendingRequest(
                future=future,
                requester_source=message.source,
                target=target_record.client_id,
            )
            futures[target_record.client_id] = future

            await self.runtime.send(
                target_record.websocket,
                make_message(
                    "scene.collect",
                    source="nexus",
                    payload={"request_id": per_client_id, "requester": message.source},
                ),
            )

        scene_bundle: dict[str, Any] = {}
        for target_record in targets:
            target_id = target_record.client_id
            future = futures[target_id]
            try:
                payload = await asyncio.wait_for(future, timeout=2)
                client_state = payload.get("state", {})
            except asyncio.TimeoutError:
                client_state = self.runtime.state_store.get_state(target_id)
            finally:
                self.runtime.pending_scene_requests.pop(f"{request_id}:{target_id}", None)

            scene_bundle[target_id] = {
                target_id: client_state,
            }

        if message.payload.include_offline:
            for record in self.runtime.registry.all_records():
                if record.client_id in scene_bundle:
                    continue
                scene_bundle[record.client_id] = self.runtime.state_store.get_state(record.client_id)

        normalized_snapshot: dict[str, Any] = {}
        for key, value in scene_bundle.items():
            if isinstance(value, dict) and key in value:
                normalized_snapshot[key] = value[key]
            else:
                normalized_snapshot[key] = value

        await self.runtime.send(
            websocket,
            make_message(
                "scene_saved",
                source="nexus",
                payload={
                    "request_id": request_id,
                    "snapshot": normalized_snapshot,
                    "client_count": len(normalized_snapshot),
                },
            ),
        )

        self.runtime.log_bus.log("info", "Scene save bundled", requester=message.source, clients=len(normalized_snapshot))

    async def _handle_scene_recall(self, websocket: WebSocketServerProtocol, message: SceneRecallMessage) -> None:
        snapshot = message.payload.snapshot
        delivered: list[str] = []
        missing: list[str] = []

        for target_id, target_state in snapshot.items():
            record = self.runtime.registry.get(target_id)
            if record is None or not record.online or record.websocket is None:
                missing.append(target_id)
                continue

            delivered.append(target_id)
            await self.runtime.send(
                record.websocket,
                make_message(
                    "scene.recall",
                    source="nexus",
                    payload={
                        "request_id": message.id,
                        "requester": message.source,
                        "state": target_state,
                    },
                ),
            )

        await self.runtime.send(
            websocket,
            make_message(
                "scene_recalled",
                source="nexus",
                payload={
                    "request_id": message.id,
                    "delivered": delivered,
                    "missing": missing,
                },
            ),
        )

        self.runtime.log_bus.log(
            "info",
            "Scene recall dispatched",
            requester=message.source,
            delivered=len(delivered),
            missing=len(missing),
        )

    async def _handle_scene_state(self, message: SceneStateMessage) -> None:
        self.runtime.state_store.set_state(message.source, message.payload.state)
        pending = self.runtime.pending_scene_requests.get(message.payload.request_id)
        if pending is None or pending.future.done():
            return
        pending.future.set_result(message.payload.model_dump())
