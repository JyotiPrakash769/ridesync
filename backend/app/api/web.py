"""Public, unauthenticated pages served by the backend:

- GET /join/{ride_id}   QR / share link landing page ("Open in RideSync")
- GET /privacy          privacy policy (linked from the app)
- GET /.well-known/assetlinks.json   Android App Links verification

The join page reveals nothing about the ride (no names, no positions,
not even whether the code exists): it only bounces to the app.
"""

from __future__ import annotations

import html


from fastapi import APIRouter
from fastapi.responses import HTMLResponse, JSONResponse, Response

from app.config import get_settings
from app.services.ride_service import RIDE_ID_ALPHABET, normalize_ride_id

router = APIRouter(tags=["web"])

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>{title}</title>
<style>
 body{{margin:0;font-family:system-ui,-apple-system,Roboto,sans-serif;background:#16130b;color:#ece1cf;
   display:flex;min-height:100vh;align-items:center;justify-content:center}}
 main{{max-width:420px;padding:32px 24px;text-align:center}}
 h1{{font-weight:500;margin:.2em 0}} p{{color:#d0c5b2;line-height:1.5}}
 .code{{font-size:2.2rem;letter-spacing:.35em;margin:16px 0 28px;font-variant-numeric:tabular-nums}}
 a.btn{{display:block;padding:18px;border-radius:999px;margin:12px 0;text-decoration:none;font-weight:600}}
 .primary{{background:#ffc72c;color:#261a00}} .secondary{{border:1px solid #9a8f80;color:#ffc72c}}
 .doc{{text-align:left}} .doc h2{{font-size:1.1rem;margin-top:1.6em}}
</style></head><body><main>{body}</main></body></html>"""


def _page(title: str, body: str, status: int = 200) -> HTMLResponse:
    return HTMLResponse(_PAGE.format(title=html.escape(title), body=body), status_code=status)


@router.get("/join/{ride_id}", response_class=HTMLResponse, include_in_schema=False)
async def join_page(ride_id: str) -> HTMLResponse:
    code = normalize_ride_id(ride_id)
    if len(code) != 6 or any(c not in RIDE_ID_ALPHABET for c in code):
        return _page("RideSync", "<h1>RideSync</h1><p>That link doesn't contain a valid ride code.</p>", 404)
    app_link = f"ridesync://join/{code}"
    download = html.escape(get_settings().APP_DOWNLOAD_URL, quote=True)
    body = f"""
<h1>Join this ride</h1>
<p>You've been invited to a RideSync convoy.</p>
<div class="code">{code}</div>
<a class="btn primary" href="{app_link}">Open in RideSync</a>
<a class="btn secondary" href="{download}">Get the app (Android)</a>
<p>Already have the app? You can also tap <b>Join a ride</b> and type the code.</p>
<script>setTimeout(function(){{location.href="{app_link}"}},300);</script>"""
    return _page(f"Join ride {code} - RideSync", body)


PRIVACY_POLICY = """
<div class="doc">
<h1>RideSync privacy policy</h1>
<p>Last updated: 24 November 2026</p>
<h2>What we collect</h2>
<p>Only what the convoy needs: the display name you type, and while you are in a ride your
phone's location (latitude/longitude, speed) and the time it was recorded. There are no
accounts, no email, no phone number, no contacts and no advertising IDs.</p>
<h2>Who sees it</h2>
<p>Only the riders of the same ride. Ride data can be read only with a secret token that the app
receives when you create or join a ride. We never sell or share data with anyone else.</p>
<h2>Background location</h2>
<p>While you are in a ride, RideSync keeps sharing your location with the screen off so your
group can still see you. A notification ("RideSync is tracking your ride") is shown the whole
time. Tracking stops when you leave the ride or it ends.</p>
<h2>How long we keep it</h2>
<p>A ride lasts at most 12 hours. Its riders, positions and events are permanently deleted
{days} days after the ride ends.</p>
<h2>Crash reports</h2>
<p>If enabled, technical error reports (no location history, no names) may be sent to our
error-tracking provider to fix bugs.</p>
<h2>Your choices</h2>
<p>Leave a ride at any time to stop sharing. Location and notification permissions can be
changed in Android settings. Uninstalling the app removes all data stored on your phone.</p>
<h2>Contact</h2>
<p>Questions or deletion requests: open an issue at
<a href="https://github.com/JyotiPrakash769/ridesync/issues" style="color:#ffc72c">github.com/JyotiPrakash769/ridesync</a>.</p>
</div>"""


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy() -> HTMLResponse:
    return _page("RideSync privacy policy",
                 PRIVACY_POLICY.format(days=get_settings().RETENTION_DAYS))


@router.get("/.well-known/assetlinks.json", include_in_schema=False)
async def assetlinks() -> Response:
    fingerprints = [f.strip() for f in get_settings().ANDROID_CERT_SHA256.split(",") if f.strip()]
    if not fingerprints:
        return Response(status_code=404)
    return JSONResponse([{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {
            "namespace": "android_app",
            "package_name": "app.ridesync.ridesync",
            "sha256_cert_fingerprints": fingerprints,
        },
    }])


