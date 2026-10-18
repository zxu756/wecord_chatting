import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/agenda_settings_screen.dart';
import 'package:wecord/features/pat/pat_suffix_sheet.dart';
import 'package:wecord/features/qr/my_qr_sheet.dart';
import 'package:wecord/features/qr/qr_link_handler.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings, under the account card: My QR code, Scan, the pat suffix and
/// the calendar subscription.
class ProfileToolsGroup extends ConsumerWidget {
  const ProfileToolsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      children: [
        SettingsRow(
          key: const ValueKey('settings-my-qr'),
          icon: Icons.qr_code_2_rounded,
          title: tr('My QR code'),
          onTap: () => unawaited(showMyQrSheet(context)),
        ),
        SettingsRow(
          key: const ValueKey('settings-scan'),
          icon: Icons.qr_code_scanner_rounded,
          title: tr('Scan'),
          onTap: () => unawaited(openQrScanner(context, ref)),
        ),
        const PatSuffixRow(),
        const AgendaSettingsRow(),
      ],
    );
  }
}

/// Friends → Add friend: Scan and My QR code side by side, above the search.
class AddFriendQrActions extends ConsumerWidget {
  const AddFriendQrActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: WeCordButton(
              key: const ValueKey('add-friend-scan'),
              label: tr('Scan'),
              icon: Icons.qr_code_scanner_rounded,
              variant: WeCordButtonVariant.secondary,
              expand: true,
              onPressed: () => unawaited(openQrScanner(context, ref)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: WeCordButton(
              key: const ValueKey('add-friend-my-qr'),
              label: tr('My QR code'),
              icon: Icons.qr_code_2_rounded,
              variant: WeCordButtonVariant.secondary,
              expand: true,
              onPressed: () => unawaited(showMyQrSheet(context)),
            ),
          ),
        ],
      ),
    );
  }
}
