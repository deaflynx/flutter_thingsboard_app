import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/location/location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';

class FakeGeolocator extends GeolocatorPlatform {
  final controller = StreamController<Position>();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      controller.stream;
}

void main() {
  late FakeGeolocator geolocator;
  late LocationService service;

  setUp(() {
    geolocator = FakeGeolocator();
    service = LocationService(logger: TbLogger(), geolocator: geolocator);
  });

  Future<List<LocationFix>> collectAfter(void Function() act) async {
    final fixes = <LocationFix>[];
    final sub = service.positionStream().listen(fixes.add);
    await pumpEventQueue();
    act();
    await pumpEventQueue();
    await sub.cancel();
    return fixes;
  }

  test(
    'services-disabled stream error surfaces as LocationServicesDisabled',
    () async {
      final fixes = await collectAfter(
        () => geolocator.controller.addError(
          const LocationServiceDisabledException(),
        ),
      );

      expect(fixes.single, isA<LocationServicesDisabled>());
    },
  );

  test(
    'permission-denied stream error surfaces as LocationPermissionDenied',
    () async {
      final fixes = await collectAfter(
        () => geolocator.controller.addError(
          const PermissionDeniedException('denied'),
        ),
      );

      expect(fixes.single, isA<LocationPermissionDenied>());
    },
  );

  test('other stream errors surface as LocationFixError', () async {
    final fixes = await collectAfter(
      () => geolocator.controller.addError(Exception('gps glitch')),
    );

    expect(fixes.single, isA<LocationFixError>());
    expect((fixes.single as LocationFixError).message, contains('gps glitch'));
  });
}
