import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notifications/notification_settings_controller.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Important contact (notify even in quiet hours)", on a friend's profile:
/// a switch that adds the friend to the people who are heard in quiet hours
/// (Settings -> Notifications -> Quiet hours).
class ImportantContactRow extends ConsumerWidget {
  const ImportantContactRow({required this.friend, super.key});

  final Profile friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider).value;
    final important = settings?.vipUserIds.contains(friend.id) ?? false;
    return SettingsRow.toggle(
      key: const ValueKey('profile-important'),
      icon: Icons.notification_important_outlined,
      tone: important ? SettingsTone.accent : SettingsTone.neutral,
      title: tr('Important contact'),
      subtitle: tr('Notify me even in quiet hours.'),
      value: important,
      // Not before the settings are loaded: a toggle on stale data could
      // undo a change made on another device.
      onChanged: settings == null
          ? null
          : (value) => unawaited(_set(context, ref, value)),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool important) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(notificationSettingsProvider.notifier)
          .setImportantContact(friend.id, important: important);
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(couldNotSaveText())));
    }
  }
}
