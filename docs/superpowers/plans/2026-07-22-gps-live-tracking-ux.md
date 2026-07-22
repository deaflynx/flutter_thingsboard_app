# GPS Live Tracking UX & Persistence (Phase 1d) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the phase-1c live-tracking experience: friendly entity name, a bundle-gated "Live location tracking" page (replacing the debug spike) with a persisted last-session + "Start again" idle state, and a full-width pulsing collapsed bar.

**Architecture:** The menu page is registered as a server-driven mobile-bundle page type (`thingsboard` repo: one backend enum value + one ui-ngx models file), hidden by default and mapped to a route app-side. The app persists one `LastTrackingRecord` via `TbStorage` (written at session start, updated at end), resolves the target's display name through the Dart client's entity-data query, and relaunches a stored config from the idle page.

**Tech Stack:** Java (thingsboard backend), Angular 18 (ui-ngx), Flutter/Dart, Riverpod codegen, `built_value` Dart client, `flutter_hooks`, `TbStorage` (secure storage).

## Global Constraints

- Repos: `thingsboard` at `/home/artem/projects/thingsboard` branch `feat/gps-tracker` (backend + ui-ngx); Flutter at `/home/artem/projects/mobile/flutter_thingsboard_app` branch `feat/gps-tracker`. Leave the pre-existing uncommitted `ui-ngx/proxy.conf.js` change alone.
- Conventional Commits; **no** `Co-Authored-By` lines.
- Dart: `dart format` on changed files only; `flutter analyze` must stay clean for changed files; codegen via `flutter pub run build_runner build --delete-conflicting-outputs` after touching `@freezed`/`@riverpod`; l10n via `flutter pub run intl_utils:generate`.
- ui-ngx verification: `cd ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json` — expect exit 0 (only pre-existing photoswipe errors, if any). No new ui-ngx test scaffolding (repo convention).
- Production Flutter UI strings are localized (`S.of(context).key`, keys added to `lib/l10n/intl_en.arb` only — other locales fall back to English).
- The page id string on the wire is `LIVE_LOCATION_TRACKING` (backend `DefaultPageId` / ui-ngx `MobileMenuPath`); the app's `Pages` enum value is `live_location_tracking` (its `.name.toUpperCase()` must equal `LIVE_LOCATION_TRACKING`, which `pagesFromString` relies on).
- Defaults locked in design: name resolved app-side via API with fallback `DEVICE · <first 8 chars of id>`; "Start again" re-derives `trackedBy` from the current logged-in user; the record is device-global and cleared on logout. Spec: `docs/superpowers/specs/2026-07-22-gps-live-tracking-ux-design.md`.

---

### Task 1: thingsboard repo — register the `LIVE_LOCATION_TRACKING` bundle page (backend + ui-ngx)

**Files:**
- Modify: `/home/artem/projects/thingsboard/common/data/src/main/java/org/thingsboard/server/common/data/mobile/layout/DefaultPageId.java`
- Modify: `/home/artem/projects/thingsboard/ui-ngx/src/app/shared/models/mobile-app.models.ts` (enum ~L96-107, `defaultMobileMenu` ~L169-179, `hideDefaultMenuItems` ~L181-184, `defaultMobilePageMap` ~L232-305)

**Interfaces:**
- Produces: a default mobile page id `LIVE_LOCATION_TRACKING`, present in every bundle layout but `visible: false` by default (admin toggles it on in Mobile center → Bundles → Layout). Icon `my_location`, label `Live location tracking`.

- [ ] **Step 1: Add the backend enum constant**

In `DefaultPageId.java`, add `LIVE_LOCATION_TRACKING` after `DASHBOARDS`:

```java
public enum DefaultPageId {

    HOME,
    ALARMS,
    DEVICES,
    CUSTOMERS,
    ASSETS,
    AUDIT_LOGS,
    NOTIFICATIONS,
    DEVICE_LIST,
    DASHBOARDS,
    LIVE_LOCATION_TRACKING
}
```

- [ ] **Step 2: Add the ui-ngx enum member**

In `mobile-app.models.ts`, add to the `MobileMenuPath` enum:

```ts
  NOTIFICATIONS = 'NOTIFICATIONS',
  LIVE_LOCATION_TRACKING = 'LIVE_LOCATION_TRACKING'
```

- [ ] **Step 3: Seed it into the default menu, hidden by default**

Append to `defaultMobileMenu`:

```ts
  MobileMenuPath.DASHBOARDS,
  MobileMenuPath.LIVE_LOCATION_TRACKING
];
```

Append to `hideDefaultMenuItems` (this makes it listed-but-off by default):

```ts
export const hideDefaultMenuItems = [
  MobileMenuPath.DEVICE_LIST,
  MobileMenuPath.DASHBOARDS,
  MobileMenuPath.LIVE_LOCATION_TRACKING
];
```

- [ ] **Step 4: Add the icon/label map entry**

Add to `defaultMobilePageMap`:

```ts
  [ MobileMenuPath.LIVE_LOCATION_TRACKING, { id: MobileMenuPath.LIVE_LOCATION_TRACKING, icon: 'my_location', label: 'Live location tracking' } ]
```

- [ ] **Step 5: Verify ui-ngx compiles**

Run: `cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json`
Expected: exit 0 (only any pre-existing photoswipe errors).

- [ ] **Step 6: Commit**

```bash
cd /home/artem/projects/thingsboard
git add common/data/src/main/java/org/thingsboard/server/common/data/mobile/layout/DefaultPageId.java ui-ngx/src/app/shared/models/mobile-app.models.ts
git commit -m "feat(mobile): add Live location tracking as a hidden-by-default bundle page"
```

---

### Task 2: Flutter — `LiveTrackingConfig.toJson` (round-trip for persistence)

**Files:**
- Modify: `lib/utils/services/live_location_tracking/model/live_tracking_config.dart`
- Test: `test/utils/services/live_location_tracking/live_tracking_config_test.dart` (existing — add cases)

**Interfaces:**
- Produces: `LiveTrackingConfig.toJson() → Map<String, dynamic>` and `LiveTrackingTarget.toJson()`; `LiveTrackingConfig.fromJson(config.toJson())` reproduces an equal config. Consumed by Task 4 (record) and Task 7 ("Start again").

- [ ] **Step 1: Add the failing round-trip test**

Append to `test/utils/services/live_location_tracking/live_tracking_config_test.dart` inside `main()`:

