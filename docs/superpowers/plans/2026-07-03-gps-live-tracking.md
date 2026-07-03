# GPS Live Tracking (Phase 1c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start/stop continuous phone GPS tracking from a dashboard mobile action; the app streams positions to a target entity as telemetry (background-capable), with system status attributes, a persistent in-app tracking bar (Stop/Pause/Hide), and a session screen.

**Architecture:** ThingsBoard owns configuration (two new mobile action types whose descriptor lives in dashboard JSON); the web runtime resolves the target entity at click time (reusing phase 1b's `resolveMobileActionTargetEntity`) and sends the app one fully-resolved config object over the existing `tbMobileHandler` bridge. The app owns the runtime: a GetIt singleton `LiveLocationTrackingService` consumes the background-capable `ILocationService.positionStream()` (phase 1a), saves each fix via a thin `ILiveTrackingRemote` wrapper around the Dart client, and exposes session state through a stream that a Riverpod provider bridges to the UI.

**Tech Stack:** Angular 18 (ui-ngx), Flutter/Dart, Riverpod codegen (`@riverpod` + build_runner), Freezed, geolocator (already wrapped).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-03-gps-tracking-design.md` (phase 1c section). Design deltas locked here: live tracking always saves **timeseries** with an optional `mirrorToAttributes` toggle (no attributes/timeseries choice); **pause** cancels the stream and writes `gpsActive=false`, resume restores both; a **terminal location failure** (permission/services) puts the session in `paused` with `lastError` instead of killing it; starting while a session is active **silently replaces** it (the spec's "prompt to replace" needs UI in the action path — deferred); the tracking bar lives in `NavigationPage` (main pages only), not the outer `RouteHanlderWidget` shell, so it never overlays login/auth pages.
- Repos/branches: ui-ngx `/home/artem/projects/thingsboard` branch `feat/gps-tracker`; Flutter `/home/artem/projects/mobile/flutter_thingsboard_app` branch `feat/gps-tracker`. Leave the pre-existing uncommitted `ui-ngx/proxy.conf.js` change alone.
- Conventional Commits; **no** `Co-Authored-By` lines.
- Dart: `dart format` on changed files (only the files you touched — never whole directories); `flutter analyze` must stay clean for changed files; codegen via `flutter pub run build_runner build --delete-conflicting-outputs`; l10n regeneration via `flutter pub run intl_utils:generate`.
- ui-ngx verification: `cd ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json` — bar: only the 4 pre-existing photoswipe errors. No new test scaffolding for ui-ngx (repo convention).
- Production Flutter UI strings are localized (`S.of(context).key`, keys in `lib/l10n/intl_en.arb` only — other locales fall back). The debug spike page stays hardcoded/untouched.
- **Wire protocol** (web → app, single arg after the action type; sent as a JS object, arrives in Dart as a `Map`):

```jsonc
{
  "target": {"entityType": "DEVICE", "id": "<uuid>"},
  "latitudeKey": "latitude",
  "longitudeKey": "longitude",
  "includeMetadata": false,        // adds gpsAccuracy/gpsAltitude/gpsSpeed/gpsHeading telemetry keys
  "mirrorToAttributes": false,     // also save the same values as SERVER_SCOPE attributes
  "accuracy": "BALANCED",          // HIGH | BALANCED | LOW
  "distanceFilterMeters": 10,      // nullable; null -> report every fix
  "intervalSeconds": 30,           // nullable; Android pacing hint only
  "maxDurationMinutes": 60,        // nullable; null -> manual stop only
  "writeStatusAttributes": true,   // gpsActive / gpsLastUpdateTime / gpsTrackedBy
  "trackedBy": "user@example.com"  // current user email (AuthUser.sub web-side)
}
```

- App reply contract: `startLiveLocation` → `{launched: true}` success result (or error result on bad config / start failure); `stopLiveLocation` → `{launched: true}` if a session was stopped, **empty result** if none active.
- Status attribute names (SERVER_SCOPE on the target entity): `gpsActive` (bool), `gpsLastUpdateTime` (ms epoch, per fix), `gpsTrackedBy` (email string).
- Action type strings on the wire: `startLiveLocation`, `stopLiveLocation` (the Dart `fromString` matches enum names case-insensitively, so Dart enum values must use exactly these names).

---

### Task 1: Flutter — extend GeoPosition with altitude/speed/heading

**Files:**
- Modify: `lib/utils/services/location/model/geo_position.dart`
- Modify: `lib/utils/services/location/location_service.dart` (`_toGeoPosition`, ~line 130)
- Test: `test/utils/services/mobile_actions/location_action_result_mapper_test.dart` (existing — must keep passing; no new assertions needed)

**Interfaces:**
- Produces: `GeoPosition` gains optional `double? altitude`, `double? speed`, `double? heading`. Task 3's `_saveFix` reads them.

- [ ] **Step 1: Extend the freezed model**

Replace the factory in `lib/utils/services/location/model/geo_position.dart`:

```dart
@freezed
abstract class GeoPosition with _$GeoPosition {
  const factory GeoPosition({
    required double latitude,
    required double longitude,
    required double accuracy,
    DateTime? timestamp,
    double? altitude,
    double? speed,
    double? heading,
  }) = _GeoPosition;
}
```

- [ ] **Step 2: Map the new fields in LocationService**

In `lib/utils/services/location/location_service.dart`, replace `_toGeoPosition`:

```dart
  GeoPosition _toGeoPosition(Position p) => GeoPosition(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    timestamp: p.timestamp,
    altitude: p.altitude,
    speed: p.speed,
    heading: p.heading,
  );
```

- [ ] **Step 3: Regenerate freezed output and verify**

```bash
cd /home/artem/projects/mobile/flutter_thingsboard_app
flutter pub run build_runner build --delete-conflicting-outputs
flutter test test/
flutter analyze 2>&1 | grep -E "geo_position|location_service" ; echo "expect no output above"
```
Expected: build succeeds, existing 3 tests pass.

- [ ] **Step 4: Format and commit**

```bash
dart format lib/utils/services/location/model/geo_position.dart lib/utils/services/location/location_service.dart
git add lib/utils/services/location/
git commit -m "feat(location): expose altitude, speed and heading on GeoPosition"
```

---

### Task 2: Flutter — LiveTrackingConfig wire model

**Files:**
- Create: `lib/utils/services/live_location_tracking/model/live_tracking_config.dart`
- Test: `test/utils/services/live_location_tracking/live_tracking_config_test.dart`

**Interfaces:**
- Consumes: `LocationAccuracyLevel` from `lib/utils/services/location/model/location_stream_settings.dart`.
- Produces (used by Tasks 3-5): `LiveTrackingTarget {entityType: String, id: String}`; `LiveTrackingConfig` with fields `target: LiveTrackingTarget`, `latitudeKey: String` (default 'latitude'), `longitudeKey: String` (default 'longitude'), `includeMetadata: bool` (default false), `mirrorToAttributes: bool` (default false), `accuracy: LocationAccuracyLevel` (default balanced), `distanceFilterMeters: int?`, `intervalSeconds: int?`, `maxDurationMinutes: int?`, `writeStatusAttributes: bool` (default true), `trackedBy: String?`; `LiveTrackingConfig.fromJson(Map<String, dynamic>)` throwing `FormatException` when `target` is missing/malformed.

- [ ] **Step 1: Write the failing tests**

Create `test/utils/services/live_location_tracking/live_tracking_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

void main() {
  test('parses a full config', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'DEVICE', 'id': 'abc-123'},
      'latitudeKey': 'lat',
      'longitudeKey': 'lng',
      'includeMetadata': true,
      'mirrorToAttributes': true,
      'accuracy': 'HIGH',
      'distanceFilterMeters': 25,
      'intervalSeconds': 60,
      'maxDurationMinutes': 120,
      'writeStatusAttributes': false,
      'trackedBy': 'user@example.com',
    });

    expect(config.target.entityType, 'DEVICE');
    expect(config.target.id, 'abc-123');
    expect(config.latitudeKey, 'lat');
    expect(config.longitudeKey, 'lng');
    expect(config.includeMetadata, true);
    expect(config.mirrorToAttributes, true);
    expect(config.accuracy, LocationAccuracyLevel.high);
    expect(config.distanceFilterMeters, 25);
    expect(config.intervalSeconds, 60);
    expect(config.maxDurationMinutes, 120);
    expect(config.writeStatusAttributes, false);
    expect(config.trackedBy, 'user@example.com');
  });

  test('applies defaults for a minimal config', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'USER', 'id': 'u-1'},
    });

    expect(config.latitudeKey, 'latitude');
    expect(config.longitudeKey, 'longitude');
    expect(config.includeMetadata, false);
    expect(config.mirrorToAttributes, false);
    expect(config.accuracy, LocationAccuracyLevel.balanced);
    expect(config.distanceFilterMeters, isNull);
    expect(config.intervalSeconds, isNull);
    expect(config.maxDurationMinutes, isNull);
    expect(config.writeStatusAttributes, true);
    expect(config.trackedBy, isNull);
  });

  test('unknown accuracy falls back to balanced', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'USER', 'id': 'u-1'},
      'accuracy': 'ULTRA',
    });

    expect(config.accuracy, LocationAccuracyLevel.balanced);
  });

  test('missing target throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {'latitudeKey': 'lat'}),
      throwsFormatException,
    );
  });

  test('malformed target throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {
        'target': {'entityType': 'DEVICE'},
      }),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_config_test.dart`
Expected: FAIL — file/classes don't exist.

- [ ] **Step 3: Implement the model**

Create `lib/utils/services/live_location_tracking/model/live_tracking_config.dart`:

```dart
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

