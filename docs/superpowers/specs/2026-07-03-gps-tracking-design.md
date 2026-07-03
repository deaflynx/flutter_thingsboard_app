# GPS Tracking via Mobile Actions — Design

**Date:** 2026-07-03
**Status:** Approved (brainstorming session with Artem)
**Repos involved:**

| Role | Working repo (CE, branch `feat/gps-tracker`) | Merge target (PE, branch `feat/gps-tracker`) |
|---|---|---|
| Platform UI (ui-ngx) | `/home/artem/projects/thingsboard` | `/home/artem/projects/thingsboard-pe` |
| Mobile app | `/home/artem/projects/mobile/flutter_thingsboard_app` | `/home/artem/projects/mobile/flutter_thingsboard_pe_app` |

Workflow: implement in CE repos first, merge into PE when a PE-only capability
(e.g. solution templates) is needed for testing. No backend (Java) changes in v1.

## Goal

Make phone GPS a first-class, reusable data source for ThingsBoard solutions:

1. **One-shot**: a dashboard mobile action that saves the phone's current
   coordinates to a configurable target entity (attributes or telemetry) —
   declaratively, no hand-edited JS, so solution templates can ship it.
2. **Live tracking**: start/stop continuous tracking from a dashboard action;
   the mobile app streams positions to the target entity as telemetry,
   **including while the app is backgrounded / screen locked** (hard v1
   requirement), with a persistent in-app status bar and session screen.

## Division of labor (chosen approach: hybrid)

- **ThingsBoard owns configuration.** All parameters live in the widget action
  descriptor inside the dashboard JSON — reusable in solution templates,
  no backend schema changes (dashboard JSON is opaque to the server).
- **The web runtime resolves the target entity at click time** (alias /
  current user / attribute indirection → concrete `{entityType, id}`) and
  hands the mobile app a fully-resolved session config via the existing
  `tbMobileHandler(type, ...args)` bridge.
- **The mobile app owns the runtime**: geolocator stream, REST saves via
  `thingsboard_client`, OS background execution, status bar, session screen.
- A separate in-app *configuration* page was rejected for v1 (not
  template-distributable, duplicates dashboard tooling). The in-app session
  screen is runtime UI only.

## ThingsBoard side (ui-ngx)

### One-shot: extend the existing `getLocation` action

Add an optional declarative save block to `GetLocationDescriptor`
(`ui-ngx/src/app/shared/models/widget.models.ts`):

- `saveToEntity?: boolean` (default false → today's behavior, fully
  backward compatible; save happens web-side after the app returns the fix,
  so old mobile apps keep working)
- `targetEntity?: TargetEntityConfig` (shared block, below)
- `saveAs?: 'attributes' | 'timeseries'` (default `attributes`, scope
  `SERVER_SCOPE`)
- `latitudeKey` / `longitudeKey` (defaults `latitude` / `longitude`)
- `includeMetadata?: boolean` — also save `accuracy` and fix timestamp
- `processLocationFunction` stays available for custom post-processing

Execution in `widget.component.ts` `handleMobileAction` (`getLocation` case):
after receiving the result, resolve target, save via
`widgetContext.attributeService.saveEntityAttributes` /
`saveEntityTimeseries`, then invoke `processLocationFunction` if present.

### Live tracking: two new `WidgetMobileActionType` values

`startLiveLocation` and `stopLiveLocation`. New types (not a mode on
`getLocation`) because:

- old app + overloaded `getLocation` would silently do a one-shot while the
  dashboard believes tracking started; an unknown type fails loudly via the
  app's `UnknownAction` fallback;
- one type = one result contract / one editor form is the existing idiom
  (`mapDirection` vs `mapLocation`);
- the action-type dropdown is the natural mode selector, and templates need a
  standalone "Stop tracking" button anyway.

`StartLiveLocationDescriptor`:

- `targetEntity: TargetEntityConfig`
- `saveAs`: telemetry (default) + `mirrorToAttributes?: boolean` so
  attribute-driven map widgets update live
- `latitudeKey` / `longitudeKey` + `includeMetadata` (accuracy, altitude,
  speed, heading as extra keys)
- `accuracy`: `high` | `balanced` | `low` (maps to geolocator accuracy)
- refresh strategy: `distanceFilterMeters?: number`,
  `intervalSeconds?: number`, or both (hybrid = whichever fires first)
- stop condition: manual only | `maxDurationMinutes`
- `writeStatusAttributes?: boolean` (system attributes, below)

`stopLiveLocation` needs no config beyond the common handlers.

Web side sends `tbMobileHandler('startLiveLocation', resolvedConfigJson)`;
the app replies immediately with a launch-style ack
(`{launched: true}` shape), not a location result.

