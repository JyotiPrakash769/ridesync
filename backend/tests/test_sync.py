import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from tests.conftest import exec_sql


def _iso(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


async def _join(client, ride_id, name="Ravi"):
    return (await client.post(f"/rides/{ride_id}/join", json={"display_name": name})).json()


async def _locations(rider_id):
    from app.db.session import engine

    async with engine.connect() as conn:
        rows = await conn.execute(
            text("SELECT lat, lng, recorded_at FROM locations WHERE rider_id=:r ORDER BY recorded_at"),
            {"r": uuid.UUID(rider_id)},
        )
        return rows.all()


async def test_sync_inserts_points_and_updates_last_position(client, ride):
    member = await _join(client, ride["ride_id"])
    t0 = datetime.now(UTC) - timedelta(minutes=10)
    pts = [
        {"lat": 20.0 + i * 0.001, "lng": 85.0, "recorded_at": _iso(t0 + timedelta(seconds=4 * i))}
        for i in range(5)
    ]
    # Send out of order: the newest point must still win.
    r = await client.post(f"/rides/{ride['ride_id']}/sync",
                          json={"rider_id": member["rider_id"], "points": pts[::-1]})
    assert r.status_code == 200
    assert r.json() == {"accepted": 5}

    rows = await _locations(member["rider_id"])
    assert [round(x.lat, 3) for x in rows] == [20.0, 20.001, 20.002, 20.003, 20.004]

    me = next(x for x in (await client.get(f"/rides/{ride['ride_id']}")).json()["riders"]
              if x["rider_id"] == member["rider_id"])
    assert (round(me["lat"], 3), me["lng"]) == (20.004, 85.0)
    assert datetime.fromisoformat(me["last_seen_at"]) == t0 + timedelta(seconds=16)
    assert me["status"] == "offline"  # 10 minutes old -> "Last seen 10m ago" in the app


async def test_older_batch_does_not_overwrite_fresher_live_position(client, ride):
    member = await _join(client, ride["ride_id"])
    await exec_sql(
        "UPDATE riders SET last_lat=21, last_lng=86, last_seen_at=now() WHERE id=:id",
        id=uuid.UUID(member["rider_id"]))
    old = _iso(datetime.now(UTC) - timedelta(minutes=5))
    r = await client.post(f"/rides/{ride['ride_id']}/sync", json={
        "rider_id": member["rider_id"], "points": [{"lat": 1, "lng": 2, "recorded_at": old}]})
    assert r.json() == {"accepted": 1}
    me = next(x for x in (await client.get(f"/rides/{ride['ride_id']}")).json()["riders"]
              if x["rider_id"] == member["rider_id"])
    assert (me["lat"], me["lng"], me["status"]) == (21, 86, "online")
    assert len(await _locations(member["rider_id"])) == 1  # still stored in the backlog


async def test_future_timestamps_are_capped_at_server_time(client, ride):
    member = await _join(client, ride["ride_id"])
    future = _iso(datetime.now(UTC) + timedelta(hours=3))
    await client.post(f"/rides/{ride['ride_id']}/sync", json={
        "rider_id": member["rider_id"], "points": [{"lat": 1, "lng": 2, "recorded_at": future}]})
    (row,) = await _locations(member["rider_id"])
    assert row.recorded_at <= datetime.now(UTC) + timedelta(seconds=5)


async def test_sync_errors(client, ride):
    member = await _join(client, ride["ride_id"])
    pt = {"lat": 1, "lng": 2, "recorded_at": _iso(datetime.now(UTC))}
    body = {"rider_id": member["rider_id"], "points": [pt]}
    assert (await client.post("/rides/ZZZZZZ/sync", json=body)).status_code == 404

    other = (await client.post("/rides", json={"leader_name": "X"})).json()
    foreign = {"rider_id": other["leader_rider_id"], "points": [pt]}
    assert (await client.post(f"/rides/{ride['ride_id']}/sync", json=foreign)).status_code == 403

    for bad in ([], [{"lat": 91, "lng": 0, "recorded_at": pt["recorded_at"]}],
                [{"lat": 1, "lng": 2, "recorded_at": "2026-01-01T00:00:00"}]):  # naive time
        r = await client.post(f"/rides/{ride['ride_id']}/sync",
                              json={"rider_id": member["rider_id"], "points": bad})
        assert r.status_code == 422, bad

    await client.post(f"/rides/{ride['ride_id']}/end", json={"rider_id": ride["leader_rider_id"]})
    assert (await client.post(f"/rides/{ride['ride_id']}/sync", json=body)).status_code == 410
