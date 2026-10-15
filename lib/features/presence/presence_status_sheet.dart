import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/presence_status.dart';

/// Lets the current user pick Online, Idle, Do Not Disturb or Invisible.
/// With [onEditCustomStatus], also offers their custom status.
Future<void> showPresenceStatusSheet(
  BuildContext context, {
  VoidCallback? onEditCustomStatus,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => PresenceStatusSheet(onEditCustomStatus: onEditCustomStatus),
  );
}

class PresenceStatusSheet extends ConsumerWidget {
  const PresenceStatusSheet({this.onEditCustomStatus, super.key});

  final VoidCallback? onEditCustomStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current =
        ref.watch(presenceSettingsProvider).valueOrNull?.status ??
        PresenceStatus.online;
    final onEditCustomStatus = this.onEditCustomStatus;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('Status'), style: theme.textTheme.titleLarge),
            ),
            for (final status in PresenceStatus.values)
              ListTile(
                key: ValueKey('presence-option-${status.value}'),
                leading: PresenceIndicator(
                  status: status,
                  borderColor: theme.colorScheme.surfaceContainerLow,
                  size: 16,
                ),
                title: Text(status.label),
                subtitle: switch (status.description) {
                  final description? => Text(description),
                  null => null,
                },
                trailing: status == current ? const Icon(Icons.check) : null,
                selected: status == current,
                onTap: () {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final settings = ref.read(presenceSettingsProvider.notifier);
                  Navigator.of(context).pop();
                  unawaited(
                    settings.setStatus(status).catchError((Object _) {
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr('Could not change status. Try again.'),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            if (onEditCustomStatus != null) ...[
              const Divider(),
              ListTile(
                key: const ValueKey('presence-custom-status'),
                leading: const Icon(Icons.add_reaction_outlined),
                title: Text(tr('Set custom status')),
                onTap: () {
                  Navigator.of(context).pop();
                  onEditCustomStatus();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
