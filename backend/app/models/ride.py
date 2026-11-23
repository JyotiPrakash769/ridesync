"""SQLAlchemy model: rides (see foundation doc §3)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CHAR, DateTime, ForeignKey, Integer, String, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.rider import Rider

RIDE_ACTIVE = "active"
RIDE_ENDED = "ended"


class Ride(Base):
    __tablename__ = "rides"

    id: Mapped[str] = mapped_column(CHAR(6), primary_key=True)
    leader_rider_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("riders.id", use_alter=True, name="fk_leader"),
        nullable=True,
    )
    status: Mapped[str] = mapped_column(
        String(10), nullable=False, default=RIDE_ACTIVE, server_default=text("'active'")
    )
    threshold_m: Mapped[int] = mapped_column(
        Integer, nullable=False, default=500, server_default=text("500")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # When the leader ended it or it expired; drives data retention.
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    riders: Mapped[list[Rider]] = relationship(
        "Rider",
        back_populates="ride",
        foreign_keys="Rider.ride_id",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
