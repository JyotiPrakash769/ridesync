"""FastAPI application entrypoint: router mounts, CORS, lifespan."""

import asyncio
import contextlib
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import join, rides, web
from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.services.positions import positions_message
from app.tasks import expiry_cleanup
from app.ws import ride_socket
from app.ws.connection_manager import manager

settings = get_settings()

if settings.SENTRY_DSN:
    import sentry_sdk

    # No request bodies / IPs / headers: rider tokens and positions must not leave the server.
    sentry_sdk.init(dsn=settings.SENTRY_DSN, send_default_pii=False, traces_sample_rate=0.0)


@asynccontextmanager
async def lifespan(_: FastAPI):
    manager.set_snapshot_fn(positions_message)
    task = None
    if os.environ.get("DISABLE_BACKGROUND_TASKS") != "1":
        task = asyncio.create_task(
            expiry_cleanup.run_forever(AsyncSessionLocal, on_ended=ride_socket.end_ride_rooms)
        )
    yield
    if task is not None:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(title="RideSync API", version="0.1.0", lifespan=lifespan)

if settings.cors_origin_list:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
        allow_headers=["Content-Type", "X-Rider-Id", "X-Rider-Token"],
    )

app.include_router(rides.router)
app.include_router(join.router)
app.include_router(ride_socket.router)
app.include_router(web.router)


@app.get("/health", tags=["meta"])
async def health() -> dict[str, str]:
    return {"status": "ok"}
