"""Offline-sync batch ingestion (POST /rides/{id}/sync)."""

from __future__ import annotations

import uuid

from fastapi import HTTPException, status
from sqlalchemy import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.location import Location
from app.schemas.ride import SyncPoint
from app.services import ride_service as rs


async def ingest(
    db: AsyncSession, ride_id: str, rider_id: uuid.UUID, points: list[SyncPoint]
) -> int:
    """Append points to `locations` and move the rider's live position to the
    newest point, but only if it is newer than what the live socket already
    reported (old queued points must never overwrite a fresher position)."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    rider = await rs.get_rider_in_ride(db, ride, rider_id)
    if rider is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not_a_rider")

    now = rs.utcnow()
    # A phone clock running ahead must not make a point look "newer than now".
    rows = [
        {"rider_id": rider.id, "lat": p.lat, "lng": p.lng, "recorded_at": min(p.recorded_at, now)}
        for p in points
    ]
    await db.execute(insert(Location), rows)

    newest = max(rows, key=lambda r: r["recorded_at"])
    if rider.last_seen_at is None or newest["recorded_at"] > rider.last_seen_at:
        rider.last_lat = newest["lat"]
        rider.last_lng = newest["lng"]
        rider.last_seen_at = newest["recorded_at"]
    await db.commit()
    return len(rows)
