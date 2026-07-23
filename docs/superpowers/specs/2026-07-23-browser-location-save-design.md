# Browser-side Location Save (widget action) — Design Spec

**Status:** Design approved, ready for implementation planning.
**Repo:** `thingsboard` / `ui-ngx` (Angular frontend). **This feature does not touch the mobile Flutter app or the backend** — it is a new frontend widget action built on existing telemetry-save HTTP APIs.
**Origin:** Follow-up carried over from `2026-07-22-gps-live-tracking-ux-design.md` ("Out of scope / follow-ups → Browser-side location save").

## Goal

Add a new **generic** widget action, `saveBrowserLocation`, that reads the browser's current geolocation once (on user trigger) and writes the coordinates (and browser-meaningful metrics) to a configurable target entity via the existing attribute/telemetry save APIs.

## Scope

- **In:** a new `WidgetActionType.saveBrowserLocation` offered on any widget action; its config editor; runtime dispatch + geolocation capture + save; localized toasts.
- **Out:** map-widget-specific placement (this is not `placeMapItem`), continuous/watch tracking, multi-entity save, mobile app, backend/enum changes. See "Out of scope" below.

## Architecture

A new member of the existing `WidgetActionType` enum (`ui-ngx/src/app/shared/models/widget.models.ts:611-621`), handled generically like `custom` / `mobileAction` (i.e. **kept in** the generic `widgetActionTypes` list, unlike `placeMapItem` which is filtered out at `widget.models.ts:669-670`). No map or backend involvement.

Three units, each independently understandable:

1. **Config model + editor** — a `saveBrowserLocation` config object on `WidgetAction`, plus an editor sub-form under `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/`.
2. **Geolocation helper** — a small, pure-ish service wrapping `navigator.geolocation.getCurrentPosition` as a Promise/Observable with a secure-context guard and typed error mapping. Nothing like this exists in the codebase today (greenfield).
3. **Dispatch handler** — a `saveBrowserLocation(...)` method wired into the action switch in `ui-ngx/src/app/modules/home/components/widget/widget.component.ts` (~`:1160-1228`), reusing the existing target-entity resolver and save path.

## Capture model

**One-shot on trigger.** A single `navigator.geolocation.getCurrentPosition(success, error, options)` per action invocation, with `options = { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }`. No `watchPosition`, no retry loop in v1.

## Target-entity model (reuse existing)

Reuse the mobile-action target model verbatim — the four modes already implemented by `resolveMobileActionTargetEntity(...)` at `widget.component.ts:1573-1621` (backed by `MobileActionTargetEntityType`):

- **currentEntity** — the widget's active entity, via `getActiveEntityInfo()` (`widget.component.ts:1910-1922`).
- **currentUser** — `{ entityType: USER, id: authUser.userId }`, via `currentUserEntityId()` (`:1623-1626`).
- **entityAlias** — resolved through `AliasController` (`getEntityAliasId` → `resolveSingleEntityInfo`).
- **fromAttribute** — an `{entityType, id}` parsed from an attribute on the current entity or current user (`parseTargetEntityAttributeValue`, `:1628+`).

The action config carries the same target descriptor shape the mobile action uses (target type + optional alias name + optional attribute source/key). The dispatch handler resolves it with the existing resolver rather than a parallel implementation.

## Save destination (configurable data keys)

Coordinates and metrics are written through configurable **data keys**, mirroring how map widgets define `xKey`/`yKey` and how `TbMap.saveItemData` (`map.ts:1303-1340`) batches by key type.

**Required keys** (always saved):

| Field | Default key name | Source |
|---|---|---|
| latitude | `latitude` | `coords.latitude` (degrees) |
| longitude | `longitude` | `coords.longitude` (degrees) |

**Optional keys** (v1 — each has a key-name input in the editor; leaving a name blank means "don't save that field"; browser-meaningful `GeolocationCoordinates` / `GeolocationPosition` fields):

| Field | Default key name | Source | Typical availability |
|---|---|---|---|
| accuracy | `accuracy` | `coords.accuracy` (m, horizontal) | always present |
| altitude | `altitude` | `coords.altitude` (m) | often null on non-GPS/desktop |
| altitudeAccuracy | `altitudeAccuracy` | `coords.altitudeAccuracy` (m) | null when altitude null |
| heading | `heading` | `coords.heading` (deg) | null/NaN when stationary or desktop |
| speed | `speed` | `coords.speed` (m/s) | null when stationary or desktop |
| timestamp | `locationTimestamp` | `position.timestamp` (epoch ms) | always present |

