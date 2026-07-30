import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_error.dart';

void main() {
  group('LiveTrackingError.fromSaveException', () {
    test('deleted target — 404 with empty server message — maps to '
        'targetNotFound', () {
      final e = ThingsboardError(
        message: '404: ',
        status: 404,
        errorCode: ThingsBoardErrorCode.itemNotFound,
      );

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.targetNotFound,
      );
    });

    test('itemNotFound code without an HTTP status maps to targetNotFound', () {
      final e = ThingsboardError(errorCode: ThingsBoardErrorCode.itemNotFound);

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.targetNotFound,
      );
    });

    test('connection failure maps to noConnection', () {
      final e = ThingsboardError(
        message: 'Unable to connect',
        errorCode: ThingsBoardErrorCode.general,
      );

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.noConnection,
      );
    });

    test('interceptor missing-token error — bare message, no status — maps '
        'to unauthorized', () {
      final e = ThingsboardError(message: 'Unauthorized!');

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.unauthorized,
      );
    });

    test('401 maps to unauthorized', () {
      final e = ThingsboardError(
        status: 401,
        errorCode: ThingsBoardErrorCode.authentication,
      );

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.unauthorized,
      );
    });

    test('expired JWT maps to unauthorized', () {
      final e = ThingsboardError(
        errorCode: ThingsBoardErrorCode.jwtTokenExpired,
      );

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.unauthorized,
      );
    });

    test('an unrecognized exception maps to the generic saveFailed', () {
      expect(
        LiveTrackingError.fromSaveException(Exception('boom')),
        LiveTrackingError.saveFailed,
      );
    });

    test('a 500 server error maps to the generic saveFailed', () {
      final e = ThingsboardError(message: '500: Unknown', status: 500);

      expect(
        LiveTrackingError.fromSaveException(e),
        LiveTrackingError.saveFailed,
      );
    });
  });
}
