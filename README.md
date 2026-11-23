# RideSync

Real-time biker convoy assistant — Flutter (Android) + FastAPI backend.

A leader creates a ride, riders join by QR or 6-character ride code (display name only, no
accounts), everyone sees live positions on one map, the leader gets "falling behind" alerts, and
GPS points recorded while offline are synced on reconnect.

Monorepo: `mobile/` (Flutter), `backend/` (FastAPI), `docs/` (contracts & design),
`docker-compose.yml` (local Postgres).

### Features (v0.2)

- **Rides:** create (QR + code + share), join (scan / code / link), session restore, leave / end.
- **Live map:** OpenStreetMap (Google Maps switchable), gliding bike markers with heading arrow,
  "You" marker, leader ring + star, 5-minute trails, recenter, rider list with status,
  distance behind leader, speed, last seen.
- **Alerts:** leader-only falling-behind alerts (100/300/500/1000 m) with spoken + vibration
  alerts; regroup point (long-press map or "Regroup at my location"); leader handoff and
  takeover after the leader has been offline 4+ minutes; ride summary at the end.
- **On the road:** foreground-service tracking with the screen off, battery-saver exemption,
  auto-reconnect, offline cache + sync, handlebar (sunlight) mode, dark/light/phone theme.
- **Security & privacy:** per-rider secret tokens on every call, rate limits, ride data only
  visible to that ride's riders, data deleted 7 days after a ride ends, privacy page.

## Prerequisites

| Tool | Version used | Notes |
|------|--------------|-------|
| Python | 3.12 | `py -3.12` on Windows |
| Postgres | 16 | via Docker (`docker compose up -d db`) or a native install |
| Flutter | 3.50 stable | `flutter doctor` should pass Flutter + Android toolchain |
| Android SDK | API 35+ | plus **Command-line Tools** and accepted licences |
| JDK | 17–21 | use Android Studio's bundled JBR: `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"` |

> Windows note: if `flutter` fails on first run with *"The system cannot move the file to a
> different disk drive"*, your `%LOCALAPPDATA%\Pub` is redirected. Set a plain pub cache:
> `setx PUB_CACHE C:\src\pub-cache` and open a new terminal.

## Backend

```powershell
docker compose up -d db                 # from repo root: creates ridesync + ridesync_test
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env                  # edit DATABASE_URL if not using the compose db
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Swagger UI: http://localhost:8000/docs · health: http://localhost:8000/health
- `--host 0.0.0.0` lets a phone on the same Wi-Fi reach your PC (allow port 8000 in the
  Windows firewall).

**Tests** (need the compose `db` running; they use the separate `ridesync_test` database and
migrate it with Alembic):

```powershell
cd backend
pytest -q
```

## Mobile

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
```

### Map provider

The map uses **OpenStreetMap** data by default (`flutter_map`; CARTO dark basemap in dark
mode, OSM standard tiles in light mode) and needs no API key. Google Maps is still built in:
build with `--dart-define=MAP_PROVIDER=google` (CI: set the repo variable `MAP_PROVIDER=google`)
plus a Maps key as below.

> OSM tile servers are community-funded and meant for light use; before many riders use the
> app, switch to Google Maps or a commercial OSM tile provider.

### Google Maps API key (only for MAP_PROVIDER=google)

1. In Google Cloud Console enable **Maps SDK for Android** and create an API key (restrict it to
   the Android app `app.ridesync.ridesync` + your signing SHA-1).
2. Put it in `mobile/android/local.properties` (git-ignored):
   ```
   MAPS_API_KEY=AIza...
   ```
   `android/app/build.gradle.kts` injects it into `AndroidManifest.xml`
   (`com.google.android.geo.API_KEY` → `${MAPS_API_KEY}`). Without a key the map is blank but the
   rest of the app works.

### Pointing the app at your backend

Backend URLs are compile-time `--dart-define`s (`lib/core/config/env.dart`). Defaults target the
Android emulator (`10.0.2.2` = your PC):

```powershell
# Emulator
flutter run
# Physical phone on the same Wi-Fi (use your PC's LAN IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000 --dart-define=WS_BASE_URL=ws://192.168.1.20:8000
```

Debug builds allow plain `http://`/`ws://` (`src/debug/AndroidManifest.xml`); release builds
expect `https://`/`wss://` (e.g. Railway).

### Sideloadable APK

