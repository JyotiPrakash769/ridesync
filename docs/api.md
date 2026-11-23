# RideSync REST API

Canonical contract: see [RideSync-v0.1-foundation.md](./RideSync-v0.1-foundation.md) §4.

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/rides` | `{leader_name}` | `{ride_id, leader_rider_id, qr_payload}` |
| GET | `/rides/{ride_id}` | — | `{status, threshold_m, riders: [...]}` |
| POST | `/rides/{ride_id}/join` | `{display_name}` | `{rider_id, ride_id}` |
| PATCH | `/rides/{ride_id}/threshold` | `{threshold_m}` (leader only) | `{threshold_m}` |
| POST | `/rides/{ride_id}/sync` | `{rider_id, points: [{lat,lng,recorded_at}]}` | `{accepted: n}` |
| POST | `/rides/{ride_id}/end` | `{rider_id}` (leader only) | `{status: "ended"}` |

Phase 0: routes are mounted and return placeholder stubs only.
