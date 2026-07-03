# Design: Reusable Location Service

**Date:** 2026-06-01
**Status:** Approved — ready for implementation planning
**Author:** ababak (with Claude)

## Background / Motivation

There is no concrete location feature requested yet. The goal of this work is
**architectural**: establish a clean, reusable abstraction for accessing the
phone's GPS so future features (device geo-tagging, "track me on a map" screens,
geofence checks, etc.) can build on a single, well-tested foundation instead of
re-implementing the fiddly permission/service-enabled handling each time.

### What already exists

Location access is **not** greenfield — but it is trapped in one place:

- `geolocator: ^12.0.0` (+ `geolocator_android`) and `permission_handler: ^11.3.1`
  are already in `pubspec.yaml`.
- A single one-shot consumer exists: `GetLocationAction`
  (`lib/utils/services/mobile_actions/actions/get_location_action.dart`). It is
  the **only** place `geolocator` is called in the entire codebase.
- It is triggered exclusively by the ThingsBoard dashboard WebView: a dashboard
  widget calls JS `tbMobileHandler(['getLocation', ...])` →
  `WidgetActionHandler.handleWidgetMobileAction` → `GetLocationAction.execute()`
  → returns lat/lng JSON back into the dashboard. It is a sibling of
  `takePhoto`, `scanQrCode`, `makePhoneCall`, etc.
- Platform permissions are **already declared**: Android
  `ACCESS_FINE_LOCATION` (maxSdk 35) + `ACCESS_COARSE_LOCATION`; iOS
  `NSLocation*UsageDescription` strings.

### The gap

The permission / service-enabled / `denied` vs `deniedForever` logic lives
inline inside `GetLocationAction`. There is no shared service, so any future
location consumer would have to duplicate that logic, and there is no streaming
capability for live-update screens.

## Goals

- A single cross-cutting `ILocationService` that owns all `geolocator` usage.
- Support **on-demand** position and a **foreground live stream** from day one
  (the stream is a cheap extension riding on the same permission code).
- A typed, exhaustive result model so callers must handle every failure state
  with the appropriate UX response.
- Refactor the existing `GetLocationAction` to delegate to the service, making
  the service immediately exercised by a real caller (not speculative) and
  giving a single source of truth for the permission dance.
- Be fully unit-testable without a device.

## Non-goals (YAGNI)

- **Background / while-closed tracking** — no use case; high cost (Android
  foreground service + `ACCESS_BACKGROUND_LOCATION`, iOS background mode + App
  Store review). The interface is shaped so this can be added later without a
  breaking change.
- **Maps or any UI** — none needed yet.
- **A Riverpod provider wrapper** — deferred until a reactive screen needs it;
  trivial to add a `@riverpod` wrapper over the GetIt singleton at that point.
- **Last-known-position caching** — add only when a caller wants it.

## Architecture & placement

A single cross-cutting service registered globally in GetIt, exactly like
`IFirebaseService` / `IEndpointService`. No feature module and no `presentation/`
layer (there is no UI use case). All `geolocator` usage is contained behind this
one interface — callers never import the plugin.

```
lib/utils/services/location/
├── i_location_service.dart          # interface
├── location_service.dart            # implementation (only file that imports geolocator)
└── model/
    ├── location_fix.dart            # sealed result (freezed)
    └── geo_position.dart            # plugin-agnostic position model (freezed)
```

Registration in `lib/locator.dart`:

```dart
..registerLazySingleton<ILocationService>(
  () => LocationService(logger: getIt()),
)
```

## Interface

```dart
abstract interface class ILocationService {
  /// One-shot fix. Handles the full permission/service-enabled dance internally.
  Future<LocationFix> getCurrentPosition();

  /// Foreground live updates. Pre-checks availability, then relays updates.
  /// Subscribers cancel via StreamSubscription (Riverpod/Bloc disposal handles this).
  Stream<LocationFix> positionStream({double distanceFilterMeters = 0});

  /// Escape hatches for the UI to resolve failure states.
  Future<bool> openLocationSettings();   // for ServicesDisabled
  Future<bool> openAppSettings();         // for PermissionDeniedForever
}
```

## Data model — sealed result (freezed)

Naming: there is already a `LocationResult` (the WebView JSON DTO in
`mobile_actions/results/`). To avoid collision, the new sealed type is
**`LocationFix`**.

