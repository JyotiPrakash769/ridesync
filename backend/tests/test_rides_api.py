import re
import uuid

from app.services.ride_service import RIDE_ID_ALPHABET, derive_status, generate_ride_id
from tests.conftest import H, exec_sql

ID_RE = re.compile(rf"^[{RIDE_ID_ALPHABET}]{{6}}$")


# ---------- POST /rides ----------

async def test_create_ride(client):
    r = await client.post("/rides", json={"leader_name": "  Asha  "})
    assert r.status_code == 201
    body = r.json()
    assert ID_RE.match(body["ride_id"])
    assert body["qr_payload"] == f"https://ridesync.app/join/{body['ride_id']}"
    uuid.UUID(body["leader_rider_id"])

    assert len(body["rider_token"]) >= 40
    g = (await client.get(f"/rides/{body['ride_id']}", headers=H(body))).json()
    assert g["leader_rider_id"] == body["leader_rider_id"]
    assert [(x["name"], x["role"]) for x in g["riders"]] == [("Asha", "leader")]


async def test_create_ride_rejects_blank_or_long_name(client):
    assert (await client.post("/rides", json={"leader_name": "   "})).status_code == 422
    assert (await client.post("/rides", json={"leader_name": "x" * 51})).status_code == 422


def test_ride_id_alphabet_has_no_ambiguous_chars():
    assert not set("0O1IL") & set(RIDE_ID_ALPHABET)
    for _ in range(500):
        assert ID_RE.match(generate_ride_id())


# ---------- GET /rides/{id} ----------

async def test_get_ride(client, ride):
    r = await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "active"
    assert body["threshold_m"] == 500
    rider = body["riders"][0]
    assert set(rider) == {
        "rider_id", "name", "role", "lat", "lng", "speed_kph", "last_seen_at", "status",
        "battery",  # v0.4 additive
    }
    assert rider["status"] == "offline"  # never seen yet


async def test_get_ride_is_case_insensitive(client, ride):
    r = await client.get(f"/rides/{ride['ride_id'].lower()}", headers=H(ride))
    assert r.status_code == 200


async def test_get_missing_ride_404(client):
    assert (await client.get("/rides/ZZZZZZ", headers={"X-Rider-Id": str(uuid.uuid4())})).status_code == 404


async def test_get_expired_ride_reads_as_ended(client, ride):
    await exec_sql("UPDATE rides SET expires_at = now() - interval '1 minute' WHERE id=:id",
                   id=ride["ride_id"])
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["status"] == "ended"


# ---------- POST /rides/{id}/join ----------

async def test_join_ride(client, ride):
    r = await client.post(f"/rides/{ride['ride_id'].lower()}/join", json={"display_name": "Ravi"})
    assert r.status_code == 201
    body = r.json()
    assert body["ride_id"] == ride["ride_id"]
    riders = (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["riders"]
    assert [(x["name"], x["role"]) for x in riders] == [("Asha", "leader"), ("Ravi", "member")]


async def test_join_missing_ride_404(client):
    r = await client.post("/rides/ZZZZZZ/join", json={"display_name": "Ravi"})
    assert r.status_code == 404


async def test_join_ended_ride_410(client, ride):
    await client.post(f"/rides/{ride['ride_id']}/end", json={"rider_id": ride["leader_rider_id"]}, headers=H(ride))
    r = await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": "Ravi"})
    assert r.status_code == 410


async def test_join_expired_ride_410_before_cleanup_runs(client, ride):
    await exec_sql("UPDATE rides SET expires_at = now() - interval '1 second' WHERE id=:id",
                   id=ride["ride_id"])
    r = await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": "Ravi"})
    assert r.status_code == 410


async def test_join_rejects_blank_name(client, ride):
    r = await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": ""})
    assert r.status_code == 422


# ---------- PATCH /rides/{id}/threshold ----------

async def _join(client, ride_id, name="Ravi"):
    return (await client.post(f"/rides/{ride_id}/join", json={"display_name": name})).json()


async def test_threshold_leader_can_set(client, ride):
    r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                           json={"rider_id": ride["leader_rider_id"], "threshold_m": 300},
                           headers=H(ride))
    assert r.status_code == 200
    assert r.json() == {"threshold_m": 300}
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["threshold_m"] == 300


