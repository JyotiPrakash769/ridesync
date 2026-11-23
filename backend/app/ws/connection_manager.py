"""In-memory WebSocket rooms: ride_id -> {rider_id: WebSocket}.

Fine for v0.1's single-instance deploy. To scale the backend horizontally
this must move to a shared broker (e.g. Redis pub/sub: publish each room
message on a `ride:{id}` channel and have every instance fan it out to its
local sockets), otherwise riders on different instances won't see each other.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi import WebSocket

log = logging.getLogger(__name__)

# Periodic rider_positions so a rider who goes silent visibly drifts
# online -> weak -> offline on everyone else's screen.
TICK_INTERVAL_S = 5.0

SnapshotFn = Callable[[str], Awaitable[dict[str, Any] | None]]


class ConnectionManager:
    def __init__(self) -> None:
        self._rooms: dict[str, dict[str, WebSocket]] = {}
        self._tickers: dict[str, asyncio.Task[None]] = {}
        self._snapshot: SnapshotFn | None = None

    def set_snapshot_fn(self, fn: SnapshotFn) -> None:
        self._snapshot = fn

    def room(self, ride_id: str) -> dict[str, WebSocket]:
        return self._rooms.get(ride_id, {})

    async def connect(self, ride_id: str, rider_id: str, ws: WebSocket) -> None:
        room = self._rooms.setdefault(ride_id, {})
        old = room.get(rider_id)
        room[rider_id] = ws
        if old is not None and old is not ws:
            # Same rider reconnected (e.g. after a network drop): keep the new socket.
            with contextlib.suppress(Exception):
                await old.close(code=1000)
        if ride_id not in self._tickers and self._snapshot is not None:
            self._tickers[ride_id] = asyncio.create_task(self._tick(ride_id))

    def disconnect(self, ride_id: str, rider_id: str, ws: WebSocket) -> None:
        """Forget this socket. Does NOT touch the rider row: a dropped socket
        must not delete or offline a rider (status comes from last_seen_at)."""
        room = self._rooms.get(ride_id)
        if room is None or room.get(rider_id) is not ws:
            return
        del room[rider_id]
        if not room:
            self._rooms.pop(ride_id, None)
            task = self._tickers.pop(ride_id, None)
            if task is not None:
                task.cancel()

    async def broadcast(self, ride_id: str, message: dict[str, Any]) -> None:
        for rider_id, ws in list(self.room(ride_id).items()):
            try:
                await ws.send_json(message)
            except Exception:  # socket already gone; its handler will clean up
                log.debug("send to %s/%s failed", ride_id, rider_id)

    async def send(self, ride_id: str, rider_id: str, message: dict[str, Any]) -> None:
        ws = self.room(ride_id).get(rider_id)
        if ws is not None:
            with contextlib.suppress(Exception):
                await ws.send_json(message)

    async def close_room(self, ride_id: str, code: int) -> None:
        for ws in list(self.room(ride_id).values()):
            with contextlib.suppress(Exception):
                await ws.close(code=code)

    async def broadcast_positions(self, ride_id: str) -> None:
        if self._snapshot is None:
            return
        msg = await self._snapshot(ride_id)
        if msg is not None:
            await self.broadcast(ride_id, msg)

    async def _tick(self, ride_id: str) -> None:
        while True:
            await asyncio.sleep(TICK_INTERVAL_S)
            try:
                await self.broadcast_positions(ride_id)
            except Exception:
                log.exception("position tick failed for %s", ride_id)


manager = ConnectionManager()
