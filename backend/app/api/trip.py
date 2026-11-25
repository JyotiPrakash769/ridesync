"""REST (v0.3): trip planner + place search (Google, proxied)."""

import uuid

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.ride import PreviewPlanIn, SetPlanIn
from app.security import rate_limit
from app.services import google_maps
from app.services import ride_service as rs
from app.services import trip_service as ts
from app.services import weather_service
from app.ws.connection_manager import manager

router = APIRouter(prefix="/rides", tags=["trip"])

TokenHeader = Header(default=None, alias="X-Rider-Token")


def _place(p) -> ts.Place | None:
    return None if p is None else ts.Place(p.lat, p.lng, p.label)


@router.put("/{ride_id}/plan", dependencies=[Depends(rate_limit("write"))])
async def set_plan(
    ride_id: str,
    body: SetPlanIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Leader only. Computes the route and broadcasts `trip_plan` to the ride."""
    rid, plan = await ts.set_plan(
        db, ride_id, body.rider_id, x_rider_token,
        _place(body.origin), _place(body.destination), [_place(s) for s in body.stops],
        ts.PlanOptions(
            route=google_maps.RouteOptions(
                avoid_tolls=body.avoid_tolls, avoid_highways=body.avoid_highways,
                alternatives=body.alternative > 0, optimize_stops=body.optimize_stops,
            ),
            alternative=body.alternative,
            departure_at=body.departure_at,
            fuel_range_km=body.fuel_range_km,
        ),
    )
    ts.route_tracker.reset(rid)
    await manager.broadcast(rid, {"type": "trip_plan", "plan": plan})
    return {"plan": plan}


@router.post("/{ride_id}/plan/preview", dependencies=[Depends(rate_limit("write"))])
async def preview_plan(
    ride_id: str,
    body: PreviewPlanIn,
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Leader only: up to 3 route options (Google alternatives exist only for
    trips without stops) to compare before saving with `alternative`."""
    options = await ts.preview_routes(
        db, ride_id, body.rider_id, x_rider_token,
        _place(body.origin), _place(body.destination), [_place(s) for s in body.stops],
        google_maps.RouteOptions(avoid_tolls=body.avoid_tolls, avoid_highways=body.avoid_highways,
                                 alternatives=True, optimize_stops=body.optimize_stops),
    )
    return {"options": options}


@router.get("/{ride_id}/places", dependencies=[Depends(rate_limit("write"))])
async def search_places(
    ride_id: str,
    q: str = Query(min_length=2, max_length=100),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    x_rider_id: uuid.UUID = Header(alias="X-Rider-Id"),
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Place search for the planner. Riders of a live ride only, so the Google
    key can't be used by anyone else through this endpoint."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    await rs.authenticate(db, ride, x_rider_id, x_rider_token)
    near = (lat, lng) if lat is not None and lng is not None else None
    results, provider = await google_maps.search_places(q, near)
    return {"results": results, "provider": provider}


@router.get("/{ride_id}/weather", dependencies=[Depends(rate_limit("read"))])
async def trip_weather(
    ride_id: str,
    x_rider_id: uuid.UUID = Header(alias="X-Rider-Id"),
    x_rider_token: str | None = TokenHeader,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Forecast at each stop and the destination for the estimated arrival hour."""
    ride = await rs.get_live_ride_or_raise(db, ride_id)
    await rs.authenticate(db, ride, x_rider_id, x_rider_token)
    if not ride.plan:
        return {"points": []}
    return {"points": await weather_service.trip_weather(ride.plan)}
