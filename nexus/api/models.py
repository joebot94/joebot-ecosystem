"""Pydantic v2 message models for Nexus protocol. 🦖"""

from __future__ import annotations

from typing import Annotated, Any, Literal
from uuid import uuid4

from pydantic import BaseModel, Field, TypeAdapter


class NexusMessage(BaseModel):
    id: str
    type: str
    source: str
    payload: dict[str, Any] = Field(default_factory=dict)


class RegisterPayload(BaseModel):
    client_id: str | None = None
    client_type: str = "app"
    capabilities: dict[str, Any] = Field(default_factory=dict)


class HeartbeatPayload(BaseModel):
    uptime_seconds: float | None = None


class StateUpdatePayload(BaseModel):
    state: dict[str, Any]


class QueryPayload(BaseModel):
    target: str


class IntentPayload(BaseModel):
    targets: list[str]
    action: str
    params: dict[str, Any] = Field(default_factory=dict)


class CapabilitiesQueryPayload(BaseModel):
    target: str


class CapabilitiesResultPayload(BaseModel):
    request_id: str
    capabilities: dict[str, Any] = Field(default_factory=dict)


class SceneSavePayload(BaseModel):
    include_offline: bool = True
    session_name: str | None = None


class SceneRecallPayload(BaseModel):
    snapshot: dict[str, Any] = Field(default_factory=dict)


class SceneStatePayload(BaseModel):
    request_id: str
    state: dict[str, Any] = Field(default_factory=dict)


class RecordingStartPayload(BaseModel):
    session_name: str
    session_id: str


class RecordingStopPayload(BaseModel):
    session_id: str


class RecordingRequestPayload(BaseModel):
    session_id: str


class RegisterMessage(NexusMessage):
    type: Literal["register"]
    payload: RegisterPayload


class HeartbeatMessage(NexusMessage):
    type: Literal["heartbeat"]
    payload: HeartbeatPayload = Field(default_factory=HeartbeatPayload)


class StateUpdateMessage(NexusMessage):
    type: Literal["state_update"]
    payload: StateUpdatePayload


class QueryMessage(NexusMessage):
    type: Literal["query"]
    payload: QueryPayload


class IntentMessage(NexusMessage):
    type: Literal["intent"]
    payload: IntentPayload


class CapabilitiesQueryMessage(NexusMessage):
    type: Literal["capabilities.query"]
    payload: CapabilitiesQueryPayload


class CapabilitiesResultMessage(NexusMessage):
    type: Literal["capabilities.result"]
    payload: CapabilitiesResultPayload


class SceneSaveMessage(NexusMessage):
    type: Literal["scene_save"]
    payload: SceneSavePayload = Field(default_factory=SceneSavePayload)


class SceneRecallMessage(NexusMessage):
    type: Literal["scene_recall"]
    payload: SceneRecallPayload


class SceneStateMessage(NexusMessage):
    type: Literal["scene.state"]
    payload: SceneStatePayload


class RecordingStartMessage(NexusMessage):
    type: Literal["recording.start"]
    payload: RecordingStartPayload


class RecordingStopMessage(NexusMessage):
    type: Literal["recording.stop"]
    payload: RecordingStopPayload


class RecordingRequestMessage(NexusMessage):
    type: Literal["recording.request"]
    payload: RecordingRequestPayload


TypedMessage = Annotated[
    RegisterMessage
    | HeartbeatMessage
    | StateUpdateMessage
    | QueryMessage
    | IntentMessage
    | CapabilitiesQueryMessage
    | CapabilitiesResultMessage
    | SceneSaveMessage
    | SceneRecallMessage
    | SceneStateMessage
    | RecordingStartMessage
    | RecordingStopMessage
    | RecordingRequestMessage,
    Field(discriminator="type"),
]

_TYPED_ADAPTER = TypeAdapter(TypedMessage)


def parse_message(raw: dict[str, Any]) -> NexusMessage | TypedMessage:
    raw = _normalize_legacy_message(raw)
    try:
        return _TYPED_ADAPTER.validate_python(raw)
    except Exception:
        return NexusMessage.model_validate(raw)


def make_message(
    message_type: str,
    source: str,
    payload: dict[str, Any] | None = None,
    message_id: str | None = None,
) -> dict[str, Any]:
    return {
        "id": message_id or f"msg_{uuid4().hex[:12]}",
        "type": message_type,
        "source": source,
        "payload": payload or {},
    }


def _normalize_legacy_message(raw: dict[str, Any]) -> dict[str, Any]:
    # Already in current envelope format.
    if {"id", "type", "source", "payload"}.issubset(raw.keys()):
        return raw

    message_type = str(raw.get("type", "") or "")
    source = str(raw.get("source") or raw.get("client_id") or "legacy_client")
    message_id = str(raw.get("id") or raw.get("request_id") or f"legacy_{uuid4().hex[:12]}")

    # Legacy registration from Atlas bridge: no "type", top-level fields.
    if (
        not message_type
        and "client_id" in raw
        and "client_type" in raw
        and ("version" in raw or "capabilities" in raw)
    ) or message_type == "registration":
        capabilities_raw = raw.get("capabilities", {})
        if isinstance(capabilities_raw, dict):
            capabilities = capabilities_raw
        elif isinstance(capabilities_raw, list):
            capabilities = {str(item): True for item in capabilities_raw}
        else:
            capabilities = {}
        return make_message(
            "register",
            source=source,
            payload={
                "client_id": source,
                "client_type": str(raw.get("client_type") or "app"),
                "capabilities": capabilities,
            },
            message_id=message_id,
        )

    # Legacy heartbeat: {"type":"heartbeat","client_id":"atlas","timestamp":"..."}
    if message_type == "heartbeat" and "payload" not in raw:
        uptime = raw.get("uptime_seconds")
        payload: dict[str, Any] = {}
        if isinstance(uptime, (int, float)):
            payload["uptime_seconds"] = float(uptime)
        return make_message("heartbeat", source=source, payload=payload, message_id=message_id)

    # Legacy state update: {"type":"state_update","client_id":"atlas","state":{...}}
    if message_type == "state_update" and "payload" not in raw and "state" in raw:
        state = raw.get("state")
        if not isinstance(state, dict):
            state = {}
        return make_message("state_update", source=source, payload={"state": state}, message_id=message_id)

    # Legacy intent: {"type":"intent","request_id":"...","targets":[...],"action":"...","params":{...}}
    if message_type == "intent" and "payload" not in raw and "targets" in raw and "action" in raw:
        targets_raw = raw.get("targets")
        params_raw = raw.get("params")
        targets = [str(item) for item in targets_raw] if isinstance(targets_raw, list) else []
        params = params_raw if isinstance(params_raw, dict) else {}
        return make_message(
            "intent",
            source=source,
            payload={"targets": targets, "action": str(raw.get("action")), "params": params},
            message_id=message_id,
        )

    # If type exists but payload/source are missing, wrap what we can.
    if message_type and "payload" not in raw:
        passthrough_payload = {k: v for k, v in raw.items() if k not in {"id", "type", "source", "client_id"}}
        return make_message(message_type, source=source, payload=passthrough_payload, message_id=message_id)

    return raw