**Save-as (reused, single setting for all keys):** one `saveAs` selector — **Attributes (server scope)** or **Time series** — applied to every saved key, reusing the existing `MobileActionSaveAs` enum and its translations (the same control the mobile "Save location to entity" action uses). Attributes are written to `SERVER_SCOPE`; time series to `LATEST_TELEMETRY`. Per-key type/scope is intentionally **not** offered (YAGNI; matches the existing mobile action).

**Null-handling (important):** `AttributeService.saveEntityAttributes` treats a `null` value as a **delete** of that key (`attribute.service.ts:71-96`). Therefore an optional metric whose captured value is `null`/`undefined`/`NaN` (e.g. `altitude`/`heading`/`speed` on a desktop), or whose key name is blank, MUST be **omitted from the save payload entirely**, never sent as null — otherwise a stale attribute/series would be silently deleted. Required latitude/longitude are always numeric and always saved.

**Save mechanism:** collect the enabled, non-null fields into one payload and call, per `saveAs`:
- `AttributeService.saveEntityAttributes(entityId, scope, AttributeData[])` (`attribute.service.ts:71`) for attribute keys, and
- `AttributeService.saveEntityTimeseries(entityId, LatestTelemetry.LATEST_TELEMETRY, AttributeData[])` (`:98`) for timeseries keys.

## Runtime flow

Dispatched from the action switch in `widget.component.ts`:

1. **Secure-context guard:** if `!window.isSecureContext || !navigator.geolocation` → show the insecure-context error toast and stop (the Geolocation API is unavailable on non-HTTPS origins).
2. `getCurrentPosition(success, error, { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 })`.
3. **On success:** resolve the target entity (existing resolver) → build the attribute/timeseries batches from the enabled, non-null fields → save → **success toast**. If the target entity cannot be resolved, show the save-failed (or a target-unresolved) toast.
4. **On geolocation error:** map `error.code` to a specific localized toast: `PERMISSION_DENIED`, `POSITION_UNAVAILABLE`, `TIMEOUT`.
5. **On save (HTTP) error:** save-failed toast.

## Feedback (toasts only)

Localized strings added to `ui-ngx/src/assets/locale/locale.constant-en_US.json` (English only; other locales fall back to English per repo convention). Distinct messages for: success, insecure-context, permission-denied, position-unavailable, timeout, save-failed. **No** post-save custom-function hook (unlike `placeMapItem`'s `afterPlaceItemCallback`).

## Files touched (all in `thingsboard/ui-ngx`)

- `src/app/shared/models/widget.models.ts` — add `WidgetActionType.saveBrowserLocation`, its `widgetActionTypeTranslationMap` entry, and the config interface fields on `WidgetAction`; ensure it stays in the generic `widgetActionTypes` list.
- `src/app/modules/home/components/widget/widget.component.ts` — add the dispatch `case` and a `saveBrowserLocation(...)` handler; reuse `resolveMobileActionTargetEntity`, `getActiveEntityInfo`, `currentUserEntityId`.
- Action editor components under `src/app/modules/home/components/widget/lib/settings/common/action/` (e.g. `widget-action.component.*`) — a config sub-form: target-entity selector (reuse the mobile-action target sub-form/component if one exists) + required latitude/longitude key rows + optional metric key rows.
- `src/assets/locale/locale.constant-en_US.json` — new i18n keys.
- New geolocation helper (e.g. `src/app/core/services/browser-geolocation.service.ts`) — wraps `getCurrentPosition` + secure-context guard + typed error mapping; the error→message mapping and the field→key batching are written as pure functions so they are inspectable and (if the repo ever adds coverage) unit-testable.

## Out of scope / follow-ups

- Continuous / `watchPosition` tracking with a stop control.
- Multi-entity save (write one capture to several targets).
- Per-key advanced telemetry options beyond attribute-scope / latest-timeseries.
- Any mobile-app or backend change.

## Global constraints (for the implementation plan)

- Repo `thingsboard`, branch `feat/gps-tracker` (same branch the phase-1d Task 1 bundle-page change lives on). Leave the pre-existing uncommitted `ui-ngx/proxy.conf.js` change alone.
- Conventional Commits; **no** `Co-Authored-By` lines.
- ui-ngx verification: `cd ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json` must exit 0 (only pre-existing photoswipe errors acceptable). Follow the repo convention of **no new test scaffolding**.
- User-facing strings localized in `locale.constant-en_US.json` only.
