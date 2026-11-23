# RideSync

Real-time biker convoy assistant — Flutter (Android) + FastAPI backend.

Monorepo: `mobile/` (Flutter), `backend/` (FastAPI), `docs/` (contracts & design).

## Setup — backend

```bash
cd backend
py -3.12 -m venv .venv

# Windows PowerShell
.\.venv\Scripts\Activate.ps1

pip install -r requirements.txt
copy .env.example .env   # then edit DATABASE_URL
```

Requires Postgres 16. Easiest: from the repo root run `docker compose up -d db`
(creates `ridesync` and `ridesync_test`). Default URL in `.env.example`:

```
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/ridesync
```

Create the DB, then run migrations:

```bash
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open http://localhost:8000/docs for Swagger UI.

Tests (need the compose `db` running): `pytest -q`

## Setup — mobile

```bash
cd mobile
flutter pub get
# Set GOOGLE_MAPS_API_KEY in android/app/src/main/AndroidManifest.xml (or via local.properties)
flutter run
```

## Environment variables

| Variable | Where | Purpose |
|----------|-------|---------|
| `DATABASE_URL` | backend | Async Postgres URL (`postgresql+asyncpg://...`) |
| `RIDE_TTL_HOURS` | backend | Ride expiry TTL (default 12) |
| `CORS_ORIGINS` | backend | Comma-separated origins (default `*`) |
| `API_BASE_URL` | mobile `env.dart` | REST base URL |
| `WS_BASE_URL` | mobile `env.dart` | WebSocket base URL |
| `GOOGLE_MAPS_API_KEY` | mobile / Android | Maps SDK key |

## Running locally

1. Start Postgres and apply Alembic migrations.
2. `uvicorn app.main:app --reload` in `backend/`.
3. Point `mobile/lib/core/config/env.dart` at your machine (use LAN IP for a physical device).
4. `flutter run` in `mobile/`.

## Deploy (Railway)

Backend ships a `Procfile`:

```
web: alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Set `DATABASE_URL`, `RIDE_TTL_HOURS`, and `CORS_ORIGINS` in the Railway service.

## Known limitations (v0.1 scope)

- No user accounts — join via ride ID / QR only.
- In-memory WebSocket rooms (single-instance only).
- Phase 0 is scaffolding only: routes and screens are stubs.
- Offline sync, live map, distance alerts, and FGS logic land in later phases.

## Docs

- [Foundation](docs/RideSync-v0.1-foundation.md) — schema, API, WS protocol
- [API](docs/api.md)
- [WebSocket protocol](docs/websocket-protocol.md)
- [Dark map style](docs/map_style_dark.json)
