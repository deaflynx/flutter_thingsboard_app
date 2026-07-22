# GPS Live Tracking UX & Persistence (Phase 1d) Design

**Status:** design — pending user review
**Date:** 2026-07-22
**Repos:** Flutter `flutter_thingsboard_app` only (mobile-only; no ui-ngx / wire-protocol changes)
**Predecessor:** Phase 1c — `docs/superpowers/specs/2026-07-03-gps-tracking-design.md`, plan `docs/superpowers/plans/2026-07-03-gps-live-tracking.md`

## Goal

Polish the phase 1c live-tracking experience on the mobile app:

1. Show the tracking **target as a human-friendly entity name** instead of `DEVICE <uuid>`.
2. Replace the debug-only **"GPS tracking spike"** menu entry with a permanent **"Live location tracking"** page.
3. Give that page a useful **idle state**: a persisted summary of the last session plus a **"Start again"** action, or a "nothing tracked" message when there is no history.
4. Polish the **collapsed tracking bar**: a full-width bar with a pulsing "live" icon.

Explicitly **out of scope** (its own later spec): saving GPS to more than one entity (multi-entity tracking), which would change the wire protocol, the tracking service, and the ui-ngx action editor.

## Scope note — app-initiated tracking

Phase 1c starts a session only from a dashboard mobile action. The "Start again" button in this phase lets the app **relaunch a session from a stored config** without a dashboard round-trip. This is a deliberate, small expansion of the model; the config is still exactly what a dashboard action produced earlier.

---

## 1. Friendly entity name

- A Riverpod `FutureProvider.family` keyed by the target `EntityId` resolves the display name via the Dart client, cached so the session page and idle page share a single lookup. (Exact client call — e.g. an entity-info lookup by `entityType`+`id` — to be confirmed in the plan.)
- **Display:** the resolved name (e.g. `My Tracker Device`). While loading or on failure (offline, or the entity was deleted) it falls back to `DEVICE · <first 8 chars of id>`.
- The last successfully resolved name is also written into the persisted record (§3), so the idle page can show a name with no network call.

## 2. Page promotion (replaces the spike)

- **Delete** the phase-1a spike: `lib/modules/location_tracking/presentation/view/live_tracking_spike_page.dart`, the `liveTrackingSpike` route constant + `GoRoute`, and the `kDebugMode`-gated menu entry in `lib/modules/more/more_page.dart`.
- Add a **permanent** (non-debug) "Live location tracking" entry on the More page, in the spot the spike entry occupied, opening the tracking page.
- Rename the route constant `liveTrackingSession` → `liveTracking` (and its path) since the page now covers both the active-session and idle states. Update the bar's `context.push(...)` accordingly.
- New l10n key for the menu title (English source in `lib/l10n/intl_en.arb`).

## 3. Idle state + persistence

### Storage

- New interface `ILiveTrackingStore` with a Hive-backed implementation, registered in GetIt (matching the project's interface + GetIt convention). Holds **one** `LastTrackingRecord` (or none).
- `LiveLocationTrackingService` gains a dependency on `ILiveTrackingStore` and:
  - **On `start(config)`** — writes a record with the raw config JSON, `startedAt`, and (once resolved) the target name; `endReason = interrupted` provisionally, so an app-kill mid-session still leaves a restartable record.
  - **On session end** (`stop` or max-duration — a terminal error *pauses* rather than ends, per phase 1c) — updates the record with `endedAt`, the final `fixCount`/`savedCount`/`saveErrorCount`, last coordinates, `lastError` if any, and the real `endReason`.
- **Cleared on logout** (device-global record; a different user must not see the previous user's last target). Hook into the existing logout/user-changed path.

### Data model

```
LastTrackingRecord {
  configJson: Map<String, dynamic>   // raw wire config, replayed by "Start again"
  targetName: String?                // cached resolved name for offline idle display
  startedAt: DateTime
  endedAt: DateTime?
  fixCount: int
  savedCount: int
  saveErrorCount: int
  lastLat: double?
  lastLng: double?
  lastError: String?                 // last terminal error seen, if any
  endReason: manual | maxDuration | interrupted
}
```

### Page behavior (`LiveTrackingPage`)

- **Active session** → live details as today, with the friendly name in the Target row.
- **Idle with a record** → read-only summary (name, started/ended, counts, last coordinates, end reason) + a **"Start again"** button that calls `service.start(storedConfig)`, with `trackedBy` **re-derived from the current logged-in user** (not the stored email).
- **Idle, no record** → "No active tracking" message.

## 4. Collapsed-bar polish

- The collapsed (hidden) pill becomes a **full-width** `primaryContainer` bar (currently a small centered chip).
- Centered **pulsing icon** while `status == tracking`: an `AnimationController` with `repeat(reverse: true)` fading/scaling the `gps_fixed` icon. While `paused`, show a static `gps_off` icon (no pulse — it is not live).
- Tap still expands the bar (`show()`).
- The collapsed pill becomes a small `HookConsumerWidget` (the file already uses `hooks_riverpod`) so `useAnimationController` drives the pulse; the expanded bar is unchanged.

## Error handling

- Name resolution failure → silent fallback to `DEVICE · <short id>`; never blocks the page.
- Store read/write failure → logged via `TbLogger`, treated as "no record" (page still renders); never crashes tracking.
- "Start again" reuses the phase-1c `start()` path, so location-permission / services failures surface through the existing session error handling (paused + `lastError`).

## Testing

- `ILiveTrackingStore` unit tests: save/read round-trip; start-writes-then-end-updates; clear-on-logout.
- Name-fallback unit test: resolved name vs `DEVICE · <short id>` on failure.
- Widget test for the bar: tracking → `gps_fixed`, paused → `gps_off`, collapsed bar spans full width. The pulse animation itself is not asserted.
- Existing phase-1c service tests must keep passing; the added store dependency is injected via a fake in those tests.

## Out of scope / follow-ups

- Multi-entity tracking (separate spec).
- History of more than one past session (only the single last record is kept).
- Editing tracking parameters from the app (config is replayed verbatim).
