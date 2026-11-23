# RideSync WebSocket protocol

Canonical contract: see [RideSync-v0.1-foundation.md](./RideSync-v0.1-foundation.md) §5.

**Endpoint:** `/ws/rides/{ride_id}?rider_id={id}`

## Client → Server

- `location_update` — `{type, lat, lng, speed_kph, ts}`
- `heartbeat` — `{type: "heartbeat"}`

## Server → Client (broadcast)

- `rider_positions` — full rider list with lat/lng/status
- `distance_alert` — rider beyond threshold
- `rider_joined` / `rider_left`
- `ride_ended`

Status derived from `last_seen_at`: `online` (<15s), `weak` (15–60s), `offline` (>60s).

Phase 0: socket accepts connections and returns a placeholder ack only.
