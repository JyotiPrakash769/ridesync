# RideSync WebSocket protocol

Canonical contract: see [RideSync-v0.1-foundation.md](./RideSync-v0.1-foundation.md) §5.

**Endpoint:** `/ws/rides/{ride_id}?rider_id={id}`

## Client → Server

- `location_update` — `{type, lat, lng, speed_kph, ts}`
- `heartbeat` — `{type: "heartbeat"}` (refreshes last_seen_at)
- `leave` — `{type: "leave"}` (member leaves for good → `rider_left`)

## Server → Client (broadcast)

- `rider_positions` — full rider list with lat/lng/status
- `distance_alert` — rider beyond threshold
- `rider_joined` / `rider_left`
- `ride_ended`

Status derived from `last_seen_at`: `online` (<15s), `weak` (15–60s), `offline` (>60s).

`rider_positions` is sent on each location_update, on connect, and every 5s per room.
Close codes: `4404` ride not found, `4410` ride ended, `4403` not a rider of this ride — do not
reconnect after these. Client reconnect backoff: 1s, 2s, 5s, 10s (capped).
