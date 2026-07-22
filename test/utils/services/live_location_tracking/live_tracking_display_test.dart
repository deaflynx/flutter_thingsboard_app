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
