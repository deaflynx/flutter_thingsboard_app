import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

class LiveTrackingTarget {
  const LiveTrackingTarget({required this.entityType, required this.id});

  factory LiveTrackingTarget.fromJson(Map<String, dynamic> json) {
    final entityType = json['entityType'];
    final id = json['id'];
    if (entityType is! String || id is! String) {
      throw const FormatException(
        'Live tracking target must contain entityType and id',
      );
    }
    return LiveTrackingTarget(entityType: entityType, id: id);
  }

  final String entityType;
  final String id;
}

/// Fully-resolved live tracking session config received from the dashboard
/// (the web side resolves aliases/attributes to a concrete target entity
/// before sending — see the phase 1c wire protocol in the plan doc).
class LiveTrackingConfig {
  const LiveTrackingConfig({
    required this.target,
    this.latitudeKey = 'latitude',
    this.longitudeKey = 'longitude',
    this.includeMetadata = false,
    this.mirrorToAttributes = false,
    this.accuracy = LocationAccuracyLevel.balanced,
    this.distanceFilterMeters,
    this.intervalSeconds,
    this.maxDurationMinutes,
    this.writeStatusAttributes = true,
    this.trackedBy,
  });

  factory LiveTrackingConfig.fromJson(Map<String, dynamic> json) {
    final targetJson = json['target'];
    if (targetJson is! Map) {
      throw const FormatException('Live tracking config is missing target');
    }
    return LiveTrackingConfig(
      target: LiveTrackingTarget.fromJson(
        Map<String, dynamic>.from(targetJson),
      ),
      latitudeKey: json['latitudeKey'] as String? ?? 'latitude',
      longitudeKey: json['longitudeKey'] as String? ?? 'longitude',
      includeMetadata: json['includeMetadata'] as bool? ?? false,
      mirrorToAttributes: json['mirrorToAttributes'] as bool? ?? false,
      accuracy: _accuracyFromString(json['accuracy'] as String?),
      distanceFilterMeters: (json['distanceFilterMeters'] as num?)?.toInt(),
      intervalSeconds: (json['intervalSeconds'] as num?)?.toInt(),
      maxDurationMinutes: (json['maxDurationMinutes'] as num?)?.toInt(),
      writeStatusAttributes: json['writeStatusAttributes'] as bool? ?? true,
      trackedBy: json['trackedBy'] as String?,
    );
  }

  final LiveTrackingTarget target;
  final String latitudeKey;
  final String longitudeKey;
  final bool includeMetadata;
  final bool mirrorToAttributes;
  final LocationAccuracyLevel accuracy;
  final int? distanceFilterMeters;
  final int? intervalSeconds;
  final int? maxDurationMinutes;
  final bool writeStatusAttributes;
  final String? trackedBy;

  static LocationAccuracyLevel _accuracyFromString(String? value) =>
      switch (value) {
        'HIGH' => LocationAccuracyLevel.high,
        'LOW' => LocationAccuracyLevel.low,
        _ => LocationAccuracyLevel.balanced,
      };
}