### Shared `TargetEntityConfig`

- `CURRENT_ENTITY` — widget's clicked/active entity (default; today's
  implicit behavior)
- `CURRENT_USER` — logged-in user entity
- `ENTITY_ALIAS` — alias picker, resolved via `widgetContext.aliasController`
- `FROM_ATTRIBUTE` — read an attribute key from current user or current
  entity whose value identifies the target: either a plain UUID + explicit
  entity-type dropdown in config, or a `{"entityType": ..., "id": ...}` JSON
  value

Always resolved web-side at click time to a concrete `{entityType, id}`.
Single target per session in v1 (config resolves to a list internally so
multi-target can be added later).

## Mobile app side (Flutter)

### Tracking session runtime

- `LiveLocationTrackingService` (GetIt singleton) owning at most one active
  session; state exposed as a Riverpod provider (project convention for
  state the router-level UI reacts to).
- Consumes `ILocationService.positionStream()` (existing abstraction over
  geolocator) with configured accuracy/filters; each fix →
  `saveEntityTelemetry` with the device timestamp (enables later offline
  backfill).
- Starting a new session while one is active prompts to replace it.
- New mobile actions: rename/repurpose the existing `getLiveLocation`
  placeholder to `startLiveLocation`, add `stopLiveLocation`.

### Background execution (v1, de-risked first — see Phase 1a)

- Android: geolocator `AndroidSettings.foregroundNotificationConfig`
  (plugin-managed foreground service + persistent notification);
  manifest gets `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`.
- iOS: `UIBackgroundModes` += `location` (both Info-Debug and Info-Release
  plists), `AppleSettings(allowBackgroundLocationUpdates: true,
  showBackgroundLocationIndicator: true, pauseLocationUpdatesAutomatically:
  false)`. While-in-use permission is sufficient when the session starts in
  the foreground.
- Tracking survives backgrounding/screen-lock, not app kill (acceptable v1;
  `gpsLastUpdateTime` staleness covers detection).

### Status bar + session screen

- Persistent tracking bar injected at the `ShellRoute` /
  `RouteHanlderWidget` level so it shows on every page: "Live tracking
  active · last update Xs ago" with **Stop**, **Pause/Resume**, **Hide**
  (collapse to small pill; does not stop tracking). Tap → session screen.
- Session screen: new module `lib/modules/location_tracking/` + go_router
  route. Shows target entity, fix count, last fix (coords/accuracy), elapsed
  time, save errors (e.g. 403), and the same controls.

## System attributes (written by the app on the target entity)

- `gpsActive` (bool) — true on start, false on clean stop; means "user
  intends to be tracking". **Not** a liveness signal (never written if the
  phone dies).
- `gpsLastUpdateTime` (ms epoch) — refreshed with every fix; the actual
  liveness signal. "Stale > 5 min" tables/alarms must key off this, via
  dashboard cell styling or a rule chain (user-space config, no code).
- `gpsTrackedBy` (user email) — who is tracking; useful for fleets.

## Phasing

1. **Phase 1a — background spike (go/no-go gate).** Flutter only, hardcoded
   config, no ThingsBoard changes. Real Android + iOS devices, ~30 min
   locked-screen run streaming fixes and saving telemetry (to the current
   user entity) to validate: foreground service + notification, iOS
   background mode, permission flows, REST saves from background, battery
   behavior. Includes all manifest/plist/permission groundwork.
2. **Phase 1b — one-shot save.** `getLocation` descriptor extension + editor
   UI + web-side resolve-and-save. Flutter: add accuracy/timestamp to the
   location result payload (currently dropped by the result mapper). Ships
   independently.
3. **Phase 1c — live tracking.** New action types in ui-ngx (editor +
   dispatch), Flutter tracking service, status bar, session screen, system
   attributes, background mode from 1a.
4. **Phase 2 — hardening.** Offline buffering with timestamp backfill,
   battery level (`gpsBatteryLevel`) / speed / heading extras, CE→PE merges
   finalized, app-bundle-level config (backend) only if a real need appears.

## Error handling

- Permission denied / services disabled: existing sealed `LocationFix`
  failure cases surface as action errors (one-shot) or session-screen /
  status-bar error states (tracking), with `openAppSettings()` escape hatch.
- REST save failures during tracking: keep tracking, surface last error in
  the session screen; buffering is Phase 2.
- Old app + new action type: `UnknownAction` → explicit error dialog on the
  dashboard (by design).

## Testing

- Dart: unit tests for the tracking service (fake `ILocationService` +
  fake client), widget tests for bar/session screen states.
- ui-ngx: editor form logic tests following existing action-editor specs.
- Manual device matrix for background behavior (Phase 1a protocol above);
  PE solution-template smoke test after CE→PE merge.
