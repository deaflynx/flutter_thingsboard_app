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
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(() => tracking);
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
      {'latitudeKey': 'lat'},
    ], FakeController());

    expect(result.toJson()['hasError'], true);
  });

  test('stop action with active session stops and returns launched', () async {
    tracking.session = LiveTrackingSession(
      config: const LiveTrackingConfig(
        target: LiveTrackingTarget(entityType: 'DEVICE', id: 'd-1'),
      ),
      status: LiveTrackingStatus.tracking,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final result = await StopLiveLocationAction().execute([
      'stopLiveLocation',
    ], FakeController());

    expect(tracking.stopped, true);
    expect(result.toJson()['hasResult'], true);
  });

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
