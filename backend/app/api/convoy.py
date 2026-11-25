"""REST (v0.2): regroup point, leader handoff/takeover, ride summary."""

import uuid

from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.ride import ChangeLeaderIn, SetRegroupIn, SetSweepIn
from app.security import rate_limit
from app.services import assist_service
from app.services import convoy_service as cs
from app.services.distance_service import tracker
from app.ws.connection_manager import manager

router = APIRouter(prefix="/rides", tags=["convoy"])

TokenHeader = Header(default=None, alias="X-Rider-Token")


@router.put("/{ride_id}/regroup", dependencies=[Depends(rate_limit("write"))])
async def set_regroup(
    ride_id: str,
    body: SetRegroupIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Leader only. `point: null` clears it. Broadcasts `regroup_point`."""
    point = None if body.point is None else (body.point.lat, body.point.lng, body.point.label)
    ride = await cs.set_regroup(db, ride_id, body.rider_id, x_rider_token, point)
    payload = cs.regroup_payload(ride)
    await manager.broadcast(ride.id, {"type": "regroup_point", "point": payload})
    return {"point": payload}


@router.post("/{ride_id}/leader", dependencies=[Depends(rate_limit("write"))])
async def change_leader(
    ride_id: str,
    body: ChangeLeaderIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Leader hands off to any rider, or a member takes over after the leader
    has been offline 3+ minutes. Broadcasts `leader_changed`."""
    ride, leader, reason = await cs.change_leader(
        db, ride_id, body.rider_id, x_rider_token, body.new_leader_id
    )
    tracker.reset(ride.id)  # distances are now measured to the new leader
    msg = {
        "type": "leader_changed",
        "leader_rider_id": str(leader.id),
        "name": leader.display_name,
        "reason": reason,
    }
    await manager.broadcast(ride.id, msg)
    await manager.broadcast_positions(ride.id)
    return msg


@router.get("/{ride_id}/summary", dependencies=[Depends(rate_limit("read"))])
async def ride_summary(
    ride_id: str,
    x_rider_id: uuid.UUID = Header(alias="X-Rider-Id"),
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Duration, per-rider distance and falling-behind counts. Works for ended
    rides too (until data retention deletes them)."""
    return await cs.summary(db, ride_id, x_rider_id, x_rider_token)


@router.put("/{ride_id}/sweep", dependencies=[Depends(rate_limit("write"))])
async def set_sweep(
    ride_id: str,
    body: SetSweepIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Leader marks the tail ("sweep") rider, or clears it. Broadcasts `sweep_changed`."""
    ride = await assist_service.set_sweep(db, ride_id, body.rider_id, x_rider_token,
                                          body.sweep_rider_id)
    sid = str(ride.sweep_rider_id) if ride.sweep_rider_id else None
    await manager.broadcast(ride.id, {"type": "sweep_changed", "sweep_rider_id": sid})
    return {"sweep_rider_id": sid}
