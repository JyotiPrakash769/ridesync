"""Keep rider secrets out of logs.

The WebSocket URL carries `?token=<rider secret>`; uvicorn logs the full path
for every connection ("WebSocket /ws/rides/X?rider_id=..&token=.. [accepted]")
and for HTTP access lines. This filter rewrites those records before any
handler (stdout, Railway) sees them.
"""

from __future__ import annotations

import logging
import re

_SECRET = re.compile(r"(token=)[^&\s\"']+", re.IGNORECASE)


def redact(text: str) -> str:
    return _SECRET.sub(r"\1[redacted]", text)


class RedactSecretsFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:  # malformed record: leave it alone
            return True
        clean = redact(msg)
        if clean != msg:
            record.msg, record.args = clean, ()
        return True


def install() -> None:
    f = RedactSecretsFilter()
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error", ""):
        logger = logging.getLogger(name)
        if not any(isinstance(x, RedactSecretsFilter) for x in logger.filters):
            logger.addFilter(f)
        for h in logger.handlers:
            if not any(isinstance(x, RedactSecretsFilter) for x in h.filters):
                h.addFilter(f)


def scrub_sentry_event(event, _hint):
    """Sentry before_send: drop query strings and redact any token text."""
    req = event.get("request") or {}
    if "query_string" in req:
        req["query_string"] = "[redacted]"
    if isinstance(req.get("url"), str):
        req["url"] = redact(req["url"])
    return event
