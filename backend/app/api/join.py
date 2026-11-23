"""REST: POST /rides/{ride_id}/join."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.ride import JoinRideIn, JoinRideOut
from app.services import ride_service as rs

router = APIRouter(prefix="/rides", tags=["rides"])


@router.post("/{ride_id}/join", response_model=JoinRideOut, status_code=status.HTTP_201_CREATED)
async def join_ride(
    ride_id: str, body: JoinRideIn, db: AsyncSession = Depends(get_db)
) -> JoinRideOut:
    rider = await rs.join_ride(db, ride_id, body.display_name)
    return JoinRideOut(rider_id=rider.id, ride_id=rider.ride_id)
