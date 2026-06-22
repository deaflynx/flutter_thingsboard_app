import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:thingsboard_app/core/auth/login/models/login_state.dart';
import 'package:thingsboard_app/core/auth/login/models/mobile_basic_info.dart';
import 'package:thingsboard_app/core/auth/oauth2/i_oauth2_client.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/communication/events/user_loaded_event.dart';
import 'package:thingsboard_app/utils/services/communication/i_communication_service.dart';
import 'package:thingsboard_app/utils/services/device_info/i_device_info_service.dart';
import 'package:thingsboard_app/utils/services/firebase/i_firebase_service.dart';
import 'package:thingsboard_app/utils/services/notification_service.dart';
import 'package:thingsboard_app/utils/services/overlay_service/i_overlay_service.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';
import 'package:thingsboard_app/thingsboard_client.dart';

part 'login_provider.g.dart';

@riverpod
class Login extends _$Login {
  // Read the live client each time: after a QR host switch the client is
  // re-created (ITbClientService.reInit), so a captured reference would go
  // stale and hit the new host with the old token -> 401 (PROD-8200).
  ThingsboardClient get _tbClient => getIt<ITbClientService>().client;
  final _deviceInfoService = getIt<IDeviceInfoService>();
  late final StreamSubscription<UserLoadedEvent> _listener;
  final _overlayService = getIt<IOverlayService>();
  @override
  LoginState build() {
    _listener = getIt<ICommunicationService>().on<UserLoadedEvent>().listen((
      _,
    ) async {
      await _safeHandleUserLoaded();
    });
    ref.onDispose(() => _listener.cancel());
    Future(() => _safeHandleUserLoaded());
    return const LoginState(isUserLoaded: false);
  }

  // Wraps handleUserLoaded() so an auth failure during user load (e.g. a
  // QR-switch to a host the account cannot access) is reported as a handled
  // error instead of escaping the Future as an unhandled exception that
  // Flutter renders as a raw stacktrace (PROD-8200). The client's onError
  // callback already surfaces a user-facing notification.
  Future<void> _safeHandleUserLoaded() async {
    try {
      await handleUserLoaded();
    } catch (e, st) {
      log('handleUserLoaded failed: $e\n$st');
      state = const LoginState(isUserLoaded: false);
    }
  }

  Future<void> logout() async {
    if (getIt<IFirebaseService>().apps.isNotEmpty &&
        state.isFullyAuthenticated()) {
      await getIt<NotificationService>().logout();
    }
    await _tbClient.logout(requestConfig: RequestConfig(ignoreErrors: true));
  }

  Future<void> handleUserLoaded() async {
    log('handle user loaded: ${_tbClient.getAuthUser()?.userId}');

    if (!_tbClient.isAuthenticated()) {
      state = const LoginState(isUserLoaded: false);
      return;
    }
    if (_tbClient.isPreVerificationToken() ||
        _tbClient.isMfaConfigurationToken()) {
      state = state.copyWith(
        isUserLoaded: true,
        userScope: _tbClient.getAuthUser()?.authority,
        user: null,
      );
      return;
    }
    await _onFullyLoggedIn();
  }

  Future<bool> login(String email, String password) async {
    try {
      final res = await _tbClient.login(
        LoginRequest(userName: email, password: password),
      );
      final user = _tbClient.getAuthUser();
      if (user != null &&
          (user.isMfaConfigurationToken() || user.isPreVerificationToken())) {
        return false;
      }
    } catch (e) {
      return false;
    }
    return true;
  }

  Future<void> loadUser() async {
    final mobileResp = await _tbClient
        .getMobileAppControllerApi()
        .getUserMobileInfo(
          pkgName: _deviceInfoService.getApplicationId(),
          platform: _deviceInfoService.getPlatformType().name,
        );
    final mobileInfo = MobileBasicInfo.fromUserMobileInfo(mobileResp.data!);

    final userInfo = (await _tbClient.getAuthControllerApi().getUser()).data!;
    final lang =
        userInfo.additionalInfo?.isMap == true
            ? userInfo.additionalInfo?.asMap['lang']
            : null;
    final langStr = lang?.toString();
    final locale = S.delegate.supportedLocales.firstWhereOrNull(
      (l) => l.toString() == langStr || l.languageCode == langStr,
    );

    await S.load(locale ?? const Locale('en'));

    state = state.copyWith(
      isUserLoaded: true,
      user: userInfo,
      userScope: authorityFromString(userInfo.authority?.name ?? 'ANONYMOUS'),
      mobileLoginInfo: mobileInfo,
    );
  }

  Future<void> _onFullyLoggedIn() async {
    await loadUser();
    if (getIt<IFirebaseService>().apps.isNotEmpty) {
      await getIt<NotificationService>().init();
    }
  }

  Future<void> twoFaConfirmed(LoginResponse response) async {
    await _onFullyLoggedIn();
  }

  Future<bool> oauthLogin(String url) async {
    try {
      final result = await getIt<IOAuth2Client>().authenticate(url);
      if (result.success) {
        await _tbClient.setUserFromJwtToken(
          result.accessToken,
          result.refreshToken,
          true,
        );
        return true;
      } else {
        _overlayService.showErrorNotification((_) => result.error!);
      }
    } catch (e) {
      _overlayService.showErrorNotification((_) => e.toString());
    }
    return false;
  }
}
