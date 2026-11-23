"""WebSocket protocol tests with two (or three) simulated clients.

Uses Starlette's TestClient (runs the app in its own loop thread) against the
real test database. Every receive is bounded by reading only messages we know
the server has sent, so a regression shows up as an assertion, not a hang.
"""

import uuid

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import app
from tests.conftest import exec_sql


@pytest.fixture
def tc():
    with TestClient(app) as c:
        yield c


def _ride(tc):
    r = tc.post("/rides", json={"leader_name": "Asha"}).json()
    b = tc.post(f"/rides/{r['ride_id']}/join", json={"display_name": "Ravi"}).json()
    return r["ride_id"], r["leader_rider_id"], b["rider_id"]


def _recv_type(ws, type_, limit=10):
    """Read until a message of `type_` arrives (skipping periodic snapshots)."""
    for _ in range(limit):
        msg = ws.receive_json()
        if msg["type"] == type_:
            return msg
    raise AssertionError(f"no {type_} within {limit} messages")


def _by_id(positions, rider_id):
    return next(r for r in positions["riders"] if r["rider_id"] == rider_id)


def test_position_from_a_reaches_b(tc):
    ride_id, a_id, b_id = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")  # own connect snapshot
        with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={b_id}") as b:
            _recv_type(b, "rider_positions")  # B's connect snapshot
            _recv_type(a, "rider_positions")  # A sees B's connect snapshot too

            a.send_json({"type": "location_update", "lat": 20.296, "lng": 85.824,
                         "speed_kph": 42.5, "ts": "2026-07-28T10:15:03Z"})
            msg = _recv_type(b, "rider_positions")
            me = _by_id(msg, a_id)
            assert (me["lat"], me["lng"], me["speed_kph"]) == (20.296, 85.824, 42.5)
            assert me["status"] == "online"
            assert me["name"] == "Asha" and me["role"] == "leader"
            assert set(me) == {"rider_id", "name", "role", "lat", "lng", "speed_kph",
                               "last_seen_at", "status"}


def test_disconnect_does_not_remove_or_offline_rider(tc):
    ride_id, a_id, b_id = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={b_id}") as b:
            _recv_type(b, "rider_positions")
            b.send_json({"type": "location_update", "lat": 1.0, "lng": 2.0})
            _recv_type(b, "rider_positions")
        # B's socket is gone. A's next snapshot still has B, still online.
        a.send_json({"type": "heartbeat"})
        a.send_json({"type": "location_update", "lat": 1.001, "lng": 2.0})
        msg = _recv_type(a, "rider_positions", limit=10)
        while _by_id(msg, a_id)["lat"] != 1.001:
            msg = _recv_type(a, "rider_positions")
        b_row = _by_id(msg, b_id)
        assert b_row["status"] == "online"
        assert (b_row["lat"], b_row["lng"]) == (1.0, 2.0)
    riders = tc.get(f"/rides/{ride_id}").json()["riders"]
    assert {r["rider_id"] for r in riders} == {a_id, b_id}


@pytest.mark.parametrize(("age_s", "expected"), [(5, "online"), (30, "weak"), (90, "offline")])
def test_status_derived_from_last_seen(tc, age_s, expected):
    import asyncio

    ride_id, a_id, b_id = _ride(tc)
    asyncio.run(exec_sql(
        "UPDATE riders SET last_seen_at = now() - make_interval(secs => :s) WHERE id = :id",
        s=age_s, id=uuid.UUID(b_id)))
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        msg = _recv_type(a, "rider_positions")
        assert _by_id(msg, b_id)["status"] == expected
        assert _by_id(msg, a_id)["status"] == "online"  # connecting counts as seen


def test_heartbeat_keeps_rider_online(tc):
    import asyncio

    ride_id, a_id, _ = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        asyncio.run(exec_sql(
            "UPDATE riders SET last_seen_at = now() - interval '40 seconds' WHERE id=:id",
            id=uuid.UUID(a_id)))
        a.send_json({"type": "heartbeat"})
        a.send_json({"type": "location_update", "lat": 0.0, "lng": 0.0})
        assert _by_id(_recv_type(a, "rider_positions"), a_id)["status"] == "online"


def test_rider_joined_broadcast(tc):
    ride_id, a_id, _ = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        c = tc.post(f"/rides/{ride_id}/join", json={"display_name": "Chen"}).json()
        msg = _recv_type(a, "rider_joined")
        assert msg == {"type": "rider_joined", "rider_id": c["rider_id"], "name": "Chen",
                       "role": "member"}


def test_leave_broadcasts_rider_left_and_removes_rider(tc):
    ride_id, a_id, b_id = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={b_id}") as b:
            _recv_type(b, "rider_positions")
            b.send_json({"type": "leave"})
            with pytest.raises(WebSocketDisconnect):
                for _ in range(10):
                    b.receive_json()
        assert _recv_type(a, "rider_left") == {"type": "rider_left", "rider_id": b_id}
    riders = tc.get(f"/rides/{ride_id}").json()["riders"]
    assert [r["rider_id"] for r in riders] == [a_id]


def test_leader_leave_is_ignored(tc):
    ride_id, a_id, b_id = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        a.send_json({"type": "leave"})
        a.send_json({"type": "location_update", "lat": 3.0, "lng": 4.0})
        assert _by_id(_recv_type(a, "rider_positions"), a_id)["lat"] == 3.0
    assert len(tc.get(f"/rides/{ride_id}").json()["riders"]) == 2


def test_ride_ended_broadcast_and_close(tc):
    ride_id, a_id, b_id = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={b_id}") as b:
        _recv_type(b, "rider_positions")
        assert tc.post(f"/rides/{ride_id}/end", json={"rider_id": a_id}).status_code == 200
        assert _recv_type(b, "ride_ended") == {"type": "ride_ended"}
        with pytest.raises(WebSocketDisconnect) as exc:
            b.receive_json()
        assert exc.value.code == 4410


def test_invalid_messages_are_ignored(tc):
    ride_id, a_id, _ = _ride(tc)
    with tc.websocket_connect(f"/ws/rides/{ride_id}?rider_id={a_id}") as a:
        _recv_type(a, "rider_positions")
        a.send_text("not json")
        a.send_json({"type": "teleport"})
        a.send_json({"type": "location_update", "lat": 999, "lng": 0})
        a.send_json({"type": "location_update", "lat": 5.0, "lng": 6.0})
        assert _by_id(_recv_type(a, "rider_positions"), a_id)["lat"] == 5.0


@pytest.mark.parametrize("case", ["missing_ride", "ended_ride", "foreign_rider", "bad_uuid"])
def test_socket_refusals(tc, case):
    ride_id, a_id, _ = _ride(tc)
    other = tc.post("/rides", json={"leader_name": "X"}).json()
    url, code = {
        "missing_ride": (f"/ws/rides/ZZZZZZ?rider_id={a_id}", 4404),
        "ended_ride": (f"/ws/rides/{ride_id}?rider_id={a_id}", 4410),
        "foreign_rider": (f"/ws/rides/{ride_id}?rider_id={other['leader_rider_id']}", 4403),
        "bad_uuid": (f"/ws/rides/{ride_id}?rider_id=nope", 4403),
    }[case]
    if case == "ended_ride":
        tc.post(f"/rides/{ride_id}/end", json={"rider_id": a_id})
    with tc.websocket_connect(url) as ws, pytest.raises(WebSocketDisconnect) as exc:
        ws.receive_json()
    assert exc.value.code == code
