import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:thingsboard_app/modules/notification/service/i_notifications_local_service.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/notification_service.dart';

import '../../helpers/test_dependencies.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class MockNotificationsLocalService extends Mock
    implements INotificationsLocalService {}

class MockUserControllerApi extends Mock implements UserControllerApi {}

class MockNotificationControllerApi extends Mock
    implements NotificationControllerApi {}

const fcmToken = 'fcm-token';
const refreshedToken = 'refreshed-token';

Response<T> response<T>([T? data]) =>
    Response<T>(requestOptions: RequestOptions(), data: data);

NotificationSettings permission(AuthorizationStatus status) =>
    NotificationSettings(
      authorizationStatus: status,
      alert: AppleNotificationSetting.notSupported,
      announcement: AppleNotificationSetting.notSupported,
      badge: AppleNotificationSetting.notSupported,
      carPlay: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.notSupported,
      notificationCenter: AppleNotificationSetting.notSupported,
      showPreviews: AppleShowPreviewSetting.notSupported,
      sound: AppleNotificationSetting.notSupported,
      timeSensitive: AppleNotificationSetting.notSupported,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

MobileSessionInfo sessionRegistered(Duration ago) => MobileSessionInfo(
  (b) =>
      b
        ..fcmTokenTimestamp =
            DateTime.now().subtract(ago).millisecondsSinceEpoch,
);

void main() {
  late MockFirebaseMessaging messaging;
  late MockFlutterLocalNotificationsPlugin localNotificationsPlugin;
  late MockNotificationsLocalService localService;
  late MockLocalDatabaseService localDatabase;
  late MockFirebaseService firebaseService;
  late MockUserControllerApi userApi;
  late StreamController<String> tokenRefreshes;

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(MobileSessionInfo());
  });

  NotificationService buildService() => NotificationService(
    messaging: messaging,
    localNotificationsPlugin: localNotificationsPlugin,
    localService: localService,
  );

  /// `logout()` only removes the server-side session for a token the service
  /// has already resolved, so prime the private token field first.
  Future<NotificationService> buildServiceWithToken() async {
    final service = buildService();
    await service.getToken();
    return service;
  }

  void stubMobileSession(MobileSessionInfo? session) => when(
    () => userApi.getMobileSession(xMobileToken: any(named: 'xMobileToken')),
  ).thenAnswer((_) async => response<MobileSessionInfo>(session));

  void verifyMobileSessionSaved(String token) => verify(
    () => userApi.saveMobileSession(
      xMobileToken: token,
      mobileSessionInfo: any(named: 'mobileSessionInfo'),
    ),
  ).called(1);

  setUp(() {
    messaging = MockFirebaseMessaging();
    localNotificationsPlugin = MockFlutterLocalNotificationsPlugin();
    localService = MockNotificationsLocalService();
    localDatabase = MockLocalDatabaseService();
    firebaseService = MockFirebaseService();
    userApi = MockUserControllerApi();
    tokenRefreshes = StreamController<String>.broadcast();
    addTearDown(tokenRefreshes.close);

    final notificationApi = MockNotificationControllerApi();
    final tbClient = MockThingsboardClient();
    when(() => tbClient.getUserControllerApi()).thenReturn(userApi);
    when(
      () => tbClient.getNotificationControllerApi(),
    ).thenReturn(notificationApi);
    when(
      () => notificationApi.getUnreadNotificationsCount(
        deliveryMethod: any(named: 'deliveryMethod'),
      ),
    ).thenAnswer((_) async => response<int>(0));
    when(() => firebaseService.apps).thenReturn(['[DEFAULT]']);

    when(() => messaging.getToken()).thenAnswer((_) async => fcmToken);
    when(() => messaging.deleteToken()).thenAnswer((_) async {});
    when(() => messaging.setAutoInitEnabled(any())).thenAnswer((_) async {});
    when(() => messaging.getInitialMessage()).thenAnswer((_) async => null);
    when(
      () => messaging.requestPermission(provisional: true),
    ).thenAnswer((_) async => permission(AuthorizationStatus.authorized));
    when(
      () => messaging.onTokenRefresh,
    ).thenAnswer((_) => tokenRefreshes.stream);

    when(
      () => localNotificationsPlugin.initialize(
        any(),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);
    when(() => localNotificationsPlugin.cancelAll()).thenAnswer((_) async {});
    when(
      () => localService.clearNotificationBadgeCount(),
    ).thenAnswer((_) async {});
    when(
      () => localService.updateNotificationsCount(any()),
    ).thenAnswer((_) async {});

    when(() => localDatabase.isPushRegistered()).thenAnswer((_) async => false);
    when(() => localDatabase.setPushRegistered()).thenAnswer((_) async {});
    when(() => localDatabase.clearPushRegistered()).thenAnswer((_) async {});

    stubMobileSession(null);
    when(
      () => userApi.saveMobileSession(
        xMobileToken: any(named: 'xMobileToken'),
        mobileSessionInfo: any(named: 'mobileSessionInfo'),
      ),
    ).thenAnswer((_) async => response<void>());
    when(
      () =>
          userApi.removeMobileSession(xMobileToken: any(named: 'xMobileToken')),
    ).thenAnswer((_) async => response<void>());

    registerTestDependencies(
      tbClient: tbClient,
      localDatabase: localDatabase,
      firebaseService: firebaseService,
    );
  });

  group('NotificationService.init', () {
    test('skips entirely when Firebase is not configured', () async {
      when(() => firebaseService.apps).thenReturn(const []);

      await buildService().init();

      verifyNever(() => messaging.getToken());
      verifyNever(() => localDatabase.setPushRegistered());
    });

    test('registers the device and marks push as registered when the '
        'server has no session for the token', () async {
      await buildService().init();

      verifyMobileSessionSaved(fcmToken);
      verify(() => localDatabase.setPushRegistered()).called(1);
    });

    test('marks push as registered without re-saving a fresh '
        'server-side session', () async {
      stubMobileSession(sessionRegistered(const Duration(days: 1)));

      await buildService().init();

      verifyNever(
        () => userApi.saveMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
          mobileSessionInfo: any(named: 'mobileSessionInfo'),
        ),
      );
      verify(() => localDatabase.setPushRegistered()).called(1);
    });

    test('rotates a token older than 30 days and marks push as '
        'registered', () async {
      stubMobileSession(sessionRegistered(const Duration(days: 31)));
      final tokens = [fcmToken, refreshedToken];
      when(
        () => messaging.getToken(),
      ).thenAnswer((_) async => tokens.removeAt(0));

      await buildService().init();

      verifyInOrder([
        () => userApi.removeMobileSession(xMobileToken: fcmToken),
        () => messaging.deleteToken(),
        () => userApi.saveMobileSession(
          xMobileToken: refreshedToken,
          mobileSessionInfo: any(named: 'mobileSessionInfo'),
        ),
      ]);
      verify(() => localDatabase.setPushRegistered()).called(1);
    });

    test('does not mark push as registered when no FCM token is '
        'available', () async {
      when(() => messaging.getToken()).thenThrow(Exception('offline'));

      await buildService().init();

      verifyNever(
        () =>
            userApi.getMobileSession(xMobileToken: any(named: 'xMobileToken')),
      );
      verifyNever(() => localDatabase.setPushRegistered());
    });

    test('does not register the device when notification permission '
        'is denied', () async {
      when(
        () => messaging.requestPermission(provisional: true),
      ).thenAnswer((_) async => permission(AuthorizationStatus.denied));

      await buildService().init();

      verifyNever(() => messaging.getToken());
      verifyNever(() => localDatabase.setPushRegistered());
    });

    test('waits for a pending stale cleanup, so the token it registers '
        'is not the one being deleted', () async {
      when(
        () => localDatabase.isPushRegistered(),
      ).thenAnswer((_) async => true);
      final deleteToken = Completer<void>();
      when(() => messaging.deleteToken()).thenAnswer((_) => deleteToken.future);
      final service = buildService();

      final cleanup = service.cleanUpStalePushRegistration();
      final init = service.init();
      await pumpEventQueue();
      verifyNever(() => messaging.getToken());

      deleteToken.complete();
      await Future.wait([cleanup, init]);

      verifyInOrder([
        () => localDatabase.clearPushRegistered(),
        () => messaging.getToken(),
        () => localDatabase.setPushRegistered(),
      ]);
    });
  });

  group('NotificationService token refresh', () {
    test('moves the mobile session to the refreshed token', () async {
      await buildService().init();

      tokenRefreshes.add(refreshedToken);
      await pumpEventQueue();

      verifyInOrder([
        () => userApi.removeMobileSession(xMobileToken: fcmToken),
        () => userApi.saveMobileSession(
          xMobileToken: refreshedToken,
          mobileSessionInfo: any(named: 'mobileSessionInfo'),
        ),
      ]);
    });

    test('registers the refreshed token when the initial token could not '
        'be obtained', () async {
      when(() => messaging.getToken()).thenThrow(Exception('offline'));
      await buildService().init();

      tokenRefreshes.add(refreshedToken);
      await pumpEventQueue();

      verifyNever(
        () => userApi.removeMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
        ),
      );
      verifyMobileSessionSaved(refreshedToken);
      verify(() => localDatabase.setPushRegistered()).called(1);
    });

    test('still saves the refreshed token when removing the previous '
        'session fails', () async {
      when(
        () => userApi.removeMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
        ),
      ).thenThrow(Exception('401'));
      await buildService().init();

      tokenRefreshes.add(refreshedToken);
      await pumpEventQueue();

      verifyMobileSessionSaved(refreshedToken);
    });
  });

  group('NotificationService.cleanUpStalePushRegistration', () {
    test('skips entirely when Firebase is not configured', () async {
      when(() => firebaseService.apps).thenReturn(const []);

      await buildService().cleanUpStalePushRegistration();

      verifyNever(() => localDatabase.isPushRegistered());
      verifyNever(() => messaging.deleteToken());
    });

    test(
      'does nothing when push notifications were never registered',
      () async {
        await buildService().cleanUpStalePushRegistration();

        verify(() => localDatabase.isPushRegistered()).called(1);
        verifyNever(() => messaging.deleteToken());
        verifyNever(() => localDatabase.clearPushRegistered());
      },
    );

    test('cleans up the local registration when the session expired '
        'after a login', () async {
      when(
        () => localDatabase.isPushRegistered(),
      ).thenAnswer((_) async => true);

      await buildService().cleanUpStalePushRegistration();

      verify(() => messaging.deleteToken()).called(1);
      verify(() => messaging.setAutoInitEnabled(false)).called(1);
      verify(() => localNotificationsPlugin.cancelAll()).called(1);
      verify(() => localService.clearNotificationBadgeCount()).called(1);
      verify(() => localDatabase.clearPushRegistered()).called(1);
      verifyNever(
        () => userApi.removeMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
        ),
      );
    });

    test('keeps the registration flag when the cleanup is interrupted, '
        'so it is retried on the next launch', () async {
      when(
        () => localDatabase.isPushRegistered(),
      ).thenAnswer((_) async => true);
      when(() => messaging.deleteToken()).thenThrow(Exception('no network'));

      await buildService().cleanUpStalePushRegistration();

      verifyNever(() => localDatabase.clearPushRegistered());
    });

    test('runs a single teardown for concurrent calls', () async {
      when(
        () => localDatabase.isPushRegistered(),
      ).thenAnswer((_) async => true);
      final service = buildService();

      await Future.wait([
        service.cleanUpStalePushRegistration(),
        service.cleanUpStalePushRegistration(),
      ]);

      verify(() => messaging.deleteToken()).called(1);
    });
  });

  group('NotificationService.logout', () {
    test('skips entirely when Firebase is not configured', () async {
      when(() => firebaseService.apps).thenReturn(const []);

      await buildService().logout();

      verifyNever(() => messaging.deleteToken());
    });

    test('removes the mobile session and cleans up the local '
        'registration', () async {
      final service = await buildServiceWithToken();

      await service.logout();

      verify(
        () => userApi.removeMobileSession(xMobileToken: fcmToken),
      ).called(1);
      verify(() => messaging.deleteToken()).called(1);
      verify(() => localDatabase.clearPushRegistered()).called(1);
    });

    test('still cleans up when removeMobileSession fails '
        '(e.g. the JWT already expired)', () async {
      when(
        () => userApi.removeMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
        ),
      ).thenThrow(Exception('401'));
      final service = await buildServiceWithToken();

      await service.logout();

      verify(() => messaging.deleteToken()).called(1);
      verify(() => localDatabase.clearPushRegistered()).called(1);
    });

    test('completes when the local teardown fails (e.g. offline) and keeps '
        'the registration flag for the next launch', () async {
      when(() => messaging.deleteToken()).thenThrow(Exception('no network'));
      final service = await buildServiceWithToken();

      await expectLater(service.logout(), completes);

      verifyNever(() => localDatabase.clearPushRegistered());
    });

    test('does not reuse the deleted FCM token on a repeated logout', () async {
      final service = await buildServiceWithToken();

      await service.logout();
      await service.logout();

      verify(
        () => userApi.removeMobileSession(
          xMobileToken: any(named: 'xMobileToken'),
        ),
      ).called(1);
    });
  });
}
