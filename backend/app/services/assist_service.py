"""Leader assist: stopped riders, arrivals, quick messages, sweep rider.

In memory like the alert tracker (single instance; Redis when scaling).
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import RideEvent
from app.services import ride_service as rs
from app.services.distance_service import haversine_m

STOPPED_AFTER_S = 180   # no real movement for 3 minutes -> "stopped"
MOVED_M = 40            # moving this far from the anchor point = moving again
ARRIVED_M = 150
EVENT_ARRIVED = "arrived"

LEADER_CODES = {"slow_down", "stop_next_fuel", "regroup", "lets_go", "speed_up"}
RIDER_CODES = {"stopping", "need_fuel", "help", "all_good", "on_my_way"}
QUICK_MIN_INTERVAL_S = 3.0


class StoppedTracker:
    """Per rider: anchor point + when they were last there. A rider who stays
    within MOVED_M of the anchor for STOPPED_AFTER_S is reported once."""

    def __init__(self) -> None:
        self._anchor: dict[tuple[str, str], tuple[float, float, float]] = {}
        self._stopped: set[tuple[str, str]] = set()

    def reset(self, ride_id: str) -> None:
        self._anchor = {k: v for k, v in self._anchor.items() if k[0] != ride_id}
        self._stopped = {k for k in self._stopped if k[0] != ride_id}

    def evaluate(self, ride_id: str, rider_id: str, name: str, lat: float, lng: float,
                 now: float) -> dict | None:
        key = (ride_id, rider_id)
        a = self._anchor.get(key)
        if a is None or haversine_m(a[0], a[1], lat, lng) > MOVED_M:
            self._anchor[key] = (lat, lng, now)
            if key in self._stopped:
                self._stopped.discard(key)
                return {"type": "rider_moving", "rider_id": rider_id, "name": name}
            return None
        if key not in self._stopped and now - a[2] >= STOPPED_AFTER_S:
            self._stopped.add(key)
            return {"type": "rider_stopped", "rider_id": rider_id, "name": name,
                    "stopped_s": round(now - a[2]), "lat": a[0], "lng": a[1]}
        return None


class ArrivalTracker:
    """Who has reached the current plan's destination (once per plan)."""

    def __init__(self) -> None:
        self._arrived: dict[tuple[str, str], set[str]] = {}  # (ride, plan stamp) -> riders

    def reset(self, ride_id: str) -> None:
        self._arrived = {k: v for k, v in self._arrived.items() if k[0] != ride_id}

    def evaluate(self, ride_id: str, plan: dict | None, rider_id: str, name: str,
                 lat: float, lng: float) -> dict | None:
        if not plan:
            return None
        d = plan["destination"]
        if haversine_m(lat, lng, d["lat"], d["lng"]) > ARRIVED_M:
            return None
        done = self._arrived.setdefault((ride_id, plan.get("updated_at", "")), set())
        if rider_id in done:
            return None
        done.add(rider_id)
        return {"type": "rider_arrived", "rider_id": rider_id, "name": name}


stopped_tracker = StoppedTracker()
arrival_tracker = ArrivalTracker()


def quick_code_allowed(code: str, is_leader: bool) -> bool:
    return code in RIDER_CODES or (is_leader and code in LEADER_CODES)


async def arrived_rider_ids(db: AsyncSession, ride) -> list[str]:
    """Riders who reached the current plan's destination (persisted events)."""
    if not ride.plan:
        return []
    since = ride.plan.get("updated_at")
    q = select(RideEvent.rider_id, RideEvent.created_at).where(
        RideEvent.ride_id == ride.id, RideEvent.type == EVENT_ARRIVED)
    rows = (await db.execute(q)).all()
    from datetime import datetime

    cut = datetime.fromisoformat(since) if since else None
    return sorted({str(r) for r, at in rows if r and (cut is None or at >= cut)})


async def record_arrival(ride_id: str, rider_id: str) -> None:
    from app.db.session import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        db.add(RideEvent(ride_id=ride_id, rider_id=uuid.UUID(rider_id), type=EVENT_ARRIVED))
        await db.commit()


async def set_sweep(db: AsyncSession, ride_id: str, rider_id: uuid.UUID, token: str | None,
                    sweep_id: uuid.UUID | None):
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    await rs.require_leader(db, ride, rider_id, token)
    if sweep_id is not None and await rs.get_rider_in_ride(db, ride, sweep_id) is None:
        from fastapi import HTTPException, status

        raise HTTPException(status.HTTP_404_NOT_FOUND, "rider_not_in_ride")
    ride.sweep_rider_id = sweep_id
    await db.commit()
    return ride
