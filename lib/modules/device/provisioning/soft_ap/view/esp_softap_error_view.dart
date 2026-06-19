import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thingsboard_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/device/provisioning/widgets/try_again_button.dart';

class EspSoftApConnectionErrorView extends StatelessWidget {
  const EspSoftApConnectionErrorView({
    required this.assetPath,
    required this.message,
    this.onTryAgain,
    this.primaryActionLabel,
    this.onPrimaryAction,
    super.key,
  });

  final String assetPath;
  final String message;
  final VoidCallback? onTryAgain;

  /// Primary button label/action. When omitted, falls back to opening the app
  /// settings (used by the Wi-Fi-not-found screen). The connection-error screen
  /// passes "Open Wi-Fi settings" so the user can join the device's network.
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SvgPicture.asset(assetPath, width: 140, height: 140),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TbTextStyles.bodyMedium.copyWith(
                color: Colors.black.withValues(alpha: .54),
              ),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
            onPressed: onPrimaryAction ?? () => openAppSettings(),
            child: Text(
              primaryActionLabel ?? S.of(context).openAppSettings,
              style: TbTextStyles.labelMedium.copyWith(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Visibility(
          visible: onTryAgain != null,
          child: TryAgainButton(onTryAgain: onTryAgain!),
        ),
      ],
    );
  }
}
