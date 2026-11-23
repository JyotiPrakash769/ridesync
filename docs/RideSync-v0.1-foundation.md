# RideSync v0.1 — Project Foundation

Monorepo layout: `/mobile` (Flutter), `/backend` (FastAPI), `/docs`. Two separate deployables, one repo, shared docs.

```
ridesync/
├── mobile/
├── backend/
├── docs/
│   ├── api.md
│   └── websocket-protocol.md
├── .gitignore
└── README.md
```

---

## 1. Flutter app structure (`/mobile`)

Feature-first, not layer-first — each feature owns its widgets/state/logic so v0.2 features (voice, crash detection) slot in as new folders without touching existing ones.

```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart                      # MaterialApp, routes, theme (dark, black+yellow)
│   ├── core/
│   │   ├── config/
│   │   │   └── env.dart              # backend base URL, WS URL
│   │   ├── network/
│   │   │   ├── api_client.dart       # dio/http wrapper for REST
│   │   │   └── ws_client.dart        # WebSocket wrapper w/ reconnect+backoff
│   │   ├── storage/
│   │   │   └── local_db.dart         # Hive/SQLite init — offline location queue
│   │   └── location/
│   │       ├── location_service.dart # foreground service + geolocator stream
│   │       └── background_task.dart  # Android foreground service entrypoint
│   ├── models/
│   │   ├── ride.dart
│   │   ├── rider.dart
│   │   └── location_point.dart
│   ├── features/
│   │   ├── ride_create/
│   │   │   ├── create_ride_screen.dart
│   │   │   └── qr_display_widget.dart
│   │   ├── ride_join/
│   │   │   ├── join_ride_screen.dart
│   │   │   └── qr_scanner_widget.dart
│   │   ├── convoy_map/
│   │   │   ├── convoy_map_screen.dart
│   │   │   ├── rider_marker.dart
│   │   │   └── map_controller.dart
│   │   ├── rider_status/
│   │   │   └── rider_status_sheet.dart
│   │   ├── alerts/
│   │   │   ├── distance_alert_banner.dart
│   │   │   └── threshold_selector.dart
│   │   └── offline_sync/
│   │       └── sync_manager.dart     # detects reconnect, flushes queued points
│   └── state/
│       └── ride_session_provider.dart # riverpod/provider — current ride+riders state
├── android/
│   └── app/src/main/AndroidManifest.xml   # ACCESS_BACKGROUND_LOCATION, FGS permissions
├── pubspec.yaml
└── test/
```

**Key packages:** `google_maps_flutter`, `geolocator`, `web_socket_channel`, `dio`, `hive` (or `sqflite`), `qr_flutter` (generate), `mobile_scanner` (read), `flutter_riverpod` (or `provider`), `flutter_foreground_task`.

---

## 2. Backend structure (`/backend`)

```
backend/
├── app/
│   ├── main.py                    # FastAPI app, router mounts, CORS
│   ├── config.py                  # env vars (DATABASE_URL, etc.)
│   ├── db/
│   │   ├── session.py             # async SQLAlchemy engine/session
│   │   └── base.py
│   ├── models/                    # SQLAlchemy ORM
│   │   ├── ride.py
│   │   ├── rider.py
│   │   └── location.py
│   ├── schemas/                   # Pydantic request/response
│   │   ├── ride.py
│   │   ├── rider.py
│   │   └── ws_messages.py
│   ├── api/
│   │   ├── rides.py                # POST /rides, GET /rides/{id}
│   │   └── join.py                 # POST /rides/{id}/join
│   ├── ws/
│   │   ├── connection_manager.py   # in-memory: ride_id -> set[WebSocket]
│   │   └── ride_socket.py          # WS /ws/rides/{id} handler
│   ├── services/
│   │   ├── ride_service.py         # ride ID gen, expiry logic
│   │   ├── distance_service.py     # haversine, threshold check
│   │   └── sync_service.py         # batch offline-point ingestion
│   └── tasks/
│       └── expiry_cleanup.py       # periodic: end rides past TTL
├── alembic/                        # DB migrations
├── requirements.txt
├── Procfile                        # Railway
└── tests/
```

---

## 3. Database schema (PostgreSQL)

```sql
-- rides
CREATE TABLE rides (
    id              CHAR(6) PRIMARY KEY,           -- short human-typeable code
    leader_rider_id UUID,                          -- FK set after leader row exists
    status          VARCHAR(10) NOT NULL DEFAULT 'active', -- active | ended
    threshold_m     INT NOT NULL DEFAULT 500,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL            -- created_at + TTL (e.g. 12h)
);

-- riders (a join-row per person per ride; no user accounts)
CREATE TABLE riders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id         CHAR(6) NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    display_name    VARCHAR(50) NOT NULL,
    role            VARCHAR(10) NOT NULL DEFAULT 'member', -- leader | member
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at    TIMESTAMPTZ,
    last_lat        DOUBLE PRECISION,
    last_lng        DOUBLE PRECISION,
    last_speed_kph  DOUBLE PRECISION,
    is_online       BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE rides
    ADD CONSTRAINT fk_leader FOREIGN KEY (leader_rider_id) REFERENCES riders(id);

-- locations: append-only backlog, mainly for offline-sync batches
CREATE TABLE locations (
    id              BIGSERIAL PRIMARY KEY,
    rider_id        UUID NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
    lat             DOUBLE PRECISION NOT NULL,
    lng             DOUBLE PRECISION NOT NULL,
    recorded_at     TIMESTAMPTZ NOT NULL,   -- client-side timestamp (may be in the past)
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_locations_rider_time ON locations(rider_id, recorded_at);
CREATE INDEX idx_riders_ride ON riders(ride_id);
```