```dart
  test('toJson round-trips through fromJson', () {
    const original = LiveTrackingConfig(
      target: LiveTrackingTarget(entityType: 'DEVICE', id: 'abc-123'),
      latitudeKey: 'lat',
      longitudeKey: 'lng',
      includeMetadata: true,
      mirrorToAttributes: true,
      accuracy: LocationAccuracyLevel.high,
      distanceFilterMeters: 25,
      intervalSeconds: 60,
      maxDurationMinutes: 120,
      writeStatusAttributes: false,
      trackedBy: 'user@example.com',
    );

    final restored = LiveTrackingConfig.fromJson(original.toJson());

    expect(restored.target.entityType, 'DEVICE');
    expect(restored.target.id, 'abc-123');
    expect(restored.latitudeKey, 'lat');
    expect(restored.longitudeKey, 'lng');
    expect(restored.includeMetadata, true);
    expect(restored.mirrorToAttributes, true);
    expect(restored.accuracy, LocationAccuracyLevel.high);
    expect(restored.distanceFilterMeters, 25);
    expect(restored.intervalSeconds, 60);
    expect(restored.maxDurationMinutes, 120);
    expect(restored.writeStatusAttributes, false);
    expect(restored.trackedBy, 'user@example.com');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_config_test.dart`
Expected: FAIL — `toJson` not defined.

- [ ] **Step 3: Implement `toJson`**

In `LiveTrackingTarget`, add:

```dart
  Map<String, dynamic> toJson() => {'entityType': entityType, 'id': id};
```

In `LiveTrackingConfig`, add (and a private `_accuracyToString`):

```dart
  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    'latitudeKey': latitudeKey,
    'longitudeKey': longitudeKey,
    'includeMetadata': includeMetadata,
    'mirrorToAttributes': mirrorToAttributes,
    'accuracy': _accuracyToString(accuracy),
    'distanceFilterMeters': distanceFilterMeters,
    'intervalSeconds': intervalSeconds,
    'maxDurationMinutes': maxDurationMinutes,
    'writeStatusAttributes': writeStatusAttributes,
    'trackedBy': trackedBy,
  };

  static String _accuracyToString(LocationAccuracyLevel level) =>
      switch (level) {
        LocationAccuracyLevel.high => 'HIGH',
        LocationAccuracyLevel.low => 'LOW',
        LocationAccuracyLevel.balanced => 'BALANCED',
      };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_config_test.dart`
Expected: PASS (all cases).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/utils/services/live_location_tracking/model/live_tracking_config.dart test/utils/services/live_location_tracking/live_tracking_config_test.dart
flutter analyze 2>&1 | grep live_tracking_config ; echo "expect no output above"
git add lib/utils/services/live_location_tracking/model/live_tracking_config.dart test/utils/services/live_location_tracking/live_tracking_config_test.dart
git commit -m "feat(location): add LiveTrackingConfig.toJson for session persistence"
```

---

### Task 3: Flutter — `LastTrackingRecord` model

**Files:**
- Create: `lib/utils/services/live_location_tracking/model/last_tracking_record.dart`
- Test: `test/utils/services/live_location_tracking/last_tracking_record_test.dart`

**Interfaces:**
- Consumes: `LiveTrackingConfig` (Task 2).
- Produces: `enum TrackingEndReason { manual, maxDuration, interrupted }`; `LastTrackingRecord` (plain class, not freezed) with fields `configJson: Map<String, dynamic>`, `targetName: String?`, `startedAt: DateTime`, `endedAt: DateTime?`, `fixCount/savedCount/saveErrorCount: int`, `lastLat/lastLng: double?`, `lastError: String?`, `endReason: TrackingEndReason`; `toJson()`/`fromJson()`; `config` getter returning `LiveTrackingConfig.fromJson(configJson)`. Consumed by Tasks 4, 6, 7.

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/live_location_tracking/last_tracking_record_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

void main() {
  final json = {
    'configJson': {
      'target': {'entityType': 'DEVICE', 'id': 'd-1'},
    },
    'targetName': 'My Tracker',
    'startedAt': 1720000000000,
    'endedAt': 1720000600000,
    'fixCount': 12,
    'savedCount': 11,
    'saveErrorCount': 1,
    'lastLat': 1.5,
    'lastLng': 2.5,
    'lastError': 'boom',
    'endReason': 'maxDuration',
  };

  test('fromJson/toJson round-trips', () {
    final record = LastTrackingRecord.fromJson(json);
    expect(record.targetName, 'My Tracker');
    expect(record.startedAt.millisecondsSinceEpoch, 1720000000000);
    expect(record.endedAt?.millisecondsSinceEpoch, 1720000600000);
    expect(record.fixCount, 12);
    expect(record.savedCount, 11);
    expect(record.saveErrorCount, 1);
    expect(record.lastLat, 1.5);
    expect(record.lastLng, 2.5);
    expect(record.lastError, 'boom');
    expect(record.endReason, TrackingEndReason.maxDuration);
    expect(record.config.target.id, 'd-1');
    expect(LastTrackingRecord.fromJson(record.toJson()).toJson(), record.toJson());
  });

  test('unknown endReason falls back to interrupted', () {
    final record = LastTrackingRecord.fromJson({
      ...json,
      'endReason': 'nonsense',
    });
    expect(record.endReason, TrackingEndReason.interrupted);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/services/live_location_tracking/last_tracking_record_test.dart`
Expected: FAIL — file/class don't exist.

- [ ] **Step 3: Implement the model**

Create `lib/utils/services/live_location_tracking/model/last_tracking_record.dart`:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';

enum TrackingEndReason { manual, maxDuration, interrupted }

TrackingEndReason _endReasonFromString(String? value) =>
    TrackingEndReason.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TrackingEndReason.interrupted,
    );

/// Snapshot of the most recent tracking session, persisted so the idle page
/// can show it and relaunch it ("Start again"). Written at session start and
/// updated at session end.
class LastTrackingRecord {
  const LastTrackingRecord({
    required this.configJson,
    required this.startedAt,
    required this.endReason,
    this.targetName,
    this.endedAt,
    this.fixCount = 0,
    this.savedCount = 0,
    this.saveErrorCount = 0,
    this.lastLat,
    this.lastLng,
    this.lastError,
  });

