"""v0.4: route options, departure, fuel range, weather, sweep, battery,
quick messages, stopped riders, arrivals."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.services import google_maps, weather_service
from app.services.assist_service import StoppedTracker, quick_code_allowed
from app.services.google_maps import nearest_neighbour_order
from app.services.route_geometry import encode_polyline
from tests.conftest import H, exec_sql

M = 1 / 111_194.93
ORIGIN = {"lat": 20.2961, "lng": 85.8245, "label": "Bhubaneswar"}
DEST = {"lat": 19.7984, "lng": 85.8247, "label": "Puri"}
FAR = {"lat": 19.9, "lng": 85.83, "label": "Far stop"}
NEAR = {"lat": 20.2, "lng": 85.83, "label": "Near stop"}


class Resp:
    def __init__(self, status, body):
        self.status_code, self._b = status, body

    def json(self):
        return self._b

    def raise_for_status(self):
        pass

    text = ""


class Fake:
    def __init__(self):
        self.calls = []

    async def post(self, url, json=None, headers=None):
        self.calls.append(json)
        n = 3 if json.get("computeAlternativeRoutes") else 1
        pts = [(w["location"]["latLng"]["latitude"], w["location"]["latLng"]["longitude"])
               for w in [json["origin"], *json["intermediates"], json["destination"]]]
        routes = [{"distanceMeters": 61000 + i * 4000, "duration": f"{4200 + i * 300}s",
                   "polyline": {"encodedPolyline": encode_polyline(pts)},
                   "legs": [{"distanceMeters": 30000, "duration": "2000s"}] * (len(pts) - 1)}
                  for i in range(n)]
        if json.get("optimizeWaypointOrder"):
            routes[0]["optimizedIntermediateWaypointIndex"] = [1, 0]
        return Resp(200, {"routes": routes})

    async def get(self, url, params=None, headers=None):
        start = datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
        times = [(start + timedelta(hours=h)).strftime("%Y-%m-%dT%H:00") for h in range(48)]
        return Resp(200, {"hourly": {
            "time": times,
            "temperature_2m": [30.0] * 48,
            "precipitation_probability": [80] * 48 if params["latitude"] < 20 else [10] * 48,
            "weather_code": [61] * 48 if params["latitude"] < 20 else [1] * 48,
        }})


@pytest.fixture
def google(monkeypatch):
    f = Fake()
    monkeypatch.setattr(google_maps, "_client", f)
    monkeypatch.setattr(get_settings(), "GOOGLE_MAPS_SERVER_KEY", "k")
    weather_service._cache.clear()
    return f


def plan_body(ride, **kw):
    return {"rider_id": ride["leader_rider_id"], "origin": ORIGIN, "destination": DEST} | kw


# ---------- route options ----------

async def test_preview_returns_three_alternatives_with_modifiers(client, ride, google):
    r = await client.post(f"/rides/{ride['ride_id']}/plan/preview", headers=H(ride),
                          json=plan_body(ride, avoid_tolls=True))
    opts = r.json()["options"]
    assert [o["label"] for o in opts] == ["Recommended", "Alternative 1", "Alternative 2"]
    assert google.calls[-1]["routeModifiers"] == {"avoidTolls": True, "avoidHighways": False}
    # nothing saved
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["plan"] is None


async def test_choose_alternative_and_options_are_saved(client, ride, google):
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride),
                         json=plan_body(ride, alternative=2, avoid_highways=True, fuel_range_km=150))
    p = r.json()["plan"]
    assert (p["distance_m"], p["route_label"], p["avoid_highways"], p["fuel_range_km"]) == \
        (69000, "Alternative 2", True, 150)


async def test_optimize_reorders_stops(client, ride, google):
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride),
                         json=plan_body(ride, stops=[FAR, NEAR], optimize_stops=True))
    assert [s["label"] for s in r.json()["plan"]["stops"]] == ["Near stop", "Far stop"]
    assert google.calls[-1]["optimizeWaypointOrder"] is True


def test_keyless_optimisation_is_nearest_neighbour():
    o = (20.3, 85.8)
    assert nearest_neighbour_order(o, [(19.9, 85.8), (20.2, 85.8), (20.0, 85.8)], (19.8, 85.8)) == [1, 2, 0]


# ---------- departure ----------

async def test_departure_extends_ride_lifetime(client, ride, google):
    dep = datetime.now(UTC) + timedelta(days=2)
    r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride),
                         json=plan_body(ride, departure_at=dep.isoformat()))
    assert r.status_code == 200
    g = (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()
    expires = datetime.fromisoformat(g["expires_at"])
    assert expires >= dep + timedelta(hours=get_settings().RIDE_TTL_HOURS) - timedelta(seconds=1)


async def test_departure_out_of_range(client, ride, google):
    for dep in (datetime.now(UTC) + timedelta(days=8), datetime.now(UTC) - timedelta(hours=3)):
        r = await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride),
                             json=plan_body(ride, departure_at=dep.isoformat()))
        assert r.status_code == 422


# ---------- weather ----------

async def test_weather_per_stop_with_warnings(client, ride, google):
    await client.put(f"/rides/{ride['ride_id']}/plan", headers=H(ride),
                     json=plan_body(ride, stops=[NEAR]))
    pts = (await client.get(f"/rides/{ride['ride_id']}/weather", headers=H(ride))).json()["points"]
    assert [(p["kind"], p["label"]) for p in pts] == [("stop", "Near stop"), ("destination", "Puri")]
    assert pts[0]["warning"] is None and pts[0]["forecast"]["summary"] == "Partly cloudy"
    assert pts[1]["warning"] == "Rain likely"
    eta0 = datetime.fromisoformat(pts[0]["eta"])
    eta1 = datetime.fromisoformat(pts[1]["eta"])
    assert timedelta(seconds=1990) <= eta1 - eta0 <= timedelta(seconds=2010)


async def test_weather_without_plan_and_auth(client, ride):
    assert (await client.get(f"/rides/{ride['ride_id']}/weather", headers=H(ride))).json() == {"points": []}
    assert (await client.get(f"/rides/{ride['ride_id']}/weather",
                             headers={"X-Rider-Id": ride["leader_rider_id"]})).status_code == 401


# ---------- sweep ----------

async def test_leader_sets_sweep(client, ride):
    m = (await client.post(f"/rides/{ride['ride_id']}/join", json={"display_name": "Tail"})).json()
    url = f"/rides/{ride['ride_id']}/sweep"
    r = await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"],
                                                      "sweep_rider_id": m["rider_id"]})
    assert r.json() == {"sweep_rider_id": m["rider_id"]}
    g = (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()
    assert g["sweep_rider_id"] == m["rider_id"]
    assert (await client.put(url, headers=H(m), json={"rider_id": m["rider_id"],
                                                      "sweep_rider_id": None})).status_code == 403
    await client.put(url, headers=H(ride), json={"rider_id": ride["leader_rider_id"], "sweep_rider_id": None})
    assert (await client.get(f"/rides/{ride['ride_id']}", headers=H(ride))).json()["sweep_rider_id"] is None


# ---------- trackers ----------

def test_stopped_tracker():
    t = StoppedTracker()
    assert t.evaluate("R", "a", "Ravi", 20.0, 85.0, now=0) is None
    assert t.evaluate("R", "a", "Ravi", 20.0 + 10 * M, 85.0, now=100) is None  # jitter
    msg = t.evaluate("R", "a", "Ravi", 20.0 + 20 * M, 85.0, now=181)
    assert msg["type"] == "rider_stopped" and msg["stopped_s"] == 181
    assert t.evaluate("R", "a", "Ravi", 20.0, 85.0, now=300) is None  # no repeat
    assert t.evaluate("R", "a", "Ravi", 20.0 + 100 * M, 85.0, now=310)["type"] == "rider_moving"


def test_quick_codes_by_role():
    assert quick_code_allowed("slow_down", True)
    assert not quick_code_allowed("slow_down", False)
    assert quick_code_allowed("need_fuel", False)
    assert not quick_code_allowed("rm -rf", True)


def _ws(tc, r):
    rid = r.get("leader_rider_id") or r["rider_id"]
    return tc.websocket_connect(f"/ws/rides/{r['ride_id']}?rider_id={rid}&token={r['rider_token']}")


def _until(ws, type_, n=12):
    for _ in range(n):
        m = ws.receive_json()
        if m["type"] == type_:
            return m
    raise AssertionError(type_)


def test_battery_quick_messages_and_arrival(google):
    with TestClient(app) as tc:
        r = tc.post("/rides", json={"leader_name": "Asha"}).json()
        m = tc.post(f"/rides/{r['ride_id']}/join", json={"display_name": "Ravi"}).json()
        m["ride_id"] = r["ride_id"]
        tc.put(f"/rides/{r['ride_id']}/plan", headers=H(r), json=plan_body(r))
        with _ws(tc, r) as a, _ws(tc, m) as b:
            a.receive_json()
            # battery travels with positions
            b.send_json({"type": "location_update", "lat": 20.1, "lng": 85.82, "battery": 12})
            pos = _until(a, "rider_positions")
            while next(x for x in pos["riders"] if x["rider_id"] == m["rider_id"])["battery"] != 12:
                pos = _until(a, "rider_positions")
            # quick messages: member can't use leader codes
            b.send_json({"type": "quick_message", "code": "slow_down"})
            b.send_json({"type": "quick_message", "code": "need_fuel"})
            q = _until(a, "quick_message")
            assert (q["code"], q["name"], q["role"]) == ("need_fuel", "Ravi", "member")
            a.send_json({"type": "quick_message", "code": "slow_down"})
            q = _until(b, "quick_message")
            if q["code"] == "need_fuel":  # the sender gets its own broadcast too
                q = _until(b, "quick_message")
            assert (q["code"], q["role"]) == ("slow_down", "leader")
            # arrival at the destination
            b.send_json({"type": "location_update", "lat": DEST["lat"], "lng": DEST["lng"]})
            arr = _until(a, "rider_arrived")
            assert arr["rider_id"] == m["rider_id"]
        g = tc.get(f"/rides/{r['ride_id']}", headers=H(r)).json()
        assert g["arrived"] == [m["rider_id"]]
