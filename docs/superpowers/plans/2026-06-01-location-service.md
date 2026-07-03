# Location Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable, fully-tested `ILocationService` that owns all GPS access behind one interface, and refactor the existing `GetLocationAction` to delegate to it.

**Architecture:** A single cross-cutting GetIt lazy-singleton service (like `IFirebaseService`). It wraps geolocator's injectable `GeolocatorPlatform` (so it is unit-testable with no device), supports a one-shot fix and a foreground live stream, and reports outcomes via an exhaustive sealed `LocationFix` type. Background tracking and UI are explicitly out of scope.

**Tech Stack:** Dart 3 sealed classes + exhaustive `switch`, freezed 3.x (for the `GeoPosition` data model), `geolocator: ^12.0.0` (`GeolocatorPlatform`), GetIt, mocktail + flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-01-location-service-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/utils/services/location/model/geo_position.dart` | Plugin-agnostic immutable position (freezed). Keeps geolocator's `Position` out of callers. |
| `lib/utils/services/location/model/location_fix.dart` | Sealed result union — `LocationSuccess` / `LocationServicesDisabled` / `LocationPermissionDenied` / `LocationPermissionDeniedForever` / `LocationFixError`. |
| `lib/utils/services/location/i_location_service.dart` | The interface callers depend on. |
| `lib/utils/services/location/location_service.dart` | Implementation; the ONLY file importing geolocator. |
| `lib/locator.dart` | Register `ILocationService` as a lazy singleton (modify). |
| `lib/utils/services/mobile_actions/actions/get_location_action.dart` | Refactor to delegate to `ILocationService` (modify). |
| `test/utils/services/location/location_service_test.dart` | Unit tests with a mocked `GeolocatorPlatform`. |

**Convention notes (verified against the codebase):**
- `LocationFix` is a **plain Dart `sealed class`** (matching the project's state unions like `lib/modules/alarm/presentation/bloc/alarm_types/alarm_types_state.dart`), NOT a freezed union. Dart 3's exhaustive `switch` gives the compiler-enforced handling the spec wants, with no codegen. The spec sketched this as "freezed sealed"; a plain sealed class is the idiomatic equivalent here.
- `GeoPosition` IS freezed `abstract class` (matching `lib/utils/services/device_profile/model/cached_device_profile.dart`).
- `getIt` is defined in `lib/locator.dart:34`; `TbLogger` is registered at `lib/locator.dart:45`, so `getIt()` resolves it.
- `GeolocatorPlatform` is exported by `package:geolocator/geolocator.dart`. Its instance methods take `locationSettings:` (NOT the static `desiredAccuracy:`).

**Intentional behavior change:** the current `GetLocationAction._checkService()` auto-opens the OS location settings and re-checks in a loop when services are off. The refactor drops that loop — the service simply reports `LocationServicesDisabled`, and the action returns the same `'Location services are disabled.'` error string it returns today. This matches the spec's "caller decides" model and removes a hidden blocking loop. The error strings returned to the dashboard WebView are preserved exactly.

---

## Task 1: `GeoPosition` model (freezed)

**Files:**
- Create: `lib/utils/services/location/model/geo_position.dart`
- Create: `test/utils/services/location/geo_position_test.dart`
- Generated: `lib/utils/services/location/model/geo_position.freezed.dart` (via build_runner)

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/location/geo_position_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';

void main() {
  test('GeoPosition value equality holds for identical fields', () {
    final ts = DateTime.fromMillisecondsSinceEpoch(1000);
    final a = GeoPosition(
      latitude: 1.5,
      longitude: 2.5,
      accuracy: 3.0,
      timestamp: ts,
    );
    final b = GeoPosition(
      latitude: 1.5,
      longitude: 2.5,
      accuracy: 3.0,
      timestamp: ts,
    );

    expect(a, equals(b));
    expect(a.latitude, 1.5);
    expect(a.longitude, 2.5);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/services/location/geo_position_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `GeoPosition` undefined (file not created yet).

- [ ] **Step 3: Create the model**

Create `lib/utils/services/location/model/geo_position.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'geo_position.freezed.dart';

/// Plugin-agnostic GPS position. Keeps `package:geolocator`'s `Position`
/// type from leaking past the location service boundary.
@freezed
abstract class GeoPosition with _$GeoPosition {
  const factory GeoPosition({
    required double latitude,
    required double longitude,
    required double accuracy,
    DateTime? timestamp,
  }) = _GeoPosition;
}
```

- [ ] **Step 4: Run code generation**

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: generates `geo_position.freezed.dart`, exits 0.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/utils/services/location/geo_position_test.dart`
Expected: PASS.

- [ ] **Step 6: Format & commit**