  factory LastTrackingRecord.fromJson(Map<String, dynamic> json) =>
      LastTrackingRecord(
        configJson: Map<String, dynamic>.from(json['configJson'] as Map),
        targetName: json['targetName'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['startedAt'] as num).toInt(),
        ),
        endedAt:
            json['endedAt'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                  (json['endedAt'] as num).toInt(),
                ),
        fixCount: (json['fixCount'] as num?)?.toInt() ?? 0,
        savedCount: (json['savedCount'] as num?)?.toInt() ?? 0,
        saveErrorCount: (json['saveErrorCount'] as num?)?.toInt() ?? 0,
        lastLat: (json['lastLat'] as num?)?.toDouble(),
        lastLng: (json['lastLng'] as num?)?.toDouble(),
        lastError: json['lastError'] as String?,
        endReason: _endReasonFromString(json['endReason'] as String?),
      );

  final Map<String, dynamic> configJson;
  final String? targetName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int fixCount;
  final int savedCount;
  final int saveErrorCount;
  final double? lastLat;
  final double? lastLng;
  final String? lastError;
  final TrackingEndReason endReason;

  LiveTrackingConfig get config => LiveTrackingConfig.fromJson(configJson);

  Map<String, dynamic> toJson() => {
    'configJson': configJson,
    'targetName': targetName,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt?.millisecondsSinceEpoch,
    'fixCount': fixCount,
    'savedCount': savedCount,
    'saveErrorCount': saveErrorCount,
    'lastLat': lastLat,
    'lastLng': lastLng,
    'lastError': lastError,
    'endReason': endReason.name,
  };

  LastTrackingRecord copyWith({
    String? targetName,
    DateTime? endedAt,
    int? fixCount,
    int? savedCount,
    int? saveErrorCount,
    double? lastLat,
    double? lastLng,
    String? lastError,
    TrackingEndReason? endReason,
  }) => LastTrackingRecord(
    configJson: configJson,
    targetName: targetName ?? this.targetName,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    fixCount: fixCount ?? this.fixCount,
    savedCount: savedCount ?? this.savedCount,
    saveErrorCount: saveErrorCount ?? this.saveErrorCount,
    lastLat: lastLat ?? this.lastLat,
    lastLng: lastLng ?? this.lastLng,
    lastError: lastError ?? this.lastError,
    endReason: endReason ?? this.endReason,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/services/live_location_tracking/last_tracking_record_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/utils/services/live_location_tracking/model/last_tracking_record.dart test/utils/services/live_location_tracking/last_tracking_record_test.dart
flutter analyze 2>&1 | grep last_tracking_record ; echo "expect no output above"
git add lib/utils/services/live_location_tracking/model/last_tracking_record.dart test/utils/services/live_location_tracking/last_tracking_record_test.dart
git commit -m "feat(location): add LastTrackingRecord model"
```

---

### Task 4: Flutter — `ILiveTrackingStore` (TbStorage-backed) + DI

**Files:**
- Create: `lib/utils/services/live_location_tracking/i_live_tracking_store.dart`
- Create: `lib/utils/services/live_location_tracking/live_tracking_store.dart`
- Modify: `lib/constants/database_keys.dart` (add key)
- Modify: `lib/locator.dart` (register after the `ILiveLocationTrackingService` block, ~L73)
- Test: `test/utils/services/live_location_tracking/live_tracking_store_test.dart`

**Interfaces:**
- Consumes: `LastTrackingRecord` (Task 3), `TbStorage` (`getItem`/`setItem`/`deleteItem`), `TbLogger`.
- Produces: `ILiveTrackingStore { Future<LastTrackingRecord?> read(); Future<void> write(LastTrackingRecord record); Future<void> clear(); }`; GetIt registration `getIt<ILiveTrackingStore>()`. Consumed by Tasks 6, 7, 10.

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/live_location_tracking/live_tracking_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

class FakeStorage implements TbStorage {
  final _map = <String, dynamic>{};

  @override
  Future<dynamic> getItem(String key) async => _map[key];

  @override
  Future<void> setItem(String key, dynamic value) async => _map[key] = value;

  @override
  Future<void> deleteItem(String key) async => _map.remove(key);
}

void main() {
  late FakeStorage storage;
  late LiveTrackingStore store;

  setUp(() {
    storage = FakeStorage();
    store = LiveTrackingStore(storage: storage, logger: TbLogger());
  });

  final record = LastTrackingRecord(
    configJson: const {
      'target': {'entityType': 'DEVICE', 'id': 'd-1'},
    },
    startedAt: DateTime.fromMillisecondsSinceEpoch(1720000000000),
    endReason: TrackingEndReason.interrupted,
    targetName: 'My Tracker',
  );

  test('read returns null when nothing stored', () async {
    expect(await store.read(), isNull);
  });

  test('write then read round-trips', () async {
    await store.write(record);
    final read = await store.read();
    expect(read?.targetName, 'My Tracker');
    expect(read?.config.target.id, 'd-1');
  });

  test('clear removes the record', () async {
    await store.write(record);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('read returns null on corrupt json', () async {
    await storage.setItem('live_tracking_last_record', '{not valid');
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_store_test.dart`
Expected: FAIL — `LiveTrackingStore` doesn't exist.

- [ ] **Step 3: Add the storage key**

In `lib/constants/database_keys.dart`, add a constant alongside the existing keys:

```dart
  static const liveTrackingLastRecord = 'live_tracking_last_record';
```

- [ ] **Step 4: Create the interface**

Create `lib/utils/services/live_location_tracking/i_live_tracking_store.dart`:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

/// Persists the single most-recent tracking session so the idle page can show
/// and relaunch it. Device-global; cleared on logout.
abstract interface class ILiveTrackingStore {
  Future<LastTrackingRecord?> read();

  Future<void> write(LastTrackingRecord record);

  Future<void> clear();
}
```

- [ ] **Step 5: Implement the store**

Create `lib/utils/services/live_location_tracking/live_tracking_store.dart`:

```dart
import 'dart:convert';

import 'package:thingsboard_app/constants/database_keys.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

class LiveTrackingStore implements ILiveTrackingStore {
  LiveTrackingStore({required TbStorage storage, required TbLogger logger})
    : _storage = storage,
      _log = logger;

  final TbStorage _storage;
  final TbLogger _log;

  @override
  Future<LastTrackingRecord?> read() async {
    try {
      final raw = await _storage.getItem(DatabaseKeys.liveTrackingLastRecord);
      if (raw is! String) {
        return null;
      }
      return LastTrackingRecord.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e, s) {
      _log.error('LiveTrackingStore.read failed', e, s);
      return null;
    }
  }

  @override
  Future<void> write(LastTrackingRecord record) async {
    try {
      await _storage.setItem(
        DatabaseKeys.liveTrackingLastRecord,
        jsonEncode(record.toJson()),
      );
    } catch (e, s) {
      _log.error('LiveTrackingStore.write failed', e, s);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.deleteItem(DatabaseKeys.liveTrackingLastRecord);
    } catch (e, s) {
      _log.error('LiveTrackingStore.clear failed', e, s);
    }
  }
}
```

- [ ] **Step 6: Register in GetIt**

In `lib/locator.dart`, add imports and register after the `ILiveLocationTrackingService` registration:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_store.dart';
```

```dart
    ..registerLazySingleton<ILiveTrackingStore>(
      () => LiveTrackingStore(storage: getIt(), logger: getIt()),
    )
```

- [ ] **Step 7: Run test, analyze, commit**

```bash
flutter test test/utils/services/live_location_tracking/live_tracking_store_test.dart
flutter analyze 2>&1 | grep -E "live_tracking_store|database_keys|locator" ; echo "expect no output above"
dart format lib/utils/services/live_location_tracking/i_live_tracking_store.dart lib/utils/services/live_location_tracking/live_tracking_store.dart lib/constants/database_keys.dart lib/locator.dart test/utils/services/live_location_tracking/live_tracking_store_test.dart
git add lib/utils/services/live_location_tracking/ lib/constants/database_keys.dart lib/locator.dart test/utils/services/live_location_tracking/live_tracking_store_test.dart
git commit -m "feat(location): add ILiveTrackingStore for last-session persistence"
```

---

### Task 5: Flutter — entity name resolver + display-name helper

**Files:**
- Modify: `lib/utils/services/entity_query_api.dart` (add `createEntityNameQuery`)
- Create: `lib/utils/services/live_location_tracking/i_entity_name_resolver.dart`
- Create: `lib/utils/services/live_location_tracking/entity_name_resolver.dart`
- Create: `lib/utils/services/live_location_tracking/live_tracking_display.dart` (pure fallback helper)
- Modify: `lib/locator.dart`
- Test: `test/utils/services/live_location_tracking/live_tracking_display_test.dart`

**Interfaces:**
- Consumes: `ITbClientService.client.getEntityQueryControllerApi().findEntityDataByQuery`, the `EntityDataHelpers.field` extension (`entity_query_api.dart`), `LiveTrackingTarget`.
- Produces: `IEntityNameResolver { Future<String?> resolveName(String entityType, String id); }` (registered in GetIt); `displayTargetName(String? resolved, LiveTrackingTarget target) → String` returning `resolved` when non-empty else `'${target.entityType} · ${shortId}'`. Consumed by Tasks 6, 7.

- [ ] **Step 1: Write the failing test (pure helper)**

Create `test/utils/services/live_location_tracking/live_tracking_display_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_display.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';

void main() {
  const target = LiveTrackingTarget(
    entityType: 'DEVICE',
    id: 'f3eda640-42e8-11f1-af6c-63e319b36637',
  );

  test('uses resolved name when present', () {
    expect(displayTargetName('My Tracker', target), 'My Tracker');
  });

  test('falls back to type and short id when name is null', () {
    expect(displayTargetName(null, target), 'DEVICE · f3eda640');
  });

  test('falls back when name is empty/whitespace', () {
    expect(displayTargetName('   ', target), 'DEVICE · f3eda640');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_display_test.dart`
Expected: FAIL — `displayTargetName` not defined.

- [ ] **Step 3: Implement the pure helper**

Create `lib/utils/services/live_location_tracking/live_tracking_display.dart`:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';

/// Human-friendly label for a tracking target: the resolved entity name when
/// available, otherwise `<TYPE> · <first 8 chars of id>`.
String displayTargetName(String? resolved, LiveTrackingTarget target) {
  if (resolved != null && resolved.trim().isNotEmpty) {
    return resolved;
  }
  final shortId =
      target.id.length > 8 ? target.id.substring(0, 8) : target.id;
  return '${target.entityType} · $shortId';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/services/live_location_tracking/live_tracking_display_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the name query builder**

In `lib/utils/services/entity_query_api.dart`, add a static method to `EntityQueryApi` (mirrors the existing `SingleEntityFilter`/`AliasEntityId` built_value pattern; `EntityType.valueOf` maps the wire string):

```dart
  static EntityDataQuery createEntityNameQuery(String entityType, String id) {
    return EntityDataQuery(
      (b) =>
          b
            ..entityFilter = SingleEntityFilter(
              (b) =>
                  b
                    ..type = 'singleEntity'
                    ..singleEntity =
                        AliasEntityId(
                          (b) =>
                              b
                                ..entityType = EntityType.valueOf(entityType)
                                ..id = id,
                        ).toBuilder(),
            )
            ..entityFields =
                BuiltList<EntityKey>([
                  EntityKey(
                    (b) =>
                        b
                          ..type = EntityKeyType.ENTITY_FIELD
                          ..key = 'name',
                  ),
                ]).toBuilder()
            ..pageLink =
                EntityDataPageLink((b) => b..pageSize = 1).toBuilder(),
    );
  }
```

- [ ] **Step 6: Create the resolver interface + impl**

Create `lib/utils/services/live_location_tracking/i_entity_name_resolver.dart`:

```dart
/// Resolves an entity's display name from its type + id. Returns null on any
/// failure (offline, deleted entity, unknown type) so callers fall back.
abstract interface class IEntityNameResolver {
  Future<String?> resolveName(String entityType, String id);
}
```

Create `lib/utils/services/live_location_tracking/entity_name_resolver.dart`:

```dart
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/entity_query_api.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';

class EntityNameResolver implements IEntityNameResolver {
  EntityNameResolver({required ITbClientService clientService, required TbLogger logger})
    : _clientService = clientService,
      _log = logger;

  final ITbClientService _clientService;
  final TbLogger _log;

  @override
  Future<String?> resolveName(String entityType, String id) async {
    try {
      final query = EntityQueryApi.createEntityNameQuery(entityType, id);
      final response = await _clientService.client
          .getEntityQueryControllerApi()
          .findEntityDataByQuery(entityDataQuery: query);
      final data = response.data?.data;
      if (data == null || data.isEmpty) {
        return null;
      }
      return data.first.field('name');
    } catch (e, s) {
      _log.error('EntityNameResolver.resolveName failed', e, s);
      return null;
    }
  }
}
```

- [ ] **Step 7: Register in GetIt**

In `lib/locator.dart` add imports and register (near the store):

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/entity_name_resolver.dart';
```

```dart
    ..registerLazySingleton<IEntityNameResolver>(
      () => EntityNameResolver(clientService: getIt(), logger: getIt()),
    )
```

- [ ] **Step 8: Analyze, format, commit**

```bash
flutter analyze 2>&1 | grep -E "entity_name_resolver|entity_query_api|live_tracking_display|locator" ; echo "expect no output above"
dart format lib/utils/services/entity_query_api.dart lib/utils/services/live_location_tracking/i_entity_name_resolver.dart lib/utils/services/live_location_tracking/entity_name_resolver.dart lib/utils/services/live_location_tracking/live_tracking_display.dart lib/locator.dart test/utils/services/live_location_tracking/live_tracking_display_test.dart
git add lib/utils/services/entity_query_api.dart lib/utils/services/live_location_tracking/ lib/locator.dart test/utils/services/live_location_tracking/live_tracking_display_test.dart
git commit -m "feat(location): add entity name resolver and display-name fallback"
```

> Note: `EntityNameResolver` itself is not unit-tested (it wraps the built_value client, which the repo does not mock); its failure path returns null and is covered by the `displayTargetName` fallback tests. Verify the query at runtime in Task 11's smoke test.

---

### Task 6: Flutter — wire store + name resolver + end reasons into the tracking service

**Files:**
- Modify: `lib/utils/services/live_location_tracking/live_location_tracking_service.dart`
- Modify: `lib/locator.dart` (pass new deps into `LiveLocationTrackingService`)
- Test: `test/utils/services/live_location_tracking/live_location_tracking_service_test.dart` (existing — extend fakes + add cases)

**Interfaces:**
- Consumes: `ILiveTrackingStore` (Task 4), `IEntityNameResolver` (Task 5), `LastTrackingRecord`/`TrackingEndReason` (Task 3).
- Produces: on `start`, writes a `LastTrackingRecord` (endReason `interrupted`, resolved `targetName`); on end via `stop` writes `endReason: manual`, via max-duration writes `endReason: maxDuration`, both with final counts + last coordinates + `lastError`. No interface signature change to `ILiveLocationTrackingService`.

- [ ] **Step 1: Extend the test fakes and add cases**

In `test/utils/services/live_location_tracking/live_location_tracking_service_test.dart`, add fakes near the top:

```dart
class FakeStore implements ILiveTrackingStore {
  LastTrackingRecord? record;
  int writeCount = 0;

  @override
  Future<LastTrackingRecord?> read() async => record;

  @override
  Future<void> write(LastTrackingRecord r) async {
    record = r;
    writeCount++;
  }

  @override
  Future<void> clear() async => record = null;
}

class FakeNameResolver implements IEntityNameResolver {
  String? name = 'My Tracker';

  @override
  Future<String?> resolveName(String entityType, String id) async => name;
}
```

Add imports:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
```

Update `setUp` to construct the service with the new deps:

```dart
  late FakeStore store;
  late FakeNameResolver nameResolver;

  setUp(() {
    location = FakeLocationService();
    remote = FakeRemote();
    store = FakeStore();
    nameResolver = FakeNameResolver();
    service = LiveLocationTrackingService(
      locationService: location,
      remote: remote,
      logger: TbLogger(),
      store: store,
      nameResolver: nameResolver,
    );
  });
```

Add cases:

```dart
  test('start writes an interrupted record with the resolved name', () async {
    await service.start(const LiveTrackingConfig(target: target));
    expect(store.record, isNotNull);
    expect(store.record!.targetName, 'My Tracker');
    expect(store.record!.endReason, TrackingEndReason.interrupted);
    expect(store.record!.endedAt, isNull);
  });

  test('stop updates the record with manual end reason and counts', () async {
    await service.start(const LiveTrackingConfig(target: target));
    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    await service.stop();
    expect(store.record!.endReason, TrackingEndReason.manual);
    expect(store.record!.endedAt, isNotNull);
    expect(store.record!.fixCount, 1);
    expect(store.record!.savedCount, 1);
    expect(store.record!.lastLat, 1.0);
    expect(store.record!.lastLng, 2.0);
  });

  test('max-duration end writes maxDuration reason', () {
    fakeAsync((async) {
      service.start(
        const LiveTrackingConfig(target: target, maxDurationMinutes: 5),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5, seconds: 1));
      async.flushMicrotasks();
      expect(store.record!.endReason, TrackingEndReason.maxDuration);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/services/live_location_tracking/live_location_tracking_service_test.dart`
Expected: FAIL — constructor has no `store`/`nameResolver`.

- [ ] **Step 3: Implement the service changes**

In `live_location_tracking_service.dart`:

Add imports:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
```

Extend the constructor and fields:

```dart
  LiveLocationTrackingService({
    required ILocationService locationService,
    required ILiveTrackingRemote remote,
    required TbLogger logger,
    required ILiveTrackingStore store,
    required IEntityNameResolver nameResolver,
    this.backgroundConfig = const BackgroundTrackingConfig(
      notificationTitle: 'ThingsBoard',
      notificationText: 'Live location tracking is active',
    ),
  }) : _locationService = locationService,
       _remote = remote,
       _log = logger,
       _store = store,
       _nameResolver = nameResolver;

  final ILocationService _locationService;
  final ILiveTrackingRemote _remote;
  final TbLogger _log;
  final ILiveTrackingStore _store;
  final IEntityNameResolver _nameResolver;
```

Replace `start` so it seeds a record (endReason interrupted) and resolves the name:

```dart
  @override
  Future<void> start(LiveTrackingConfig config) async {
    await stop();
    final startedAt = DateTime.now();
    _setSession(
      LiveTrackingSession(
        config: config,
        status: LiveTrackingStatus.tracking,
        startedAt: startedAt,
      ),
    );
    final name = await _nameResolver.resolveName(
      config.target.entityType,
      config.target.id,
    );
    await _store.write(
      LastTrackingRecord(
        configJson: config.toJson(),
        targetName: name,
        startedAt: startedAt,
        endReason: TrackingEndReason.interrupted,
      ),
    );
    await _writeStatusAttributes({
      'gpsActive': true,
      if (config.trackedBy != null) 'gpsTrackedBy': config.trackedBy,
    });
    _subscribe(config);
    final maxDuration = config.maxDurationMinutes;
    if (maxDuration != null) {
      _maxDurationTimer = Timer(
        Duration(minutes: maxDuration),
        () => _finish(TrackingEndReason.maxDuration),
      );
    }
  }
```

Replace `stop` to delegate to a private `_finish(manual)`, and add `_finish`:

```dart
  @override
  Future<void> stop() => _finish(TrackingEndReason.manual);

  Future<void> _finish(TrackingEndReason reason) async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _cancelSubscription();
    final current = _session;
    if (current != null) {
      await _writeStatusAttributes({'gpsActive': false});
      await _updateRecordOnEnd(current, reason);
      _setSession(null);
    }
  }

  Future<void> _updateRecordOnEnd(
    LiveTrackingSession session,
    TrackingEndReason reason,
  ) async {
    final existing = await _store.read();
    if (existing == null) {
      return;
    }
    await _store.write(
      existing.copyWith(
        endedAt: DateTime.now(),
        fixCount: session.fixCount,
        savedCount: session.savedCount,
        saveErrorCount: session.saveErrorCount,
        lastLat: session.lastFix?.latitude,
        lastLng: session.lastFix?.longitude,
        lastError: session.lastError,
        endReason: reason,
      ),
    );
  }
```

(Leave `pause`, `resume`, `_onFix`, `_saveFix`, `_pauseWithError`, `_subscribe`, `_writeStatusAttributes`, `_setSession`, `_cancelSubscription` unchanged.)

- [ ] **Step 4: Update the locator wiring**

In `lib/locator.dart`, update the `ILiveLocationTrackingService` registration to pass the new deps:

```dart
    ..registerLazySingleton<ILiveLocationTrackingService>(
      () => LiveLocationTrackingService(
        locationService: getIt(),
        remote: getIt(),
        logger: getIt(),
        store: getIt(),
        nameResolver: getIt(),
      ),
    )
```

(Ensure the `ILiveTrackingStore` and `IEntityNameResolver` registrations from Tasks 4–5 appear **before** this one.)

- [ ] **Step 5: Run tests, analyze, commit**

```bash
flutter test test/utils/services/live_location_tracking/
flutter analyze 2>&1 | grep -E "live_location_tracking_service|locator" ; echo "expect no output above"
dart format lib/utils/services/live_location_tracking/live_location_tracking_service.dart lib/locator.dart test/utils/services/live_location_tracking/live_location_tracking_service_test.dart
git add lib/utils/services/live_location_tracking/live_location_tracking_service.dart lib/locator.dart test/utils/services/live_location_tracking/live_location_tracking_service_test.dart
git commit -m "feat(location): persist last session with end reason and resolved name"
```

---

### Task 7: Flutter — name provider, `LiveTrackingPage` (active + idle + Start again), l10n

**Files:**
- Modify: `lib/l10n/intl_en.arb` (append keys)
- Modify: `lib/modules/location_tracking/presentation/provider/live_tracking_provider.dart` (add name + record providers)
- Create: `lib/modules/location_tracking/presentation/view/live_tracking_page.dart`
- Delete: `lib/modules/location_tracking/presentation/view/live_tracking_session_page.dart` (superseded)
- Test: `test/modules/location_tracking/live_tracking_page_test.dart`

**Interfaces:**
- Consumes: `liveTrackingProvider` (session), `ILiveTrackingStore` + `IEntityNameResolver` via `getIt`, `displayTargetName` (Task 5), `LiveTrackingConfig.fromJson` (Task 2), `LastTrackingRecord` (Task 3), current-user email.
- Produces: `LiveTrackingPage` widget; `targetNameProvider` (`FutureProvider.family<String?, ({String entityType, String id})>`); `lastRecordProvider` (`FutureProvider<LastTrackingRecord?>`). Consumed by Task 8 (route).

- [ ] **Step 1: Add l10n keys**

In `lib/l10n/intl_en.arb`, change the current last entry `"liveTrackingLastError": "Last error"` to have a trailing comma and append before the closing `}`:

```json
  "liveTrackingLastError": "Last error",
  "liveTrackingMenuTitle": "Live location tracking",
  "liveTrackingNoRecord": "No active tracking and no recent session.",
  "liveTrackingLastSession": "Last session",
  "liveTrackingStartAgain": "Start again",
  "liveTrackingEnded": "Ended",
  "liveTrackingEndReason": "End reason",
  "liveTrackingEndReasonManual": "Stopped manually",
  "liveTrackingEndReasonMaxDuration": "Reached max duration",
  "liveTrackingEndReasonInterrupted": "Interrupted"
