import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/location_action_result_mapper.dart';

class _Mapper with LocationActionResultMapper {}

void main() {
  test('LocationSuccess maps to success json with accuracy and ts', () {
    final result = _Mapper().mapLocationFixToResult(
      LocationSuccess(
        GeoPosition(
          latitude: 50.45,
          longitude: 30.52,
          accuracy: 12.5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
        ),
      ),
    );

    final json = result.toJson();
    final resultJson = json['result'] as Map<String, dynamic>;
    expect(json['hasResult'], true);
    expect(json['hasError'], false);
    expect(resultJson['latitude'], 50.45);
    expect(resultJson['longitude'], 30.52);
    expect(resultJson['accuracy'], 12.5);
    expect(resultJson['ts'], 1720000000000);
  });

  test('LocationSuccess without timestamp omits ts key', () {
    final result = _Mapper().mapLocationFixToResult(
      const LocationSuccess(
        GeoPosition(latitude: 1, longitude: 2, accuracy: 3),
      ),
    );

    final json = result.toJson();
    final resultJson = json['result'] as Map<String, dynamic>;
    expect(resultJson.containsKey('ts'), false);
    expect(resultJson['accuracy'], 3);
  });

  test('LocationPermissionDenied maps to error result', () {
    final result = _Mapper().mapLocationFixToResult(
      const LocationPermissionDenied(),
    );

    final json = result.toJson();
    expect(json['hasError'], true);
    expect(json['hasResult'], false);
  });
}
