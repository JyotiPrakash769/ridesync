"""Async SQLAlchemy engine and session factory."""

import os
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import get_settings

settings = get_settings()

_engine_kwargs: dict = {"echo": False, "pool_pre_ping": True}
if os.environ.get("DB_NULL_POOL") == "1":
    # Tests drive the app from several event loops (httpx + Starlette TestClient);
    # pooled asyncpg connections are bound to the loop that created them.
    _engine_kwargs = {"echo": False, "poolclass": NullPool}

engine = create_async_engine(settings.DATABASE_URL, **_engine_kwargs)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
