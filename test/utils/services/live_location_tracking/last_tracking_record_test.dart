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
    expect(
      LastTrackingRecord.fromJson(record.toJson()).toJson(),
      record.toJson(),
    );
  });

  test('unknown endReason falls back to interrupted', () {
    final record = LastTrackingRecord.fromJson({
      ...json,
      'endReason': 'nonsense',
    });
    expect(record.endReason, TrackingEndReason.interrupted);
  });
}
