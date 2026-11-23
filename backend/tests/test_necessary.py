"""Join landing page, privacy page, App Links, QR base URL, data retention."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.config import get_settings
from tests.conftest import H, exec_sql


async def test_join_page_bounces_to_app_without_leaking_ride_data(client, ride):
    rid = ride["ride_id"]
    r = await client.get(f"/join/{rid.lower()}")
    assert r.status_code == 200 and "text/html" in r.headers["content-type"]
    assert f"ridesync://join/{rid}" in r.text
    assert get_settings().APP_DOWNLOAD_URL in r.text
    assert "Asha" not in r.text  # leader's name is private


async def test_join_page_rejects_bad_codes_and_escapes(client):
    for bad in ("ABC", "OOOOOO", "<script>x"):
        r = await client.get(f"/join/{bad}")
        assert r.status_code == 404
        assert "<script>x" not in r.text


async def test_privacy_page(client):
    r = await client.get("/privacy")
    assert r.status_code == 200
    assert "privacy policy" in r.text.lower()
    assert f"{get_settings().RETENTION_DAYS} days" in r.text


async def test_assetlinks_only_when_configured(client, monkeypatch):
    assert (await client.get("/.well-known/assetlinks.json")).status_code == 404
    monkeypatch.setattr(get_settings(), "ANDROID_CERT_SHA256", "AA:BB, CC:DD")
    r = await client.get("/.well-known/assetlinks.json")
    body = r.json()
    assert body[0]["target"]["package_name"] == "app.ridesync.ridesync"
    assert body[0]["target"]["sha256_cert_fingerprints"] == ["AA:BB", "CC:DD"]


async def test_qr_payload_uses_public_base_url(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "PUBLIC_BASE_URL", "https://rs.example.app/")
    r = (await client.post("/rides", json={"leader_name": "A"})).json()
    assert r["qr_payload"] == f"https://rs.example.app/join/{r['ride_id']}"


async def _ended_at(ride_id):
    from app.db.session import engine

    async with engine.connect() as conn:
        return (await conn.execute(text("SELECT ended_at FROM rides WHERE id=:i"),
                                   {"i": ride_id})).scalar()


async def test_end_and_expiry_record_ended_at(client, ride):
    from app.db.session import AsyncSessionLocal
    from app.tasks.expiry_cleanup import mark_expired_rides

    await client.post(f"/rides/{ride['ride_id']}/end",
                      json={"rider_id": ride["leader_rider_id"]}, headers=H(ride))
    assert await _ended_at(ride["ride_id"]) is not None

    other = (await client.post("/rides", json={"leader_name": "B"})).json()
    await exec_sql("UPDATE rides SET expires_at = now() - interval '1 hour' WHERE id=:i",
                   i=other["ride_id"])
    async with AsyncSessionLocal() as db:
        await mark_expired_rides(db)
    assert await _ended_at(other["ride_id"]) is not None


async def test_retention_deletes_old_ended_rides_with_their_data(client, ride):
    from app.db.session import AsyncSessionLocal, engine
    from app.tasks.expiry_cleanup import purge_old_rides

    member = (await client.post(f"/rides/{ride['ride_id']}/join",
                                json={"display_name": "Ravi"})).json()
    await client.post(f"/rides/{ride['ride_id']}/sync", headers=H(member), json={
        "rider_id": member["rider_id"],
        "points": [{"lat": 1, "lng": 2, "recorded_at": datetime.now(UTC).isoformat()}]})
    active = (await client.post("/rides", json={"leader_name": "Still riding"})).json()
    await client.post(f"/rides/{ride['ride_id']}/end",
                      json={"rider_id": ride["leader_rider_id"]}, headers=H(ride))

    async with AsyncSessionLocal() as db:
        assert await purge_old_rides(db, retention_days=7) == 0  # ended just now: kept
    await exec_sql("UPDATE rides SET ended_at = now() - interval '8 days' WHERE id=:i",
                   i=ride["ride_id"])
    async with AsyncSessionLocal() as db:
        assert await purge_old_rides(db, retention_days=7) == 1

    async with engine.connect() as conn:
        left = {t: (await conn.execute(text(f"SELECT count(*) FROM {t}"))).scalar()
                for t in ("rides", "riders", "locations")}
    assert left == {"rides": 1, "riders": 1, "locations": 0}  # only the active ride remains
    assert (await client.get(f"/rides/{active['ride_id']}", headers=H(active))).status_code == 200


async def test_retention_never_touches_active_rides(client, ride):
    from app.db.session import AsyncSessionLocal
    from app.tasks.expiry_cleanup import purge_old_rides

    await exec_sql("UPDATE rides SET created_at = now() - interval '30 days'")
    async with AsyncSessionLocal() as db:
        assert await purge_old_rides(db, retention_days=7,
                                     now=datetime.now(UTC) + timedelta(days=60)) == 0