```dart
@freezed
sealed class LocationFix with _$LocationFix {
  const factory LocationFix.success(GeoPosition position) = LocationSuccess;
  const factory LocationFix.servicesDisabled()            = LocationServicesDisabled;
  const factory LocationFix.permissionDenied()            = LocationPermissionDenied;
  const factory LocationFix.permissionDeniedForever()     = LocationPermissionDeniedForever;
  const factory LocationFix.error(String message)         = LocationFixError;
}

@freezed
class GeoPosition with _$GeoPosition {
  const factory GeoPosition({
    required double latitude,
    required double longitude,
    required double accuracy,
    DateTime? timestamp,
  }) = _GeoPosition;
}
```

Callers `switch` over `LocationFix`; Dart 3 exhaustive pattern matching forces
handling of every failure state. `GeoPosition` is our own model so geolocator's
`Position` type never leaks past the service boundary.

Each failure state maps to a distinct caller UX:

| State | Meaning | Typical caller response |
|---|---|---|
| `LocationSuccess` | got a fix | use `position` |
| `LocationServicesDisabled` | OS location is off | prompt + `openLocationSettings()` |
| `LocationPermissionDenied` | app permission denied (re-askable) | inform / re-request later |
| `LocationPermissionDeniedForever` | denied permanently | deep-link via `openAppSettings()` |
| `LocationFixError` | unexpected platform error | show message, log |

## Data flow

### On-demand (the refactor)

`GetLocationAction` shrinks to a thin mapper; the permission logic now lives in
the service. The WebView bridge above it (`tbMobileHandler` →
`WidgetActionHandler` → `execute`) is untouched.

```dart
final fix = await getIt<ILocationService>().getCurrentPosition();
return switch (fix) {
  LocationSuccess(:final position) =>
      WidgetMobileActionResult.success(
        LocationResult(position.latitude, position.longitude),
      ),
  LocationServicesDisabled()        => /* openLocationSettings + error string */,
  LocationPermissionDenied()        => /* error string */,
  LocationPermissionDeniedForever() => /* error string */,
  LocationFixError(:final message)  => /* error string */,
};
```

### Stream

`positionStream` does an availability pre-check; on failure it emits a single
terminal `LocationFix` (e.g. `permissionDenied`) then closes; on success it
relays each geolocator position update as `LocationFix.success(...)`. This keeps
the result model consistent between the one-shot and streaming paths, and lets
stream subscribers observe a mid-stream permission/service loss.

## Testability

`geolocator`'s public API is static (`Geolocator.getCurrentPosition()`), which
is normally unmockable. The plugin exposes an injectable
`GeolocatorPlatform.instance`, so the service takes it as an optional dependency:

```dart
LocationService({required TbLogger logger, GeolocatorPlatform? geolocator})
  : _geolocator = geolocator ?? GeolocatorPlatform.instance;
```

Tests inject a mock `GeolocatorPlatform` (mocktail) and assert each branch maps
to the correct `LocationFix`:

- location services off → `LocationServicesDisabled`
- `LocationPermission.denied` → `LocationPermissionDenied`
- `LocationPermission.deniedForever` → `LocationPermissionDeniedForever`
- valid `Position` → `LocationSuccess` with mapped `GeoPosition`
- thrown exception → `LocationFixError`

Fully unit-testable with no device.

## Implementation outline

1. Add `geolocator_platform_interface` usage is already transitively available
   via `geolocator`; confirm `GeolocatorPlatform` import path.
2. Create `model/geo_position.dart` and `model/location_fix.dart` (freezed),
   run `build_runner`.
3. Create `i_location_service.dart` and `location_service.dart` implementing the
   permission/service-enabled flow and mapping to `LocationFix`.
4. Register `ILocationService` as a lazy singleton in `lib/locator.dart`.
5. Refactor `GetLocationAction` to delegate to `getIt<ILocationService>()` and
   map `LocationFix` to its existing `WidgetMobileActionResult` outputs.
6. Add unit tests for `LocationService` using a mocked `GeolocatorPlatform`.
7. `flutter analyze` + `dart format` the changed files.

## Open questions

None blocking. Accuracy level is fixed at `high` internally for now (matching
current `GetLocationAction` behavior); a parameter can be added later without a
breaking change.
