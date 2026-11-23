"""v0.2: regroup point, leader handoff / takeover, ride summary."""

import uuid
from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import H, exec_sql

PT = {"lat": 20.3, "lng": 85.8, "label": "Fuel station"}


async def _join(client, ride, name="Ravi"):
    return (await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": name})).json()


async def _get(client, ride):
    return (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()


# ---------- regroup ----------

async def test_leader_sets_and_clears_regroup(client, ride):
    url = f"/rides/{ride['ride_id']}/regroup"
    r = await client.put(url, headers=H(ride),
                         json={"rider_id": ride["leader_rider_id"], "point": PT})
    assert r.status_code == 200
    assert {k: r.json()["point"][k] for k in ("lat", "lng", "label")} == PT
    assert (await _get(client, ride))["regroup"]["label"] == "Fuel station"

    r = await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"], "point": None})
    assert r.json() == {"point": None}
    assert (await _get(client, ride))["regroup"] is None


async def test_regroup_is_leader_only_and_validated(client, ride):
    member = await _join(client, ride)
    url = f"/rides/{ride['ride_id']}/regroup"
    r = await client.put(url, headers=H(member), json={"rider_id": member["rider_id"], "point": PT})
    assert r.status_code == 403
    r = await client.put(url, json={"rider_id": ride["leader_rider_id"], "point": PT})
    assert r.status_code == 401
    bad = PT | {"label": "x" * 41}
    r = await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"], "point": bad})
    assert r.status_code == 422


# ---------- leader handoff / takeover ----------

async def test_leader_hands_off(client, ride):
    member = await _join(client, ride)
    r = await client.post(f"/rides/{ride['ride_id']}/leader", headers=H(ride),
                          json={"rider_id": ride["leader_rider_id"],
                                "new_leader_id": member["rider_id"]})
    assert r.status_code == 200
    assert r.json() | {} == {"type": "leader_changed", "leader_rider_id": member["rider_id"],
                             "name": "Ravi", "reason": "handoff"}
    g = await _get(client, ride)
    assert g["leader_rider_id"] == member["rider_id"]
    roles = {x["rider_id"]: x["role"] for x in g["riders"]}
    assert roles == {member["rider_id"]: "leader", ride["leader_rider_id"]: "member"}
    # old leader lost leader powers, new one has them
    end = {"rider_id": ride["leader_rider_id"]}
    assert (await client.post(f"/rides/{ride['ride_id']}/end", json=end,
                              headers=H(ride))).status_code == 403
    assert (await client.patch(f"/rides/{ride['ride_id']}/threshold", headers=H(member),
                               json={"rider_id": member["rider_id"], "threshold_m": 300})
            ).status_code == 200


async def test_member_cannot_take_over_while_leader_is_around(client, ride):
    member = await _join(client, ride)
    await exec_sql("UPDATE riders SET last_seen_at = now() - interval '2 minutes' WHERE role='leader'")
    r = await client.post(f"/rides/{ride['ride_id']}/leader", headers=H(member),
                          json={"rider_id": member["rider_id"], "new_leader_id": member["rider_id"]})
    assert r.status_code == 403


async def test_member_takes_over_after_leader_offline_3_minutes(client, ride):
    member = await _join(client, ride)
    await exec_sql("UPDATE riders SET last_seen_at = now() - interval '241 seconds' WHERE role='leader'")
    r = await client.post(f"/rides/{ride['ride_id']}/leader", headers=H(member),
                          json={"rider_id": member["rider_id"], "new_leader_id": member["rider_id"]})
    assert r.status_code == 200 and r.json()["reason"] == "takeover"
    assert (await _get(client, ride))["leader_rider_id"] == member["rider_id"]


async def test_member_cannot_appoint_someone_else(client, ride):
    a = await _join(client, ride, "A")
    b = await _join(client, ride, "B")
    await exec_sql("UPDATE riders SET last_seen_at = now() - interval '10 minutes' WHERE role='leader'")
    r = await client.post(f"/rides/{ride['ride_id']}/leader", headers=H(a),
                          json={"rider_id": a["rider_id"], "new_leader_id": b["rider_id"]})
    assert r.status_code == 403


async def test_handoff_target_must_be_in_ride(client, ride):
    r = await client.post(f"/rides/{ride['ride_id']}/leader", headers=H(ride),
                          json={"rider_id": ride["leader_rider_id"],
                                "new_leader_id": str(uuid.uuid4())})
    assert r.status_code == 404


def test_leader_changed_and_regroup_are_broadcast():
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "Asha"}).json()
        m = tc.post(f"/rides/{r['ride_id']}/join", json={"display_name": "Ravi"}).json()
        url = f"/ws/rides/{r['ride_id']}?rider_id={m['rider_id']}&token={m['rider_token']}"
        with tc.websocket_connect(url) as ws:
            ws.receive_json()
            tc.put(f"/rides/{r['ride_id']}/regroup", headers=H(r),
                   json={"rider_id": r["leader_rider_id"], "point": PT})
            msg = ws.receive_json()
            while msg["type"] != "regroup_point":
                msg = ws.receive_json()
            assert msg["point"]["label"] == "Fuel station"

            tc.post(f"/rides/{r['ride_id']}/leader", headers=H(r),
                    json={"rider_id": r["leader_rider_id"], "new_leader_id": m["rider_id"]})
            msg = ws.receive_json()
            while msg["type"] != "leader_changed":
                msg = ws.receive_json()
            assert (msg["leader_rider_id"], msg["reason"]) == (m["rider_id"], "handoff")


