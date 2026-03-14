"""Heartbeat watcher for Nexus. 🦖"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable

from core.registry import ClientRecord, ClientRegistry


class HeartbeatWatcher:
    def __init__(
        self,
        registry: ClientRegistry,
        timeout_seconds: int,
        check_interval_seconds: int,
        on_timeout: Callable[[ClientRecord], Awaitable[None]],
    ) -> None:
        self.registry = registry
        self.timeout_seconds = timeout_seconds
        self.check_interval_seconds = check_interval_seconds
        self.on_timeout = on_timeout
        self._task: asyncio.Task[None] | None = None
        self._running = False

    def start(self) -> None:
        if self._task is not None:
            return
        self._running = True
        self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        self._running = False
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        self._task = None

    async def _loop(self) -> None:
        while self._running:
            stale = self.registry.stale_online_clients(self.timeout_seconds)
            for record in stale:
                await self.on_timeout(record)
            await asyncio.sleep(self.check_interval_seconds)
