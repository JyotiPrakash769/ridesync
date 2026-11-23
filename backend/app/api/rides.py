"""REST: rides (create, read, threshold, end, sync). Join lives in api/join.py.

Authenticated routes need the caller's secret token in `X-Rider-Token`
(rider_id stays in the body as documented; GET uses `X-Rider-Id`).
"""

import uuid

from fastapi import APIRouter, Depends, Header, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models.ride import RIDE_ENDED
from app.schemas.ride import (
    CreateRideIn,
    CreateRideOut,
    EndRideIn,
    EndRideOut,
    RideOut,
    SyncIn,
    SyncOut,
    ThresholdIn,
    ThresholdOut,
)
from app.schemas.rider import RiderOut
from app.security import rate_limit
from app.services import ride_service as rs
from app.services import sync_service
from app.services.distance_service import tracker
from app.ws.connection_manager import manager
from app.ws.ride_socket import end_ride_rooms

router = APIRouter(prefix="/rides", tags=["rides"])

TokenHeader = Header(default=None, alias="X-Rider-Token")


def rider_out(rider, now=None) -> RiderOut:
    return RiderOut(
        rider_id=str(rider.id),
        name=rider.display_name,
        role=rider.role,
        lat=rider.last_lat,
        lng=rider.last_lng,
        speed_kph=rider.last_speed_kph,
        last_seen_at=rider.last_seen_at,
        status=rs.derive_status(rider.last_seen_at, now),
    )


@router.post(
    "",
    response_model=CreateRideOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("create"))],
)
async def create_ride(body: CreateRideIn, db: AsyncSession = Depends(get_db)) -> CreateRideOut:
    ride, leader, token = await rs.create_ride(db, body.leader_name)
    return CreateRideOut(
        ride_id=ride.id,
        leader_rider_id=leader.id,
        qr_payload=rs.qr_payload(ride.id),
        rider_token=token,
    )


@router.get("/{ride_id}", response_model=RideOut, dependencies=[Depends(rate_limit("read"))])
async def get_ride(
    ride_id: str,
    x_rider_id: uuid.UUID = Header(alias="X-Rider-Id"),
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> RideOut:
    """Riders of this ride only: names and positions are private to the group."""
    ride = await rs.get_ride_or_404(db, ride_id)
    await rs.authenticate(db, ride, x_rider_id, x_rider_token)
    now = rs.utcnow()
    riders = await rs.list_riders(db, ride.id)
    return RideOut(
        ride_id=ride.id,
        # An expired ride reads as ended even before the cleanup task runs.
        status="active" if rs.is_ride_live(ride, now) else RIDE_ENDED,
        threshold_m=ride.threshold_m,
        leader_rider_id=ride.leader_rider_id,
        expires_at=ride.expires_at,
        riders=[rider_out(r, now) for r in riders],
    )


@router.patch(
    "/{ride_id}/threshold",
    response_model=ThresholdOut,
    dependencies=[Depends(rate_limit("write"))],
)
async def set_threshold(
    ride_id: str,
    body: ThresholdIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> ThresholdOut:
    ride = await rs.set_threshold(db, ride_id, body.rider_id, x_rider_token, body.threshold_m)
    tracker.reset(ride.id)  # re-evaluate everyone against the new threshold
    await manager.broadcast(ride.id, {"type": "threshold_updated", "threshold_m": ride.threshold_m})
    return ThresholdOut(threshold_m=ride.threshold_m)


@router.post(
    "/{ride_id}/end", response_model=EndRideOut, dependencies=[Depends(rate_limit("write"))]
)
async def end_ride(
    ride_id: str,
    body: EndRideIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> EndRideOut:
    ride = await rs.end_ride(db, ride_id, body.rider_id, x_rider_token)
    await end_ride_rooms([ride.id])
    return EndRideOut(status="ended")


@router.post(
    "/{ride_id}/sync", response_model=SyncOut, dependencies=[Depends(rate_limit("write"))]
)
async def sync_points(
    ride_id: str,
    body: SyncIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> SyncOut:
    accepted = await sync_service.ingest(db, ride_id, body.rider_id, x_rider_token, body.points)
    await manager.broadcast_positions(rs.normalize_ride_id(ride_id))
    return SyncOut(accepted=accepted)
