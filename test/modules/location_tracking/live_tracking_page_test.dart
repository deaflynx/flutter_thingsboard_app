import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_page.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_entity_name_resolver.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

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

class _FakeTrackingService implements ILiveLocationTrackingService {
  final _controller = StreamController<LiveTrackingSession?>.broadcast();

  @override
  LiveTrackingSession? session;

  @override
  Stream<LiveTrackingSession?> get sessionStream => _controller.stream;

  @override
  Future<void> start(LiveTrackingConfig config) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
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
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(
      () => _FakeTrackingService(),
    );

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      find.text('No active tracking and no recent session.'),
      findsOneWidget,
    );
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
    GetIt.I.registerLazySingleton<ILiveLocationTrackingService>(
      () => _FakeTrackingService(),
    );

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Start again'), findsOneWidget);
    expect(find.text('My Tracker'), findsWidgets);
  });
}
