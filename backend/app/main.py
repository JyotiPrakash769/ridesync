"""FastAPI application entrypoint: router mounts, CORS, lifespan."""

import asyncio
import contextlib
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import join, rides
from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.services.positions import positions_message
from app.tasks import expiry_cleanup
from app.ws import ride_socket
from app.ws.connection_manager import manager

settings = get_settings()


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

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(rides.router)
app.include_router(join.router)
app.include_router(ride_socket.router)


@app.get("/health", tags=["meta"])
async def health() -> dict[str, str]:
    return {"status": "ok"}
