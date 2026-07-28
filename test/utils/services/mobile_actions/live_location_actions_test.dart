import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/start_live_location_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/stop_live_location_action.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/widget_mobile_action_type.dart';

class FakeController extends Fake implements InAppWebViewController {}

class FakeStore implements ILiveTrackingStore {
  LastTrackingRecord? record;

  @override
  Future<LastTrackingRecord?> read() async => record;

  @override
  Future<void> write(LastTrackingRecord record) async {
    this.record = record;
  }

  @override
  Future<void> clear() async {
    record = null;
  }
}

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
  late FakeStore store;

  setUp(() {
    tracking = FakeTrackingService();
    store = FakeStore();
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(() => tracking);
    GetIt.I.registerLazySingleton<ILiveTrackingStore>(() => store);
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

  test(
    'start action parses config, starts service, returns launched',
    () async {
      final result = await StartLiveLocationAction().execute([
        'startLiveLocation',
        {
          'target': {'entityType': 'DEVICE', 'id': 'd-1'},
          'keys': [
            {'key': 'LATITUDE', 'label': 'latitude', 'valueType': 'ATTRIBUTE'},
          ],
          'trackedBy': 'me@tb.io',
        },
      ], FakeController());

      final json = result.toJson();
      expect(tracking.startedWith?.target.id, 'd-1');
      expect(json['hasResult'], true);
      final resultJson = json['result'] as Map<String, dynamic>;
      expect(resultJson['launched'], true);
    },
  );

  test('start action with missing config returns an error result', () async {
    final result = await StartLiveLocationAction().execute([
      'startLiveLocation',
    ], FakeController());

    expect(result.toJson()['hasError'], true);
    expect(tracking.startedWith, isNull);
  });

  test('start action with malformed target returns an error result', () async {
    final result = await StartLiveLocationAction().execute([
      'startLiveLocation',
      {'keys': <dynamic>[]},
    ], FakeController());

    expect(result.toJson()['hasError'], true);
  });

  test('stop action with active session stops and returns launched', () async {
    tracking.session = LiveTrackingSession(
      config: const LiveTrackingConfig(
        target: LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1'),
        targetName: 'Test Device B1',
        keys: [
          LiveTrackingKey(
            key: LiveTrackingKeyType.latitude,
            label: 'latitude',
            valueType: LiveTrackingValueType.attribute,
          ),
        ],
      ),
      status: LiveTrackingStatus.tracking,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final result = await StopLiveLocationAction().execute([
      'stopLiveLocation',
    ], FakeController());

    expect(tracking.stopped, true);
    final json = result.toJson();
    expect(json['hasResult'], true);
    final resultJson = json['result'] as Map<String, dynamic>;
    expect(resultJson['launched'], true);
    final trackingInfo = resultJson['trackingInfo'] as Map<String, dynamic>;
    expect(trackingInfo['targetName'], 'Test Device B1');
    expect(trackingInfo['keys'], ['latitude']);
  });

  test(
    'stop action falls back to the stored name when config has none',
    () async {
      tracking.session = LiveTrackingSession(
        config: const LiveTrackingConfig(
          target: LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1'),
          keys: [
            LiveTrackingKey(
              key: LiveTrackingKeyType.latitude,
              label: 'latitude',
              valueType: LiveTrackingValueType.attribute,
            ),
          ],
        ),
        status: LiveTrackingStatus.tracking,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      store.record = LastTrackingRecord(
        configJson: tracking.session!.config.toJson(),
        targetName: 'Resolved Name',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        endReason: TrackingEndReason.interrupted,
      );

      final result = await StopLiveLocationAction().execute([
        'stopLiveLocation',
      ], FakeController());

      final resultJson = result.toJson()['result'] as Map<String, dynamic>;
      final trackingInfo = resultJson['trackingInfo'] as Map<String, dynamic>;
      expect(trackingInfo['targetName'], 'Resolved Name');
    },
  );

  test('stop action with no session returns empty result', () async {
    final result = await StopLiveLocationAction().execute([
      'stopLiveLocation',
    ], FakeController());

    final json = result.toJson();
    expect(tracking.stopped, false);
    expect(json['hasResult'], false);
    expect(json['hasError'], false);
  });
}