class LiveTrackingTarget {
  const LiveTrackingTarget({required this.entityType, required this.id});

  factory LiveTrackingTarget.fromJson(Map<String, dynamic> json) {
    final entityType = json['entityType'];
    final id = json['id'];
    if (entityType is! String || id is! String) {
      throw const FormatException(
        'Live tracking target must contain entityType and id',
      );
    }
    return LiveTrackingTarget(entityType: entityType, id: id);
  }

  final String entityType;
  final String id;
}

/// Fully-resolved live tracking session config received from the dashboard
/// (the web side resolves aliases/attributes to a concrete target entity
/// before sending — see the phase 1c wire protocol in the plan doc).
class LiveTrackingConfig {
  const LiveTrackingConfig({
    required this.target,
    this.latitudeKey = 'latitude',
    this.longitudeKey = 'longitude',
    this.includeMetadata = false,
    this.mirrorToAttributes = false,
    this.accuracy = LocationAccuracyLevel.balanced,
    this.distanceFilterMeters,
    this.intervalSeconds,
    this.maxDurationMinutes,
    this.writeStatusAttributes = true,
    this.trackedBy,
  });

  factory LiveTrackingConfig.fromJson(Map<String, dynamic> json) {
    final targetJson = json['target'];
    if (targetJson is! Map) {
      throw const FormatException('Live tracking config is missing target');
    }
    return LiveTrackingConfig(
      target: LiveTrackingTarget.fromJson(
        Map<String, dynamic>.from(targetJson),
      ),
      latitudeKey: json['latitudeKey'] as String? ?? 'latitude',
      longitudeKey: json['longitudeKey'] as String? ?? 'longitude',
      includeMetadata: json['includeMetadata'] as bool? ?? false,
      mirrorToAttributes: json['mirrorToAttributes'] as bool? ?? false,
      accuracy: _accuracyFromString(json['accuracy'] as String?),
      distanceFilterMeters: (json['distanceFilterMeters'] as num?)?.toInt(),
      intervalSeconds: (json['intervalSeconds'] as num?)?.toInt(),
      maxDurationMinutes: (json['maxDurationMinutes'] as num?)?.toInt(),
      writeStatusAttributes: json['writeStatusAttributes'] as bool? ?? true,
      trackedBy: json['trackedBy'] as String?,
    );
  }

  final LiveTrackingTarget target;
  final String latitudeKey;
  final String longitudeKey;
  final bool includeMetadata;
  final bool mirrorToAttributes;
  final LocationAccuracyLevel accuracy;
  final int? distanceFilterMeters;
  final int? intervalSeconds;
  final int? maxDurationMinutes;
  final bool writeStatusAttributes;
  final String? trackedBy;

  static LocationAccuracyLevel _accuracyFromString(String? value) =>
      switch (value) {
        'HIGH' => LocationAccuracyLevel.high,
        'LOW' => LocationAccuracyLevel.low,
        _ => LocationAccuracyLevel.balanced,
      };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_config_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/utils/services/live_location_tracking/ test/utils/services/live_location_tracking/
flutter analyze 2>&1 | grep live_tracking ; echo "expect no output above"
git add lib/utils/services/live_location_tracking/ test/utils/services/live_location_tracking/
git commit -m "feat(location): add live tracking wire config model"
```

---

### Task 3: Flutter — tracking session service (the core)

**Files:**
- Create: `lib/utils/services/live_location_tracking/model/live_tracking_session.dart` (freezed)
- Create: `lib/utils/services/live_location_tracking/i_live_tracking_remote.dart`
- Create: `lib/utils/services/live_location_tracking/live_tracking_remote.dart`
- Create: `lib/utils/services/live_location_tracking/i_live_location_tracking_service.dart`
- Create: `lib/utils/services/live_location_tracking/live_location_tracking_service.dart`
- Modify: `lib/locator.dart` (register remote + service after the `ILocationService` block, ~line 61)
- Test: `test/utils/services/live_location_tracking/live_location_tracking_service_test.dart`

**Interfaces:**
- Consumes: `LiveTrackingConfig`/`LiveTrackingTarget` (Task 2), `GeoPosition` with altitude/speed/heading (Task 1), `ILocationService.positionStream({LocationStreamSettings settings})`, `LocationStreamSettings`/`BackgroundTrackingConfig`/`LocationAccuracyLevel`, sealed `LocationFix` cases, `ITbClientService.client.getTelemetryControllerApi()` (`saveEntityTelemetry`/`saveEntityAttributesV2`, string params, JSON-string body), `TbLogger`.
- Produces (used by Tasks 4-5):
  - `enum LiveTrackingStatus { tracking, paused }`
  - `LiveTrackingSession` (freezed): `config`, `status`, `startedAt: DateTime`, `fixCount: int`, `savedCount: int`, `saveErrorCount: int`, `lastFix: GeoPosition?`, `lastError: String?`
  - `ILiveLocationTrackingService`: `LiveTrackingSession? get session`, `Stream<LiveTrackingSession?> get sessionStream`, `Future<void> start(LiveTrackingConfig config)`, `Future<void> stop()`, `Future<void> pause()`, `Future<void> resume()`
  - `ILiveTrackingRemote`: `Future<void> saveTelemetry(LiveTrackingTarget target, int ts, Map<String, dynamic> values)`, `Future<void> saveAttributes(LiveTrackingTarget target, Map<String, dynamic> attributes)`
  - GetIt registrations: `getIt<ILiveTrackingRemote>()`, `getIt<ILiveLocationTrackingService>()`

- [ ] **Step 1: Create the session model**

Create `lib/utils/services/live_location_tracking/model/live_tracking_session.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';

part 'live_tracking_session.freezed.dart';

enum LiveTrackingStatus { tracking, paused }

@freezed
abstract class LiveTrackingSession with _$LiveTrackingSession {
  const factory LiveTrackingSession({
    required LiveTrackingConfig config,
    required LiveTrackingStatus status,
    required DateTime startedAt,
    @Default(0) int fixCount,
    @Default(0) int savedCount,
    @Default(0) int saveErrorCount,
    GeoPosition? lastFix,
    String? lastError,
  }) = _LiveTrackingSession;
}
```

Run: `flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: Create the remote interface + implementation**

Create `lib/utils/services/live_location_tracking/i_live_tracking_remote.dart`:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';

/// Thin REST boundary for live tracking saves. Kept as an interface so the
/// tracking service is unit-testable and the CE/PE client difference stays
/// behind one seam.
abstract interface class ILiveTrackingRemote {
  /// Saves one timeseries sample: `{ts, values}` on the target entity.
  Future<void> saveTelemetry(
    LiveTrackingTarget target,
    int ts,
    Map<String, dynamic> values,
  );

  /// Saves SERVER_SCOPE attributes on the target entity.
  Future<void> saveAttributes(
    LiveTrackingTarget target,
    Map<String, dynamic> attributes,
  );
}
```

Create `lib/utils/services/live_location_tracking/live_tracking_remote.dart`:

```dart
import 'dart:convert';

import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';

class LiveTrackingRemote implements ILiveTrackingRemote {
  LiveTrackingRemote({required ITbClientService clientService})
    : _clientService = clientService;

  final ITbClientService _clientService;

  @override
  Future<void> saveTelemetry(
    LiveTrackingTarget target,
    int ts,
    Map<String, dynamic> values,
  ) async {
    await _clientService.client.getTelemetryControllerApi().saveEntityTelemetry(
      entityType: target.entityType,
      entityId: target.id,
      scope: 'ANY',
      body: jsonEncode({'ts': ts, 'values': values}),
    );
  }

