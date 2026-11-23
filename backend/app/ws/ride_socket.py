"""WS /ws/rides/{ride_id}?rider_id= : live positions for one ride."""

from __future__ import annotations

import logging
import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError
from sqlalchemy import delete

from app.db.session import AsyncSessionLocal
from app.models.rider import ROLE_LEADER, Rider
from app.schemas.ws_messages import (
    CLOSE_LEFT,
    CLOSE_NOT_A_RIDER,
    CLOSE_RIDE_ENDED,
    CLOSE_RIDE_NOT_FOUND,
    Heartbeat,
    Leave,
    LocationUpdate,
    client_message_adapter,
)
from app.services import ride_service as rs
from app.services.distance_service import tracker
from app.services.positions import evaluate_alerts
from app.ws.connection_manager import manager

log = logging.getLogger(__name__)
router = APIRouter()


async def _authorize(ride_id: str, rider_id: str) -> tuple[str, int | None]:
    """Returns (normalized ride id, close code or None if allowed)."""
    ride_id = rs.normalize_ride_id(ride_id)
    try:
        rid = uuid.UUID(rider_id)
    except ValueError:
        return ride_id, CLOSE_NOT_A_RIDER
    async with AsyncSessionLocal() as db:
        ride = await db.get(rs.Ride, ride_id)
        if ride is None:
            return ride_id, CLOSE_RIDE_NOT_FOUND
        if not rs.is_ride_live(ride):
            return ride_id, CLOSE_RIDE_ENDED
        if await rs.get_rider_in_ride(db, ride, rid) is None:
            return ride_id, CLOSE_NOT_A_RIDER
        rider = await db.get(Rider, rid)
        rider.last_seen_at = rs.utcnow()
        rider.is_online = True
        await db.commit()
    return ride_id, None


async def on_location(ride_id: str, rider_id: str, msg: LocationUpdate) -> None:
    async with AsyncSessionLocal() as db:
        rider = await db.get(Rider, uuid.UUID(rider_id))
        if rider is None:
            return
        rider.last_lat = msg.lat
        rider.last_lng = msg.lng
        rider.last_speed_kph = msg.speed_kph
        rider.last_seen_at = rs.utcnow()  # server clock, not msg.ts
        rider.is_online = True
        await db.commit()
    await manager.broadcast_positions(ride_id)
    # Alerts go to the whole room per the protocol; the app shows them to the leader.
    for alert in await evaluate_alerts(ride_id):
        await manager.broadcast(ride_id, alert)


async def on_heartbeat(rider_id: str) -> None:
    async with AsyncSessionLocal() as db:
        rider = await db.get(Rider, uuid.UUID(rider_id))
        if rider is not None:
            rider.last_seen_at = rs.utcnow()
            rider.is_online = True
            await db.commit()


async def on_leave(ride_id: str, rider_id: str) -> bool:
    """Members leave for good; the leader ends the ride via REST instead."""
    async with AsyncSessionLocal() as db:
        rider = await db.get(Rider, uuid.UUID(rider_id))
        if rider is None or rider.role == ROLE_LEADER:
            return False
        await db.execute(delete(Rider).where(Rider.id == rider.id))
        await db.commit()
    tracker.forget_rider(ride_id, rider_id)
    await manager.broadcast(ride_id, {"type": "rider_left", "rider_id": rider_id})
    return True


@router.websocket("/ws/rides/{ride_id}")
async def ride_socket(ws: WebSocket, ride_id: str, rider_id: str = "") -> None:
    await ws.accept()
    ride_id, refuse = await _authorize(ride_id, rider_id)
    if refuse is not None:
        await ws.close(code=refuse)
        return
    rider_id = str(uuid.UUID(rider_id))

    await manager.connect(ride_id, rider_id, ws)
    try:
        await manager.broadcast_positions(ride_id)
        while True:
            raw = await ws.receive_text()
            try:
                msg = client_message_adapter.validate_json(raw)
            except ValidationError:
                log.debug("ignoring invalid ws message from %s: %.200s", rider_id, raw)
                continue
            if isinstance(msg, LocationUpdate):
                await on_location(ride_id, rider_id, msg)
            elif isinstance(msg, Heartbeat):
                await on_heartbeat(rider_id)
            elif isinstance(msg, Leave) and await on_leave(ride_id, rider_id):
                await ws.close(code=CLOSE_LEFT)
                return
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(ride_id, rider_id, ws)


async def end_ride_rooms(ride_ids: list[str]) -> None:
    """Notify and close rooms for rides that ended (leader or expiry)."""
    for rid in ride_ids:
        tracker.reset(rid)
        await manager.broadcast(rid, {"type": "ride_ended"})
        await manager.close_room(rid, CLOSE_RIDE_ENDED)
