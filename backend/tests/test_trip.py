"""Trip planner: polyline codec, route distance, Google proxy (mocked),
keyless fallbacks, plan API, off-route detection."""

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.services import google_maps
from app.services.route_geometry import (
    decode_polyline,
    distance_to_route_m,
    encode_polyline,
    length_m,
)
from app.services.trip_service import OffRouteTracker
from tests.conftest import H, exec_sql

GOOGLE_EXAMPLE = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
GOOGLE_EXAMPLE_ENC = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
M = 1 / 111_194.93


# ---------- geometry ----------

def test_polyline_matches_googles_reference_example():
    assert encode_polyline(GOOGLE_EXAMPLE) == GOOGLE_EXAMPLE_ENC
    assert decode_polyline(GOOGLE_EXAMPLE_ENC) == GOOGLE_EXAMPLE


def test_polyline_round_trip_negative_and_dense():
    pts = [(20.29612, 85.82451), (20.29598, 85.82466), (-33.86882, 151.20929)]
    assert decode_polyline(encode_polyline(pts)) == pts


def test_distance_to_route():
    route = [(20.0, 85.0), (20.0 + 1000 * M, 85.0)]  # 1 km north
    assert distance_to_route_m((20.0 + 500 * M, 85.0), route) < 1
    east = 300 * M / 0.9397  # 300 m east at lat 20
    assert distance_to_route_m((20.0 + 500 * M, 85.0 + east), route) == pytest.approx(300, rel=0.01)
    # beyond the end: distance to the endpoint
    assert distance_to_route_m((20.0 + 1400 * M, 85.0), route) == pytest.approx(400, rel=0.01)
    assert length_m(route) == pytest.approx(1000, rel=1e-6)


# ---------- fake Google ----------

class FakeResp:
    def __init__(self, status, body):
        self.status_code, self._body = status, body

    def json(self):
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            import httpx
            raise httpx.HTTPStatusError("x", request=None, response=None)

    @property
    def text(self):
        return str(self._body)


class FakeClient:
    def __init__(self):
        self.calls = []

    async def post(self, url, json=None, headers=None):
        self.calls.append((url, json, headers))
        if "computeRoutes" in url:
            if json["travelMode"] == "TWO_WHEELER" and getattr(self, "no_two_wheeler", False):
                return FakeResp(400, {"error": "unsupported"})
            pts = [(w["location"]["latLng"]["latitude"], w["location"]["latLng"]["longitude"])
                   for w in [json["origin"], *json["intermediates"], json["destination"]]]
            return FakeResp(200, {"routes": [{
                "distanceMeters": 61000, "duration": "4200s",
                "polyline": {"encodedPolyline": encode_polyline(pts)},
                "legs": [{"distanceMeters": 61000, "duration": "4200s"}],
            }]})
        return FakeResp(200, {"places": [{
            "displayName": {"text": "Puri Beach"}, "formattedAddress": "Puri, Odisha",
            "location": {"latitude": 19.7984, "longitude": 85.8247}}]})

    async def get(self, url, params=None, headers=None):
        self.calls.append((url, params, headers))
        return FakeResp(200, [{"name": "Puri", "display_name": "Puri, Odisha, India",
                               "lat": "19.81", "lon": "85.83"}])


@pytest.fixture
def fake_google(monkeypatch):
    fc = FakeClient()
    monkeypatch.setattr(google_maps, "_client", fc)
    monkeypatch.setattr(get_settings(), "GOOGLE_MAPS_SERVER_KEY", "test-key")
    return fc


@pytest.fixture
def no_key(monkeypatch):
    fc = FakeClient()
    monkeypatch.setattr(google_maps, "_client", fc)
    monkeypatch.setattr(get_settings(), "GOOGLE_MAPS_SERVER_KEY", "")
    return fc


DEST = {"lat": 19.7984, "lng": 85.8247, "label": "Puri"}
ORIGIN = {"lat": 20.2961, "lng": 85.8245, "label": "Bhubaneswar"}
STOP = {"lat": 20.05, "lng": 85.85, "label": "Fuel"}


# ---------- plan API ----------

