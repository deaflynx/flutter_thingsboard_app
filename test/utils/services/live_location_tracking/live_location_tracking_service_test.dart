import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_notifications.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_error.dart';
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

  /// When set, [resolveName] returns this completer's future instead of
  /// resolving immediately, letting tests control exactly when the
  /// (network) name lookup completes relative to other service calls.
  Completer<String?>? pendingCompleter;

  @override
  Future<String?> resolveName(String entityType, String id) {
    final pending = pendingCompleter;
    if (pending != null) {
      return pending.future;
    }
    return Future.value(name);
  }
}

class FakeNotifications implements ILiveTrackingNotifications {
  final shownTargetNames = <String?>[];
  int clearCount = 0;
  bool pausedShown = false;

  @override
  Future<void> showPaused({String? targetName}) async {
    shownTargetNames.add(targetName);
    pausedShown = true;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    pausedShown = false;
  }
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

LiveTrackingKey _key(
  LiveTrackingKeyType key,
  String label,
  LiveTrackingValueType valueType,
) => LiveTrackingKey(key: key, label: label, valueType: valueType);

void main() {
  const target = LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1');
  final positionKeys = [
    _key(
      LiveTrackingKeyType.latitude,
      'latitude',
      LiveTrackingValueType.attribute,
    ),
    _key(
      LiveTrackingKeyType.longitude,
      'longitude',
      LiveTrackingValueType.attribute,
    ),
  ];
  final statusKeys = [
    _key(
      LiveTrackingKeyType.gpsActive,
      'gpsActive',
      LiveTrackingValueType.attribute,
    ),
    _key(
      LiveTrackingKeyType.gpsTrackedBy,
      'gpsTrackedBy',
      LiveTrackingValueType.attribute,
    ),
  ];
  final fix = GeoPosition(
    latitude: 1,
    longitude: 2,
    accuracy: 5,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
    altitude: 100,
    speed: 3,
    heading: 90,
  );

  LiveTrackingConfig configOf({
    List<LiveTrackingKey>? keys,
    String? trackedBy,
    int? maxDurationSeconds,
    String? targetName,
  }) => LiveTrackingConfig(
    target: target,
    keys: keys ?? positionKeys,
    trackedBy: trackedBy,
    maxDurationSeconds: maxDurationSeconds,
    targetName: targetName,
  );

  late FakeLocationService location;
  late FakeRemote remote;
  late FakeStore store;
  late FakeNameResolver nameResolver;
  late FakeNotifications notifications;
  late LiveLocationTrackingService service;

  setUp(() {
    location = FakeLocationService();
    remote = FakeRemote();
    store = FakeStore();
    nameResolver = FakeNameResolver();
    notifications = FakeNotifications();
    service = LiveLocationTrackingService(
      locationService: location,
      remote: remote,
      logger: TbLogger(),
      store: store,
      nameResolver: nameResolver,
      notifications: notifications,
    );
  });

  test('start emits a tracking session and writes status keys', () async {
    await service.start(
      configOf(keys: [...positionKeys, ...statusKeys], trackedBy: 'me@tb.io'),
    );

    expect(service.session?.status, LiveTrackingStatus.tracking);
    expect(remote.attributeCalls.single.$2, {
      'gpsActive': true,
      'gpsTrackedBy': 'me@tb.io',
    });
    expect(location.lastSettings?.background, isNotNull);
  });

  test('start without status keys configured writes nothing', () async {
    await service.start(configOf(trackedBy: 'me@tb.io'));

    expect(remote.attributeCalls, isEmpty);
  });

  test('fix routes each configured key to its label and value type', () async {
    await service.start(
      configOf(
        keys: [
          _key(
            LiveTrackingKeyType.latitude,
            'lat',
            LiveTrackingValueType.attribute,
          ),
          _key(
            LiveTrackingKeyType.longitude,
            'lng',
            LiveTrackingValueType.attribute,
          ),
          _key(
            LiveTrackingKeyType.accuracy,
            'gpsAccuracy',
            LiveTrackingValueType.timeseries,
          ),
          _key(
            LiveTrackingKeyType.speed,
            'gpsSpeed',
            LiveTrackingValueType.timeseries,
          ),
        ],
      ),
    );
    remote.attributeCalls.clear();

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    final (savedTarget, ts, values) = remote.telemetryCalls.single;
    expect(savedTarget.id, 'd-1');
    expect(ts, 1720000000000);
    expect(values, {'gpsAccuracy': 5.0, 'gpsSpeed': 3.0});
    expect(remote.attributeCalls.single.$2, {'lat': 1.0, 'lng': 2.0});
    expect(service.session?.fixCount, 1);
    expect(service.session?.savedCount, 1);
    expect(service.session?.lastFix, fix);
  });

  test('values the dashboard did not ask for are not saved', () async {
    await service.start(
      configOf(
        keys: [
          _key(
            LiveTrackingKeyType.latitude,
            'latitude',
            LiveTrackingValueType.timeseries,
          ),
          _key(
            LiveTrackingKeyType.longitude,
            'longitude',
            LiveTrackingValueType.timeseries,
          ),
        ],
      ),
    );

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(remote.telemetryCalls.single.$3, {
      'latitude': 1.0,
      'longitude': 2.0,
    });
    expect(remote.attributeCalls, isEmpty);
  });

  test('save failure increments saveErrorCount and keeps tracking', () async {
    await service.start(
      configOf(
        keys: [
          _key(
            LiveTrackingKeyType.latitude,
            'latitude',
            LiveTrackingValueType.timeseries,
          ),
        ],
      ),
    );
    remote.throwOnTelemetry = Exception('boom');

    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(service.session?.status, LiveTrackingStatus.tracking);
    expect(service.session?.saveErrorCount, 1);
    expect(service.session?.savedCount, 0);
    expect(service.session?.lastError, LiveTrackingError.saveFailed);
  });

  test('a successful fix clears the previous error', () async {
    await service.start(
      configOf(
        keys: [
          _key(
            LiveTrackingKeyType.latitude,
            'latitude',
            LiveTrackingValueType.timeseries,
          ),
        ],
      ),
    );
    remote.throwOnTelemetry = Exception('boom');
    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();
    expect(service.session?.lastError, LiveTrackingError.saveFailed);

    remote.throwOnTelemetry = null;
    location.controller!.add(LocationSuccess(fix));
    await pumpEventQueue();

    expect(service.session?.lastError, isNull);
    expect(service.session?.savedCount, 1);
    expect(service.session?.saveErrorCount, 1);
  });

  test(
    'services disabled mid-session pauses and writes gpsActive=false',
    () async {
      await service.start(configOf(keys: [...positionKeys, ...statusKeys]));
      remote.attributeCalls.clear();

      location.controller!.add(const LocationServicesDisabled());
      await pumpEventQueue();

      expect(service.session?.status, LiveTrackingStatus.paused);
      expect(
        service.session?.lastError,
        LiveTrackingError.locationServicesDisabled,
      );
      expect(remote.attributeCalls.single.$2, {'gpsActive': false});
      expect(notifications.pausedShown, true);
    },
  );

  test(
    'pause cancels the stream and writes gpsActive=false; resume restores',
    () async {
      await service.start(configOf(keys: [...positionKeys, ...statusKeys]));
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
    },
  );

  test('stop clears the session and writes gpsActive=false', () async {
    await service.start(configOf(keys: [...positionKeys, ...statusKeys]));
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

  test(
    'terminal permission failure pauses the session with an error',
    () async {
      await service.start(configOf());

      location.controller!.add(const LocationPermissionDenied());
      await pumpEventQueue();

      expect(service.session?.status, LiveTrackingStatus.paused);
      expect(service.session?.lastError, isNotNull);
      expect(notifications.pausedShown, true);
    },
  );

  test('pause shows the paused notification with the config target name '
      'and resume clears it', () async {
    await service.start(configOf(targetName: 'Car 42'));

    await service.pause();
    expect(notifications.pausedShown, true);
    expect(notifications.shownTargetNames.single, 'Car 42');

    await service.resume();
    expect(notifications.pausedShown, false);
  });

  test('stop while paused clears the paused notification', () async {
    await service.start(configOf());
    await service.pause();
    expect(notifications.pausedShown, true);

    await service.stop();
    expect(notifications.pausedShown, false);
  });

  test('maxDurationSeconds auto-stops the session', () {
    fakeAsync((async) {
      service.start(configOf(maxDurationSeconds: 300));
      async.flushMicrotasks();
      expect(service.session, isNotNull);

      async.elapse(const Duration(minutes: 5, seconds: 1));
      async.flushMicrotasks();
      expect(service.session, isNull);
    });
  });

  test('start writes an interrupted record with the resolved name', () async {
    await service.start(configOf());
    // Name resolution now happens off the critical path (see finding #1);
    // let its fire-and-forget patch land before asserting on it.
    await pumpEventQueue();
    expect(store.record, isNotNull);
    expect(store.record!.targetName, 'My Tracker');
    expect(store.record!.endReason, TrackingEndReason.interrupted);
    expect(store.record!.endedAt, isNull);
  });

  test('a name resolution that completes after stop() does not resurrect the '
      'stopped session, its subscription, or its persisted record', () async {
    final resolverCompleter = Completer<String?>();
    nameResolver.pendingCompleter = resolverCompleter;

    unawaited(service.start(configOf()));
    await pumpEventQueue();

    // The interrupted record and GPS subscription must already exist
    // before the name ever resolves: resolveName must not gate them.
    expect(store.record, isNotNull);
    expect(store.record!.endReason, TrackingEndReason.interrupted);
    expect(store.record!.targetName, isNull);
    expect(location.controller?.hasListener, true);

    await service.stop();
    await pumpEventQueue();

    expect(service.session, isNull);
    expect(store.record!.endReason, TrackingEndReason.manual);
    expect(location.controller?.hasListener, false);

    resolverCompleter.complete('Late Name');
    await pumpEventQueue();

    expect(
      service.session,
      isNull,
      reason: 'a late name resolution must not resurrect the session',
    );
    expect(
      store.record!.endReason,
      TrackingEndReason.manual,
      reason: 'a late name resolution must not overwrite the ended record',
    );
    expect(store.record!.targetName, isNot('Late Name'));
    expect(
      location.controller?.hasListener,
      false,
      reason: 'a late name resolution must not resurrect the subscription',
    );
  });

  test('stop updates the record with manual end reason and counts', () async {
    await service.start(configOf());
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
      service.start(configOf(maxDurationSeconds: 300));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5, seconds: 1));
      async.flushMicrotasks();
      expect(store.record!.endReason, TrackingEndReason.maxDuration);
    });
  });
}
