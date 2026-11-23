"""REST: rides (create, read, threshold, end). Join lives in api/join.py."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models.ride import RIDE_ENDED
from app.schemas.ride import (
    CreateRideIn,
    CreateRideOut,
    EndRideIn,
    EndRideOut,
    RideOut,
    ThresholdIn,
    ThresholdOut,
)
from app.schemas.rider import RiderOut
from app.services import ride_service as rs

router = APIRouter(prefix="/rides", tags=["rides"])


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


@router.post("", response_model=CreateRideOut, status_code=status.HTTP_201_CREATED)
async def create_ride(body: CreateRideIn, db: AsyncSession = Depends(get_db)) -> CreateRideOut:
    ride, leader = await rs.create_ride(db, body.leader_name)
    return CreateRideOut(
        ride_id=ride.id, leader_rider_id=leader.id, qr_payload=rs.qr_payload(ride.id)
    )


@router.get("/{ride_id}", response_model=RideOut)
async def get_ride(ride_id: str, db: AsyncSession = Depends(get_db)) -> RideOut:
    ride = await rs.get_ride_or_404(db, ride_id)
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


@router.patch("/{ride_id}/threshold", response_model=ThresholdOut)
async def set_threshold(
    ride_id: str, body: ThresholdIn, db: AsyncSession = Depends(get_db)
) -> ThresholdOut:
    ride = await rs.set_threshold(db, ride_id, body.rider_id, body.threshold_m)
    return ThresholdOut(threshold_m=ride.threshold_m)


@router.post("/{ride_id}/end", response_model=EndRideOut)
async def end_ride(ride_id: str, body: EndRideIn, db: AsyncSession = Depends(get_db)) -> EndRideOut:
    await rs.end_ride(db, ride_id, body.rider_id)
    return EndRideOut(status="ended")
