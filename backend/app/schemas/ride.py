"""REST request/response schemas (foundation doc §4)."""

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, Field, StringConstraints

from app.schemas.rider import RiderOut

DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)]


class CreateRideIn(BaseModel):
    leader_name: DisplayName


class CreateRideOut(BaseModel):
    ride_id: str
    leader_rider_id: uuid.UUID
    qr_payload: str


class JoinRideIn(BaseModel):
    display_name: DisplayName


class JoinRideOut(BaseModel):
    rider_id: uuid.UUID
    ride_id: str


class RideOut(BaseModel):
    ride_id: str
    status: Literal["active", "ended"]
    threshold_m: int
    leader_rider_id: uuid.UUID | None
    expires_at: datetime
    riders: list[RiderOut]


ALLOWED_THRESHOLDS_M = (100, 300, 500, 1000)


class ThresholdIn(BaseModel):
    # rider_id added to the documented body so the leader can be identified
    # (no auth in v0.1); agreed during planning.
    rider_id: uuid.UUID
    threshold_m: Literal[100, 300, 500, 1000]


class ThresholdOut(BaseModel):
    threshold_m: int


class EndRideIn(BaseModel):
    rider_id: uuid.UUID


class EndRideOut(BaseModel):
    status: Literal["ended"]


MAX_SYNC_POINTS = 1000


class SyncPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    recorded_at: AwareDatetime  # client clock; must carry a timezone


class SyncIn(BaseModel):
    rider_id: uuid.UUID
    points: list[SyncPoint] = Field(min_length=1, max_length=MAX_SYNC_POINTS)


class SyncOut(BaseModel):
    accepted: int
