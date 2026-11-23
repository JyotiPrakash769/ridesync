"""SQLAlchemy model: ride_events (append-only log used by the ride summary)."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CHAR, BigInteger, DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

EVENT_FALLING_BEHIND = "falling_behind"
EVENT_LEADER_CHANGED = "leader_changed"
EVENT_REGROUP_SET = "regroup_set"
EVENT_REGROUP_CLEARED = "regroup_cleared"


class RideEvent(Base):
    __tablename__ = "ride_events"
    __table_args__ = (Index("idx_ride_events_ride", "ride_id", "created_at"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    ride_id: Mapped[str] = mapped_column(
        CHAR(6), ForeignKey("rides.id", ondelete="CASCADE"), nullable=False
    )
    rider_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("riders.id", ondelete="SET NULL")
    )
    type: Mapped[str] = mapped_column(String(24), nullable=False)
    distance_m: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
