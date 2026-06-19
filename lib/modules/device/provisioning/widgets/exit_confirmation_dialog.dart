import 'package:flutter/material.dart';
import 'package:thingsboard_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/utils/ui/tb_alert_dialog.dart';

class ExitConfirmationDialog extends StatelessWidget {
  const ExitConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return TbAlertDialog(
      title: Text(S.of(context).exitDeviceProvisioning),
      content: Text(S.of(context).areYouSure),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            S.of(context).cancel.toUpperCase(),
            style: TbTextStyles.labelLarge.copyWith(
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        TextButton(
          // Returns `true` so the caller can pop the provisioning page itself,
          // guarded by `canPop`. Previously this popped twice unconditionally;
          // the second pop emptied the navigator stack and crashed GoRouter
          // ("popped the last page off of the stack") when the provisioning
          // page was the only remaining route.
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            S.of(context).yes.toUpperCase(),
            style: TbTextStyles.labelLarge.copyWith(
              color: Colors.black.withValues(alpha: .87),
            ),
          ),
        ),
      ],
    );
  }
}
