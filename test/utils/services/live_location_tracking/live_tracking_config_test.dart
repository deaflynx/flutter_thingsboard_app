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
