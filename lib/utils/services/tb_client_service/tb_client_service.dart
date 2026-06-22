import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/communication/events/user_loaded_event.dart';
import 'package:thingsboard_app/utils/services/communication/i_communication_service.dart';
import 'package:thingsboard_app/utils/services/endpoint/i_endpoint_service.dart';
import 'package:thingsboard_app/utils/services/loading_service/i_loading_service.dart';
import 'package:thingsboard_app/utils/services/overlay_service/i_overlay_service.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';
import 'package:thingsboard_app/utils/utils.dart';
import 'package:thingsboard_app/thingsboard_client.dart';

class TbClientService implements ITbClientService {
  late ThingsboardClient _client;
  @override
  ThingsboardClient get client => _client;
  final IOverlayService _overlayService = getIt();

  bool _suppressErrorNotifications = false;
  @override
  bool get suppressErrorNotifications => _suppressErrorNotifications;
  @override
  set suppressErrorNotifications(bool value) =>
      _suppressErrorNotifications = value;
  @override
  Future<void> init() async {
    final endpoint = await getIt<IEndpointService>().getEndpoint();
    log('TbClient::init() endpoint: $endpoint');

    _client = ThingsboardClient(
      endpoint,
      storage: getIt(),
      onUserLoaded: () {
        onUserLoaded();
      },
      onError: (e) {
        onClientError(e);
      },
      onLoadStarted: () {
        onLoadStarted();
      },
      onLoadFinished: () {
        onLoadFinished();
      },
      computeFunc: <Q, R>(callback, message) => compute(callback, message),
    );

    try {
      await _client.init();
    } catch (e) {
      log('Failed to init tbClient: $e');
      onInitError(e);
    }
  }

  void onUserLoaded() {
    log('onUser loaded: ${_client.getAuthUser()?.userId}');
    getIt<ICommunicationService>().fire(const UserLoadedEvent());
  }

  String _getMessage(dynamic e, BuildContext context) {
    final message =
        e is ThingsboardError
            ? (e.message ?? S.of(context).unknownError)
            : S.of(context).unknownError;

    return '${S.of(context).fatalApplicationErrorOccurred}\n$message';
  }

  void onInitError(dynamic e) {
    _overlayService.showAlertDialog(
      content:
          (context) => DialogContent(
            title: S.of(context).fatalError,
            message: _getMessage(e, context),
            ok: S.of(context).cancel,
          ),
    );
  }

  void onClientError(ThingsboardError e) {
    log('client on error: $e');
    if (_suppressErrorNotifications) {
      // An endpoint switch is in progress; the new session loads data in the
      // background and benign 401/403 responses must not surface as toasts on
      // a successful switch (PROD-8200).
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Utils.isConnectionError(e)) {
        _overlayService.showAlertDialog(
          content:
              (context) => DialogContent(
                title: S.of(context).connectionError,
                message: S.of(context).failedToConnectToServer,
              ),
        );

        return;
      }
      _overlayService.showErrorNotification((_) => e.message!);
    });
  }

  static void onLoadFinished() {
    getIt<ILoadingService>().isLoading.value = false;
    log('client on load finish');
  }

  static void onLoadStarted() {
    getIt<ILoadingService>().isLoading.value = true;
    log('client on load');
  }

  @override
  Future<void> reInit({
    required String endpoint,
    required VoidCallback onDone,
    required ErrorCallback onAuthError,
  }) async {
    log('TbClient:reinit()');
    _client = ThingsboardClient(
      endpoint,
      storage: getIt(),
      onUserLoaded: () {
        onUserLoaded();
      },
      onError: (e) {
        onAuthError(e);
        onClientError(e);
      },
      onLoadStarted: () {
        onLoadStarted();
      },
      onLoadFinished: () {
        onLoadFinished();
      },
      computeFunc: <Q, R>(callback, message) => compute(callback, message),
    );
    await _client.init();
    onDone();
  }
}