```bash
dart format lib/utils/services/location/model/geo_position.dart test/utils/services/location/geo_position_test.dart
git add lib/utils/services/location/model/geo_position.dart lib/utils/services/location/model/geo_position.freezed.dart test/utils/services/location/geo_position_test.dart
git commit -m "feat(location): add GeoPosition model"
```

---

## Task 2: `LocationFix` sealed result

**Files:**
- Create: `lib/utils/services/location/model/location_fix.dart`
- Create: `test/utils/services/location/location_fix_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/location/location_fix_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';

String describe(LocationFix fix) => switch (fix) {
      LocationSuccess(:final position) => 'ok:${position.latitude}',
      LocationServicesDisabled() => 'services-off',
      LocationPermissionDenied() => 'denied',
      LocationPermissionDeniedForever() => 'denied-forever',
      LocationFixError(:final message) => 'error:$message',
    };

void main() {
  test('every LocationFix variant is matched exhaustively', () {
    expect(
      describe(
        const LocationSuccess(
          GeoPosition(latitude: 10, longitude: 20, accuracy: 1),
        ),
      ),
      'ok:10.0',
    );
    expect(describe(const LocationServicesDisabled()), 'services-off');
    expect(describe(const LocationPermissionDenied()), 'denied');
    expect(describe(const LocationPermissionDeniedForever()), 'denied-forever');
    expect(describe(const LocationFixError('boom')), 'error:boom');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/services/location/location_fix_test.dart`
Expected: FAIL — `LocationFix` and variants undefined.

- [ ] **Step 3: Create the sealed class**

Create `lib/utils/services/location/model/location_fix.dart`:

```dart
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';

/// Outcome of a location request. Exhaustively matched with `switch`, so every
/// caller is forced by the compiler to handle each failure mode.
sealed class LocationFix {
  const LocationFix();
}

/// A position was obtained.
final class LocationSuccess extends LocationFix {
  const LocationSuccess(this.position);

  final GeoPosition position;
}

/// The OS location services are turned off. Caller may prompt the user and
/// call [ILocationService.openLocationSettings].
final class LocationServicesDisabled extends LocationFix {
  const LocationServicesDisabled();
}

/// Permission was denied but can be requested again later.
final class LocationPermissionDenied extends LocationFix {
  const LocationPermissionDenied();
}

/// Permission was permanently denied. Caller must deep-link via
/// [ILocationService.openAppSettings].
final class LocationPermissionDeniedForever extends LocationFix {
  const LocationPermissionDeniedForever();
}

/// An unexpected platform error occurred.
final class LocationFixError extends LocationFix {
  const LocationFixError(this.message);

  final String message;
}
```

> Note: the doc-comment references to `ILocationService` resolve once Task 3 lands; they are comments only and do not affect compilation.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/utils/services/location/location_fix_test.dart`
Expected: PASS.

- [ ] **Step 5: Format & commit**

```bash
dart format lib/utils/services/location/model/location_fix.dart test/utils/services/location/location_fix_test.dart
git add lib/utils/services/location/model/location_fix.dart test/utils/services/location/location_fix_test.dart
git commit -m "feat(location): add LocationFix sealed result"
```

---

## Task 3: `ILocationService` interface

**Files:**
- Create: `lib/utils/services/location/i_location_service.dart`

(No test — interface declaration only; it is exercised through Task 4.)

- [ ] **Step 1: Create the interface**

Create `lib/utils/services/location/i_location_service.dart`:

```dart
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';

/// Single entry point for GPS access across the app. Implementations own all
/// permission / service-enabled handling so callers never touch the geolocator
/// plugin directly.
abstract interface class ILocationService {
  /// Resolves a single current position, performing the full permission and
  /// service-enabled checks internally.
  Future<LocationFix> getCurrentPosition();

  /// Foreground live position updates. Pre-checks availability, then relays
  /// each update as a [LocationSuccess]. Emits a terminal failure [LocationFix]
  /// (and stops) if location is unavailable. Subscribers must cancel their
  /// [StreamSubscription] when done (Riverpod/Bloc disposal handles this).
  Stream<LocationFix> positionStream({double distanceFilterMeters = 0});

  /// Opens the OS location settings screen. Returns true if it was opened.
  Future<bool> openLocationSettings();

