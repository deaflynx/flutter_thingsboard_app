import 'dart:async';
import 'dart:io';

import 'package:esp_provisioning_softap/esp_provisioning_softap.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:plugin_wifi_connect/plugin_wifi_connect.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/device/provisioning/bloc/bloc.dart'
    show DeviceProvisioningStatus;
import 'package:thingsboard_app/modules/device/provisioning/models/wifi_network.dart';
import 'package:thingsboard_app/modules/device/provisioning/soft_ap/bloc/bloc.dart';
import 'package:thingsboard_app/utils/services/communication/events/device_provisioning_status_changed_event.dart';
import 'package:thingsboard_app/utils/services/communication/i_communication_service.dart';

import 'package:thingsboard_app/utils/services/provisioning/soft_ap/i_soft_ap_service.dart';

class EspSoftApBloc extends Bloc<EspSoftApEvent, EspSoftApState> {
  EspSoftApBloc({
    required this.softApService,
    required this.logger,
    required this.communicationService,
    required this.deviceName,
    required this.pop,
  }) : super(
          Platform.isAndroid
              ? const EspManuallyConnectToDeviceNetworkState()
              : const EspSoftAppLoadingState(),
        ) {
    on(_onEvent);

    subscription = communicationService
        .on<DeviceProvisioningStatusChangedEvent>()
        .listen((event) {
      if (event.status == DeviceProvisioningStatus.done) {
        add(const EspSoftApProvisioningDoneEvent());
      }
    });

    // PluginWifiConnect.connect(deviceName);

    if (Platform.isIOS) {
     add(const EspSoftApAutoConnectToDeviceWifi());
    }
  }

  factory EspSoftApBloc.create({
    required String deviceName,
    required String pop,
  }) {
    return EspSoftApBloc(
      softApService: getIt<ISoftApService>(),
      logger: getIt<TbLogger>(),
      communicationService: getIt<ICommunicationService>(),
      deviceName: deviceName,
      pop: pop,
    );
  }

  final ISoftApService softApService;
  late Provisioning provisioning;
  final TbLogger logger;
  final ICommunicationService communicationService;
  final String deviceName;
  final String pop;
  late final StreamSubscription subscription;

  /// Retries remaining for the in-progress connection attempt. Reset per
  /// platform on each user-initiated attempt (see [_maxConnectionRetries]).
  int connectionRetries = 0;

  /// Retries after the first attempt before giving up. iOS needs a few to ride
  /// out the one-time "Local Network" permission prompt (the first local-network
  /// access fails while that system dialog is up, then a retry succeeds once the
  /// user taps Allow). Android has no such prompt, so it fails fast and surfaces
  /// the actionable error screen in a few seconds instead of ~90s (PROD-6042).
  int get _maxConnectionRetries => Platform.isIOS ? 4 : 1;

  /// Upper bound for the exponential backoff between retries.
  static const _maxBackoffSeconds = 8;

  /// Monotonic id of the current connection attempt. Bumped whenever the user
  /// initiates one (Ready / Try again); the retry loop checks it at every
  /// suspension point so a superseded attempt stops emitting (PROD-5940).
  int _connectAttempt = 0;

  /// 1-based number of the connection try currently in progress, shown on the
  /// loading screen so the (intentionally long) retry sequence tells the user
  /// what is happening instead of a bare spinner (PROD-6042).
  int _attemptNo = 0;
  List<WifiNetwork> wiFis = [];

