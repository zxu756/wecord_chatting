import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings switch for push notifications on this browser; nothing where
/// web push isn't available.
class PushSettingsTile extends ConsumerStatefulWidget {
  const PushSettingsTile({super.key});

  @override
  ConsumerState<PushSettingsTile> createState() => _PushSettingsTileState();
}

class _PushSettingsTileState extends ConsumerState<PushSettingsTile> {
  var _busy = false;

  Future<void> _toggle(bool enable) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (enable) {
        final error = await enablePush(ref);
        final message = switch (error) {
          null => null,
          PushEnableError.denied => tr(
            "Allow notifications for WeCord in your browser, then try again.",
          ),
          PushEnableError.notConfigured => tr(
            "Push notifications aren't set up on this server yet.",
          ),
          PushEnableError.failed => tr(
            'Could not turn on push notifications. Try again.',
          ),
        };
        if (message != null) {
          messenger?.showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        await disablePush(ref);
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Something went wrong. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(pushStatusProvider).value;
    if (status == null || status == PushStatus.unsupported) {
      return const SizedBox.shrink();
    }
    return SettingsRow.toggle(
      key: const ValueKey('push-notifications'),
      icon: Icons.phonelink_ring_outlined,
      title: tr('Push notifications'),
      subtitle: status == PushStatus.denied
          ? tr("Notifications are blocked in this browser's settings.")
          : tr('Get notified on this browser even when WeCord is closed.'),
      value: status == PushStatus.on,
      onChanged: _busy || status == PushStatus.denied
          ? null
          : (value) => unawaited(_toggle(value)),
    );
  }
}
