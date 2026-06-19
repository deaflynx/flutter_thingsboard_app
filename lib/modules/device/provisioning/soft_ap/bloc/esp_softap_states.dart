import 'package:equatable/equatable.dart';
import 'package:thingsboard_app/modules/device/provisioning/models/wifi_network.dart';

sealed class EspSoftApState extends Equatable {
  const EspSoftApState();

  @override
  List<Object?> get props => [];
}

final class EspSoftAppLoadingState extends EspSoftApState {
  const EspSoftAppLoadingState({this.attempt});

  /// 1-based attempt number shown to the user while connecting to the device.
  /// `null` for generic loading that isn't part of the connection sequence.
  final int? attempt;

  @override
  List<Object?> get props => [attempt];
}

final class EspSoftApConnectionErrorState extends EspSoftApState {
  const EspSoftApConnectionErrorState();
}

final class EspSoftApWifiNetworksNotFoundState extends EspSoftApState {
  const EspSoftApWifiNetworksNotFoundState();
}

final class EspManuallyConnectToDeviceNetworkState extends EspSoftApState {
  const EspManuallyConnectToDeviceNetworkState();
}

final class EspSoftApWiFiListState extends EspSoftApState {
  const EspSoftApWiFiListState(this.wifiList);

  final List<WifiNetwork> wifiList;

  @override
  List<Object?> get props => [wifiList];
}

final class EspSoftApProvisioningInProgressState extends EspSoftApState {
  const EspSoftApProvisioningInProgressState({
    required this.ssid,
    required this.password,
  });

  final String ssid;
  final String password;

  @override
  List<Object?> get props => [ssid, password];
}

final class EspSoftApProvisioningDoneState extends EspSoftApState {
  const EspSoftApProvisioningDoneState();
}