```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://<your-app>.up.railway.app --dart-define=WS_BASE_URL=wss://<your-app>.up.railway.app
```

Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`. Copy it to the phone and install
(allow "Install unknown apps" for your file manager), or `adb install -r <apk>`.
The release build is currently signed with the **debug key** (see `build.gradle.kts`); create a
release keystore before distributing beyond testers.

### CI release APK

`.github/workflows/android-release.yml` builds the APK on GitHub Actions and attaches it to a
GitHub Release whenever a `v*` tag is pushed (or via *Run workflow*). Set repo variables
`API_BASE_URL` / `WS_BASE_URL` and the secret `MAPS_API_KEY` first, otherwise the build targets
the emulator host and has no map key.

```powershell
git tag v0.1.1; git push origin v0.1.1
```

### Deep links / QR

The QR encodes `https://ridesync.app/join/{ride_id}`; `ridesync://join/{ride_id}` is the
custom-scheme fallback. Both intent filters are in `AndroidManifest.xml`. The https link only
opens the app directly after you host `https://ridesync.app/.well-known/assetlinks.json` with
your signing certificate's SHA-256 — template in [docs/assetlinks.json](docs/assetlinks.json).
Until then Android opens it in the browser; the in-app scanner and `ridesync://` links work
regardless. Test from a PC:

```powershell
adb shell am start -a android.intent.action.VIEW -d "ridesync://join/K7Q2MX"
```

## Environment variables

| Variable | Where | Purpose |
|----------|-------|---------|
| `DATABASE_URL` | backend `.env` | Async Postgres URL (`postgresql+asyncpg://...`) |
| `RIDE_TTL_HOURS` | backend `.env` | Ride lifetime from creation (default 12) |
| `CORS_ORIGINS` | backend `.env` | Comma-separated origins (default `*`) |
| `RETENTION_DAYS` | backend `.env` | Delete ended rides after N days (default 7) |
| `PUBLIC_BASE_URL` | backend `.env` | This backend's public URL; QR links become `<url>/join/CODE` |
| `APP_DOWNLOAD_URL` | backend `.env` | Where the join page sends people without the app |
| `ANDROID_CERT_SHA256` | backend `.env` | Signing-cert SHA-256(s); enables `/.well-known/assetlinks.json` |
| `SENTRY_DSN` | backend `.env` / CI secret | Optional crash reporting (off when empty) |
| `TEST_DATABASE_URL` | backend tests | Optional override (default: compose `ridesync_test`) |
| `API_BASE_URL` | mobile `--dart-define` | REST base URL |
| `WS_BASE_URL` | mobile `--dart-define` | WebSocket base URL |
| `MAPS_API_KEY` | `mobile/android/local.properties` | Google Maps SDK key |

## Deploy (Railway)

1. New project → **Add PostgreSQL**.
2. New service from this repo, **root directory `backend`**. Railway's Python builder installs
   `requirements.txt` and runs the `Procfile`:
   ```
   web: alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT
   ```
3. Variables: `DATABASE_URL=${{Postgres.DATABASE_URL}}` (the app adds the asyncpg driver
   itself), `RIDE_TTL_HOURS=12`, `RETENTION_DAYS=7`, `PUBLIC_BASE_URL=https://<your service>`,
   `CORS_ORIGINS=` (empty). `backend/railway.json` sets the `/health` healthcheck.
4. Keep the service at **one instance**: WebSocket rooms and alert state are in memory.
5. Build the APK with the Railway `https://` / `wss://` URLs (above).

Expired rides are ended by an in-process loop every 5 minutes
(`app/tasks/expiry_cleanup.py`); requests never depend on it because every route checks
`expires_at` directly.

## Release signing (once)

`powershell -ExecutionPolicy Bypass -File scripts\setup-release-signing.ps1` creates a keystore in
`%USERPROFILE%\.ridesync-signing` and uploads it as GitHub secrets, so every CI release installs
over the previous one. Back the keystore up. Set the backend's `ANDROID_CERT_SHA256` to its
SHA-256 so join links open the app directly.

## Known limitations

- No accounts: anyone with the ride code can join (that's the design); everything after joining
  needs the rider's secret token.
- Single backend instance only (in-memory WebSocket rooms + alert state; Redis pub/sub needed
  to scale).
- Distance alerts measure straight-line distance to the leader, not along the road; paused while
  the leader is weak/offline.
- Location runs in the main isolate, kept alive by the foreground service. If Android kills the
  app anyway (aggressive OEM battery savers), tracking stops until it is reopened.
- Offline queue holds up to ~10,000 points (≈11 h); oldest are dropped beyond that. Points are
  discarded if the ride ended before they could be synced.
- https App Links need `assetlinks.json` hosted on `ridesync.app` (not set up).
- Release APK is signed with the debug key.
- Android only (no iOS), no voice, crash detection, SOS, hazards, recording or weather.

## Docs

- [Foundation](docs/RideSync-v0.1-foundation.md) — schema, API, WS protocol (with v0.1 additions)
- [API](docs/api.md)
- [WebSocket protocol](docs/websocket-protocol.md)
- [Dark map style](docs/map_style_dark.json)
