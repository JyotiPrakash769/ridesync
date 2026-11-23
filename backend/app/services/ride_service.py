"""Ride lifecycle: ID generation, create/join/end/threshold, expiry, status.

Lifecycle rules (decided, see foundation doc notes):
- A ride lives until expires_at (created_at + RIDE_TTL_HOURS) or until the
  leader ends it. The leader disconnecting does NOT end the ride.
- Missing ride -> 404. Ended or expired ride -> 410.
"""

from __future__ import annotations

import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.ride import RIDE_ACTIVE, RIDE_ENDED, Ride
from app.models.rider import ROLE_LEADER, ROLE_MEMBER, Rider

# RFC 4648 base32 (A-Z, 2-7) minus the ambiguous O, I, L. Base32 already has
# no 0/1, so every 0/O and 1/I/L confusion is impossible.
RIDE_ID_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ234567"
RIDE_ID_LENGTH = 6

QR_LINK_TEMPLATE = "https://ridesync.app/join/{ride_id}"
QR_SCHEME_TEMPLATE = "ridesync://join/{ride_id}"

ONLINE_MAX_S = 15
WEAK_MAX_S = 60

RiderStatus = Literal["online", "weak", "offline"]


def utcnow() -> datetime:
    return datetime.now(UTC)


def generate_ride_id() -> str:
    return "".join(secrets.choice(RIDE_ID_ALPHABET) for _ in range(RIDE_ID_LENGTH))


def normalize_ride_id(raw: str) -> str:
    return raw.strip().upper()


def derive_status(last_seen_at: datetime | None, now: datetime | None = None) -> RiderStatus:
    """online <15s, weak 15-60s, offline >60s (or never seen)."""
    if last_seen_at is None:
        return "offline"
    age = ((now or utcnow()) - last_seen_at).total_seconds()
    if age < ONLINE_MAX_S:
        return "online"
    if age <= WEAK_MAX_S:
        return "weak"
    return "offline"


def is_ride_live(ride: Ride, now: datetime | None = None) -> bool:
    return ride.status == RIDE_ACTIVE and ride.expires_at > (now or utcnow())


async def get_ride_or_404(db: AsyncSession, ride_id: str) -> Ride:
    ride = await db.get(Ride, normalize_ride_id(ride_id))
    if ride is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "ride_not_found")
    return ride


async def get_live_ride_or_raise(db: AsyncSession, ride_id: str) -> Ride:
    """404 if the ride doesn't exist, 410 if it ended or expired."""
    ride = await get_ride_or_404(db, ride_id)
    if not is_ride_live(ride):
        raise HTTPException(status.HTTP_410_GONE, "ride_ended")
    return ride


async def get_rider_in_ride(db: AsyncSession, ride: Ride, rider_id: uuid.UUID) -> Rider | None:
    rider = await db.get(Rider, rider_id)
    if rider is None or rider.ride_id != ride.id:
        return None
    return rider


async def require_leader(db: AsyncSession, ride: Ride, rider_id: uuid.UUID) -> Rider:
    rider = await get_rider_in_ride(db, ride, rider_id)
    if rider is None or rider.role != ROLE_LEADER or ride.leader_rider_id != rider.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "leader_only")
    return rider


async def list_riders(db: AsyncSession, ride_id: str) -> list[Rider]:
    rows = await db.scalars(
        select(Rider).where(Rider.ride_id == ride_id).order_by(Rider.joined_at, Rider.id)
    )
    return list(rows)


async def create_ride(db: AsyncSession, leader_name: str) -> tuple[Ride, Rider]:
    now = utcnow()
    ttl = timedelta(hours=get_settings().RIDE_TTL_HOURS)
    for _ in range(10):
        ride_id = generate_ride_id()
        if await db.get(Ride, ride_id) is None:
            break
    else:  # pragma: no cover - 29^6 ≈ 594M ids
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "ride_id_exhausted")

    ride = Ride(id=ride_id, status=RIDE_ACTIVE, created_at=now, expires_at=now + ttl)
    db.add(ride)
    await db.flush()
    leader = Rider(ride_id=ride_id, display_name=leader_name, role=ROLE_LEADER, joined_at=now)
    db.add(leader)
    await db.flush()
    ride.leader_rider_id = leader.id
    await db.commit()
    return ride, leader


async def join_ride(db: AsyncSession, ride_id: str, display_name: str) -> Rider:
    ride = await get_live_ride_or_raise(db, ride_id)
    rider = Rider(ride_id=ride.id, display_name=display_name, role=ROLE_MEMBER, joined_at=utcnow())
    db.add(rider)
    await db.commit()
    return rider


async def set_threshold(
    db: AsyncSession, ride_id: str, rider_id: uuid.UUID, threshold_m: int
) -> Ride:
    ride = await get_live_ride_or_raise(db, ride_id)
    await require_leader(db, ride, rider_id)
    ride.threshold_m = threshold_m
    await db.commit()
    return ride


async def end_ride(db: AsyncSession, ride_id: str, rider_id: uuid.UUID) -> Ride:
    ride = await get_live_ride_or_raise(db, ride_id)
    await require_leader(db, ride, rider_id)
    ride.status = RIDE_ENDED
    await db.commit()
    return ride


def qr_payload(ride_id: str) -> str:
    return QR_LINK_TEMPLATE.format(ride_id=ride_id)