  @override
  Future<void> saveAttributes(
    LiveTrackingTarget target,
    Map<String, dynamic> attributes,
  ) async {
    await _clientService.client
        .getTelemetryControllerApi()
        .saveEntityAttributesV2(
          entityType: target.entityType,
          entityId: target.id,
          scope: 'SERVER_SCOPE',
          body: jsonEncode(attributes),
        );
  }
}
```

- [ ] **Step 3: Create the service interface**

Create `lib/utils/services/live_location_tracking/i_live_location_tracking_service.dart`:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

/// App-wide owner of at most one live GPS tracking session. Runs the
/// location stream, saves telemetry/attributes per fix, and exposes session
/// state for the tracking bar / session screen.
abstract interface class ILiveLocationTrackingService {
  LiveTrackingSession? get session;

  /// Emits on every session change; emits `null` when tracking stops.
  Stream<LiveTrackingSession?> get sessionStream;

  /// Starts a session, replacing any active one.
  Future<void> start(LiveTrackingConfig config);

  Future<void> stop();

  /// Suspends position updates without discarding the session; writes
  /// `gpsActive=false` so the platform sees data flow honestly stopped.
  Future<void> pause();

  Future<void> resume();
}
```

- [ ] **Step 4: Write the failing service tests**

Create `test/utils/services/live_location_tracking/live_location_tracking_service_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

class FakeLocationService implements ILocationService {
  StreamController<LocationFix>? controller;
  LocationStreamSettings? lastSettings;
  int streamRequests = 0;

  @override
  Stream<LocationFix> positionStream({
    LocationStreamSettings settings = const LocationStreamSettings(),
  }) {
    streamRequests++;
    lastSettings = settings;
    controller = StreamController<LocationFix>();
    return controller!.stream;
  }

  @override
  Future<LocationFix> getCurrentPosition() => throw UnimplementedError();

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class FakeRemote implements ILiveTrackingRemote {
  final telemetryCalls = <(LiveTrackingTarget, int, Map<String, dynamic>)>[];
  final attributeCalls = <(LiveTrackingTarget, Map<String, dynamic>)>[];
  Object? throwOnTelemetry;

  @override
  Future<void> saveTelemetry(
    LiveTrackingTarget target,
    int ts,
    Map<String, dynamic> values,
  ) async {
    if (throwOnTelemetry != null) {
      throw throwOnTelemetry!;
    }
    telemetryCalls.add((target, ts, values));
  }

  @override
  Future<void> saveAttributes(
    LiveTrackingTarget target,
    Map<String, dynamic> attributes,
  ) async {
    attributeCalls.add((target, attributes));
  }
}

void main() {
  const target = LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1');
  final fix = GeoPosition(
    latitude: 1,
    longitude: 2,
    accuracy: 5,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
    altitude: 100,
    speed: 3,
    heading: 90,
  );

  late FakeLocationService location;
  late FakeRemote remote;
  late LiveLocationTrackingService service;

  setUp(() {
    location = FakeLocationService();
    remote = FakeRemote();
    service = LiveLocationTrackingService(
      locationService: location,
      remote: remote,
      logger: TbLogger(),
    );
  });

  test('start emits a tracking session and writes status attributes',
      () async {
    await service.start(
      const LiveTrackingConfig(target: target, trackedBy: 'me@tb.io'),
    );

    expect(service.session?.status, LiveTrackingStatus.tracking);
    expect(remote.attributeCalls.single.$2, {
      'gpsActive': true,
      'gpsTrackedBy': 'me@tb.io',
    });
    expect(location.lastSettings?.background, isNotNull);
  });

  test('start with writeStatusAttributes=false writes nothing', () async {
    await service.start(
      const LiveTrackingConfig(target: target, writeStatusAttributes: false),
    );

    expect(remote.attributeCalls, isEmpty);
  });

  test('fix saves telemetry with configured keys and gpsLastUpdateTime',
      () async {
    await service.start(
      const LiveTrackingConfig(
        target: target,
        latitudeKey: 'lat',
        longitudeKey: 'lng',
      ),
    );
    remote.attributeCalls.clear();

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    final (savedTarget, ts, values) = remote.telemetryCalls.single;
    expect(savedTarget.id, 'd-1');
    expect(ts, 1720000000000);
    expect(values, {'lat': 1.0, 'lng': 2.0});
    expect(remote.attributeCalls.single.$2, {
      'gpsLastUpdateTime': 1720000000000,
    });
    expect(service.session?.fixCount, 1);
    expect(service.session?.savedCount, 1);
    expect(service.session?.lastFix, fix);
  });

  test('includeMetadata adds gps metadata telemetry keys', () async {
    await service.start(
      const LiveTrackingConfig(
        target: target,
        includeMetadata: true,
        writeStatusAttributes: false,
      ),
    );

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(remote.telemetryCalls.single.$3, {
      'latitude': 1.0,
      'longitude': 2.0,
      'gpsAccuracy': 5.0,
      'gpsAltitude': 100.0,
      'gpsSpeed': 3.0,
      'gpsHeading': 90.0,
    });
  });

  test('mirrorToAttributes copies values into the attribute save', () async {
    await service.start(
      const LiveTrackingConfig(target: target, mirrorToAttributes: true),
    );
    remote.attributeCalls.clear();

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(remote.attributeCalls.single.$2, {
      'latitude': 1.0,
      'longitude': 2.0,
      'gpsLastUpdateTime': 1720000000000,
    });
  });

  test('save failure increments saveErrorCount and keeps tracking', () async {
    await service.start(const LiveTrackingConfig(target: target));
    remote.throwOnTelemetry = Exception('boom');

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(service.session?.status, LiveTrackingStatus.tracking);
    expect(service.session?.saveErrorCount, 1);
    expect(service.session?.savedCount, 0);
    expect(service.session?.lastError, contains('boom'));
  });

  test('pause cancels the stream and writes gpsActive=false; resume restores',
      () async {
    await service.start(const LiveTrackingConfig(target: target));
    remote.attributeCalls.clear();

    await service.pause();
    expect(service.session?.status, LiveTrackingStatus.paused);
    expect(remote.attributeCalls.single.$2, {'gpsActive': false});
    expect(location.controller!.hasListener, false);

    remote.attributeCalls.clear();
    await service.resume();
    expect(service.session?.status, LiveTrackingStatus.tracking);
    expect(remote.attributeCalls.single.$2, {'gpsActive': true});
    expect(location.streamRequests, 2);
  });

  test('stop clears the session and writes gpsActive=false', () async {
    await service.start(const LiveTrackingConfig(target: target));
    remote.attributeCalls.clear();
    final emissions = <LiveTrackingSession?>[];
    final sub = service.sessionStream.listen(emissions.add);

    await service.stop();
    await pumpEventQueue();

    expect(service.session, isNull);
    expect(remote.attributeCalls.single.$2, {'gpsActive': false});
    expect(emissions.last, isNull);
    await sub.cancel();
  });

  test('terminal permission failure pauses the session with an error',
      () async {
    await service.start(const LiveTrackingConfig(target: target));

    location.controller!.add(const LocationPermissionDenied());
    await pumpEventQueue();

    expect(service.session?.status, LiveTrackingStatus.paused);
    expect(service.session?.lastError, isNotNull);
  });

  test('maxDurationMinutes auto-stops the session', () {
    fakeAsync((async) {
      service.start(
        const LiveTrackingConfig(target: target, maxDurationMinutes: 5),
      );
      async.flushMicrotasks();
      expect(service.session, isNotNull);

      async.elapse(const Duration(minutes: 5, seconds: 1));
      async.flushMicrotasks();
      expect(service.session, isNull);
    });
  });
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `flutter test test/utils/services/live_location_tracking/live_location_tracking_service_test.dart`
Expected: FAIL — `LiveLocationTrackingService` doesn't exist.

- [ ] **Step 6: Implement the service**

Create `lib/utils/services/live_location_tracking/live_location_tracking_service.dart`:

```dart
import 'dart:async';

import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

class LiveLocationTrackingService implements ILiveLocationTrackingService {
  LiveLocationTrackingService({
    required ILocationService locationService,
    required ILiveTrackingRemote remote,
    required TbLogger logger,
    // Android notification strings are OS-level, set once at construction;
    // English defaults are acceptable for v1 (the locator can later pass
    // localized strings without touching this class).
    this.backgroundConfig = const BackgroundTrackingConfig(
      notificationTitle: 'ThingsBoard',
      notificationText: 'Live location tracking is active',
    ),
  }) : _locationService = locationService,
       _remote = remote,
       _log = logger;

  final ILocationService _locationService;
  final ILiveTrackingRemote _remote;
  final TbLogger _log;
  final BackgroundTrackingConfig backgroundConfig;

  final _sessionController = StreamController<LiveTrackingSession?>.broadcast();
  LiveTrackingSession? _session;
  StreamSubscription<LocationFix>? _subscription;
  Timer? _maxDurationTimer;

  @override
  LiveTrackingSession? get session => _session;

  @override
  Stream<LiveTrackingSession?> get sessionStream => _sessionController.stream;

  @override
  Future<void> start(LiveTrackingConfig config) async {
    await stop();
    _setSession(
      LiveTrackingSession(
        config: config,
        status: LiveTrackingStatus.tracking,
        startedAt: DateTime.now(),
      ),
    );
    await _writeStatusAttributes({
      'gpsActive': true,
      if (config.trackedBy != null) 'gpsTrackedBy': config.trackedBy,
    });
    _subscribe(config);
    final maxDuration = config.maxDurationMinutes;
    if (maxDuration != null) {
      _maxDurationTimer = Timer(Duration(minutes: maxDuration), stop);
    }
  }

  @override
  Future<void> stop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (_session != null) {
      await _writeStatusAttributes({'gpsActive': false});
      _setSession(null);
    }
  }

