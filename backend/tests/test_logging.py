import logging

from app.logging_redact import RedactSecretsFilter, redact, scrub_sentry_event


def test_redact_token_in_ws_url():
    line = '("1.2.3.4", 5) - "WebSocket /ws/rides/ABC234?rider_id=u&token=s3cr3t_-x" [accepted]'
    out = redact(line)
    assert "s3cr3t" not in out and "token=[redacted]" in out and "rider_id=u" in out


def test_filter_rewrites_uvicorn_style_records():
    rec = logging.LogRecord("uvicorn.error", logging.INFO, __file__, 1,
                            '%s - "WebSocket %s" [accepted]',
                            ("('1.2.3.4', 5)", "/ws/rides/X?rider_id=a&token=abc"), None)
    assert RedactSecretsFilter().filter(rec)
    assert "abc" not in rec.getMessage()


def test_sentry_scrub():
    ev = {"request": {"url": "https://h/ws/rides/X?token=abc", "query_string": "token=abc"}}
    out = scrub_sentry_event(ev, None)
    assert "abc" not in str(out)


def test_filter_installed_on_uvicorn_loggers():
    import app.main  # noqa: F401

    for name in ("uvicorn.access", "uvicorn.error"):
        assert any(isinstance(f, RedactSecretsFilter) for f in logging.getLogger(name).filters)
