from sqlalchemy import text


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


async def test_schema_applied():
    from app.db.session import engine

    async with engine.connect() as conn:
        rows = await conn.execute(
            text("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")
        )
        tables = {r[0] for r in rows}
    assert {"rides", "riders", "locations"} <= tables
