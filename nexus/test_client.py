"""Simple Nexus protocol test client. 🦖"""

from __future__ import annotations

import asyncio
import json
import uuid

from websockets.client import connect

NEXUS_URL = "ws://127.0.0.1:8675"
CLIENT_ID = "nexus_test_client"


def make_message(message_type: str, payload: dict | None = None) -> str:
    return json.dumps(
        {
            "id": f"msg_{uuid.uuid4().hex[:8]}",
            "type": message_type,
            "source": CLIENT_ID,
            "payload": payload or {},
        }
    )


async def listen(ws) -> None:
    async for raw in ws:
        print(f"[recv] {raw}")


async def main() -> None:
    async with connect(NEXUS_URL, ping_interval=None) as ws:
        print(f"Connected to {NEXUS_URL}")
        await ws.send(
            make_message(
                "register",
                {"client_id": CLIENT_ID, "client_type": "tool", "capabilities": {"query": True, "intent": True}},
            )
        )
        await ws.send(make_message("state_update", {"state": {"status": "ready", "value": 42}}))

        listener = asyncio.create_task(listen(ws))

        for _ in range(3):
            await ws.send(make_message("heartbeat", {"uptime_seconds": 1.0}))
            await asyncio.sleep(2)

        await ws.send(make_message("query", {"target": CLIENT_ID}))
        await asyncio.sleep(2)
        listener.cancel()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