# ---------- summary ----------

DEG_PER_M = 1 / 111_194.93


def test_summary_after_a_ride():
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "Asha"}).json()
        m = tc.post(f"/rides/{r['ride_id']}/join", json={"display_name": "Ravi"}).json()
        rid = r["ride_id"]
        lurl = f"/ws/rides/{rid}?rider_id={r['leader_rider_id']}&token={r['rider_token']}"
        murl = f"/ws/rides/{rid}?rider_id={m['rider_id']}&token={m['rider_token']}"
        with tc.websocket_connect(lurl) as a, tc.websocket_connect(murl) as b:
            a.receive_json()
            # leader at 0; member rides 0 -> 600 m behind (alert) in 3 steps
            a.send_json({"type": "location_update", "lat": 20.0, "lng": 85.0})
            for step_m in (0, 300, 600):
                b.send_json({"type": "location_update", "lat": 20.0 - step_m * DEG_PER_M,
                             "lng": 85.0})
            for _ in range(12):  # drain until the alert went out
                if a.receive_json()["type"] == "distance_alert":
                    break
        # Timestamps of live snapshots are "now" for each tick; spread them so
        # the plausibility filter sees real riding speeds.
        import asyncio
        asyncio.run(exec_sql(
            "UPDATE locations SET recorded_at = now() - (interval '1 minute' * (10 - id))"))
        assert tc.post(f"/rides/{rid}/end", json={"rider_id": r["leader_rider_id"]},
                       headers=H(r)).status_code == 200

        s = tc.get(f"/rides/{rid}/summary", headers=H(m))
        assert s.status_code == 200
        s = s.json()
        assert s["status"] == "ended" and s["ended_at"] is not None
        assert s["falling_behind_total"] == 1
        me = next(x for x in s["riders"] if x["rider_id"] == m["rider_id"])
        assert me["falling_behind_count"] == 1 and me["max_gap_m"] == 600
        assert abs(me["distance_km"] - 0.6) < 0.02


async def test_summary_requires_rider_token(client, ride):
    assert (await client.get(f"/rides/{ride['ride_id']}/summary",
                             headers={"X-Rider-Id": ride["leader_rider_id"]})).status_code == 401
    other = (await client.post("/rides", json={"leader_name": "X"})).json()
    assert (await client.get(f"/rides/{ride['ride_id']}/summary",
                             headers=H(other))).status_code == 403


def test_track_km_skips_gps_jumps():
    from app.services.convoy_service import track_km

    t = datetime(2026, 1, 1, tzinfo=UTC)
    pts = [(20.0, 85.0, t), (20.0 + 1000 * DEG_PER_M, 85.0, t + timedelta(minutes=1)),
           (25.0, 85.0, t + timedelta(minutes=2)),  # 500 km in a minute: noise
           (20.0 + 2000 * DEG_PER_M, 85.0, t + timedelta(minutes=3))]
    assert abs(track_km(pts[:2]) - 1.0) < 1e-3
    # the jump to 25.0 and the jump back are both implausible -> only the first km counts
    assert abs(track_km(pts) - 1.0) < 1e-3