```

Run: `flutter pub run intl_utils:generate`
Expected: `lib/generated/l10n.dart` gains the new getters.

- [ ] **Step 2: Add providers**

In `lib/modules/location_tracking/presentation/provider/live_tracking_provider.dart`, add imports:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
```

Add two providers at the bottom of the file:

```dart
@riverpod
Future<String?> targetName(
  Ref ref, {
  required String entityType,
  required String id,
}) => getIt<IEntityNameResolver>().resolveName(entityType, id);

@riverpod
Future<LastTrackingRecord?> lastRecord(Ref ref) =>
    getIt<ILiveTrackingStore>().read();
```

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: regenerates `live_tracking_provider.g.dart` with `targetNameProvider` and `lastRecordProvider`.

- [ ] **Step 3: Write the failing widget test**

Create `test/modules/location_tracking/live_tracking_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_page.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

class _FakeStore implements ILiveTrackingStore {
  _FakeStore(this.record);
  final LastTrackingRecord? record;
  @override
  Future<LastTrackingRecord?> read() async => record;
  @override
  Future<void> write(LastTrackingRecord r) async {}
  @override
  Future<void> clear() async {}
}

class _FakeResolver implements IEntityNameResolver {
  @override
  Future<String?> resolveName(String entityType, String id) async => null;
}

Widget _wrap() => const ProviderScope(
  child: MaterialApp(
    localizationsDelegates: [S.delegate],
    home: LiveTrackingPage(),
  ),
);

void main() {
  tearDown(() => GetIt.I.reset());

  testWidgets('idle with no record shows the empty message', (tester) async {
    GetIt.I.registerLazySingleton<ILiveTrackingStore>(() => _FakeStore(null));
    GetIt.I.registerLazySingleton<IEntityNameResolver>(() => _FakeResolver());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('No active tracking and no recent session.'), findsOneWidget);
  });

  testWidgets('idle with a record shows Start again', (tester) async {
    final record = LastTrackingRecord(
      configJson: const {
        'target': {'entityType': 'DEVICE', 'id': 'd-1'},
      },
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: DateTime.fromMillisecondsSinceEpoch(60000),
      endReason: TrackingEndReason.manual,
      targetName: 'My Tracker',
    );
    GetIt.I.registerLazySingleton<ILiveTrackingStore>(() => _FakeStore(record));
    GetIt.I.registerLazySingleton<IEntityNameResolver>(() => _FakeResolver());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Start again'), findsOneWidget);
    expect(find.text('My Tracker'), findsWidgets);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/modules/location_tracking/live_tracking_page_test.dart`
