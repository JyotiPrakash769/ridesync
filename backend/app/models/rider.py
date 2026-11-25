"""SQLAlchemy model: riders (one row per person per ride; no accounts)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CHAR, Boolean, DateTime, Float, ForeignKey, Index, SmallInteger, String, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.location import Location
    from app.models.ride import Ride

ROLE_LEADER = "leader"
ROLE_MEMBER = "member"


class Rider(Base):
    __tablename__ = "riders"
    __table_args__ = (Index("idx_riders_ride", "ride_id"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()"),
    )
    ride_id: Mapped[str] = mapped_column(
        CHAR(6), ForeignKey("rides.id", ondelete="CASCADE"), nullable=False
    )
    display_name: Mapped[str] = mapped_column(String(50), nullable=False)
    role: Mapped[str] = mapped_column(
        String(10), nullable=False, default=ROLE_MEMBER, server_default=text("'member'")
    )
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_lat: Mapped[float | None] = mapped_column(Float)
    last_lng: Mapped[float | None] = mapped_column(Float)
    last_speed_kph: Mapped[float | None] = mapped_column(Float)
    # Phone battery %, reported with location updates (leader assist).
    battery: Mapped[int | None] = mapped_column(SmallInteger)
    # SHA-256 of the rider's secret token (app/security.py). Never the token.
    token_hash: Mapped[str | None] = mapped_column(String(64))
    # Kept because it is in the schema contract; display status is always
    # derived from last_seen_at (services.ride_service.derive_status).
    is_online: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )

    ride: Mapped[Ride] = relationship("Ride", back_populates="riders", foreign_keys=[ride_id])
    locations: Mapped[list[Location]] = relationship(
        "Location", back_populates="rider", cascade="all, delete-orphan", passive_deletes=True
    )
