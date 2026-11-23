"""Per-rider secret tokens and simple rate limiting.

v0.1 identified riders only by rider_id, which is visible to everyone in the
ride (rider_positions, GET /rides). Anyone with the ride code could therefore
act as the leader. Now each rider receives a random secret `rider_token` when
creating/joining; only its SHA-256 is stored. Every authenticated call sends
`X-Rider-Id` + `X-Rider-Token` (REST) or `?rider_id=&token=` (WebSocket).
"""

from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request, status


def new_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def token_matches(token: str | None, token_hash: str | None) -> bool:
    if not token or not token_hash:
        return False
    return hmac.compare_digest(hash_token(token), token_hash)


def unauthorized() -> HTTPException:
    return HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_rider_token")


# ---------- rate limiting ----------


def client_ip(request: Request) -> str:
    # Railway (and most PaaS) put the real client first in X-Forwarded-For.
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


class RateLimiter:
    """In-memory sliding window per (bucket, key). Single-instance only, like
    the WebSocket rooms; move to Redis together with them when scaling."""

    def __init__(self) -> None:
        self._hits: dict[tuple[str, str], deque[float]] = defaultdict(deque)
        self.enabled = os.environ.get("DISABLE_RATE_LIMIT") != "1"

    def hit(self, bucket: str, key: str, limit: int, window_s: float = 60.0) -> bool:
        """Records a hit; returns False if the caller is over the limit."""
        if not self.enabled:
            return True
        now = time.monotonic()
        q = self._hits[(bucket, key)]
        while q and now - q[0] > window_s:
            q.popleft()
        if len(q) >= limit:
            return False
        q.append(now)
        return True

    def reset(self) -> None:
        self._hits.clear()


limiter = RateLimiter()

# Requests per minute per client IP.
LIMITS = {
    "create": 10,   # POST /rides
    "join": 20,     # POST /rides/{id}/join  (also slows down ride-code guessing)
    "read": 120,    # GET /rides/{id}, summary
    "write": 60,    # threshold / end / sync / regroup / leader
    "ws": 30,       # WebSocket connects
}


def rate_limit(bucket: str):
    """FastAPI dependency: 429 when the client IP exceeds LIMITS[bucket]."""

    async def dep(request: Request) -> None:
        if not limiter.hit(bucket, client_ip(request), LIMITS[bucket]):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "rate_limited")

    return dep
