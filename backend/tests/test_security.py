"""Security: rider tokens, privacy of ride data, rate limits, message limits."""

import uuid

from fastapi.testclient import TestClient
from sqlalchemy import text

from app.main import app
from app.security import LIMITS, hash_token, limiter, token_matches
from tests.conftest import H


def test_token_hashing():
    t = "abc"
    assert hash_token(t) != t and len(hash_token(t)) == 64
    assert token_matches(t, hash_token(t))
    assert not token_matches("abd", hash_token(t))
    assert not token_matches(None, hash_token(t))
    assert not token_matches(t, None)


async def test_tokens_are_unique_and_only_hashes_are_stored(client, ride):
    from app.db.session import engine

    member = (await client.post(f"/rides/{ride['ride_id']}/join",
                                json={"display_name": "Ravi"})).json()
    assert member["rider_token"] != ride["rider_token"]
    async with engine.connect() as conn:
        stored = (await conn.execute(text("SELECT token_hash FROM riders"))).scalars().all()
    assert ride["rider_token"] not in stored and member["rider_token"] not in stored
    assert hash_token(ride["rider_token"]) in stored


async def test_rider_ids_alone_no_longer_grant_leader_powers(client, ride):
    """v0.1 hole: leader_rider_id is visible to the group, so knowing it let anyone end
    the ride. Now the secret token is required."""
    member = (await client.post(f"/rides/{ride['ride_id']}/join",
                                json={"display_name": "Mallory"})).json()
    leader_id = ride["leader_rider_id"]
    body = {"rider_id": leader_id}
    # member tries leader's id with own token / no token / garbage
    for headers in (H(member) | {"X-Rider-Id": leader_id}, {}, {"X-Rider-Token": "x" * 43}):
        r = await client.post(f"/rides/{ride['ride_id']}/end", json=body, headers=headers)
        assert r.status_code == 401
        r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                               json=body | {"threshold_m": 100}, headers=headers)
        assert r.status_code == 401
    g = (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()
    assert (g["status"], g["threshold_m"]) == ("active", 500)


async def test_get_ride_requires_a_rider_of_that_ride(client, ride):
    rid = ride["ride_id"]
    assert (await client.get(f"/rides/{rid}")).status_code == 422  # no X-Rider-Id
    assert (await client.get(f"/rides/{rid}",
                             headers={"X-Rider-Id": ride["leader_rider_id"]})).status_code == 401
    other = (await client.post("/rides", json={"leader_name": "X"})).json()
    assert (await client.get(f"/rides/{rid}", headers=H(other))).status_code == 403
    assert (await client.get(f"/rides/{rid}", headers=H(ride))).status_code == 200


async def test_v01_riders_without_token_cannot_authenticate(client, ride):
    from tests.conftest import exec_sql

    await exec_sql("UPDATE riders SET token_hash = NULL")
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).status_code == 401


async def test_create_and_join_are_rate_limited(client, ride):
    limiter.reset()
    codes = [(await client.post("/rides", json={"leader_name": "A"})).status_code
             for _ in range(LIMITS["create"] + 2)]
    assert codes[: LIMITS["create"]] == [201] * LIMITS["create"]
    assert codes[-1] == 429

    limiter.reset()
    codes = [(await client.post(f"/rides/{ride['ride_id']}/join",
                                json={"display_name": "B"})).status_code
             for _ in range(LIMITS["join"] + 1)]
    assert codes[-1] == 429


async def test_rate_limit_is_per_client_ip(client):
    limiter.reset()
    for i in range(LIMITS["create"]):
        await client.post("/rides", json={"leader_name": "A"},
                          headers={"X-Forwarded-For": "1.1.1.1"})
    blocked = await client.post("/rides", json={"leader_name": "A"},
                                headers={"X-Forwarded-For": "1.1.1.1"})
    other = await client.post("/rides", json={"leader_name": "A"},
                              headers={"X-Forwarded-For": "2.2.2.2"})
    assert (blocked.status_code, other.status_code) == (429, 201)


def test_oversized_ws_messages_are_dropped():
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "A"}).json()
        url = f"/ws/rides/{r['ride_id']}?rider_id={r['leader_rider_id']}&token={r['rider_token']}"
        with tc.websocket_connect(url) as ws:
            ws.receive_json()
            ws.send_text('{"type":"location_update","lat":1,"lng":2,"pad":"' + "x" * 5000 + '"}')
            ws.send_json({"type": "location_update", "lat": 3.0, "lng": 4.0})
            msg = ws.receive_json()
            while msg["type"] != "rider_positions":
                msg = ws.receive_json()
            assert msg["riders"][0]["lat"] == 3.0


def test_cors_disabled_by_default():
    with TestClient(app) as tc:
        r = tc.options("/rides", headers={"Origin": "https://evil.example",
                                          "Access-Control-Request-Method": "POST"})
        assert "access-control-allow-origin" not in r.headers


def test_unknown_uuid_header_is_401_not_500():
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "A"}).json()
        g = tc.get(f"/rides/{r['ride_id']}",
                   headers={"X-Rider-Id": str(uuid.uuid4()), "X-Rider-Token": "t"})
        assert g.status_code == 401
