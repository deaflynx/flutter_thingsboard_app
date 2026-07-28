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
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(() => tracking);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('renders nothing without a session', (tester) async {
    await tester.pumpWidget(_wrap(const LiveTrackingBar()));

    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('shows controls for an active session and stops on tap', (
    tester,
  ) async {
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

    await tester.pumpWidget(_wrap(const LiveTrackingBar()));
    await tester.pump();

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop));
    expect(tracking.stopCalled, true);
  });

  testWidgets(
    'collapsed bar spans full width and shows gps_fixed when tracking',
    (tester) async {
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

      await tester.pumpWidget(_wrap(const LiveTrackingBar()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pump();

      expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
      final collapsedMaterialFinder =
          find
              .ancestor(
                of: find.byIcon(Icons.gps_fixed),
                matching: find.byType(Material),
              )
              .first;
      final material = tester.widget<Material>(collapsedMaterialFinder);
      final colors =
          Theme.of(tester.element(collapsedMaterialFinder)).colorScheme;
      expect(material.color, colors.primaryContainer);
      final size = tester.getSize(collapsedMaterialFinder);
      expect(
        size.width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
    },
  );
}
