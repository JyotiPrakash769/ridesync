"""Test harness: runs against the real Postgres test DB (docker compose `db`).

TEST_DATABASE_URL defaults to the ridesync_test database created by
docker/initdb. The schema is applied with Alembic once per session, and every
table is truncated between tests.
"""

import os
import subprocess
import sys
from pathlib import Path

TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/ridesync_test",
)
# Must be set before app modules import settings.
os.environ["DATABASE_URL"] = TEST_DB_URL
os.environ["DB_NULL_POOL"] = "1"  # no pooled connections shared across event loops
os.environ["DISABLE_BACKGROUND_TASKS"] = "1"
os.environ["WS_MIN_UPDATE_INTERVAL_S"] = "0"  # tests send updates back-to-back
os.environ["CORS_ORIGINS"] = ""  # test the production default, not a local .env

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

BACKEND_DIR = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session", autouse=True)
def _migrate_test_db() -> None:
    env = {**os.environ, "ALEMBIC_DATABASE_URL": TEST_DB_URL}
    subprocess.run(
        [sys.executable, "-m", "alembic", "downgrade", "base"], cwd=BACKEND_DIR, env=env, check=True
    )
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"], cwd=BACKEND_DIR, env=env, check=True
    )


@pytest.fixture(autouse=True)
async def _clean_tables() -> None:
    from app.db.session import engine
    from app.security import limiter

    limiter.reset()

    async with engine.begin() as conn:
        await conn.execute(text("TRUNCATE locations, riders, rides RESTART IDENTITY CASCADE"))


@pytest.fixture
async def client():
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def exec_sql(sql: str, **params) -> None:
    from app.db.session import engine

    async with engine.begin() as conn:
        await conn.execute(text(sql), params)


@pytest.fixture
async def ride(client):
    """A fresh ride with its leader: dict(ride_id, leader_rider_id, qr_payload)."""
    r = await client.post("/rides", json={"leader_name": "Asha"})
    assert r.status_code == 201, r.text
    return r.json()


def H(x: dict) -> dict:
    """Auth headers for a create (leader) or join response dict."""
    rid = x.get("leader_rider_id") or x["rider_id"]
    return {"X-Rider-Id": str(rid), "X-Rider-Token": x["rider_token"]}
