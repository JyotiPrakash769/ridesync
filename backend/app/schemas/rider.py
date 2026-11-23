"""Rider-facing schemas (shared by REST and WebSocket payloads)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel

RiderStatus = Literal["online", "weak", "offline"]


class RiderOut(BaseModel):
    """One rider, same shape in GET /rides/{id} and WS rider_positions."""

    rider_id: str
    name: str
    role: Literal["leader", "member"]
    lat: float | None
    lng: float | None
    speed_kph: float | None
    last_seen_at: datetime | None
    status: RiderStatus
