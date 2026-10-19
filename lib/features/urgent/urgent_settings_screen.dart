import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Notifications -> Urgent messages.
void openUrgentSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const UrgentSettingsScreen()),
  );
}

/// The row in Settings -> Notifications.
class UrgentSettingsRow extends ConsumerWidget {
  const UrgentSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(mutedUrgentSendersProvider).value?.length ?? 0;
    return SettingsRow(
      key: const ValueKey('urgent-settings-tile'),
      icon: Icons.priority_high_rounded,
      title: tr('Urgent messages'),
      value: muted == 0 ? null : tr('{count} turned off', {'count': muted}),
      onTap: () => openUrgentSettings(context),
    );
  }
}

/// What urgent messages do, and the people whose urgent messages are off.
class UrgentSettingsScreen extends ConsumerWidget {
  const UrgentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final muted = ref.watch(mutedUrgentSendersProvider);
    return SettingsPage(
      key: const ValueKey('urgent-settings-screen'),
      title: tr('Urgent messages'),
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            tr(
              'A friend or group member can mark their message urgent for you. You get a notification even in quiet hours or when the chat is muted, and a red banner in the chat until you tap Got it. At most 5 a day from each person. Blocked people can not do it.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.45, color: c.muted),
          ),
        ),
        muted.when(
          loading: () => const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr('Could not load the list.'),
              style: TextStyle(color: c.dangerText),
            ),
          ),
          data: (senders) => senders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr('You have not turned off anyone.'),
                    key: const ValueKey('urgent-settings-empty'),
                    style: TextStyle(fontSize: 14, color: c.subtle),
                  ),
                )
              : SettingsGroup(
                  header: tr('Turned off'),
                  children: [
                    for (final sender in senders) _MutedRow(sender: sender),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MutedRow extends ConsumerStatefulWidget {
  const _MutedRow({required this.sender});

  final MutedUrgentSender sender;

  @override
  ConsumerState<_MutedRow> createState() => _MutedRowState();
}

class _MutedRowState extends ConsumerState<_MutedRow> {
  var _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(urgentRepositoryProvider)
          .setAllowedFrom(widget.sender.senderId, allowed: true);
      ref.invalidate(mutedUrgentSendersProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.sender;
    return SettingsRow(
      key: ValueKey('urgent-muted-${sender.senderId}'),
      icon: Icons.person_off_outlined,
      title: sender.name,
      trailing: WeCordButton(
        key: ValueKey('urgent-allow-${sender.senderId}'),
        label: tr('Allow'),
        size: WeCordButtonSize.small,
        variant: WeCordButtonVariant.secondary,
        loading: _busy,
        onPressed: _busy ? null : () => unawaited(_allow()),
      ),
      showChevron: false,
    );
  }
}