async def test_leader_plans_trip_with_google(client, ride, fake_google):
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json={
        "rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST, "stops": [STOP]})
    assert r.status_code == 200, r.text
    plan = r.json()["plan"]
    assert (plan["distance_m"], plan["duration_s"], plan["provider"], plan["approximate"]) == \
        (61000, 4200, "google:two_wheeler", False)
    assert decode_polyline(plan["polyline"])[1] == (20.05, 85.85)
    url, body, headers = fake_google.calls[-1]
    assert headers["X-Goog-Api-Key"] == "test-key" and body["travelMode"] == "TWO_WHEELER"
    g = (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()
    assert g["plan"]["destination"]["label"] == "Puri"


async def test_falls_back_to_drive_when_two_wheeler_unsupported(client, ride, fake_google):
    fake_google.no_two_wheeler = True
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json={
        "rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST})
    assert r.json()["plan"]["provider"] == "google:drive"


async def test_without_key_plan_is_approximate(client, ride, no_key):
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json={
        "rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST})
    plan = r.json()["plan"]
    assert plan["approximate"] is True and plan["provider"] == "straight_line"
    assert 54_000 < plan["distance_m"] < 57_000  # ~55 km straight line
    assert no_key.calls == []  # Google never called without a key


async def test_origin_defaults_to_leader_position(client, ride, no_key):
    body = {"rider_id": ride["leader_rider_id"], "destination": DEST}
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json=body)
    assert r.status_code == 422  # leader has no position yet
    await exec_sql("UPDATE riders SET last_lat=20.3, last_lng=85.8 WHERE role='leader'")
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json=body)
    assert r.json()["plan"]["origin"] == {"lat": 20.3, "lng": 85.8, "label": "Start"}


async def test_plan_is_leader_only_clearable_and_limited(client, ride, no_key):
    m = (await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": "R"})).json()
    url = f"/rides/{ride['ride_id']}/plan"
    assert (await client.put(url, headers=H(m), json={
        "rider_id": m["rider_id"], "origin": ORIGIN, "destination": DEST})).status_code == 403
    assert (await client.put(url, json={
        "rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST})).status_code == 401
    too_many = {"rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST,
                "stops": [STOP] * 6}
    assert (await client.put(url, headers=H(ride), json=too_many)).status_code == 422
    await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"],
                                                  "origin": ORIGIN, "destination": DEST})
    r = await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"],
                                                      "destination": None})
    assert r.json() == {"plan": None}


# ---------- places ----------

async def test_place_search_google(client, ride, fake_google):
    r = await client.get(f"/rides/{ride['ride_id']}/places",
                         params={"q": "puri", "lat": 20.3, "lng": 85.8}, headers=H(ride))
    assert r.json() == {"provider": "google", "results": [
        {"name": "Puri Beach", "address": "Puri, Odisha", "lat": 19.7984, "lng": 85.8247}]}
    body = fake_google.calls[-1][1]
    assert body["locationBias"]["circle"]["center"] == {"latitude": 20.3, "longitude": 85.8}


async def test_place_search_osm_fallback_and_auth(client, ride, no_key):
    r = await client.get(f"/rides/{ride['ride_id']}/places", params={"q": "puri"}, headers=H(ride))
    assert r.json()["provider"] == "osm" and r.json()["results"][0]["lat"] == 19.81
    assert "RideSync" in no_key.calls[-1][2]["User-Agent"]
    assert (await client.get(f"/rides/{ride['ride_id']}/places", params={"q": "puri"},
                             headers={"X-Rider-Id": ride["leader_rider_id"]})).status_code == 401
    assert (await client.get(f"/rides/{ride['ride_id']}/places", params={"q": "p"},
                             headers=H(ride))).status_code == 422


# ---------- off-route ----------

ROUTE_PLAN = {"approximate": False, "polyline": encode_polyline([(20.0, 85.0), (20.0 + 2000 * M, 85.0)])}
E = 1 / (111_194.93 * 0.9397)


def test_off_route_transitions_with_hysteresis():
    t = OffRouteTracker()
    on = lambda east_m: t.evaluate("R", ROUTE_PLAN, "a", "Ravi", 20.0 + 1000 * M, 85.0 + east_m * E)  # noqa: E731
    assert on(50) is None
    msg = on(300)
    assert msg["off_route"] is True and msg["name"] == "Ravi" and 290 < msg["distance_m"] < 310
    assert on(400) is None  # still off: no repeat
    assert on(200) is None  # between 150 and 250: stays off
    back = on(100)
    assert back["off_route"] is False
    assert on(300)["off_route"] is True  # fires again


def test_off_route_ignored_for_approximate_or_missing_plans():
    t = OffRouteTracker()
    assert t.evaluate("R", {"approximate": True, "polyline": "_p~iF~ps|U"}, "a", "R", 0, 0) is None
    assert t.evaluate("S", None, "a", "R", 0, 0) is None


def test_trip_plan_and_route_status_are_broadcast(fake_google):
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "Asha"}).json()
        m = tc.post(f"/rides/{r['ride_id']}/join", json={"display_name": "Ravi"}).json()
        url = f"/ws/rides/{r['ride_id']}?rider_id={m['rider_id']}&token={m['rider_token']}"
        with tc.websocket_connect(url) as ws:
            ws.receive_json()
            tc.put(f"/rides/{r['ride_id']}/plan", headers=H(r), json={
                "rider_id": r["leader_rider_id"],
                "origin": {"lat": 20.0, "lng": 85.0, "label": "A"},
                "destination": {"lat": 20.0 + 2000 * M, "lng": 85.0, "label": "B"}})
            msg = ws.receive_json()
            while msg["type"] != "trip_plan":
                msg = ws.receive_json()
            assert msg["plan"]["destination"]["label"] == "B"

            ws.send_json({"type": "location_update", "lat": 20.0 + 1000 * M, "lng": 85.0 + 400 * E})
            msg = ws.receive_json()
            while msg["type"] != "route_status":
                msg = ws.receive_json()
            assert msg["rider_id"] == m["rider_id"] and msg["off_route"] is True


async def test_summary_includes_plan(client, ride, no_key):
    await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride), json={
        "rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST})
    s = (await client.get(f"/rides/{ride['ride_id']}/summary", headers=H(ride))).json()
    assert s["destination"] == "Puri" and 54 < s["planned_distance_km"] < 57
