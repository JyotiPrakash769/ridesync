# RideSync REST API

Canonical contract: see [RideSync-v0.1-foundation.md](./RideSync-v0.1-foundation.md) §4.

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/rides` | `{leader_name}` | `{ride_id, leader_rider_id, qr_payload}` |
| GET | `/rides/{ride_id}` | — | `{ride_id, status, threshold_m, leader_rider_id, expires_at, riders: [...]}` |
| POST | `/rides/{ride_id}/join` | `{display_name}` | `{rider_id, ride_id}` |
| PATCH | `/rides/{ride_id}/threshold` | `{rider_id, threshold_m}` (leader only) | `{threshold_m}` |
| POST | `/rides/{ride_id}/sync` | `{rider_id, points: [{lat,lng,recorded_at}]}` | `{accepted: n}` |
| POST | `/rides/{ride_id}/end` | `{rider_id}` (leader only) | `{status: "ended"}` |

Errors: `404` unknown ride, `410` ended/expired ride, `403` leader-only action by a
non-leader, `422` invalid body. `threshold_m` must be one of 100, 300, 500, 1000.
Ride IDs: 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ234567`, case-insensitive on input.
