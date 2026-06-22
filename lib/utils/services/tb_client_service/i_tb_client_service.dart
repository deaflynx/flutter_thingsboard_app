import 'dart:ui';

import 'package:thingsboard_app/thingsboard_client.dart';

abstract interface class ITbClientService {
  Future<void> init();
  ThingsboardClient get client;

  /// When true, transient client errors are logged but not shown to the user
  /// as notifications. Used to silence benign background errors (e.g. a 403 on
  /// a permission probe) while an endpoint switch is settling (PROD-8200).
  bool get suppressErrorNotifications;
  set suppressErrorNotifications(bool value);

  Future<void> reInit({
    required String endpoint,
    required VoidCallback onDone,
    required ErrorCallback onAuthError,
  });
}