async def test_threshold_member_forbidden(client, ride):
    member = await _join(client, ride["ride_id"])
    r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                           json={"rider_id": member["rider_id"], "threshold_m": 300},
                           headers=H(member))
    assert r.status_code == 403


async def test_threshold_unknown_or_foreign_rider(client, ride):
    other = (await client.post("/rides", json={"leader_name": "Other"})).json()
    # unknown rider -> 401 (can't authenticate)
    r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                           json={"rider_id": str(uuid.uuid4()), "threshold_m": 300},
                           headers={"X-Rider-Token": "nope"})
    assert r.status_code == 401
    # valid leader of ANOTHER ride -> 403
    r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                           json={"rider_id": other["leader_rider_id"], "threshold_m": 300},
                           headers=H(other))
    assert r.status_code == 403


async def test_threshold_rejects_unsupported_value(client, ride):
    r = await client.patch(f"/rides/{ride['ride_id']}/threshold",
                           json={"rider_id": ride["leader_rider_id"], "threshold_m": 250},
                           headers=H(ride))
    assert r.status_code == 422


async def test_threshold_404_and_410(client, ride):
    body = {"rider_id": ride["leader_rider_id"], "threshold_m": 300}
    assert (await client.patch("/rides/ZZZZZZ/threshold", json=body, headers=H(ride))).status_code == 404
    await client.post(f"/rides/{ride['ride_id']}/end", json={"rider_id": ride["leader_rider_id"]}, headers=H(ride))
    assert (await client.patch(f"/rides/{ride['ride_id']}/threshold", json=body,
                               headers=H(ride))).status_code == 410


# ---------- POST /rides/{id}/end ----------

async def test_end_ride_by_leader(client, ride):
    r = await client.post(f"/rides/{ride['ride_id']}/end", json={"rider_id": ride["leader_rider_id"]}, headers=H(ride))
    assert r.status_code == 200
    assert r.json() == {"status": "ended"}
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["status"] == "ended"


async def test_end_ride_member_forbidden(client, ride):
    member = await _join(client, ride["ride_id"])
    r = await client.post(f"/rides/{ride['ride_id']}/end", json={"rider_id": member["rider_id"]},
                          headers=H(member))
    assert r.status_code == 403
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["status"] == "active"


async def test_end_ride_404_and_twice_410(client, ride):
    body = {"rider_id": ride["leader_rider_id"]}
    h = H(ride)
    assert (await client.post("/rides/ZZZZZZ/end", json=body, headers=h)).status_code == 404
    assert (await client.post(f"/rides/{ride['ride_id']}/end", json=body, headers=h)).status_code == 200
    assert (await client.post(f"/rides/{ride['ride_id']}/end", json=body, headers=h)).status_code == 410


# ---------- expiry cleanup ----------

async def test_expiry_cleanup_marks_only_expired(client):
    from app.db.session import AsyncSessionLocal
    from app.tasks.expiry_cleanup import mark_expired_rides

    ra = (await client.post("/rides", json={"leader_name": "A"})).json()
    rb = (await client.post("/rides", json={"leader_name": "B"})).json()
    a, b = ra["ride_id"], rb["ride_id"]
    await exec_sql("UPDATE rides SET expires_at = now() - interval '1 hour' WHERE id=:id", id=a)
    async with AsyncSessionLocal() as db:
        assert await mark_expired_rides(db) == [a]
        assert await mark_expired_rides(db) == []
    assert (await client.get(f"/rides/{a}", headers=H(ra))).json()["status"] == "ended"
    assert (await client.get(f"/rides/{b}", headers=H(rb))).json()["status"] == "active"


# ---------- status derivation ----------

def test_derive_status_boundaries():
    from datetime import UTC, datetime, timedelta

    now = datetime(2026, 1, 1, tzinfo=UTC)
    ago = lambda s: now - timedelta(seconds=s)  # noqa: E731
    assert derive_status(None, now) == "offline"
    assert derive_status(ago(0), now) == "online"
    assert derive_status(ago(14.9), now) == "online"
    assert derive_status(ago(15), now) == "weak"
    assert derive_status(ago(60), now) == "weak"
    assert derive_status(ago(60.1), now) == "offline"
