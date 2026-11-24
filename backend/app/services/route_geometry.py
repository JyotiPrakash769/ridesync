"""Route geometry: Google encoded polylines, lengths, point-to-route distance."""

from __future__ import annotations

import math

from app.services.distance_service import EARTH_RADIUS_M, haversine_m

LatLng = tuple[float, float]


def encode_polyline(points: list[LatLng], precision: int = 5) -> str:
    factor = 10**precision
    out: list[str] = []
    prev_lat = prev_lng = 0
    for lat, lng in points:
        ilat, ilng = round(lat * factor), round(lng * factor)
        for delta in (ilat - prev_lat, ilng - prev_lng):
            v = ~(delta << 1) if delta < 0 else delta << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        prev_lat, prev_lng = ilat, ilng
    return "".join(out)


def decode_polyline(encoded: str, precision: int = 5) -> list[LatLng]:
    factor = 10**precision
    points: list[LatLng] = []
    i = lat = lng = 0
    while i < len(encoded):
        for axis in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lng += delta
        points.append((lat / factor, lng / factor))
    return points


def length_m(points: list[LatLng]) -> float:
    return sum(haversine_m(*a, *b) for a, b in zip(points, points[1:], strict=False))


def distance_to_route_m(p: LatLng, route: list[LatLng]) -> float:
    """Shortest distance from p to the polyline (local flat-earth projection,
    accurate to well under 1% at the few-hundred-metre scale that matters)."""
    if not route:
        return math.inf
    if len(route) == 1:
        return haversine_m(*p, *route[0])
    lat0 = math.radians(p[0])
    kx = math.cos(lat0) * math.pi / 180 * EARTH_RADIUS_M
    ky = math.pi / 180 * EARTH_RADIUS_M

    def xy(q: LatLng) -> tuple[float, float]:
        return ((q[1] - p[1]) * kx, (q[0] - p[0]) * ky)

    best = math.inf
    for a, b in zip(route, route[1:], strict=False):
        (ax, ay), (bx, by) = xy(a), xy(b)
        dx, dy = bx - ax, by - ay
        seg2 = dx * dx + dy * dy
        t = 0.0 if seg2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg2))
        cx, cy = ax + t * dx, ay + t * dy
        best = min(best, math.hypot(cx, cy))
    return best
