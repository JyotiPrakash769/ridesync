"""v0.2 convoy features: regroup point, leader handoff / takeover, event log,
ride summary.

Leader takeover rule (agreed): a member may make *themselves* leader only
when the current leader has been offline (no update for 60 s) for at least
another 3 minutes, i.e. last seen more than TAKEOVER_AFTER_S ago.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import datetime

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import (
    EVENT_FALLING_BEHIND,
    EVENT_LEADER_CHANGED,
    EVENT_REGROUP_CLEARED,
    EVENT_REGROUP_SET,
    RideEvent,
)
from app.models.location import Location
from app.models.ride import Ride
from app.models.rider import ROLE_LEADER, ROLE_MEMBER, Rider
from app.services import ride_service as rs
from app.services.distance_service import haversine_m

OFFLINE_AFTER_S = rs.WEAK_MAX_S  # 60
TAKEOVER_AFTER_S = OFFLINE_AFTER_S + 180

# A segment implying more than this is GPS noise, not riding.
MAX_PLAUSIBLE_KPH = 250


def add_event(
    db: AsyncSession, ride_id: str, type_: str,
    rider_id: uuid.UUID | None = None, distance_m: int | None = None,
) -> None:
    db.add(RideEvent(ride_id=ride_id, rider_id=rider_id, type=type_, distance_m=distance_m))


# ---------- regroup ----------

def regroup_payload(ride: Ride) -> dict | None:
    if ride.regroup_lat is None or ride.regroup_lng is None:
        return None
    return {
        "lat": ride.regroup_lat,
        "lng": ride.regroup_lng,
        "label": ride.regroup_label or "",
        "set_at": ride.regroup_set_at.isoformat() if ride.regroup_set_at else None,
    }


async def set_regroup(
    db: AsyncSession, ride_id: str, rider_id: uuid.UUID, token: str | None,
    point: tuple[float, float, str] | None,
) -> Ride:
    """Leader sets (or with point=None clears) the meeting point."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    leader = await rs.require_leader(db, ride, rider_id, token)
    if point is None:
        ride.regroup_lat = ride.regroup_lng = ride.regroup_label = ride.regroup_set_at = None
        add_event(db, ride.id, EVENT_REGROUP_CLEARED, leader.id)
    else:
        ride.regroup_lat, ride.regroup_lng, ride.regroup_label = point
        ride.regroup_set_at = rs.utcnow()
        add_event(db, ride.id, EVENT_REGROUP_SET, leader.id)
    await db.commit()
    return ride


# ---------- leader handoff / takeover ----------

def leader_is_gone(leader: Rider, ride: Ride, now: datetime) -> bool:
    seen = leader.last_seen_at or ride.created_at
    return (now - seen).total_seconds() > TAKEOVER_AFTER_S


async def change_leader(
    db: AsyncSession, ride_id: str, caller_id: uuid.UUID, token: str | None,
    new_leader_id: uuid.UUID,
) -> tuple[Ride, Rider, str]:
    """Returns (ride, new leader, reason) where reason is handoff|takeover."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    caller = await rs.authenticate(db, ride, caller_id, token)
    target = await rs.get_rider_in_ride(db, ride, new_leader_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "rider_not_in_ride")
    current = await db.get(Rider, ride.leader_rider_id) if ride.leader_rider_id else None

    if current is not None and caller.id == current.id:
        reason = "handoff"
    elif target.id == caller.id and (current is None or leader_is_gone(current, ride, rs.utcnow())):
        reason = "takeover"
    else:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "leader_only")

    if current is not None and current.id != target.id:
        current.role = ROLE_MEMBER
    target.role = ROLE_LEADER
    ride.leader_rider_id = target.id
    add_event(db, ride.id, EVENT_LEADER_CHANGED, target.id)
    await db.commit()
    return ride, target, reason


# ---------- events from the live socket ----------

async def record_falling_behind(ride_id: str, alerts: list[dict]) -> None:
    from app.db.session import AsyncSessionLocal

    if not alerts:
        return
    async with AsyncSessionLocal() as db:
        for a in alerts:
            add_event(db, ride_id, EVENT_FALLING_BEHIND, uuid.UUID(a["rider_id"]), a["distance_m"])
        await db.commit()


# ---------- summary ----------

def track_km(points: list[tuple[float, float, datetime]]) -> float:
    """Distance along time-ordered points, skipping implausible GPS jumps."""
    total = 0.0
    for (la1, ln1, t1), (la2, ln2, t2) in zip(points, points[1:], strict=False):
        d = haversine_m(la1, ln1, la2, ln2)
        dt = (t2 - t1).total_seconds()
        if dt <= 0 or d / dt * 3.6 > MAX_PLAUSIBLE_KPH:
            continue
        total += d
    return total / 1000


async def summary(db: AsyncSession, ride_id: str, rider_id: uuid.UUID, token: str | None) -> dict:
    ride = await rs.get_ride_or_404(db, ride_id)
    await rs.authenticate(db, ride, rider_id, token)
    now = rs.utcnow()
    ended_at = ride.ended_at or (None if rs.is_ride_live(ride, now) else ride.expires_at)
    riders = await rs.list_riders(db, ride.id)

    locs = await db.execute(
        select(Location.rider_id, Location.lat, Location.lng, Location.recorded_at)
        .join(Rider, Rider.id == Location.rider_id)
        .where(Rider.ride_id == ride.id)
        .order_by(Location.rider_id, Location.recorded_at)
    )
    tracks: dict[uuid.UUID, list[tuple[float, float, datetime]]] = defaultdict(list)
    for rid, lat, lng, at in locs:
        tracks[rid].append((lat, lng, at))

    events = (await db.scalars(
        select(RideEvent).where(RideEvent.ride_id == ride.id).order_by(RideEvent.created_at)
    )).all()
    behind_count: dict[uuid.UUID, int] = defaultdict(int)
    max_gap: dict[uuid.UUID, int] = defaultdict(int)
    for e in events:
        if e.type == EVENT_FALLING_BEHIND and e.rider_id is not None:
            behind_count[e.rider_id] += 1
            max_gap[e.rider_id] = max(max_gap[e.rider_id], e.distance_m or 0)

    end = ended_at or now
    return {
        "ride_id": ride.id,
        "status": "active" if rs.is_ride_live(ride, now) else "ended",
        "started_at": ride.created_at.isoformat(),
        "ended_at": ended_at.isoformat() if ended_at else None,
        "duration_s": max(0, int((end - ride.created_at).total_seconds())),
        "falling_behind_total": sum(behind_count.values()),
        "leader_changes": sum(1 for e in events if e.type == EVENT_LEADER_CHANGED),
        "planned_distance_km": round(ride.plan["distance_m"] / 1000, 1) if ride.plan else None,
        "destination": ride.plan["destination"]["label"] if ride.plan else None,
        "riders": [
            {
                "rider_id": str(r.id),
                "name": r.display_name,
                "role": r.role,
                "distance_km": round(track_km(tracks.get(r.id, [])), 2),
                "falling_behind_count": behind_count.get(r.id, 0),
                "max_gap_m": max_gap.get(r.id) or None,
            }
            for r in riders
        ],
    }


