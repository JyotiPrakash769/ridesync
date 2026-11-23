"""Distance math and "falling behind" alert debouncing.

Alerts compare each member with the leader's last position and fire only on
an under -> over threshold transition per rider. Decisions (agreed):
- Reference point is the leader.
- While the leader is weak/offline (stale position) alerts are paused and the
  per-rider state is cleared, so when the leader is back online anyone still
  over the threshold fires exactly once.
- A threshold change resets state the same way.

State is in memory (single instance, like ConnectionManager). With several
backend instances it would need to live in Redis next to the pub/sub rooms.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

EARTH_RADIUS_M = 6_371_000.0

# Once over, a rider must come back under 90% of the threshold to re-arm,
# so GPS jitter around the threshold can't fire repeated alerts.
REARM_RATIO = 0.9


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in meters."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(a)))


@dataclass(frozen=True)
class Point:
    rider_id: str
    name: str
    lat: float | None
    lng: float | None
    status: str  # online | weak | offline

    @property
    def has_position(self) -> bool:
        return self.lat is not None and self.lng is not None


@dataclass(frozen=True)
class Alert:
    rider_id: str
    name: str
    distance_m: int

    def message(self) -> dict:
        return {
            "type": "distance_alert",
            "rider_id": self.rider_id,
            "name": self.name,
            "distance_m": self.distance_m,
        }


class AlertTracker:
    def __init__(self) -> None:
        self._over: dict[str, dict[str, bool]] = {}

    def reset(self, ride_id: str) -> None:
        self._over.pop(ride_id, None)

    def forget_rider(self, ride_id: str, rider_id: str) -> None:
        self._over.get(ride_id, {}).pop(rider_id, None)

    def is_over(self, ride_id: str, rider_id: str) -> bool:
        return self._over.get(ride_id, {}).get(rider_id, False)

    def evaluate(
        self, ride_id: str, leader: Point | None, members: list[Point], threshold_m: int
    ) -> list[Alert]:
        if leader is None or not leader.has_position or leader.status != "online":
            # Stale reference point: pause and clear, so resume re-evaluates fresh.
            self.reset(ride_id)
            return []
        room = self._over.setdefault(ride_id, {})
        alerts: list[Alert] = []
        for m in members:
            if m.rider_id == leader.rider_id or not m.has_position:
                continue
            d = haversine_m(leader.lat, leader.lng, m.lat, m.lng)
            was_over = room.get(m.rider_id, False)
            now_over = d > threshold_m * REARM_RATIO if was_over else d > threshold_m
            if now_over and not was_over:
                alerts.append(Alert(m.rider_id, m.name, round(d)))
            room[m.rider_id] = now_over
        return alerts


tracker = AlertTracker()
