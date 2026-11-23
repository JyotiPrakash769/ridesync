"""Periodic job: mark rides past expires_at as ended.

Called every CLEANUP_INTERVAL_S from the FastAPI lifespan loop in app.main
(fine for a single instance). With several instances or a platform cron
(e.g. a Railway cron service), call mark_expired_rides() from that scheduler
instead and drop the in-process loop.

REST/WS handlers never depend on this having run: they compare expires_at
directly, so an expired ride already answers 410.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from datetime import timedelta

from sqlalchemy import delete, func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.ride import RIDE_ACTIVE, RIDE_ENDED, Ride
from app.services.ride_service import utcnow

log = logging.getLogger(__name__)

CLEANUP_INTERVAL_S = 300


async def mark_expired_rides(db: AsyncSession, now: datetime | None = None) -> list[str]:
    """Set status='ended' on active rides past expires_at. Returns their ids."""
    result = await db.execute(
        update(Ride)
        .where(Ride.status == RIDE_ACTIVE, Ride.expires_at <= (now or utcnow()))
        .values(status=RIDE_ENDED, ended_at=Ride.expires_at)
        .returning(Ride.id)
    )
    ended = [row[0] for row in result]
    await db.commit()
    return ended


async def purge_old_rides(
    db: AsyncSession, retention_days: int, now: datetime | None = None
) -> int:
    """Data retention: delete rides that ended more than `retention_days` ago.
    Riders, locations and events go with them (ON DELETE CASCADE)."""
    cutoff = (now or utcnow()) - timedelta(days=retention_days)
    result = await db.execute(
        delete(Ride).where(
            Ride.status == RIDE_ENDED,
            func.coalesce(Ride.ended_at, Ride.expires_at) < cutoff,
        )
    )
    await db.commit()
    return result.rowcount or 0


async def run_forever(session_factory, on_ended=None) -> None:
    """Loop used by the app lifespan. on_ended(ride_ids) lets the WS layer notify rooms."""
    while True:
        try:
            async with session_factory() as db:
                ended = await mark_expired_rides(db)
                purged = await purge_old_rides(db, get_settings().RETENTION_DAYS)
            if purged:
                log.info("retention: deleted %d old rides", purged)
            if ended:
                log.info("expired rides ended: %s", ended)
                if on_ended is not None:
                    await on_ended(ended)
        except Exception:  # keep the loop alive; next tick retries
            log.exception("expiry cleanup failed")
        await asyncio.sleep(CLEANUP_INTERVAL_S)
