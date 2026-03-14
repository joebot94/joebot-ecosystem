#!/usr/bin/env python3
"""Automated Nexus protocol demo check for the Joebot stack."""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from websockets.asyncio.client import connect

ROOT = Path(__file__).resolve().parents[1]
NEXUS_DIR = ROOT / "nexus"
NEXUS_URL = "ws://127.0.0.1:8675"


class DemoError(RuntimeError):
    pass


def make_message(source: str, msg_type: str, payload: dict[str, Any] | None = None) -> str:
    return json.dumps(
        {
            "id": f"msg_{uuid.uuid4().hex[:8]}",
            "type": msg_type,
            "source": source,
            "payload": payload or {},
        }
    )


async def wait_for(
    ws,
    predicate,
    *,
    timeout: float = 8.0,
    label: str = "message",
) -> dict[str, Any]:
    end = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < end:
        raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
        parsed = json.loads(raw)
        if predicate(parsed):
            return parsed
    raise DemoError(f"Timed out waiting for {label}")


async def register(ws, client_id: str, client_type: str) -> None:
    await ws.send(
        make_message(
            client_id,
            "register",
            {"client_id": client_id, "client_type": client_type},
        )
    )
    await wait_for(
        ws,
        lambda m: m.get("type") == "registered",
        label=f"registered for {client_id}",
    )


def start_nexus() -> subprocess.Popen[str]:
    process = subprocess.Popen(
        [sys.executable, "-u", "main.py"],
        cwd=NEXUS_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    return process


def wait_for_startup_line(process: subprocess.Popen[str], timeout: float = 8.0) -> str:
    assert process.stdout is not None
    end = time.time() + timeout
    lines: list[str] = []

    while time.time() < end:
        line = process.stdout.readline()
        if not line:
            continue
        line = line.rstrip("\n")
        lines.append(line)
        if "🦖" in line and "8675" in line:
            return line

    joined = "\n".join(lines[-8:])
    raise DemoError(f"Nexus did not show startup line with 🦖 on 8675.\nRecent output:\n{joined}")


async def run_demo() -> None:
    monitor = await connect(NEXUS_URL, ping_interval=None)
    dirty = await connect(NEXUS_URL, ping_interval=None)
    glitch = await connect(NEXUS_URL, ping_interval=None)

    try:
        await register(monitor, "observatory", "monitor")
        await register(dirty, "dirtymixer_v1", "mixer")
        await register(glitch, "glitch_catalog", "catalog")

        await dirty.send(
            make_message(
                "dirtymixer_v1",
                "state_update",
                {"state": {"channels": [{"id": 1, "mix": 171}], "mode": "Managed"}},
            )
        )
        await wait_for(
            monitor,
            lambda m: m.get("type") == "client.state"
            and m.get("payload", {}).get("client_id") == "dirtymixer_v1",
            label="dirtymixer client.state",
        )

        await dirty.close()
        await wait_for(
            monitor,
            lambda m: m.get("type") == "client.status"
            and m.get("payload", {}).get("client_id") == "dirtymixer_v1"
            and m.get("payload", {}).get("online") is False,
            label="dirtymixer offline status",
        )

        dirty = await connect(NEXUS_URL, ping_interval=None)
        await register(dirty, "dirtymixer_v1", "mixer")
        await wait_for(
            monitor,
            lambda m: m.get("type") == "client.status"
            and m.get("payload", {}).get("client_id") == "dirtymixer_v1"
            and m.get("payload", {}).get("online") is True,
            label="dirtymixer online status",
        )

        await glitch.send(
            make_message(
                "glitch_catalog",
                "scene_save",
                {"include_offline": True},
            )
        )
        await wait_for(
            glitch,
            lambda m: m.get("type") == "scene_saved",
            timeout=10,
            label="scene_saved",
        )
    finally:
        for ws in (monitor, dirty, glitch):
            try:
                await ws.close()
            except Exception:
                pass


def main() -> int:
    nexus = start_nexus()
    try:
        startup = wait_for_startup_line(nexus)
        print(f"[PASS] Nexus startup: {startup}")
        asyncio.run(run_demo())
        print("[PASS] Register + state_update + offline/online + scene_save checks")
        print("Demo complete: 🦖🟢🟢🟢")
        return 0
    except Exception as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1
    finally:
        nexus.terminate()
        try:
            nexus.wait(timeout=2)
        except subprocess.TimeoutExpired:
            nexus.kill()


if __name__ == "__main__":
    raise SystemExit(main())
