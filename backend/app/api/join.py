"""REST: POST /rides/{ride_id}/join."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.ride import JoinRideIn, JoinRideOut
from app.security import rate_limit
from app.services import ride_service as rs
from app.ws.connection_manager import manager

router = APIRouter(prefix="/rides", tags=["rides"])


@router.post(
    "/{ride_id}/join",
    response_model=JoinRideOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("join"))],
)
async def join_ride(
    ride_id: str, body: JoinRideIn, db: AsyncSession = Depends(get_db)
) -> JoinRideOut:
    rider, token = await rs.join_ride(db, ride_id, body.display_name)
    await manager.broadcast(
        rider.ride_id,
        {"type": "rider_joined", "rider_id": str(rider.id), "name": rider.display_name,
         "role": rider.role},
    )
    return JoinRideOut(rider_id=rider.id, ride_id=rider.ride_id, rider_token=token)