  Future<void> _onEvent(
    EspSoftApEvent event,
    Emitter<EspSoftApState> emit,
  ) async {
    switch (event) {
      case EspSoftApConnectToDeviceEvent():
        await _onEspSoftApConnectToDeviceEvent(emit, event);

      case EspSoftApStartProvisioningEvent():
       _onEspSoftApStartProvisioningEvent(emit, event);

      case EspSoftApAutoConnectToDeviceWifi():
        bool? connectionResult;
        try {
          connectionResult = await PluginWifiConnect.connect(deviceName);
        } catch (_) {
          emit(const EspManuallyConnectToDeviceNetworkState());
        } finally {
          if (connectionResult == true) {
            await Future.delayed(const Duration(seconds: 5));
            add(const EspSoftApConnectToDeviceEvent());
          } else {
            emit(const EspManuallyConnectToDeviceNetworkState());
          }
        }


      case EspSoftApManuallyConnectToDeviceWifi():
        emit(const EspManuallyConnectToDeviceNetworkState());

      case EspSoftApProvisioningDoneEvent():
        emit(const EspSoftApProvisioningDoneState());

      case EspSoftApRescanWifiEvent():
        emit(EspSoftApWiFiListState(wiFis));
    }
  }
Future<void> _onEspSoftApStartProvisioningEvent(Emitter<EspSoftApState> emit, EspSoftApStartProvisioningEvent event) async {
 emit(
          EspSoftApProvisioningInProgressState(
            ssid: event.ssid,
            password: event.password,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        communicationService.fire(
          const DeviceProvisioningStatusChangedEvent(
            DeviceProvisioningStatus.wifi,
          ),
        );

        try {
          await softApService.sendWifiConfig(
            provisioning,
            ssid: event.ssid,
            password: event.password,
          );
          await softApService.applyWifiConfig(provisioning);

          communicationService.fire(
            const DeviceProvisioningStatusChangedEvent(
              DeviceProvisioningStatus.confirmation,
            ),
          );

          int getStatusTries = 5;
          while (getStatusTries >= 0) {
            if (isClosed) return;

            await Future.delayed(const Duration(seconds: 10));
            final status = await softApService.getStatus(provisioning);
            logger.info(
              'SoftAp get connection status: ${status.state},'
              ' failed reason: ${status.failedReason}, '
              'ip: ${status.ip}, '
              'getStatus tries left: $getStatusTries',
            );

            if (status.state == WifiConnectionState.Connected) {
              await PluginWifiConnect.disconnect();
              communicationService.fire(
                const DeviceProvisioningStatusChangedEvent(
                  DeviceProvisioningStatus.success,
                ),
              );

              break;
            } else if (status.state == WifiConnectionState.ConnectionFailed) {
              await PluginWifiConnect.disconnect();
              communicationService.fire(
                const DeviceProvisioningStatusChangedEvent(
                  DeviceProvisioningStatus.fail,
                ),
              );

              break;
            } else if (getStatusTries == 0 &&
                status.state == WifiConnectionState.Connecting) {
              logger.info(
                'SoftAp no more tries left to get device connection '
                'status but the status still connecting considered as failed',
              );
              communicationService.fire(
                const DeviceProvisioningStatusChangedEvent(
                  DeviceProvisioningStatus.fail,
                ),
              );
            }

            --getStatusTries;
          }
        } catch (e) {
          logger.error('Error provisioning device $e');
          communicationService.fire(
            const DeviceProvisioningStatusChangedEvent(
              DeviceProvisioningStatus.fail,
            ),
          );
        } 

}
  Future<void> _onEspSoftApConnectToDeviceEvent(
    Emitter<EspSoftApState> emit,
    EspSoftApConnectToDeviceEvent event,
  ) async {
    // A user-initiated tap (Ready / Try again) starts a fresh attempt: it
    // supersedes any in-flight retry chain and resets the retry budget. An
    // internal retry re-dispatch carries the generation of its own attempt.
    if (event.attempt == null) {
      _connectAttempt++;
      connectionRetries = _maxConnectionRetries;
      _attemptNo = 0;
    }
    final attempt = event.attempt ?? _connectAttempt;

    // Bail before touching the UI if a newer attempt has already taken over,
    // so a stale retry can never repaint the screen behind the user's back.
    if (isClosed || attempt != _connectAttempt) return;

    emit(EspSoftAppLoadingState(attempt: ++_attemptNo));

    try {
      provisioning = await softApService
          .startProvisioning(hostname: '192.168.4.1:80', pop: pop)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception(
              'SoftAp startProvisioning timeout reached.',
            ),
          );
    } catch (e) {
      logger.error('SoftAp Error connecting to device $e');
      if (isClosed || attempt != _connectAttempt) return;

      if (connectionRetries > 0) {
        // Exponential backoff (1s, 2s, 4s, 8s…) capped at [_maxBackoffSeconds].
        // Fast early retries catch the moment the iOS user grants Local Network
        // permission; the bounded total avoids the old ~90s dead wait.
        final retryIndex = _maxConnectionRetries - connectionRetries;
        final backoff = 1 << retryIndex;
        final delaySeconds =
            backoff > _maxBackoffSeconds ? _maxBackoffSeconds : backoff;

        --connectionRetries;
        logger.debug(
          'SoftAp retrying connection in ${delaySeconds}s, '
          'retries left $connectionRetries',
        );
        await Future.delayed(Duration(seconds: delaySeconds));
        if (isClosed || attempt != _connectAttempt) return;
        add(EspSoftApConnectToDeviceEvent(attempt: attempt));
      } else {
        emit(const EspSoftApConnectionErrorState());
      }
      return;
    }

    if (isClosed || attempt != _connectAttempt) return;
    await scanWifi(emit);
  }

  Future<void> scanWifi(Emitter<EspSoftApState> emit) async {
    try {
      final wifiList =
          await softApService.startScanWiFi(provisioning).timeout(
                const Duration(seconds: 20),
                onTimeout: () => throw Exception(
                  'SoftAp startScanWiFi timeout reached',
                ),
              );
    
      if (wifiList != null && wifiList.isNotEmpty) {
    
        wiFis = wifiList.map((e) => WifiNetwork.fromJson(e)).toList();
        emit(EspSoftApWiFiListState(wiFis));
      } else {
        throw Exception('Wi-Fi networks are empty');
      }
    } catch (e) {
      logger.error('Error scan WiFi network $e');
      emit(const EspSoftApWifiNetworksNotFoundState());
    }
  }

  @override
  Future<void> close() {
    provisioning.dispose();
    subscription.cancel();
    return super.close();
  }
}