  /// Opens this app's settings screen (for permanently-denied permission).
  Future<bool> openAppSettings();
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/utils/services/location/i_location_service.dart`
Expected: No issues.

- [ ] **Step 3: Format & commit**

```bash
dart format lib/utils/services/location/i_location_service.dart
git add lib/utils/services/location/i_location_service.dart
git commit -m "feat(location): add ILocationService interface"
```

---

## Task 4: `LocationService` implementation (TDD, the core)

**Files:**
- Create: `lib/utils/services/location/location_service.dart`
- Create: `test/utils/services/location/location_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/location/location_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/location/location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';

class MockGeolocatorPlatform extends Mock implements GeolocatorPlatform {}

Position _fakePosition() => Position(
      latitude: 12.34,
      longitude: 56.78,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late MockGeolocatorPlatform geo;
  late LocationService service;

  setUpAll(() {
    registerFallbackValue(const LocationSettings());
  });

  setUp(() {
    geo = MockGeolocatorPlatform();
    service = LocationService(logger: TbLogger(), geolocator: geo);
  });

  test('returns LocationServicesDisabled when services are off', () async {
    when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => false);

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationServicesDisabled>());
    verifyNever(() => geo.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ));
  });

  test('returns LocationPermissionDenied when request stays denied', () async {
    when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(() => geo.checkPermission())
        .thenAnswer((_) async => LocationPermission.denied);
    when(() => geo.requestPermission())
        .thenAnswer((_) async => LocationPermission.denied);

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationPermissionDenied>());
  });

  test('returns LocationPermissionDeniedForever', () async {
    when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(() => geo.checkPermission())
        .thenAnswer((_) async => LocationPermission.deniedForever);

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationPermissionDeniedForever>());
  });

  test('returns LocationSuccess with mapped GeoPosition', () async {
    when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(() => geo.checkPermission())
        .thenAnswer((_) async => LocationPermission.whileInUse);
    when(() => geo.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        )).thenAnswer((_) async => _fakePosition());

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationSuccess>());
    final pos = (fix as LocationSuccess).position;
    expect(pos.latitude, 12.34);
    expect(pos.longitude, 56.78);
    expect(pos.accuracy, 5);
  });

  test('re-requests permission when initially denied, then succeeds',
      () async {
    when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(() => geo.checkPermission())
        .thenAnswer((_) async => LocationPermission.denied);
    when(() => geo.requestPermission())
        .thenAnswer((_) async => LocationPermission.whileInUse);
    when(() => geo.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        )).thenAnswer((_) async => _fakePosition());

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationSuccess>());
    verify(() => geo.requestPermission()).called(1);
  });

  test('maps thrown errors to LocationFixError', () async {
    when(() => geo.isLocationServiceEnabled())
        .thenThrow(Exception('platform boom'));

    final fix = await service.getCurrentPosition();

    expect(fix, isA<LocationFixError>());
    expect((fix as LocationFixError).message, contains('boom'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/services/location/location_service_test.dart`
Expected: FAIL — `LocationService` undefined.

- [ ] **Step 3: Implement the service**

Create `lib/utils/services/location/location_service.dart`:

```dart
import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';

class LocationService implements ILocationService {
  LocationService({
    required TbLogger logger,
    GeolocatorPlatform? geolocator,
  })  : _log = logger,
        _geolocator = geolocator ?? GeolocatorPlatform.instance;

  final TbLogger _log;
  final GeolocatorPlatform _geolocator;

  @override
  Future<LocationFix> getCurrentPosition() async {
    try {
      final unavailable = await _ensureAvailable();
      if (unavailable != null) {
        return unavailable;
      }

      final position = await _geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LocationSuccess(_toGeoPosition(position));
    } catch (e, s) {
      _log.error('LocationService.getCurrentPosition failed', e, s);
      return LocationFixError(e.toString());
    }
  }

  @override
  Stream<LocationFix> positionStream({double distanceFilterMeters = 0}) async* {
    final unavailable = await _ensureAvailable();
    if (unavailable != null) {
      yield unavailable;
      return;
    }

    final raw = _geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters.round(),
      ),
    );

    yield* raw.transform(
      StreamTransformer<Position, LocationFix>.fromHandlers(
        handleData: (position, sink) =>
            sink.add(LocationSuccess(_toGeoPosition(position))),
        handleError: (e, s, sink) {
          _log.error('LocationService.positionStream error', e, s);
          sink.add(LocationFixError(e.toString()));
        },
      ),
    );
  }

  @override
  Future<bool> openLocationSettings() => _geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => _geolocator.openAppSettings();

  /// Returns `null` when location is available, otherwise a failure
  /// [LocationFix] describing why it is not.
  Future<LocationFix?> _ensureAvailable() async {
    final serviceEnabled = await _geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationServicesDisabled();
    }

    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const LocationPermissionDenied();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationPermissionDeniedForever();
    }
    return null;
  }

  GeoPosition _toGeoPosition(Position p) => GeoPosition(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        timestamp: p.timestamp,
      );
}
```

> If `flutter analyze` flags the `TbLogger.error` signature, check `lib/core/logger/tb_logger.dart` for the exact method name/arity and adjust the two `_log.error(...)` calls to match (the project's logger API is the source of truth).

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/utils/services/location/location_service_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Format & commit**

```bash
dart format lib/utils/services/location/location_service.dart test/utils/services/location/location_service_test.dart
git add lib/utils/services/location/location_service.dart test/utils/services/location/location_service_test.dart
git commit -m "feat(location): add LocationService backed by GeolocatorPlatform"
```

---

## Task 5: Register `ILocationService` in the locator

**Files:**
- Modify: `lib/locator.dart`

- [ ] **Step 1: Add the import**

At the top of `lib/locator.dart`, with the other imports, add:

```dart
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/location_service.dart';
```

- [ ] **Step 2: Add the registration**

In `setUpRootDependencies()`, inside the `getIt` cascade, add this line next to the other `registerLazySingleton` utility-service entries (e.g. right after the `ITbImageGalleryService` registration around `lib/locator.dart:54`):

```dart
    ..registerLazySingleton<ILocationService>(
      () => LocationService(logger: getIt()),
    )
