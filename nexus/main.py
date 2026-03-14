"""Nexus entrypoint. 🦖"""

from __future__ import annotations

import asyncio

from api.websocket_server import run_server


if __name__ == "__main__":
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        print("\nNexus stopped.")
