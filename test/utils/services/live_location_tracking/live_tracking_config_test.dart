import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

void main() {
  test('parses a full config', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'DEVICE', 'id': 'abc-123'},
      'keys': [
        {'key': 'LATITUDE', 'label': 'lat', 'valueType': 'ATTRIBUTE'},
        {'key': 'LONGITUDE', 'label': 'lng', 'valueType': 'ATTRIBUTE'},
        {'key': 'SPEED', 'label': 'gpsSpeed', 'valueType': 'TIMESERIES'},
      ],
      'targetName': 'Test Device B1',
      'dashboard': {'id': 'dash-1', 'title': 'GPS tracker'},
      'accuracy': 'HIGH',
      'distanceFilterMeters': 25,
      'intervalSeconds': 60,
      'maxDurationSeconds': 7200,
      'trackedBy': 'user@example.com',
    });

    expect(config.target.entityType, 'DEVICE');
    expect(config.target.id, 'abc-123');
    expect(config.targetName, 'Test Device B1');
    expect(config.dashboard?.id, 'dash-1');
    expect(config.dashboard?.title, 'GPS tracker');
    expect(config.keys.length, 3);
    expect(config.keys.first.key, LiveTrackingKeyType.latitude);
    expect(config.keys.first.label, 'lat');
    expect(config.keys.first.valueType, LiveTrackingValueType.attribute);
    expect(config.keys.last.key, LiveTrackingKeyType.speed);
    expect(config.keys.last.valueType, LiveTrackingValueType.timeseries);
    expect(config.accuracy, LocationAccuracyLevel.high);
    expect(config.distanceFilterMeters, 25);
    expect(config.intervalSeconds, 60);
    expect(config.maxDurationSeconds, 7200);
    expect(config.trackedBy, 'user@example.com');
  });

  test('applies defaults for a minimal config', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'USER', 'id': 'u-1'},
      'keys': [
        {'key': 'LATITUDE', 'label': 'latitude', 'valueType': 'ATTRIBUTE'},
      ],
    });

    expect(config.accuracy, LocationAccuracyLevel.balanced);
    expect(config.distanceFilterMeters, isNull);
    expect(config.intervalSeconds, isNull);
    expect(config.maxDurationSeconds, isNull);
    expect(config.trackedBy, isNull);
    expect(config.targetName, isNull);
    expect(config.dashboard, isNull);
  });

  test('dashboard with only null fields parses as null', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'USER', 'id': 'u-1'},
      'keys': [
        {'key': 'LATITUDE', 'label': 'latitude', 'valueType': 'ATTRIBUTE'},
      ],
      'dashboard': {'id': null, 'title': null},
    });

    expect(config.dashboard, isNull);
  });

  test('unknown accuracy falls back to balanced', () {
    final config = LiveTrackingConfig.fromJson(const {
      'target': {'entityType': 'USER', 'id': 'u-1'},
      'keys': [
        {'key': 'LATITUDE', 'label': 'latitude', 'valueType': 'ATTRIBUTE'},
      ],
      'accuracy': 'ULTRA',
    });

    expect(config.accuracy, LocationAccuracyLevel.balanced);
  });

  test('unknown value type falls back to attribute', () {
    final key = LiveTrackingKey.fromJson(const {
      'key': 'LATITUDE',
      'label': 'latitude',
      'valueType': 'SOMETHING_ELSE',
    });

    expect(key.valueType, LiveTrackingValueType.attribute);
  });

  test('missing target throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {
        'keys': [
          {'key': 'LATITUDE', 'label': 'latitude', 'valueType': 'ATTRIBUTE'},
        ],
      }),
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

  test('missing keys throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {
        'target': {'entityType': 'DEVICE', 'id': 'abc-123'},
      }),
      throwsFormatException,
    );
  });

  test('unknown key throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {
        'target': {'entityType': 'DEVICE', 'id': 'abc-123'},
        'keys': [
          {'key': 'TEMPERATURE', 'label': 'temp', 'valueType': 'TIMESERIES'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('key without a label throws FormatException', () {
    expect(
      () => LiveTrackingConfig.fromJson(const {
        'target': {'entityType': 'DEVICE', 'id': 'abc-123'},
        'keys': [
          {'key': 'LATITUDE', 'label': '', 'valueType': 'ATTRIBUTE'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('toJson round-trips through fromJson', () {
    const original = LiveTrackingConfig(
      target: LiveTrackingTarget(entityType: 'DEVICE', id: 'abc-123'),
      keys: [
        LiveTrackingKey(
          key: LiveTrackingKeyType.latitude,
          label: 'lat',
          valueType: LiveTrackingValueType.attribute,
        ),
        LiveTrackingKey(
          key: LiveTrackingKeyType.heading,
          label: 'gpsHeading',
          valueType: LiveTrackingValueType.timeseries,
        ),
      ],
      targetName: 'Test Device B1',
      dashboard: LiveTrackingDashboard(id: 'dash-1', title: 'GPS tracker'),
      accuracy: LocationAccuracyLevel.high,
      distanceFilterMeters: 25,
      intervalSeconds: 60,
      maxDurationSeconds: 7200,
      trackedBy: 'user@example.com',
    );

    final restored = LiveTrackingConfig.fromJson(original.toJson());

    expect(restored.target.entityType, 'DEVICE');
    expect(restored.target.id, 'abc-123');
    expect(restored.keys.length, 2);
    expect(restored.keys.first.label, 'lat');
    expect(restored.keys.first.valueType, LiveTrackingValueType.attribute);
    expect(restored.keys.last.key, LiveTrackingKeyType.heading);
    expect(restored.keys.last.valueType, LiveTrackingValueType.timeseries);
    expect(restored.targetName, 'Test Device B1');
    expect(restored.dashboard?.id, 'dash-1');
    expect(restored.dashboard?.title, 'GPS tracker');
    expect(restored.accuracy, LocationAccuracyLevel.high);
    expect(restored.distanceFilterMeters, 25);
    expect(restored.intervalSeconds, 60);
    expect(restored.maxDurationSeconds, 7200);
    expect(restored.trackedBy, 'user@example.com');
  });
}
