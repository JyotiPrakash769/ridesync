"""Google Maps Platform calls (server side, key never leaves the backend),
with keyless fallbacks so the planner works before a key is configured:

- places: Places API (New) Text Search, else OSM Nominatim (light use only)
- routes: Routes API computeRoutes (TWO_WHEELER, then DRIVE), else straight
  lines between the points, flagged approximate.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx
from fastapi import HTTPException, status

from app.config import get_settings
from app.services.route_geometry import LatLng, encode_polyline, length_m

log = logging.getLogger(__name__)

PLACES_URL = "https://places.googleapis.com/v1/places:searchText"
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
APPROX_SPEED_KPH = 40  # straight-line fallback ETA

_client: httpx.AsyncClient | None = None


def client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=15)
    return _client


def _key() -> str:
    return get_settings().GOOGLE_MAPS_SERVER_KEY.strip()


def upstream_error(what: str) -> HTTPException:
    return HTTPException(status.HTTP_502_BAD_GATEWAY, f"{what}_unavailable")


# ---------- places ----------

async def search_places(query: str, near: LatLng | None) -> tuple[list[dict], str]:
    """Returns (results [{name, address, lat, lng}], provider)."""
    if _key():
        body: dict = {"textQuery": query, "maxResultCount": 8, "languageCode": "en"}
        if near:
            body["locationBias"] = {"circle": {
                "center": {"latitude": near[0], "longitude": near[1]}, "radius": 50000.0}}
        try:
            r = await client().post(PLACES_URL, json=body, headers={
                "X-Goog-Api-Key": _key(),
                "X-Goog-FieldMask": "places.displayName,places.formattedAddress,places.location",
            })
            r.raise_for_status()
        except httpx.HTTPError as e:
            log.warning("places search failed: %s", type(e).__name__)
            raise upstream_error("places") from e
        return [
            {
                "name": (p.get("displayName") or {}).get("text") or p.get("formattedAddress", ""),
                "address": p.get("formattedAddress", ""),
                "lat": p["location"]["latitude"],
                "lng": p["location"]["longitude"],
            }
            for p in r.json().get("places", [])
            if "location" in p
        ], "google"

    params = {"q": query, "format": "jsonv2", "limit": 8, "addressdetails": 0}
    if near:
        d = 0.5  # ~50 km bias box
        params["viewbox"] = f"{near[1]-d},{near[0]+d},{near[1]+d},{near[0]-d}"
    try:
        r = await client().get(NOMINATIM_URL, params=params,
                               headers={"User-Agent": get_settings().NOMINATIM_USER_AGENT})
        r.raise_for_status()
    except httpx.HTTPError as e:
        raise upstream_error("places") from e
    return [
        {"name": p.get("name") or p.get("display_name", "").split(",")[0],
         "address": p.get("display_name", ""), "lat": float(p["lat"]), "lng": float(p["lon"])}
        for p in r.json()
    ], "osm"


# ---------- routes ----------

@dataclass
class Route:
    polyline: str
    distance_m: int
    duration_s: int
    legs: list[dict]
    provider: str
    approximate: bool


def _waypoint(p: LatLng) -> dict:
    return {"location": {"latLng": {"latitude": p[0], "longitude": p[1]}}}


async def compute_route(points: list[LatLng]) -> Route:
    """points = origin, *stops, destination."""
    if _key():
        for mode in ("TWO_WHEELER", "DRIVE"):
            body = {
                "origin": _waypoint(points[0]),
                "destination": _waypoint(points[-1]),
                "intermediates": [_waypoint(p) for p in points[1:-1]],
                "travelMode": mode,
                "polylineQuality": "OVERVIEW",
                "units": "METRIC",
                "languageCode": "en-IN",
            }
            try:
                r = await client().post(ROUTES_URL, json=body, headers={
                    "X-Goog-Api-Key": _key(),
                    "X-Goog-FieldMask": "routes.distanceMeters,routes.duration,"
                    "routes.polyline.encodedPolyline,routes.legs.distanceMeters,routes.legs.duration",
                })
            except httpx.HTTPError as e:
                raise upstream_error("routing") from e
            if r.status_code == 400 and mode == "TWO_WHEELER":
                continue  # two-wheeler not available for this region/route: try car
            if r.status_code >= 400:
                log.warning("routes api %s: %.200s", r.status_code, r.text)
                raise upstream_error("routing")
            routes = r.json().get("routes") or []
            if not routes:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "no_route_found")
            rt = routes[0]
            return Route(
                polyline=rt["polyline"]["encodedPolyline"],
                distance_m=int(rt.get("distanceMeters", 0)),
                duration_s=_secs(rt.get("duration", "0s")),
                legs=[{"distance_m": int(leg.get("distanceMeters", 0)),
                       "duration_s": _secs(leg.get("duration", "0s"))} for leg in rt.get("legs", [])],
                provider=f"google:{mode.lower()}",
                approximate=False,
            )

    legs = []
    for a, b in zip(points, points[1:], strict=False):
        d = length_m([a, b])
        legs.append({"distance_m": round(d), "duration_s": round(d / (APPROX_SPEED_KPH / 3.6))})
    return Route(
        polyline=encode_polyline(points),
        distance_m=sum(leg["distance_m"] for leg in legs),
        duration_s=sum(leg["duration_s"] for leg in legs),
        legs=legs,
        provider="straight_line",
        approximate=True,
    )


def _secs(v: str) -> int:
    try:
        return round(float(str(v).rstrip("s")))
    except ValueError:
        return 0
