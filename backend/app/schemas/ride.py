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
    rider_token: str  # secret; send as X-Rider-Token / ?token=


class JoinRideIn(BaseModel):
    display_name: DisplayName


class JoinRideOut(BaseModel):
    rider_id: uuid.UUID
    ride_id: str
    rider_token: str  # secret; send as X-Rider-Token / ?token=


class RideOut(BaseModel):
    ride_id: str
    status: Literal["active", "ended"]
    threshold_m: int
    leader_rider_id: uuid.UUID | None
    expires_at: datetime
    riders: list[RiderOut]
    regroup: dict | None = None  # {lat, lng, label, set_at} (v0.2)
    plan: dict | None = None  # trip plan (v0.3), same shape as the trip_plan message
    sweep_rider_id: uuid.UUID | None = None  # v0.4
    arrived: list[str] = []  # v0.4: rider ids at the plan's destination


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


class RegroupIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    label: Annotated[str, StringConstraints(strip_whitespace=True, max_length=40)] = ""


class SetRegroupIn(BaseModel):
    rider_id: uuid.UUID
    point: RegroupIn | None  # null clears the regroup point


class ChangeLeaderIn(BaseModel):
    rider_id: uuid.UUID  # caller
    new_leader_id: uuid.UUID


class PlaceIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    label: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] = ""


class SetPlanIn(BaseModel):
    rider_id: uuid.UUID
    # null destination clears the plan; null origin = leader's live position
    origin: PlaceIn | None = None
    destination: PlaceIn | None
    stops: list[PlaceIn] = Field(default_factory=list, max_length=5)
    avoid_tolls: bool = False
    avoid_highways: bool = False
    optimize_stops: bool = False
    alternative: int = Field(default=0, ge=0, le=2)  # index from /plan/preview
    departure_at: AwareDatetime | None = None
    fuel_range_km: int | None = Field(default=None, ge=30, le=1000)


class PreviewPlanIn(BaseModel):
    rider_id: uuid.UUID
    origin: PlaceIn | None = None
    destination: PlaceIn
    stops: list[PlaceIn] = Field(default_factory=list, max_length=5)
    avoid_tolls: bool = False
    avoid_highways: bool = False
    optimize_stops: bool = False


class SetSweepIn(BaseModel):
    rider_id: uuid.UUID
    sweep_rider_id: uuid.UUID | None