Expected: FAIL — `LiveTrackingPage` doesn't exist.

- [ ] **Step 5: Implement `LiveTrackingPage`**

Create `lib/modules/location_tracking/presentation/view/live_tracking_page.dart`. It renders one of three states. (The active-session details reuse the phase-1c layout; the Target row now uses `displayTargetName` fed by `targetNameProvider`.)

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/provider/live_tracking_provider.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_display.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';

class LiveTrackingPage extends ConsumerWidget {
  const LiveTrackingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveTrackingProvider).session;
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).liveTrackingSessionTitle)),
      body:
          session != null
              ? _ActiveSession(session: session)
              : _IdleView(),
    );
  }
}

class _ActiveSession extends ConsumerWidget {
  const _ActiveSession({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = session.status == LiveTrackingStatus.tracking;
    final lastFix = session.lastFix;
    final target = session.config.target;
    final nameAsync = ref.watch(
      targetNameProvider(entityType: target.entityType, id: target.id),
    );
    final name = displayTargetName(nameAsync.valueOrNull, target);
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingTarget),
          subtitle: Text(name),
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

class _IdleView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(lastRecordProvider);
    return recordAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(S.of(context).liveTrackingNoRecord)),
      data: (record) {
        if (record == null) {
          return Center(child: Text(S.of(context).liveTrackingNoRecord));
        }
        return _LastSession(record: record);
      },
    );
  }
}

