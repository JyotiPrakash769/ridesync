"""Builds rider_positions snapshots (shared by REST, WS handler and ticker)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from app.db.session import AsyncSessionLocal
from app.models.rider import Rider
from app.services import ride_service as rs


def rider_payload(rider: Rider, now: datetime | None = None) -> dict[str, Any]:
    return {
        "rider_id": str(rider.id),
        "name": rider.display_name,
        "role": rider.role,
        "lat": rider.last_lat,
        "lng": rider.last_lng,
        "speed_kph": rider.last_speed_kph,
        "last_seen_at": rider.last_seen_at.isoformat() if rider.last_seen_at else None,
        "status": rs.derive_status(rider.last_seen_at, now),
    }


async def positions_message(ride_id: str) -> dict[str, Any] | None:
    async with AsyncSessionLocal() as db:
        ride = await db.get(rs.Ride, ride_id)
        if ride is None or not rs.is_ride_live(ride):
            return None
        now = rs.utcnow()
        riders = await rs.list_riders(db, ride_id)
        return {"type": "rider_positions", "riders": [rider_payload(r, now) for r in riders]}


async def evaluate_alerts(ride_id: str) -> list[dict[str, Any]]:
    """Run the distance tracker for a ride; returns distance_alert messages."""
    from app.models.rider import ROLE_LEADER
    from app.services.distance_service import Point, tracker

    async with AsyncSessionLocal() as db:
        ride = await db.get(rs.Ride, ride_id)
        if ride is None or not rs.is_ride_live(ride):
            tracker.reset(ride_id)
            return []
        now = rs.utcnow()
        riders = await rs.list_riders(db, ride_id)
        points = [
            Point(str(r.id), r.display_name, r.last_lat, r.last_lng,
                  rs.derive_status(r.last_seen_at, now))
            for r in riders
        ]
        leader = next(
            (p for p, r in zip(points, riders, strict=True) if r.role == ROLE_LEADER), None
        )
        return [a.message() for a in tracker.evaluate(ride_id, leader, points, ride.threshold_m)]