  @override
  Future<void> pause() async {
    final current = _session;
    if (current == null || current.status != LiveTrackingStatus.tracking) {
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    _setSession(current.copyWith(status: LiveTrackingStatus.paused));
    await _writeStatusAttributes({'gpsActive': false});
  }

  @override
  Future<void> resume() async {
    final current = _session;
    if (current == null || current.status != LiveTrackingStatus.paused) {
      return;
    }
    _setSession(
      current.copyWith(status: LiveTrackingStatus.tracking, lastError: null),
    );
    await _writeStatusAttributes({'gpsActive': true});
    _subscribe(current.config);
  }

  void _subscribe(LiveTrackingConfig config) {
    _subscription = _locationService
        .positionStream(
          settings: LocationStreamSettings(
            accuracy: config.accuracy,
            distanceFilterMeters: config.distanceFilterMeters ?? 0,
            interval:
                config.intervalSeconds != null
                    ? Duration(seconds: config.intervalSeconds!)
                    : null,
            background: backgroundConfig,
          ),
        )
        .listen(_onFix);
  }

  Future<void> _onFix(LocationFix fix) async {
    final current = _session;
    if (current == null) {
      return;
    }
    switch (fix) {
      case LocationSuccess(:final position):
        _setSession(
          current.copyWith(fixCount: current.fixCount + 1, lastFix: position),
        );
        await _saveFix(current.config, position);
      case LocationServicesDisabled():
        await _pauseWithError('Location services are disabled.');
      case LocationPermissionDenied():
        await _pauseWithError('Location permission denied.');
      case LocationPermissionDeniedForever():
        await _pauseWithError('Location permission permanently denied.');
      case LocationFixError(:final message):
        _setSession(_session?.copyWith(lastError: message));
    }
  }

  Future<void> _saveFix(LiveTrackingConfig config, GeoPosition position) async {
    final values = <String, dynamic>{
      config.latitudeKey: position.latitude,
      config.longitudeKey: position.longitude,
      if (config.includeMetadata) ...{
        'gpsAccuracy': position.accuracy,
        if (position.altitude != null) 'gpsAltitude': position.altitude,
        if (position.speed != null) 'gpsSpeed': position.speed,
        if (position.heading != null) 'gpsHeading': position.heading,
      },
    };
    final ts =
        (position.timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    try {
      await _remote.saveTelemetry(config.target, ts, values);
      final attributes = <String, dynamic>{
        if (config.mirrorToAttributes) ...values,
        if (config.writeStatusAttributes) 'gpsLastUpdateTime': ts,
      };
      if (attributes.isNotEmpty) {
        await _remote.saveAttributes(config.target, attributes);
      }
      final current = _session;
      if (current != null) {
        _setSession(current.copyWith(savedCount: current.savedCount + 1));
      }
    } catch (e, s) {
      _log.error('LiveLocationTrackingService: save failed', e, s);
      final current = _session;
      if (current != null) {
        _setSession(
          current.copyWith(
            saveErrorCount: current.saveErrorCount + 1,
            lastError: e.toString(),
          ),
        );
      }
    }
  }

  Future<void> _pauseWithError(String message) async {
    final current = _session;
    if (current == null) {
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    _setSession(
      current.copyWith(status: LiveTrackingStatus.paused, lastError: message),
    );
    await _writeStatusAttributes({'gpsActive': false});
  }

  Future<void> _writeStatusAttributes(Map<String, dynamic> attributes) async {
    final config = _session?.config;
    if (config == null || !config.writeStatusAttributes) {
      return;
    }
    try {
      await _remote.saveAttributes(config.target, attributes);
    } catch (e, s) {
      _log.error('LiveLocationTrackingService: status attributes failed', e, s);
    }
  }

  void _setSession(LiveTrackingSession? session) {
    _session = session;
    _sessionController.add(session);
  }
}
```

- [ ] **Step 7: Regenerate freezed, run tests**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter test test/utils/services/live_location_tracking/
```
Expected: PASS (10 service tests + 5 config tests).

- [ ] **Step 8: Register in GetIt**

In `lib/locator.dart`, after the `ILocationService` registration block, add:

```dart
  getIt.registerLazySingleton<ILiveTrackingRemote>(
    () => LiveTrackingRemote(clientService: getIt()),
  );
  getIt.registerLazySingleton<ILiveLocationTrackingService>(
    () => LiveLocationTrackingService(
      locationService: getIt(),
      remote: getIt(),
      logger: getIt(),
    ),
  );
```

with imports:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_remote.dart';
```

- [ ] **Step 9: Analyze, format, commit**

```bash
dart format lib/utils/services/live_location_tracking/ lib/locator.dart test/utils/services/live_location_tracking/
flutter analyze 2>&1 | grep -E "live_location|live_tracking|locator" ; echo "expect no output above"
git add lib/utils/services/live_location_tracking/ lib/locator.dart test/utils/services/live_location_tracking/
git commit -m "feat(location): add live location tracking session service"
```

---

### Task 4: Flutter — start/stop mobile actions

**Files:**
- Modify: `lib/utils/services/mobile_actions/widget_mobile_action_type.dart`
- Delete: `lib/utils/services/mobile_actions/actions/get_live_location_action.dart`
- Create: `lib/utils/services/mobile_actions/actions/start_live_location_action.dart`
- Create: `lib/utils/services/mobile_actions/actions/stop_live_location_action.dart`
- Modify: `lib/utils/services/mobile_actions/widget_action_handler.dart` (registration list)
- Test: `test/utils/services/mobile_actions/live_location_actions_test.dart`

**Interfaces:**
- Consumes: `ILiveLocationTrackingService` via `getIt` (Task 3), `LiveTrackingConfig.fromJson` (Task 2), `MobileAction` base class (has `handleError(e)`), `WidgetMobileActionResult` factories, `MobileActionResult.launched(bool)`.
- Produces: enum values `startLiveLocation`, `stopLiveLocation` (replacing `getLiveLocation`); `fromString` matches them case-insensitively (existing mechanism). Bridge behavior per Global Constraints reply contract.

- [ ] **Step 1: Write the failing tests**

Create `test/utils/services/mobile_actions/live_location_actions_test.dart`:

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/start_live_location_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/stop_live_location_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_type.dart';

class FakeController extends Fake implements InAppWebViewController {}

class FakeTrackingService implements ILiveLocationTrackingService {
  LiveTrackingConfig? startedWith;
  bool stopped = false;

  @override
  LiveTrackingSession? session;

  @override
  Stream<LiveTrackingSession?> get sessionStream => const Stream.empty();

  @override
  Future<void> start(LiveTrackingConfig config) async {
    startedWith = config;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
}

void main() {
  late FakeTrackingService tracking;

  setUp(() {
    tracking = FakeTrackingService();
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(
      () => tracking,
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('action type strings parse to the new enum values', () {
    expect(
      WidgetMobileActionType.fromString('startLiveLocation'),
      WidgetMobileActionType.startLiveLocation,
    );
    expect(
      WidgetMobileActionType.fromString('stopLiveLocation'),
      WidgetMobileActionType.stopLiveLocation,
    );
  });

  test('start action parses config, starts service, returns launched',
      () async {
    final result = await StartLiveLocationAction().execute([
      'startLiveLocation',
      {
        'target': {'entityType': 'DEVICE', 'id': 'd-1'},
        'trackedBy': 'me@tb.io',
      },
    ], FakeController());

    final json = result.toJson();
    expect(tracking.startedWith?.target.id, 'd-1');
    expect(json['hasResult'], true);
    final resultJson = json['result'] as Map<String, dynamic>;
    expect(resultJson['launched'], true);
  });

  test('start action with missing config returns an error result', () async {
    final result =
        await StartLiveLocationAction().execute(['startLiveLocation'], FakeController());

    expect(result.toJson()['hasError'], true);
    expect(tracking.startedWith, isNull);
  });

  test('start action with malformed target returns an error result',
      () async {
    final result = await StartLiveLocationAction().execute([
      'startLiveLocation',
      {'latitudeKey': 'lat'},
    ], FakeController());

    expect(result.toJson()['hasError'], true);
  });

  test('stop action with active session stops and returns launched',
      () async {
    tracking.session = LiveTrackingSession(
      config: const LiveTrackingConfig(
        target: LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1'),
      ),
      status: LiveTrackingStatus.tracking,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final result =
        await StopLiveLocationAction().execute(['stopLiveLocation'], FakeController());

    expect(tracking.stopped, true);
    expect(result.toJson()['hasResult'], true);
  });

  test('stop action with no session returns empty result', () async {
    final result =
        await StopLiveLocationAction().execute(['stopLiveLocation'], FakeController());

    final json = result.toJson();
    expect(tracking.stopped, false);
    expect(json['hasResult'], false);
    expect(json['hasError'], false);
  });
}
```

Note: `MobileAction.execute` takes a non-nullable `InAppWebViewController`; the new actions never dereference it, so the test passes the `FakeController` (a `Fake` from flutter_test) defined at the top of the file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/utils/services/mobile_actions/live_location_actions_test.dart`
Expected: FAIL — enum values / action classes don't exist.

- [ ] **Step 3: Update the enum**

In `lib/utils/services/mobile_actions/widget_mobile_action_type.dart`, replace `getLiveLocation,` with:

```dart
  startLiveLocation,
  stopLiveLocation,
```

- [ ] **Step 4: Replace the placeholder action with the two real ones**

Delete `lib/utils/services/mobile_actions/actions/get_live_location_action.dart`.

Create `lib/utils/services/mobile_actions/actions/start_live_location_action.dart`:

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_type.dart';

/// Starts a live tracking session from a fully-resolved dashboard config
/// (see the phase 1c wire protocol). Replaces any active session.
class StartLiveLocationAction extends MobileAction {
  @override
  Future<WidgetMobileActionResult> execute(
    List args,
    InAppWebViewController controller,
  ) async {
    try {
      if (args.length < 2 || args[1] is! Map) {
        return WidgetMobileActionResult.errorResult(
          'Live tracking config is missing.',
        );
      }
      final config = LiveTrackingConfig.fromJson(
        Map<String, dynamic>.from(args[1] as Map),
      );
      await getIt<ILiveLocationTrackingService>().start(config);
      return WidgetMobileActionResult.successResult(
        MobileActionResult.launched(true),
      );
    } on FormatException catch (e) {
      return WidgetMobileActionResult.errorResult(e.message);
    } catch (e) {
      return handleError(e);
    }
  }

  @override
  WidgetMobileActionType get type => WidgetMobileActionType.startLiveLocation;
}
```

Create `lib/utils/services/mobile_actions/actions/stop_live_location_action.dart`:

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_result.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_type.dart';

class StopLiveLocationAction extends MobileAction {
  @override
  Future<WidgetMobileActionResult> execute(
    List args,
    InAppWebViewController controller,
  ) async {
    try {
      final service = getIt<ILiveLocationTrackingService>();
      if (service.session == null) {
        return WidgetMobileActionResult.emptyResult();
      }
      await service.stop();
      return WidgetMobileActionResult.successResult(
        MobileActionResult.launched(true),
      );
    } catch (e) {
      return handleError(e);
    }
  }

  @override
  WidgetMobileActionType get type => WidgetMobileActionType.stopLiveLocation;
}
```

(If `handleError` is not defined on `MobileAction` — the old placeholder got it from the `LocationActionResultMapper` mixin — replace `return handleError(e);` with `return WidgetMobileActionResult.errorResult(e.toString());` in both actions. Check the base class first.)

- [ ] **Step 5: Update the registration list**

In `lib/utils/services/mobile_actions/widget_action_handler.dart`, replace the `GetLiveLocationAction()` entry (and its import) with:

```dart
    StartLiveLocationAction(),
    StopLiveLocationAction(),
```

and imports:

```dart
import 'package:thingsboard_app/utils/services/mobile_actions/actions/start_live_location_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/stop_live_location_action.dart';
```

- [ ] **Step 6: Run all tests, analyze, commit**

```bash
flutter test test/
flutter analyze 2>&1 | grep -E "mobile_actions|live_location" ; echo "expect no output above"
dart format lib/utils/services/mobile_actions/widget_mobile_action_type.dart lib/utils/services/mobile_actions/widget_action_handler.dart lib/utils/services/mobile_actions/actions/start_live_location_action.dart lib/utils/services/mobile_actions/actions/stop_live_location_action.dart test/utils/services/mobile_actions/live_location_actions_test.dart
git add lib/utils/services/mobile_actions/ test/utils/services/mobile_actions/
git commit -m "feat(location): add startLiveLocation and stopLiveLocation mobile actions"
```

---

### Task 5: Flutter — Riverpod provider, tracking bar, session screen

**Files:**
- Modify: `lib/l10n/intl_en.arb` (append keys before the closing `}`)
- Create: `lib/modules/location_tracking/presentation/provider/live_tracking_provider.dart` (+ generated `.g.dart`, `.freezed.dart`)
- Create: `lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart`
- Create: `lib/modules/location_tracking/presentation/view/live_tracking_session_page.dart`
- Modify: `lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart` (add session route)
- Modify: `lib/modules/main/navigation_page.dart:64` (insert the bar)
- Test: `test/modules/location_tracking/live_tracking_bar_test.dart`

**Interfaces:**
- Consumes: `ILiveLocationTrackingService` (session + sessionStream + stop/pause/resume), `LiveTrackingSession`/`LiveTrackingStatus`, `S.of(context)` l10n, go_router `context.push`.
- Produces: `liveTrackingProvider` (codegen from `class LiveTracking extends _$LiveTracking`) with state `LiveTrackingViewState {session: LiveTrackingSession?, hidden: bool}` and notifier methods `hide()`, `show()`, `stop()`, `pause()`, `resume()`; route constant `LocationTrackingRoutes.liveTrackingSession = '/liveTrackingSession'`.

- [ ] **Step 1: Add l10n keys**

In `lib/l10n/intl_en.arb`, before the final closing brace (add a comma to the current last entry), append:

```json
  "liveTrackingActive": "Live location tracking",
  "liveTrackingPaused": "Live tracking paused",
  "liveTrackingFixes": "Fixes",
  "liveTrackingSaved": "Saved",
  "liveTrackingErrors": "Errors",
  "liveTrackingStop": "Stop",
  "liveTrackingPause": "Pause",
  "liveTrackingResume": "Resume",
  "liveTrackingHide": "Hide",
  "liveTrackingSessionTitle": "Live location tracking",
  "liveTrackingNoSession": "No active tracking session",
  "liveTrackingTarget": "Target entity",
  "liveTrackingStatus": "Status",
  "liveTrackingStarted": "Started",
  "liveTrackingLastFix": "Last fix",
  "liveTrackingLastError": "Last error"
```

Run: `flutter pub run intl_utils:generate`
Expected: `lib/generated/l10n.dart` gains the new getters (other locales fall back to English).

- [ ] **Step 2: Create the provider**

Create `lib/modules/location_tracking/presentation/provider/live_tracking_provider.dart`:

```dart
import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

part 'live_tracking_provider.freezed.dart';
part 'live_tracking_provider.g.dart';

@freezed
abstract class LiveTrackingViewState with _$LiveTrackingViewState {
  const factory LiveTrackingViewState({
    LiveTrackingSession? session,
    @Default(false) bool hidden,
  }) = _LiveTrackingViewState;
}

@riverpod
class LiveTracking extends _$LiveTracking {
  late final StreamSubscription<LiveTrackingSession?> _listener;

  @override
  LiveTrackingViewState build() {
    final service = getIt<ILiveLocationTrackingService>();
    _listener = service.sessionStream.listen((session) {
      state = LiveTrackingViewState(
        session: session,
        hidden: session == null ? false : state.hidden,
      );
    });
    ref.onDispose(() => _listener.cancel());
    return LiveTrackingViewState(session: service.session);
  }

  void hide() => state = state.copyWith(hidden: true);

  void show() => state = state.copyWith(hidden: false);

  Future<void> stop() => getIt<ILiveLocationTrackingService>().stop();

  Future<void> pause() => getIt<ILiveLocationTrackingService>().pause();

  Future<void> resume() => getIt<ILiveLocationTrackingService>().resume();
}
```

Run: `flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 3: Create the tracking bar**

Create `lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/config/routes/v2/routes_config/routes/location_tracking_routes.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/provider/live_tracking_provider.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

/// Persistent bar shown on all main pages while a tracking session exists.
class LiveTrackingBar extends ConsumerWidget {
  const LiveTrackingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(liveTrackingProvider);
    final session = viewState.session;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final tracking = session.status == LiveTrackingStatus.tracking;

    if (viewState.hidden) {
      return Material(
        color: colors.primaryContainer,
        child: InkWell(
          onTap: () => ref.read(liveTrackingProvider.notifier).show(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Icon(
              tracking ? Icons.gps_fixed : Icons.gps_off,
              size: 16,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
      );
    }

    return Material(
      color: colors.primaryContainer,
      child: InkWell(
        onTap:
            () => context.push(LocationTrackingRoutes.liveTrackingSession),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                tracking ? Icons.gps_fixed : Icons.gps_off,
                color: colors.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracking
                          ? S.of(context).liveTrackingActive
                          : S.of(context).liveTrackingPaused,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      '${S.of(context).liveTrackingFixes}: '
                      '${session.fixCount} · '
                      '${S.of(context).liveTrackingSaved}: '
                      '${session.savedCount}'
                      '${session.saveErrorCount > 0 ? ' · ${S.of(context).liveTrackingErrors}: ${session.saveErrorCount}' : ''}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip:
                    tracking
                        ? S.of(context).liveTrackingPause
                        : S.of(context).liveTrackingResume,
                icon: Icon(
                  tracking ? Icons.pause : Icons.play_arrow,
                  color: colors.onPrimaryContainer,
                ),
                onPressed: () {
                  final notifier = ref.read(liveTrackingProvider.notifier);
                  tracking ? notifier.pause() : notifier.resume();
                },
              ),
              IconButton(
                tooltip: S.of(context).liveTrackingStop,
                icon: Icon(Icons.stop, color: colors.onPrimaryContainer),
                onPressed:
                    () => ref.read(liveTrackingProvider.notifier).stop(),
              ),
              IconButton(
                tooltip: S.of(context).liveTrackingHide,
                icon: Icon(
                  Icons.expand_less,
                  color: colors.onPrimaryContainer,
                ),
                onPressed:
                    () => ref.read(liveTrackingProvider.notifier).hide(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create the session screen and route**

Create `lib/modules/location_tracking/presentation/view/live_tracking_session_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/provider/live_tracking_provider.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

class LiveTrackingSessionPage extends ConsumerWidget {
  const LiveTrackingSessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveTrackingProvider).session;
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).liveTrackingSessionTitle)),
      body:
          session == null
              ? Center(child: Text(S.of(context).liveTrackingNoSession))
              : _SessionDetails(session: session),
    );
  }
}