class _LastSession extends ConsumerWidget {
  const _LastSession({required this.record});

  final LastTrackingRecord record;

  String _endReasonLabel(BuildContext context) => switch (record.endReason) {
    TrackingEndReason.manual => S.of(context).liveTrackingEndReasonManual,
    TrackingEndReason.maxDuration =>
      S.of(context).liveTrackingEndReasonMaxDuration,
    TrackingEndReason.interrupted =>
      S.of(context).liveTrackingEndReasonInterrupted,
  };

  Future<void> _startAgain(WidgetRef ref) async {
    // AuthUser.sub is the current user's email (phase-1c trackedBy semantics);
    // re-derive it so a relaunch is attributed to whoever is logged in now.
    final email = getIt<ITbClientService>().client.getAuthUser()?.sub;
    final config = LiveTrackingConfig.fromJson({
      ...record.configJson,
      if (email != null) 'trackedBy': email,
    });
    await ref.read(liveTrackingProvider.notifier).startConfig(config);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = record.config.target;
    final name = displayTargetName(record.targetName, target);
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingLastSession),
          subtitle: Text(name),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStarted),
          subtitle: Text(record.startedAt.toLocal().toString()),
        ),
        if (record.endedAt != null)
          ListTile(
            title: Text(S.of(context).liveTrackingEnded),
            subtitle: Text(record.endedAt!.toLocal().toString()),
          ),
        ListTile(
          title: Text(S.of(context).liveTrackingEndReason),
          subtitle: Text(_endReasonLabel(context)),
        ),
        ListTile(
          title: Text(
            '${S.of(context).liveTrackingFixes}: ${record.fixCount} · '
            '${S.of(context).liveTrackingSaved}: ${record.savedCount} · '
            '${S.of(context).liveTrackingErrors}: ${record.saveErrorCount}',
          ),
        ),
        if (record.lastLat != null && record.lastLng != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastFix),
            subtitle: Text(
              '${record.lastLat!.toStringAsFixed(6)}, '
              '${record.lastLng!.toStringAsFixed(6)}',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _startAgain(ref),
            icon: const Icon(Icons.play_arrow),
            label: Text(S.of(context).liveTrackingStartAgain),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Add `startConfig` to the provider notifier**

In `live_tracking_provider.dart`, add a method to the `LiveTracking` class (used by "Start again"):

```dart
  Future<void> startConfig(LiveTrackingConfig config) =>
      getIt<ILiveLocationTrackingService>().start(config);
```

Add import:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
```

- [ ] **Step 7: Delete the old session page**

```bash
git rm lib/modules/location_tracking/presentation/view/live_tracking_session_page.dart
```

(Task 8 updates the route + bar that referenced it.)

- [ ] **Step 8: Run test, regen, analyze, commit**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter test test/modules/location_tracking/live_tracking_page_test.dart
flutter analyze 2>&1 | grep -E "live_tracking_page|live_tracking_provider" ; echo "expect no output above"
dart format lib/modules/location_tracking/ test/modules/location_tracking/live_tracking_page_test.dart lib/l10n
git add lib/modules/location_tracking/ lib/l10n/intl_en.arb lib/generated/ test/modules/location_tracking/live_tracking_page_test.dart
git commit -m "feat(location): add Live tracking page with idle last-session and Start again"
```

> `trackedBy` uses `getAuthUser()?.sub` — confirmed as the current user's email in the Dart client's `AuthUser` (`user_models.dart`: `String sub;`, `String? userId;`). The value is only a label.

---

### Task 8: Flutter — page mapping, route rename, spike removal, bar route update

**Files:**
- Modify: `lib/utils/services/layouts/pages_layout.dart` (add enum value)
- Modify: `lib/modules/main/providers/navigation_helper.dart` (4 switches + localized title)
- Modify: `lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart` (rename route, drop spike, point to new page)
- Modify: `lib/modules/more/more_page.dart` (remove `kDebugMode` spike entry + import)
- Modify: `lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart` (update `context.push`)
- Delete: `lib/modules/location_tracking/presentation/view/live_tracking_spike_page.dart`
- Test: `test/modules/location_tracking/navigation_helper_live_tracking_test.dart`

**Interfaces:**
- Consumes: `Pages` enum; `PageLayout`.
- Produces: `Pages.live_location_tracking`; `NavigationHelper.getPath(...) == '/liveTracking'`, `getLabel(...) == 'Live location tracking'`, `getIcon(...) == Icons.my_location`; route constant `LocationTrackingRoutes.liveTracking = '/liveTracking'` builds `LiveTrackingPage`.

- [ ] **Step 1: Write the failing test**

Create `test/modules/location_tracking/navigation_helper_live_tracking_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/modules/main/providers/navigation_helper.dart';
import 'package:thingsboard_app/utils/services/layouts/pages_layout.dart';

void main() {
  const layout = PageLayout(id: Pages.live_location_tracking);

  test('parses LIVE_LOCATION_TRACKING from server string', () {
    expect(pagesFromString('LIVE_LOCATION_TRACKING'), Pages.live_location_tracking);
  });

  test('maps to route, label and icon', () {
    expect(NavigationHelper.getPath(layout), '/liveTracking');
    expect(NavigationHelper.getLabel(layout), 'Live location tracking');
    expect(NavigationHelper.getIcon(layout), Icons.my_location);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/location_tracking/navigation_helper_live_tracking_test.dart`
Expected: FAIL — `Pages.live_location_tracking` doesn't exist.

- [ ] **Step 3: Add the enum value**

In `lib/utils/services/layouts/pages_layout.dart`, add to `Pages` before `undefined`:

```dart
  dashboards,
  live_location_tracking,
  undefined,
```

- [ ] **Step 4: Map it in NavigationHelper**

In `lib/modules/main/providers/navigation_helper.dart`:

`getLabel` — add before the `undefined`/`null` case:

```dart
    case Pages.live_location_tracking:
      return 'Live location tracking';
```

`getIcon` — add before the `undefined`/`null` case:

```dart
    case Pages.live_location_tracking:
      return Icons.my_location;
```

`getPath` — add before the `undefined`/`null` case:

```dart
    case Pages.live_location_tracking:
      return '/liveTracking';
```

`getLocalizedTitle` — add a case in the `switch (id)`:

```dart
      case 'live_location_tracking':
        return s.liveTrackingMenuTitle;
```

- [ ] **Step 5: Rename the route + drop the spike**

Replace `lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart` with:

```dart
import 'package:go_router/go_router.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_page.dart';

class LocationTrackingRoutes {
  static const liveTracking = '/liveTracking';
}

final List<GoRoute> locationTrackingRoutes = [
  GoRoute(
    path: LocationTrackingRoutes.liveTracking,
    builder: (context, state) {
      return const LiveTrackingPage();
    },
  ),
];
```

- [ ] **Step 6: Update the bar's push target**

In `lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart`, change:

```dart
          onTap: () => context.push(LocationTrackingRoutes.liveTracking),
```

- [ ] **Step 7: Remove the debug spike menu entry**

In `lib/modules/more/more_page.dart`, delete the `if (kDebugMode) MoreMenuItemWidget(... liveTrackingSpike ...)` block (the block at ~L85-96) and remove the now-unused `kDebugMode` import if nothing else uses it (check first: `grep -n kDebugMode lib/modules/more/more_page.dart`).

- [ ] **Step 8: Delete the spike page**

```bash
git rm lib/modules/location_tracking/presentation/view/live_tracking_spike_page.dart
```

- [ ] **Step 9: Run tests, analyze, commit**

```bash
flutter test test/modules/location_tracking/
flutter analyze 2>&1 | grep -E "navigation_helper|location_tracking_routes|more_page|live_tracking_bar|pages_layout" ; echo "expect no output above"
dart format lib/utils/services/layouts/pages_layout.dart lib/modules/main/providers/navigation_helper.dart lib/config/routes/v2/routes_config/routes/location_tracking_routes.dart lib/modules/more/more_page.dart lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart test/modules/location_tracking/navigation_helper_live_tracking_test.dart
git add lib/ test/modules/location_tracking/navigation_helper_live_tracking_test.dart
git commit -m "feat(location): map live tracking bundle page and remove debug spike"
```

---

### Task 9: Flutter — collapsed bar polish (full-width, pulsing icon)

**Files:**
- Modify: `lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart`
- Test: `test/modules/location_tracking/live_tracking_bar_test.dart` (existing — add case)

**Interfaces:**
- Consumes: `liveTrackingProvider` (session + hidden). No new produced interface.

- [ ] **Step 1: Add the failing widget test**

Add to `test/modules/location_tracking/live_tracking_bar_test.dart` a case asserting the collapsed bar is full-width and shows `gps_fixed` while tracking. (Match the existing test file's harness for providing a session with `hidden: true`; the existing file already builds the bar with an overridden provider — mirror it.)

```dart
  testWidgets('collapsed bar spans full width and shows gps_fixed when tracking',
      (tester) async {
    // Arrange: session active + hidden == true (reuse this file's existing
    // helper that pumps LiveTrackingBar with a tracking session, then tap Hide
    // or seed hidden=true as the existing tests do).
    // Assert:
    expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
    final material = tester.widget<Material>(
      find.ancestor(of: find.byIcon(Icons.gps_fixed), matching: find.byType(Material)).first,
    );
    expect(material.color, isNotNull);
    final size = tester.getSize(find.byType(Material).first);
    expect(size.width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/location_tracking/live_tracking_bar_test.dart`
Expected: FAIL — collapsed bar is not full-width / not pulsing yet.

- [ ] **Step 3: Implement the pulsing full-width collapsed bar**

In `live_tracking_bar.dart`, add imports:

```dart
import 'package:flutter_hooks/flutter_hooks.dart';
```

Replace the `if (viewState.hidden) { return Material(...); }` block with a call to a new widget, and add that widget at the bottom of the file:

```dart
    if (viewState.hidden) {
      return _CollapsedBar(tracking: tracking);
    }
```

```dart
class _CollapsedBar extends HookConsumerWidget {
  const _CollapsedBar({required this.tracking});

  final bool tracking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 900),
    );
    useEffect(() {
      if (tracking) {
        controller.repeat(reverse: true);
      } else {
        controller.stop();
        controller.value = 1;
      }
      return null;
    }, [tracking]);

    return Material(
      color: colors.primaryContainer,
      child: InkWell(
        onTap: () => ref.read(liveTrackingProvider.notifier).show(),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.35, end: 1).animate(controller),
                child: Icon(
                  tracking ? Icons.gps_fixed : Icons.gps_off,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Change the outer `LiveTrackingBar` from `ConsumerWidget` to `ConsumerWidget` (unchanged) — only the collapsed branch is extracted. Keep the expanded `Material(...)` return as-is.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/modules/location_tracking/live_tracking_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
flutter analyze 2>&1 | grep live_tracking_bar ; echo "expect no output above"
dart format lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart test/modules/location_tracking/live_tracking_bar_test.dart
git add lib/modules/location_tracking/presentation/widgets/live_tracking_bar.dart test/modules/location_tracking/live_tracking_bar_test.dart
git commit -m "feat(location): full-width pulsing collapsed tracking bar"
```

---

### Task 10: Flutter — stop tracking and clear the record on logout

**Files:**
- Modify: `lib/core/context/tb_context.dart` (`logout`, ~L299-314)

**Interfaces:**
- Consumes: `ILiveLocationTrackingService`, `ILiveTrackingStore` via `getIt`.

- [ ] **Step 1: Add the teardown to logout**

In `lib/core/context/tb_context.dart`, inside `logout(...)`, before `await tbClient.logout(...)`, add:

```dart
    await getIt<ILiveLocationTrackingService>().stop();
    await getIt<ILiveTrackingStore>().clear();
```

Add imports if not present:

```dart
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
```

- [ ] **Step 2: Analyze, format, commit**

```bash
flutter analyze 2>&1 | grep tb_context ; echo "expect no output above"
dart format lib/core/context/tb_context.dart
git add lib/core/context/tb_context.dart
git commit -m "feat(location): stop tracking and clear last-session record on logout"
```

---

### Task 11: End-to-end smoke test (manual, real Android device)

**Files:** none (verification only).

- [ ] **Step 1: Stack** — local TB CE backend built with the Task 1 backend change; `yarn start` ui-ngx with the Task 1 model change; Flutter debug build on the Android 16 phone. In **Mobile center → Bundles → Layout**, confirm "Live location tracking" appears in the page list and is **off by default**; toggle it **on** and save.

- [ ] **Step 2: Menu entry** — reopen the app (re-login so the bundle reloads). "Live location tracking" appears in the More menu with the `my_location` icon; the debug "GPS tracking spike" entry is gone.

- [ ] **Step 3: Friendly name** — start tracking from a dashboard action targeting a named device; open the page via the bar → the Target row shows the device **name** (not `DEVICE <uuid>`). Kill network briefly → falls back to `DEVICE · <short id>` without error.

- [ ] **Step 4: Idle + Start again** — stop tracking; open the page from the menu → shows the **last session** summary (name, ended, end reason "Stopped manually", counts, last coordinates) + **Start again**. Tap it → a new session starts for the same entity, `gpsActive=true`, `gpsTrackedBy` = the currently logged-in user.

- [ ] **Step 5: End reasons** — start with max duration 1 min → after auto-stop the idle page shows end reason "Reached max duration". Force-kill the app mid-session, relaunch, open the page → shows "Interrupted" with Start again still available.

- [ ] **Step 6: Collapsed bar** — Hide the bar → it collapses to a **full-width** purple bar with a **pulsing** `gps_fixed` icon while tracking; pause → static `gps_off`; tap → expands.

- [ ] **Step 7: Logout** — log out while a session is active → tracking stops (`gpsActive=false`); log back in → the idle page shows "No active tracking and no recent session." (record cleared).
