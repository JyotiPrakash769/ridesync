# RideSync — Agent Instructions

## Project
Real-time biker convoy assistant. Flutter (Android) + FastAPI backend.
Full schema, API contract, and WebSocket protocol: @docs/RideSync-v0.1-foundation.md
Map styling: @docs/map_style_dark.json

## Ground rules
- We are building this in phases (Phase 0–4). Only implement what the current
  prompt asks for. Do not get ahead and implement later-phase features even
  if they seem like an obvious next step — stop and ask instead.
- Do not deviate from the schema, API contract, or WebSocket message format in
  the foundation doc without asking first. If something in the doc is
  ambiguous or you think it's wrong, say so — don't silently improvise.
- After finishing a phase, tell me exactly how to verify it runs (commands to
  run, what "working" looks like) — don't just say it's done.
- Prefer asking a clarifying question over guessing on anything touching:
  ride/room lifecycle, permission handling (Android location), or WebSocket
  reconnect behavior — these are the areas most likely to have a wrong
  assumption baked in silently.

## Stack
Flutter (mobile/), FastAPI + SQLAlchemy async + Alembic (backend/), Postgres,
WebSockets, Google Maps SDK, Railway deploy target. No auth in v0.1 — ride
joined via ride ID / QR only.

## Design tokens
Material 3: `ColorScheme.fromSeed(#FFC72C)`, dark by default, light supported
(mobile/lib/core/theme/app_theme.dart). Widgets use colorScheme/textTheme
tokens only — no hex except the map style JSON and the status colors:
online #5DCAA5 / weak #EF9F27 / offline #E24B4A (always paired with a label).
M3 default type scale; `FontFeature.tabularFigures()` on distances, speeds,
timers. 56 dp minimum touch targets. (Replaces the earlier Oswald /
JetBrains Mono / fixed-surface tokens.)

## Tooling notes
In this Flutter version Material is imported from
`package:material_ui/material_ui.dart`, not `flutter/material.dart`.
