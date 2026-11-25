"""Trip planner: the leader sets origin, destination and up to MAX_STOPS stops;
the server computes the route (Google or approximate) and stores it on the
ride. Everyone receives it via `trip_plan`.

Off-route: a rider farther than OFF_ROUTE_M from the planned route is flagged
once (transition), and cleared when back within ON_ROUTE_M. Not evaluated for
approximate (straight-line) plans, which don't follow roads.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from fastapi import HTTPException, status

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import RideEvent
from app.services import google_maps
from app.services import ride_service as rs
from app.config import get_settings
from app.services.google_maps import RouteOptions
from app.services.route_geometry import LatLng, decode_polyline, distance_to_route_m

MAX_DEPARTURE_AHEAD = timedelta(days=7)
ARRIVED_M = 150

MAX_STOPS = 5
OFF_ROUTE_M = 250
ON_ROUTE_M = 150
EVENT_PLAN_SET = "plan_set"
EVENT_OFF_ROUTE = "off_route"


@dataclass(frozen=True)
class Place:
    lat: float
    lng: float
    label: str

    def json(self) -> dict:
        return {"lat": self.lat, "lng": self.lng, "label": self.label}


@dataclass(frozen=True)
class PlanOptions:
    route: RouteOptions = RouteOptions()
    alternative: int = 0              # which of the computed routes to keep
    departure_at: datetime | None = None
    fuel_range_km: int | None = None


async def _resolve_origin(db, ride, leader, origin: Place | None) -> Place:
    if origin is not None:
        return origin
    if leader.last_lat is None or leader.last_lng is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "origin_required")
    return Place(leader.last_lat, leader.last_lng, "Start")


def _check_departure(departure_at: datetime | None) -> None:
    if departure_at is None:
        return
    now = rs.utcnow()
    if departure_at < now - timedelta(hours=1) or departure_at > now + MAX_DEPARTURE_AHEAD:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "departure_out_of_range")


async def preview_routes(
    db: AsyncSession, ride_id: str, rider_id: uuid.UUID, token: str | None,
    origin: Place | None, destination: Place, stops: list[Place], opts: RouteOptions,
) -> list[dict]:
    """Leader only: compute route options without saving (compare before choosing)."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    leader = await rs.require_leader(db, ride, rider_id, token)
    origin = await _resolve_origin(db, ride, leader, origin)
    routes = await google_maps.compute_routes(
        [(origin.lat, origin.lng), *[(s.lat, s.lng) for s in stops], (destination.lat, destination.lng)],
        opts,
    )
    return [
        {"index": i, "label": r.label, "distance_m": r.distance_m, "duration_s": r.duration_s,
         "polyline": r.polyline, "approximate": r.approximate, "stop_order": r.stop_order}
        for i, r in enumerate(routes)
    ]


async def set_plan(
    db: AsyncSession, ride_id: str, rider_id: uuid.UUID, token: str | None,
    origin: Place | None, destination: Place | None, stops: list[Place],
    options: PlanOptions = PlanOptions(),
) -> tuple[str, dict | None]:
    """Leader only. destination=None clears the plan. origin=None uses the
    leader's live position. A departure time keeps the ride alive until
    departure + RIDE_TTL_HOURS (planning the night before)."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    leader = await rs.require_leader(db, ride, rider_id, token)
    if destination is None:
        ride.plan = None
        await db.commit()
        return ride.id, None
    _check_departure(options.departure_at)
    origin = await _resolve_origin(db, ride, leader, origin)
    routes = await google_maps.compute_routes(
        [(origin.lat, origin.lng), *[(s.lat, s.lng) for s in stops], (destination.lat, destination.lng)],
        options.route,
    )
    route = routes[min(options.alternative, len(routes) - 1)]
    if route.stop_order:
        stops = [stops[i] for i in route.stop_order]
    if options.departure_at is not None:
        keep_until = options.departure_at + timedelta(hours=get_settings().RIDE_TTL_HOURS)
        if keep_until > ride.expires_at:
            ride.expires_at = keep_until
    plan = {
        "origin": origin.json(),
        "destination": destination.json(),
        "stops": [s.json() for s in stops],
        "polyline": route.polyline,
        "distance_m": route.distance_m,
        "duration_s": route.duration_s,
        "legs": route.legs,
        "provider": route.provider,
        "approximate": route.approximate,
        "route_label": route.label,
        "avoid_tolls": options.route.avoid_tolls,
        "avoid_highways": options.route.avoid_highways,
        "departure_at": options.departure_at.isoformat() if options.departure_at else None,
        "fuel_range_km": options.fuel_range_km,
        "updated_at": rs.utcnow().isoformat(),
    }
    ride.plan = plan
    db.add(RideEvent(ride_id=ride.id, rider_id=leader.id, type=EVENT_PLAN_SET,
                     distance_m=route.distance_m))
    await db.commit()
    return ride.id, plan


class OffRouteTracker:
    """Per ride: decoded route + which riders are currently off it."""

    def __init__(self) -> None:
        self._routes: dict[str, list[LatLng] | None] = {}
        self._off: dict[str, set[str]] = {}

    def reset(self, ride_id: str) -> None:
        self._routes.pop(ride_id, None)
        self._off.pop(ride_id, None)

    def _route(self, ride_id: str, plan: dict | None) -> list[LatLng] | None:
        if ride_id not in self._routes:
            usable = plan and not plan.get("approximate") and plan.get("polyline")
            self._routes[ride_id] = decode_polyline(plan["polyline"]) if usable else None
        return self._routes[ride_id]

    def evaluate(self, ride_id: str, plan: dict | None, rider_id: str, name: str,
                 lat: float, lng: float) -> dict | None:
        """Returns a route_status message on a transition, else None."""
        route = self._route(ride_id, plan)
        if not route:
            return None
        d = distance_to_route_m((lat, lng), route)
        off = self._off.setdefault(ride_id, set())
        was_off = rider_id in off
        if not was_off and d > OFF_ROUTE_M:
            off.add(rider_id)
            return {"type": "route_status", "rider_id": rider_id, "name": name,
                    "off_route": True, "distance_m": round(d)}
        if was_off and d < ON_ROUTE_M:
            off.discard(rider_id)
            return {"type": "route_status", "rider_id": rider_id, "name": name,
                    "off_route": False, "distance_m": round(d)}
        return None


route_tracker = OffRouteTracker()
