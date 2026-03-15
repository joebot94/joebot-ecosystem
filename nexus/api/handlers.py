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
    RecordingRequestMessage,
    RecordingStartMessage,
    RecordingStopMessage,
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
        if msg_type == "recording.start" and isinstance(message, RecordingStartMessage):
            await self._handle_recording_start(websocket, message)
            return
        if msg_type == "recording.stop" and isinstance(message, RecordingStopMessage):
            await self._handle_recording_stop(websocket, message)
            return
        if msg_type == "recording.request" and isinstance(message, RecordingRequestMessage):
            await self._handle_recording_request(websocket, message)
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
        self.runtime.record_event(
            event_type="client.connected",
            source=client_id,
            summary="Client connected",
            payload={"client_id": client_id, "client_type": client_type},
        )
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
        self.runtime.record_event(
            event_type="state_update",
            source=client_id,
            summary="State update received",
            payload={"state": message.payload.state},
        )
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
        self.runtime.record_event(
            event_type="intent",
            source=message.source,
            summary=f"Intent routed to {len(delivered)} target(s)",
            payload={
                "action": message.payload.action,
                "targets": message.payload.targets,
                "delivered": delivered,
                "missing": missing,
                "params": message.payload.params,
            },
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
        self.runtime.record_event(
            event_type="scene_save.requested",
            source=message.source,
            summary="Scene save requested",
            payload=message.payload.model_dump(),
        )

        normalized_snapshot = await self._collect_snapshot_from_clients(
            requester_source=message.source,
            request_id_prefix=request_id,
            include_offline=message.payload.include_offline,
        )

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
        self.runtime.record_event(
            event_type="scene_save.completed",
            source=message.source,
            summary=f"Scene save completed ({len(normalized_snapshot)} clients)",
            payload={"request_id": request_id, "snapshot": normalized_snapshot},
        )

    async def _collect_snapshot_from_clients(
        self,
        requester_source: str,
        request_id_prefix: str,
        include_offline: bool,
    ) -> dict[str, Any]:
        targets = [
            record
            for record in self.runtime.registry.online_records()
            if record.websocket is not None and record.client_type != "monitor"
        ]

        futures: dict[str, asyncio.Future[dict[str, Any]]] = {}
        for target_record in targets:
            per_client_id = f"{request_id_prefix}:{target_record.client_id}"
            future: asyncio.Future[dict[str, Any]] = asyncio.get_running_loop().create_future()
            self.runtime.pending_scene_requests[per_client_id] = PendingRequest(
                future=future,
                requester_source=requester_source,
                target=target_record.client_id,
            )
            futures[target_record.client_id] = future

            await self.runtime.send(
                target_record.websocket,
                make_message(
                    "scene.collect",
                    source="nexus",
                    payload={"request_id": per_client_id, "requester": requester_source},
                ),
            )

        snapshot: dict[str, Any] = {}
        for target_record in targets:
            target_id = target_record.client_id
            future = futures[target_id]
            try:
                payload = await asyncio.wait_for(future, timeout=2)
                client_state = payload.get("state", {})
            except asyncio.TimeoutError:
                client_state = self.runtime.state_store.get_state(target_id)
            finally:
                self.runtime.pending_scene_requests.pop(f"{request_id_prefix}:{target_id}", None)

            snapshot[target_id] = client_state if isinstance(client_state, dict) else {"value": client_state}

        if include_offline:
            for record in self.runtime.registry.all_records():
                if record.client_type == "monitor" or record.client_id in snapshot:
                    continue
                snapshot[record.client_id] = self.runtime.state_store.get_state(record.client_id)

        return snapshot

    async def _handle_scene_recall(self, websocket: WebSocketServerProtocol, message: SceneRecallMessage) -> None:
        snapshot = message.payload.snapshot
        self.runtime.record_event(
            event_type="scene_recall.requested",
            source=message.source,
            summary="Scene recall requested",
            payload={"snapshot_clients": sorted(snapshot.keys())},
        )
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
        self.runtime.record_event(
            event_type="scene_recall.completed",
            source=message.source,
            summary=f"Scene recall dispatched to {len(delivered)} client(s)",
            payload={"delivered": delivered, "missing": missing},
        )

    async def _handle_recording_start(self, websocket: WebSocketServerProtocol, message: RecordingStartMessage) -> None:
        session = self.runtime.event_recorder.start_recording(
            session_id=message.payload.session_id,
            session_name=message.payload.session_name,
        )
        self.runtime.record_event(
            event_type="recording.start",
            source=message.source,
            summary=f"Recording started: {message.payload.session_name}",
            payload=message.payload.model_dump(),
        )
        await self.runtime.send(
            websocket,
            make_message(
                "recording.started",
                source="nexus",
                payload=session.as_dict(),
            ),
        )
        self.runtime.log_bus.log(
            "info",
            "Recording started",
            session_id=message.payload.session_id,
            session_name=message.payload.session_name,
            source=message.source,
        )

        baseline_snapshot = await self._collect_snapshot_from_clients(
            requester_source=message.source,
            request_id_prefix=f"recstart_{uuid4().hex[:12]}",
            include_offline=False,
        )
        captured_clients: list[str] = []
        for client_id, client_state in baseline_snapshot.items():
            if not isinstance(client_state, dict) or not client_state:
                continue
            captured_clients.append(client_id)
            self.runtime.state_store.set_state(client_id, client_state)
            self.runtime.record_event(
                event_type="state_update",
                source=client_id,
                summary="Baseline state captured at recording start",
                payload={"state": client_state, "baseline": True},
            )

        self.runtime.log_bus.log(
            "info",
            "Recording baseline captured",
            session_id=message.payload.session_id,
            clients=len(captured_clients),
            client_ids=captured_clients,
        )

    async def _handle_recording_stop(self, websocket: WebSocketServerProtocol, message: RecordingStopMessage) -> None:
        self.runtime.record_event(
            event_type="recording.stop.requested",
            source=message.source,
            summary="Recording stop requested",
            payload=message.payload.model_dump(),
        )
        session = self.runtime.event_recorder.stop_recording(message.payload.session_id)
        if session is None:
            await self.runtime.send(
                websocket,
                make_message(
                    "error",
                    source="nexus",
                    payload={"error": "unknown_recording_session", "session_id": message.payload.session_id},
                ),
            )
            self.runtime.record_event(
                event_type="error",
                source="nexus",
                summary="Recording stop failed: unknown session",
                payload=message.payload.model_dump(),
            )
            return

        await self.runtime.send(
            websocket,
            make_message(
                "recording.stopped",
                source="nexus",
                payload=session.as_dict(),
            ),
        )
        self.runtime.log_bus.log("info", "Recording stopped", session_id=message.payload.session_id, source=message.source)

    async def _handle_recording_request(self, websocket: WebSocketServerProtocol, message: RecordingRequestMessage) -> None:
        session = self.runtime.event_recorder.get_session_log(message.payload.session_id)
        if session is None:
            await self.runtime.send(
                websocket,
                make_message(
                    "recording.log",
                    source="nexus",
                    payload={"session_id": message.payload.session_id, "log": None, "found": False},
                ),
            )
            return

        await self.runtime.send(
            websocket,
            make_message(
                "recording.log",
                source="nexus",
                payload={"session_id": message.payload.session_id, "log": session.as_dict(), "found": True},
            ),
        )

    async def _handle_scene_state(self, message: SceneStateMessage) -> None:
        self.runtime.state_store.set_state(message.source, message.payload.state)
        pending = self.runtime.pending_scene_requests.get(message.payload.request_id)
        if pending is None or pending.future.done():
            return
        pending.future.set_result(message.payload.model_dump())