`rides.id` as a 6-char code (e.g. base32, ambiguous chars stripped) doubles as the human-typeable fallback and the QR payload. Live position (`riders.last_lat/last_lng`) is what the map reads; `locations` is the durable trail, mainly populated by offline-sync batches and periodic snapshots — no need to write every 3–5s WS tick to Postgres.

---

## 4. REST API

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/rides` | `{leader_name}` | `{ride_id, leader_rider_id, qr_payload}` |
| GET | `/rides/{ride_id}` | — | `{ride_id, status, threshold_m, leader_rider_id, expires_at, riders: [...]}` |
| POST | `/rides/{ride_id}/join` | `{display_name}` | `{rider_id, ride_id}` |
| PATCH | `/rides/{ride_id}/threshold` | `{rider_id, threshold_m}` (leader only; threshold_m ∈ 100/300/500/1000) | `{threshold_m}` |
| POST | `/rides/{ride_id}/sync` | `{rider_id, points: [{lat,lng,recorded_at}]}` | `{accepted: n}` |
| POST | `/rides/{ride_id}/end` | `{rider_id}` (leader only) | `{status: "ended"}` |

Each `riders[]` entry has the same shape as a `rider_positions` entry (§5).
`ride_id` is case-insensitive on input. Errors: `404` ride doesn't exist, `410` ride ended or
expired (checked against `expires_at` directly), `403` leader-only action by a non-leader,
`422` validation. `rider_id` was added to the PATCH threshold body (v0.1 has no auth, so the
leader is identified the same way as for `/end`).

`qr_payload` = deep link, e.g. `https://ridesync.app/join/{ride_id}` (Android App Link) with a `ridesync://join/{ride_id}` custom-scheme fallback.

---

## 5. WebSocket protocol (`/ws/rides/{ride_id}?rider_id={id}`)

**Client → Server**

```json
{"type": "location_update", "lat": 20.296, "lng": 85.824, "speed_kph": 42.5, "ts": "2026-07-28T10:15:03Z"}
```
```json
{"type": "heartbeat"}
```
```json
{"type": "leave"}
```
`leave` (v0.1 addition) is sent by a member who taps "Leave ride": the server deletes the rider
row and broadcasts `rider_left`. A dropped socket never removes or offlines a rider. The leader
ends the ride via `POST /rides/{id}/end` instead.

**Server → Client (broadcast to all riders in the room)**

```json
{
  "type": "rider_positions",
  "riders": [
    {"rider_id": "...", "name": "Pranit", "role": "member", "lat": 20.296, "lng": 85.824,
     "speed_kph": 42.5, "last_seen_at": "...", "status": "online"}
  ]
}
```
```json
{"type": "distance_alert", "rider_id": "...", "name": "Pranit", "distance_m": 510}
```
```json
{"type": "rider_joined", "rider_id": "...", "name": "Pranit", "role": "member"}
```
```json
{"type": "rider_left", "rider_id": "..."}
```
```json
{"type": "ride_ended"}
```

`status` is derived server-side from `last_seen_at` gap: `online` (<15s), `weak` (15–60s), `offline` (>60s) — maps to the green/yellow/red dot in the status list.

`rider_positions` is broadcast on every `location_update`, when a rider connects, and every 5s
per active room (so silent riders visibly go weak → offline). `last_seen_at` uses the server
clock; the client `ts` is accepted but not trusted. `heartbeat` refreshes `last_seen_at` only.
`rider_joined` is sent when `POST /join` succeeds; `ride_ended` when the leader ends the ride or
it expires, followed by closing every socket in the room.

Close codes (v0.1 addition): `4404` ride not found, `4410` ride ended/expired, `4403` rider not
in this ride. Clients must not reconnect after these; any other close → reconnect with backoff.

---

## 6. Environment variables

```
# backend/.env
DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/ridesync
RIDE_TTL_HOURS=12
CORS_ORIGINS=*

# mobile — core/config/env.dart
API_BASE_URL=https://ridesync-backend.up.railway.app
WS_BASE_URL=wss://ridesync-backend.up.railway.app
GOOGLE_MAPS_API_KEY=...
```

---

## 7. Repo hygiene

```
.gitignore essentials:
  mobile: build/, .dart_tool/, android/local.properties, *.g.dart (if not committing generated code)
  backend: __pycache__/, .venv/, .env, *.db

README.md sections: setup (backend), setup (mobile), running locally,
env vars required, deploy (Railway), known limitations (v0.1 scope).
```

---

## Notes / decisions baked in

- **Ride ID doubles as room key and QR payload** — no separate "room" concept needed.
- **No `users` table** — `riders` rows are ephemeral, scoped to one ride, deleted via `ON DELETE CASCADE` when a ride is cleaned up.
- **`expires_at`** is set at creation (`created_at + RIDE_TTL_HOURS`); a periodic task (`tasks/expiry_cleanup.py`) marks rides `ended` past that point — answers the "what happens when the leader closes the app" question by *not* depending on the leader's connection state at all. A ride stays alive until it expires or the leader explicitly ends it.
- **In-memory `ConnectionManager`** is fine for v0.1 single-instance deploy; if you ever scale the backend horizontally, this needs to move to Redis pub/sub — not needed now, just flagging it so it doesn't surprise you later.
