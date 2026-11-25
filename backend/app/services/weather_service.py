"""Weather along the planned trip (Open-Meteo: free, no key; light use).

For each stop and the destination we estimate the arrival time (departure, or
now if already riding, plus the planned leg durations) and read the hourly
forecast for that hour.
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta

import httpx

from app.services import google_maps
from app.services import ride_service as rs

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
CACHE_S = 30 * 60
_cache: dict[tuple[float, float], tuple[float, dict]] = {}

RAIN_WARN_PCT = 60
HEAT_WARN_C = 38


def describe(code: int) -> str:
    if code == 0:
        return "Clear"
    if code in (1, 2, 3):
        return "Partly cloudy"
    if code in (45, 48):
        return "Fog"
    if 51 <= code <= 57:
        return "Drizzle"
    if 61 <= code <= 67:
        return "Rain"
    if 71 <= code <= 77:
        return "Snow"
    if 80 <= code <= 82:
        return "Showers"
    if code >= 95:
        return "Thunderstorm"
    return "Cloudy"


async def _forecast(lat: float, lng: float) -> dict:
    key = (round(lat, 2), round(lng, 2))
    hit = _cache.get(key)
    if hit and time.monotonic() - hit[0] < CACHE_S:
        return hit[1]
    r = await google_maps.client().get(FORECAST_URL, params={
        "latitude": key[0], "longitude": key[1],
        "hourly": "temperature_2m,precipitation_probability,weather_code",
        "timezone": "UTC", "forecast_days": 7,
    })
    r.raise_for_status()
    data = r.json()
    _cache[key] = (time.monotonic(), data)
    return data


def _at(hourly: dict, when: datetime) -> dict | None:
    times = hourly.get("time") or []
    target = when.strftime("%Y-%m-%dT%H:00")
    if target not in times:
        return None
    i = times.index(target)
    code = int((hourly.get("weather_code") or [0])[i] or 0)
    return {
        "temp_c": (hourly.get("temperature_2m") or [None])[i],
        "rain_pct": (hourly.get("precipitation_probability") or [None])[i],
        "code": code,
        "summary": describe(code),
    }


def waypoint_etas(plan: dict, now: datetime) -> list[tuple[str, str, float, float, datetime]]:
    """[(kind, label, lat, lng, eta)] for stops then destination."""
    dep = plan.get("departure_at")
    start = datetime.fromisoformat(dep) if dep else now
    if start < now:
        start = now
    legs = plan.get("legs") or []
    places = [("stop", s) for s in plan.get("stops", [])] + [("destination", plan["destination"])]
    out, t = [], start
    for i, (kind, p) in enumerate(places):
        t = t + timedelta(seconds=(legs[i]["duration_s"] if i < len(legs) else 0))
        out.append((kind, p.get("label", ""), p["lat"], p["lng"], t))
    return out


async def trip_weather(plan: dict) -> list[dict]:
    now = rs.utcnow()
    result = []
    for kind, label, lat, lng, eta in waypoint_etas(plan, now):
        item = {"kind": kind, "label": label, "eta": eta.isoformat(), "forecast": None, "warning": None}
        try:
            f = _at((await _forecast(lat, lng)).get("hourly", {}), eta)
        except httpx.HTTPError:
            f = None
        if f:
            item["forecast"] = f
            if (f["rain_pct"] or 0) >= RAIN_WARN_PCT or f["code"] >= 95:
                item["warning"] = f"{f['summary']} likely"
            elif f["temp_c"] is not None and f["temp_c"] >= HEAT_WARN_C:
                item["warning"] = f"Very hot ({round(f['temp_c'])}°C)"
            elif f["code"] in (45, 48):
                item["warning"] = "Fog"
        result.append(item)
    return result
