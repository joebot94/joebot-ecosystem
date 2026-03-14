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
    | SceneStateMessage,
    Field(discriminator="type"),
]

_TYPED_ADAPTER = TypeAdapter(TypedMessage)


def parse_message(raw: dict[str, Any]) -> NexusMessage | TypedMessage:
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
