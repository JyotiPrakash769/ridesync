"""WebSocket message schemas (foundation doc §5).

Client -> server: location_update, heartbeat, leave.
Server -> client: rider_positions, distance_alert, rider_joined, rider_left,
ride_ended, threshold_updated.

`leave` and `threshold_updated` are v0.1 additions agreed during planning:
`leave` is the only trigger for `rider_left` (a dropped socket never removes a
rider), `threshold_updated` carries PATCH /threshold changes to the room.
"""

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, TypeAdapter


class LocationUpdate(BaseModel):
    type: Literal["location_update"]
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    speed_kph: float | None = Field(default=None, ge=0, le=500)
    # Client clock; accepted but not trusted. last_seen_at uses server time.
    ts: datetime | None = None


class Heartbeat(BaseModel):
    type: Literal["heartbeat"]


class Leave(BaseModel):
    type: Literal["leave"]


ClientMessage = Annotated[LocationUpdate | Heartbeat | Leave, Field(discriminator="type")]
client_message_adapter: TypeAdapter[ClientMessage] = TypeAdapter(ClientMessage)

# Close codes sent when a socket is refused or the ride is over (additive to §5).
CLOSE_RIDE_NOT_FOUND = 4404
CLOSE_RIDE_ENDED = 4410
CLOSE_NOT_A_RIDER = 4403
CLOSE_UNAUTHORIZED = 4401  # missing / wrong rider token
CLOSE_RATE_LIMITED = 4429  # too many connects from this IP; client may retry later
CLOSE_LEFT = 1000
