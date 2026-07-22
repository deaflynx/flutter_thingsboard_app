import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_store.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';

class FakeStorage implements TbStorage {
  final _map = <String, dynamic>{};

  @override
  Future<dynamic> getItem(String key, {dynamic defaultValue}) async =>
      _map[key] ?? defaultValue;

  @override
  Future<void> setItem(String key, dynamic value) async => _map[key] = value;

  @override
  Future<void> deleteItem(String key) async => _map.remove(key);

  @override
  Future<bool> containsKey(String key) async => _map.containsKey(key);
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