class _SessionDetails extends ConsumerWidget {
  const _SessionDetails({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = session.status == LiveTrackingStatus.tracking;
    final lastFix = session.lastFix;
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingTarget),
          subtitle: Text(
            '${session.config.target.entityType} ${session.config.target.id}',
          ),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStatus),
          subtitle: Text(
            tracking
                ? S.of(context).liveTrackingActive
                : S.of(context).liveTrackingPaused,
          ),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStarted),
          subtitle: Text(session.startedAt.toLocal().toString()),
        ),
        ListTile(
          title: Text(
            '${S.of(context).liveTrackingFixes}: ${session.fixCount} · '
            '${S.of(context).liveTrackingSaved}: ${session.savedCount} · '
            '${S.of(context).liveTrackingErrors}: ${session.saveErrorCount}',
          ),
        ),
        if (lastFix != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastFix),
            subtitle: Text(
              '${lastFix.latitude.toStringAsFixed(6)}, '
              '${lastFix.longitude.toStringAsFixed(6)} '
              '(±${lastFix.accuracy.toStringAsFixed(0)} m)',
            ),
          ),
        if (session.lastError != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastError),
            subtitle: Text(
              session.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final notifier = ref.read(liveTrackingProvider.notifier);
                    tracking ? notifier.pause() : notifier.resume();
                  },
                  icon: Icon(tracking ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    tracking
                        ? S.of(context).liveTrackingPause
                        : S.of(context).liveTrackingResume,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      () => ref.read(liveTrackingProvider.notifier).stop(),
                  icon: const Icon(Icons.stop),
                  label: Text(S.of(context).liveTrackingStop),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

In `lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart`, add the constant and route:

```dart
class LocationTrackingRoutes {
  static const liveTrackingSpike = '/liveTrackingSpike';
  static const liveTrackingSession = '/liveTrackingSession';
}
```

and in the list:

```dart
  GoRoute(
    path: LocationTrackingRoutes.liveTrackingSession,
    builder: (context, state) {
      return const LiveTrackingSessionPage();
    },
  ),
```

with import `package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_session_page.dart`.

- [ ] **Step 5: Insert the bar into the main shell**

In `lib/modules/main/navigation_page.dart` line 64, replace `body: child,` with:

```dart
          body: Column(
            children: [
              const LiveTrackingBar(),
              Expanded(child: child),
            ],
          ),
```

Add import: `package:thingsboard_app/modules/location_tracking/presentation/widgets/live_tracking_bar.dart`.
(`child` here is the `NavigationPage` constructor's page content — confirm the local name in the build method; it may be `widget.child` or a local variable.)

- [ ] **Step 6: Write the widget test**

Create `test/modules/location_tracking/live_tracking_bar_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/widgets/live_tracking_bar.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

class FakeTrackingService implements ILiveLocationTrackingService {
  final controller = StreamController<LiveTrackingSession?>.broadcast();
  bool stopCalled = false;

  @override
  LiveTrackingSession? session;

  @override
  Stream<LiveTrackingSession?> get sessionStream => controller.stream;

  @override
  Future<void> start(LiveTrackingConfig config) async {}

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [S.delegate],
    home: Scaffold(body: child),
  ),
);

void main() {
  late FakeTrackingService tracking;

  setUp(() {
    tracking = FakeTrackingService();
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(
      () => tracking,
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('renders nothing without a session', (tester) async {
    await tester.pumpWidget(_wrap(const LiveTrackingBar()));

    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('shows controls for an active session and stops on tap',
      (tester) async {
    tracking.session = LiveTrackingSession(
      config: const LiveTrackingConfig(
        target: LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1'),
      ),
      status: LiveTrackingStatus.tracking,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await tester.pumpWidget(_wrap(const LiveTrackingBar()));
    await tester.pump();

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop));
    expect(tracking.stopCalled, true);
  });
}
```

- [ ] **Step 7: Run tests, analyze, format, commit**

```bash
flutter test test/
flutter analyze 2>&1 | grep -E "location_tracking|navigation_page|intl_en" ; echo "expect no output above"
dart format lib/modules/location_tracking/ lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart lib/modules/main/navigation_page.dart test/modules/location_tracking/
git add lib/modules/location_tracking/ lib/config/routes/ lib/modules/main/navigation_page.dart lib/l10n/ lib/generated/ test/modules/location_tracking/
git commit -m "feat(location): add live tracking bar, session screen and provider"
```

---

### Task 6: ui-ngx — action types, descriptor model, locale keys

**Files:**
- Modify: `ui-ngx/src/app/shared/models/widget.models.ts`
- Modify: `ui-ngx/src/assets/locale/locale.constant-en_US.json` (`widget-action.mobile` object)

**Interfaces:**
- Produces (used by Tasks 7-8): enum values `WidgetMobileActionType.startLiveLocation = 'startLiveLocation'` and `stopLiveLocation = 'stopLiveLocation'`; `MobileActionLocationAccuracy` enum (`high='HIGH'`, `balanced='BALANCED'`, `low='LOW'`) + `mobileActionLocationAccuracyTranslationMap`; `StartLiveLocationDescriptor extends ProcessLaunchResultDescriptor` with `targetEntity?: MobileActionTargetEntityConfig`, `latitudeKey?`, `longitudeKey?`, `includeMetadata?`, `mirrorToAttributes?`, `accuracy?: MobileActionLocationAccuracy`, `distanceFilterMeters?: number`, `intervalSeconds?: number`, `maxDurationMinutes?: number`, `writeStatusAttributes?: boolean`; the descriptor added to the `WidgetMobileActionDescriptors` intersection.

- [ ] **Step 1: Extend the action type enum + translation map**

In `widget.models.ts`, in `WidgetMobileActionType` after `getLocation = 'getLocation',` add:

```typescript
  startLiveLocation = 'startLiveLocation',
  stopLiveLocation = 'stopLiveLocation',
```

In `widgetMobileActionTypeTranslationMap` after the `getLocation` entry add:

```typescript
    [ WidgetMobileActionType.startLiveLocation, 'widget-action.mobile.start-live-location' ],
    [ WidgetMobileActionType.stopLiveLocation, 'widget-action.mobile.stop-live-location' ],
```

- [ ] **Step 2: Add the accuracy enum and descriptor**

Directly below the `SaveLocationDescriptor` interface (added in phase 1b), insert:

```typescript
export enum MobileActionLocationAccuracy {
  high = 'HIGH',
  balanced = 'BALANCED',
  low = 'LOW'
}

export const mobileActionLocationAccuracyTranslationMap = new Map<MobileActionLocationAccuracy, string>(
  [
    [ MobileActionLocationAccuracy.high, 'widget-action.mobile.accuracy-high' ],
    [ MobileActionLocationAccuracy.balanced, 'widget-action.mobile.accuracy-balanced' ],
    [ MobileActionLocationAccuracy.low, 'widget-action.mobile.accuracy-low' ]
  ]
);

export interface StartLiveLocationDescriptor extends ProcessLaunchResultDescriptor {
  targetEntity?: MobileActionTargetEntityConfig;
  latitudeKey?: string;
  longitudeKey?: string;
  includeMetadata?: boolean;
  mirrorToAttributes?: boolean;
  accuracy?: MobileActionLocationAccuracy;
  distanceFilterMeters?: number;
  intervalSeconds?: number;
  maxDurationMinutes?: number;
  writeStatusAttributes?: boolean;
}
```

Extend the intersection type by adding one line to `WidgetMobileActionDescriptors`:

```typescript
export type WidgetMobileActionDescriptors = ProcessImageDescriptor &
                                            LaunchMapDescriptor &
                                            ScanQrCodeDescriptor &
                                            MakePhoneCallDescriptor &
                                            GetLocationDescriptor &
                                            StartLiveLocationDescriptor &
                                            ProvisionSuccessDescriptor;
```

Note: `StartLiveLocationDescriptor` and `SaveLocationDescriptor` (via `GetLocationDescriptor`) both declare `targetEntity`/`latitudeKey`/`longitudeKey`/`includeMetadata` with identical types — the intersection stays valid.

- [ ] **Step 3: Add locale keys**

In `locale.constant-en_US.json`, in the `widget-action.mobile` object (after the phase 1b keys, keeping JSON commas valid), add:

```json
          "start-live-location": "Start live location tracking",
          "stop-live-location": "Stop live location tracking",
          "accuracy": "Accuracy",
          "accuracy-high": "High",
          "accuracy-balanced": "Balanced",
          "accuracy-low": "Low",
          "distance-filter-meters": "Distance filter (meters)",
          "interval-seconds": "Time interval (seconds)",
          "max-duration-minutes": "Maximum duration (minutes)",
          "mirror-to-attributes": "Also mirror latest values to attributes",
          "write-status-attributes": "Write tracking status attributes (gpsActive, gpsLastUpdateTime, gpsTrackedBy)",
          "include-metadata-live": "Also save accuracy, altitude, speed and heading"
```

- [ ] **Step 4: Verify and commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx
npx tsc --noEmit -p src/tsconfig.app.json
node -e "JSON.parse(require('fs').readFileSync('src/assets/locale/locale.constant-en_US.json','utf8')); console.log('JSON OK')"
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/shared/models/widget.models.ts ui-ngx/src/assets/locale/locale.constant-en_US.json
git commit -m "feat(mobile-actions): add live location tracking action types and descriptor model"
```
Expected: tsc shows only the 4 pre-existing photoswipe errors; JSON OK.

---

### Task 7: ui-ngx — editor support for the new action types

**Files:**
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/mobile-action-editor.component.ts`
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/mobile-action-editor.component.html`

**Interfaces:**
- Consumes: Task 6's enums/descriptor; phase 1b's target-entity controls (currently inline in the `getLocation` case) and `updateSaveLocationValidators`.
- Produces: descriptor form output with the exact field names from Task 6; a reusable private `addTargetEntityControls(action)` + `updateTargetEntityValidators(targetRequired)` pair; an `<ng-template #targetEntityConfig>` HTML block reused by both `getLocation` and `startLiveLocation`.

- [ ] **Step 1: Extract the target-entity control builder (TS)**

In `mobile-action-editor.component.ts`:

Add imports to the `@shared/models/widget.models` import: `MobileActionLocationAccuracy`, `mobileActionLocationAccuracyTranslationMap`.

Add class fields next to the existing 1b fields:

```typescript
  locationAccuracies = Object.values(MobileActionLocationAccuracy);
  locationAccuracyTranslations = mobileActionLocationAccuracyTranslationMap;
```

Add two private methods (below `updateMobileActionType`), and delete the 1b `updateSaveLocationValidators` method (its logic moves into the second one):

```typescript
  private addTargetEntityControls(action?: WidgetMobileActionDescriptor) {
    const targetEntity = action?.targetEntity;
    this.mobileActionTypeFormGroup.addControl(
      'targetEntity',
      this.fb.group({
        type: [targetEntity?.type || MobileActionTargetEntityType.currentEntity, []],
        aliasName: [targetEntity?.aliasName, []],
        attributeSource: [targetEntity?.attributeSource || MobileActionAttributeSource.currentUser, []],
        attributeKey: [targetEntity?.attributeKey, []],
        defaultEntityType: [targetEntity?.defaultEntityType, []]
      })
    );
    this.mobileActionTypeFormGroup.addControl(
      'latitudeKey',
      this.fb.control(action?.latitudeKey || 'latitude', [])
    );
    this.mobileActionTypeFormGroup.addControl(
      'longitudeKey',
      this.fb.control(action?.longitudeKey || 'longitude', [])
    );
    this.mobileActionTypeFormGroup.addControl(
      'includeMetadata',
      this.fb.control(action?.includeMetadata || false, [])
    );
  }

  private updateTargetEntityValidators(targetRequired: boolean) {
    const type: MobileActionTargetEntityType = this.mobileActionTypeFormGroup.get('targetEntity.type').value;
    const aliasName = this.mobileActionTypeFormGroup.get('targetEntity.aliasName');
    const attributeKey = this.mobileActionTypeFormGroup.get('targetEntity.attributeKey');
    aliasName.setValidators(
      targetRequired && type === MobileActionTargetEntityType.entityAlias ? [Validators.required] : []);
    attributeKey.setValidators(
      targetRequired && type === MobileActionTargetEntityType.fromAttribute ? [Validators.required] : []);
    aliasName.updateValueAndValidity({emitEvent: false});
    attributeKey.updateValueAndValidity({emitEvent: false});
  }
```

- [ ] **Step 2: Rewrite the `getLocation` case to use the helpers**

Replace the 1b-added block in `case WidgetMobileActionType.getLocation:` (everything from `const targetEntity = action?.targetEntity;` to the second `valueChanges` subscription, keeping `processLocationFunction` control untouched) with:

```typescript
          this.mobileActionTypeFormGroup.addControl(
            'saveToEntity',
            this.fb.control(action?.saveToEntity || false, [])
          );
          this.addTargetEntityControls(action);
          this.mobileActionTypeFormGroup.addControl(
            'saveAs',
            this.fb.control(action?.saveAs || MobileActionSaveAs.attributes, [])
          );
          this.updateTargetEntityValidators(this.mobileActionTypeFormGroup.get('saveToEntity').value);
          this.mobileActionTypeFormGroup.get('saveToEntity').valueChanges.pipe(
            takeUntilDestroyed(this.destroyRef)
          ).subscribe(() =>
            this.updateTargetEntityValidators(this.mobileActionTypeFormGroup.get('saveToEntity').value));
          this.mobileActionTypeFormGroup.get('targetEntity.type').valueChanges.pipe(
            takeUntilDestroyed(this.destroyRef)
          ).subscribe(() =>
            this.updateTargetEntityValidators(this.mobileActionTypeFormGroup.get('saveToEntity').value));
```

- [ ] **Step 3: Add the two new cases**

After the `getLocation` case's `break;` and before `case WidgetMobileActionType.deviceProvision:`, add:

```typescript
        case WidgetMobileActionType.startLiveLocation:
          processLaunchResultFunction = action?.processLaunchResultFunction;
          if (changed) {
            const defaultLaunchResultFunction = getDefaultProcessLaunchResultFunction(targetType);
            if (defaultLaunchResultFunction !== processLaunchResultFunction) {
              processLaunchResultFunction = getDefaultProcessLaunchResultFunction(type);
            }
          }
          this.addTargetEntityControls(action);
          this.mobileActionTypeFormGroup.addControl(
            'accuracy',
            this.fb.control(action?.accuracy || MobileActionLocationAccuracy.balanced, [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'distanceFilterMeters',
            this.fb.control(action?.distanceFilterMeters, [Validators.min(0)])
          );
          this.mobileActionTypeFormGroup.addControl(
            'intervalSeconds',
            this.fb.control(action?.intervalSeconds, [Validators.min(1)])
          );
          this.mobileActionTypeFormGroup.addControl(
            'maxDurationMinutes',
            this.fb.control(action?.maxDurationMinutes, [Validators.min(1)])
          );
          this.mobileActionTypeFormGroup.addControl(
            'mirrorToAttributes',
            this.fb.control(action?.mirrorToAttributes || false, [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'writeStatusAttributes',
            this.fb.control(action?.writeStatusAttributes !== false, [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'processLaunchResultFunction',
            this.fb.control(processLaunchResultFunction, [])
          );
          this.updateTargetEntityValidators(true);
          this.mobileActionTypeFormGroup.get('targetEntity.type').valueChanges.pipe(
            takeUntilDestroyed(this.destroyRef)
          ).subscribe(() => this.updateTargetEntityValidators(true));
          break;
        case WidgetMobileActionType.stopLiveLocation:
          processLaunchResultFunction = action?.processLaunchResultFunction;
          if (changed) {
            const defaultStopLaunchResultFunction = getDefaultProcessLaunchResultFunction(targetType);
            if (defaultStopLaunchResultFunction !== processLaunchResultFunction) {
              processLaunchResultFunction = getDefaultProcessLaunchResultFunction(type);
            }
          }
          this.mobileActionTypeFormGroup.addControl(
            'processLaunchResultFunction',
            this.fb.control(processLaunchResultFunction, [])
          );
          break;
```

Note the `processLaunchResultFunction` local variable is already declared at the top of the switch (`let processLaunchResultFunction: TbFunction;`) — reuse it, don't redeclare.

- [ ] **Step 4: Add the editor panels in `getActionConfigs`**

In `getActionConfigs()`, add cases:

```typescript
      case this.mobileActionType.startLiveLocation:
      case this.mobileActionType.stopLiveLocation:
        this.actionConfig.push({
          title: 'widget-action.mobile.process-launch-result-function',
          formControlName: 'processLaunchResultFunction',
          functionName: 'processLaunchResult',
          functionArgs: ['launched', '$event', 'widgetContext', 'entityId', 'entityName', 'additionalParams', 'entityLabel'],
          helpId: 'widget/action/mobile_process_launch_result_fn'
        });
        break;
```

- [ ] **Step 5: Restructure the HTML with a shared target-entity template**

In `mobile-action-editor.component.html`, inside `<ng-container [formGroup]="mobileActionTypeFormGroup">`:

1. Declare the shared template once (place it directly after the `<ng-container [formGroup]=...>` opening tag):

```html
    <ng-template #targetEntityConfig>
      <ng-container formGroupName="targetEntity">
        <div class="tb-form-row">
          <div class="fixed-title-width">{{ 'widget-action.mobile.target-entity-type' | translate }}</div>
          <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
            <mat-select formControlName="type">
              <mat-option *ngFor="let type of targetEntityTypes" [value]="type">
                {{ targetEntityTypeTranslations.get(type) | translate }}
              </mat-option>
            </mat-select>
          </mat-form-field>
        </div>
        @if (mobileActionTypeFormGroup.get('targetEntity.type').value === targetEntityType.entityAlias) {
          <div class="tb-form-row">
            <div class="fixed-title-width">{{ 'widget-action.mobile.target-entity-alias-name' | translate }}*</div>
            <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
              <input matInput required formControlName="aliasName"
                     placeholder="{{ 'widget-action.mobile.target-entity-alias-name' | translate }}">
              <mat-icon matSuffix
                        matTooltipPosition="above"
                        matTooltipClass="tb-error-tooltip"
                        [matTooltip]="'widget-action.mobile.target-entity-alias-name-required' | translate"
                        *ngIf="mobileActionTypeFormGroup.get('targetEntity.aliasName').hasError('required')
                               && mobileActionTypeFormGroup.get('targetEntity.aliasName').touched"
                        class="tb-error">
                warning
              </mat-icon>
            </mat-form-field>
          </div>
        }
        @if (mobileActionTypeFormGroup.get('targetEntity.type').value === targetEntityType.fromAttribute) {
          <div class="tb-form-row">
            <div class="fixed-title-width">{{ 'widget-action.mobile.target-attribute-source' | translate }}</div>
            <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
              <mat-select formControlName="attributeSource">
                <mat-option *ngFor="let source of attributeSources" [value]="source">
                  {{ attributeSourceTranslations.get(source) | translate }}
                </mat-option>
              </mat-select>
            </mat-form-field>
          </div>
          <div class="tb-form-row">
            <div class="fixed-title-width">{{ 'widget-action.mobile.target-attribute-key' | translate }}*</div>
            <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
              <input matInput required formControlName="attributeKey"
                     placeholder="{{ 'widget-action.mobile.target-attribute-key' | translate }}">
              <mat-icon matSuffix
                        matTooltipPosition="above"
                        matTooltipClass="tb-error-tooltip"
                        [matTooltip]="'widget-action.mobile.target-attribute-key-required' | translate"
                        *ngIf="mobileActionTypeFormGroup.get('targetEntity.attributeKey').hasError('required')
                               && mobileActionTypeFormGroup.get('targetEntity.attributeKey').touched"
                        class="tb-error">
                warning
              </mat-icon>
            </mat-form-field>
          </div>
          <div class="tb-form-row">
            <div class="fixed-title-width">{{ 'widget-action.mobile.target-default-entity-type' | translate }}</div>
            <tb-entity-type-select class="flex-1" appearance="outline" formControlName="defaultEntityType">
            </tb-entity-type-select>
          </div>
        }
      </ng-container>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.latitude-key' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput formControlName="latitudeKey">
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.longitude-key' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput formControlName="longitudeKey">
        </mat-form-field>
      </div>
    </ng-template>
```

2. In the existing phase 1b `getLocation` block, delete the inline `<ng-container formGroupName="targetEntity">...</ng-container>` plus the latitude-key/longitude-key rows and replace them with `<ng-container *ngTemplateOutlet="targetEntityConfig"></ng-container>` (keep the saveToEntity toggle, save-as select, and includeMetadata toggle where they are; the includeMetadata row stays in the getLocation block, using the 1b `include-metadata` key).

3. Add the `startLiveLocation` block after the `getLocation` block:

```html
    @if (mobileActionFormGroup.get('type').value === mobileActionType.startLiveLocation) {
      <ng-container *ngTemplateOutlet="targetEntityConfig"></ng-container>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.accuracy' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <mat-select formControlName="accuracy">
            <mat-option *ngFor="let accuracy of locationAccuracies" [value]="accuracy">
              {{ locationAccuracyTranslations.get(accuracy) | translate }}
            </mat-option>
          </mat-select>
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.distance-filter-meters' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput type="number" min="0" formControlName="distanceFilterMeters">
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.interval-seconds' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput type="number" min="1" formControlName="intervalSeconds">
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.max-duration-minutes' | translate }}</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput type="number" min="1" formControlName="maxDurationMinutes">
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <mat-slide-toggle class="mat-slide" formControlName="includeMetadata">
          {{ 'widget-action.mobile.include-metadata-live' | translate }}
        </mat-slide-toggle>
      </div>
      <div class="tb-form-row">
        <mat-slide-toggle class="mat-slide" formControlName="mirrorToAttributes">
          {{ 'widget-action.mobile.mirror-to-attributes' | translate }}
        </mat-slide-toggle>
      </div>
      <div class="tb-form-row">
        <mat-slide-toggle class="mat-slide" formControlName="writeStatusAttributes">
          {{ 'widget-action.mobile.write-status-attributes' | translate }}
        </mat-slide-toggle>
      </div>
    }
```

(`stopLiveLocation` needs no type-specific block — its only config is the `processLaunchResultFunction` panel from `getActionConfigs` plus the common handlers.)

Note: `*ngTemplateOutlet` requires `NgTemplateOutlet`; the module declaring this component imports `CommonModule`/`SharedModule`, which provides it — verify, and if the template outlet directive is missing at build time, add `NgTemplateOutlet` to the declaring module's imports.

- [ ] **Step 6: Verify and commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/
git commit -m "feat(mobile-actions): live location tracking configuration UI"
```
Expected: only the 4 pre-existing photoswipe errors.

---

### Task 8: ui-ngx — dispatch the new actions from the widget runtime

**Files:**
- Modify: `ui-ngx/src/app/modules/home/components/widget/widget.component.ts`

**Interfaces:**
- Consumes: Task 6's `MobileActionLocationAccuracy` and descriptor fields; phase 1b's `resolveMobileActionTargetEntity(mobileAction, currentEntityId): Observable<EntityId>` and `getCurrentAuthUser`; `defer` (already imported by the 1b fix commit — verify); the existing `handleMobileAction` args/result switch.
- Produces: the wire config object exactly as specified in Global Constraints.

- [ ] **Step 1: Add the args cases**

In `handleMobileAction`'s first `switch (type)` (args assembly), after the `scanQrCode`/`getLocation` case, add:

```typescript
      case WidgetMobileActionType.startLiveLocation:
        argsObservable = defer(() =>
          this.resolveMobileActionTargetEntity(mobileAction, entityId)).pipe(
          map((targetEntityId) => [this.buildLiveTrackingConfig(mobileAction, targetEntityId)])
        );
        break;
      case WidgetMobileActionType.stopLiveLocation:
        argsObservable = of([]);
        break;
```

Confirm `defer` is in the `rxjs` import list (added by the 1b hardening commit); add if missing. Confirm the `argsObservable.subscribe({...})` has an `error:` handler routing to `handleWidgetMobileActionError` — it does for the map/phone-call functions; the new case reuses the same path.

- [ ] **Step 2: Add the config builder**

Add a private method next to `saveMobileActionLocation`:

```typescript
  private buildLiveTrackingConfig(mobileAction: WidgetMobileActionDescriptor,
                                  targetEntityId: EntityId): object {
    return {
      target: {
        entityType: targetEntityId.entityType,
        id: targetEntityId.id
      },
      latitudeKey: mobileAction.latitudeKey || 'latitude',
      longitudeKey: mobileAction.longitudeKey || 'longitude',
      includeMetadata: !!mobileAction.includeMetadata,
      mirrorToAttributes: !!mobileAction.mirrorToAttributes,
      accuracy: mobileAction.accuracy || MobileActionLocationAccuracy.balanced,
      distanceFilterMeters: isDefinedAndNotNull(mobileAction.distanceFilterMeters)
        ? mobileAction.distanceFilterMeters : null,
      intervalSeconds: isDefinedAndNotNull(mobileAction.intervalSeconds)
        ? mobileAction.intervalSeconds : null,
      maxDurationMinutes: isDefinedAndNotNull(mobileAction.maxDurationMinutes)
        ? mobileAction.maxDurationMinutes : null,
      writeStatusAttributes: mobileAction.writeStatusAttributes !== false,
      trackedBy: getCurrentAuthUser(this.store)?.sub || null
    };
  }
```

Add `MobileActionLocationAccuracy` to the `@shared/models/widget.models` import list.

- [ ] **Step 3: Route the launched result**

In the result-handling switch (the `hasResult` branch), extend the launched-result case group:

```typescript
                    case WidgetMobileActionType.mapDirection:
                    case WidgetMobileActionType.mapLocation:
                    case WidgetMobileActionType.makePhoneCall:
                    case WidgetMobileActionType.startLiveLocation:
                    case WidgetMobileActionType.stopLiveLocation:
```

(the body — `processLaunchResultFunction` invocation — is unchanged).

- [ ] **Step 4: Verify and commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/widget.component.ts
git commit -m "feat(mobile-actions): dispatch live location tracking start/stop to the mobile app"
```
Expected: only the 4 pre-existing photoswipe errors.

---

### Task 9: End-to-end smoke test (manual, real device)

**Files:** none (verification only).

- [ ] **Step 1: Stack** — local TB CE backend + `yarn start` ui-ngx + Flutter debug build on the Android phone (endpoint = machine LAN IP).

- [ ] **Step 2: Start action** — dashboard widget action → Mobile action → **Start live location tracking**: target Current user, accuracy Balanced, distance filter 10 m, status attributes on. Trigger from the phone: tracking bar appears on all main pages, Android notification visible, `gpsActive=true`/`gpsTrackedBy` attributes on your user, telemetry `latitude`/`longitude` flowing, `gpsLastUpdateTime` refreshing.

- [ ] **Step 3: Bar controls** — Pause (bar shows paused, `gpsActive=false`, telemetry stops), Resume, Hide (collapses to pill; tracking continues), tap bar → session screen shows live counters.

- [ ] **Step 4: Background** — lock the screen 10 min while moving; telemetry keeps flowing (phase 1a already proved the plumbing; this validates it wired through the service).

- [ ] **Step 5: Stop paths** — dashboard **Stop live location tracking** action stops the session (bar disappears, `gpsActive=false`); repeat stop → dashboard's empty-result handler fires. Start with max duration 2 min → auto-stops.

- [ ] **Step 6: Replace semantics** — start tracking targeting entity A, then start again targeting entity B → A gets `gpsActive=false`, B `true`, single session.

- [ ] **Step 7: Old-app compat** — (optional) an app build without this feature receiving `startLiveLocation` → explicit "unknown action" error dialog on the dashboard.