```

- [ ] **Step 3: Verify it analyzes and resolves**

Run: `flutter analyze lib/locator.dart`
Expected: No issues. (`getIt()` resolves `TbLogger`, registered at `lib/locator.dart:45`.)

- [ ] **Step 4: Format & commit**

```bash
dart format lib/locator.dart
git add lib/locator.dart
git commit -m "feat(location): register ILocationService in the locator"
```

---

## Task 6: Refactor `GetLocationAction` to delegate

**Files:**
- Modify: `lib/utils/services/mobile_actions/actions/get_location_action.dart`

- [ ] **Step 1: Replace the file contents**

Overwrite `lib/utils/services/mobile_actions/actions/get_location_action.dart` with:

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_type.dart';

class GetLocationAction extends MobileAction {
  @override
  Future<WidgetMobileActionResult> execute(
    List args,
    InAppWebViewController controller,
  ) async {
    try {
      final fix = await getIt<ILocationService>().getCurrentPosition();
      return switch (fix) {
        LocationSuccess(:final position) =>
          WidgetMobileActionResult.successResult(
            MobileActionResult.location(
              position.latitude,
              position.longitude,
            ),
          ),
        LocationServicesDisabled() => WidgetMobileActionResult.errorResult(
            'Location services are disabled.',
          ),
        LocationPermissionDenied() => WidgetMobileActionResult.errorResult(
            'Location permissions are denied.',
          ),
        LocationPermissionDeniedForever() =>
          WidgetMobileActionResult.errorResult(
            'Location permissions are permanently denied, we cannot request permissions.',
          ),
        LocationFixError(:final message) =>
          WidgetMobileActionResult.errorResult(message),
      };
    } catch (e) {
      return handleError(e);
    }
  }

  @override
  WidgetMobileActionType get type => WidgetMobileActionType.getLocation;
}
```

This preserves the exact error strings the dashboard WebView receives today, and `WidgetActionHandler`'s static `actions` list still constructs `GetLocationAction()` with no arguments — unchanged.

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/utils/services/mobile_actions/actions/get_location_action.dart`
Expected: No issues. (Confirm `geolocator` is no longer imported here — it should now live only in `location_service.dart`.)

- [ ] **Step 3: Confirm geolocator is contained**

Run: `grep -rl "package:geolocator" lib`
Expected: only `lib/utils/services/location/location_service.dart`.

- [ ] **Step 4: Format & commit**

```bash
dart format lib/utils/services/mobile_actions/actions/get_location_action.dart
git add lib/utils/services/mobile_actions/actions/get_location_action.dart
git commit -m "refactor(location): make GetLocationAction delegate to ILocationService"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full location test suite**

Run: `flutter test test/utils/services/location/`
Expected: all tests PASS.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues introduced by these files.

- [ ] **Step 3: Confirm formatting is clean**

Run: `dart format --output=none --set-exit-if-changed lib/utils/services/location test/utils/services/location lib/utils/services/mobile_actions/actions/get_location_action.dart`
Expected: exit 0 (nothing to reformat).

---

## Self-Review (completed by plan author)

- **Spec coverage:** interface (Task 3) covers on-demand + stream + settings escape hatches; sealed result (Task 2) covers all five failure/success states; placement & registration (Tasks 1–5) match the cross-cutting-singleton design; refactor (Task 6) makes the service the single source of truth; testability via injected `GeolocatorPlatform` (Task 4) is implemented. Background tracking / UI / Riverpod wrapper / last-known caching correctly absent (non-goals).
- **Placeholder scan:** no TBD/TODO; every code step shows full code; every command has expected output. The one conditional note (TbLogger.error signature) points at a concrete source file to check.
- **Type consistency:** `LocationFix` variant names (`LocationSuccess`, `LocationServicesDisabled`, `LocationPermissionDenied`, `LocationPermissionDeniedForever`, `LocationFixError`) are identical across Tasks 2, 4, and 6. `GeoPosition` fields (`latitude`, `longitude`, `accuracy`, `timestamp`) are consistent across Tasks 1, 4, and the tests. `ILocationService` method names match between Tasks 3, 4, and 6.
```
