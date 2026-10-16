import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Lets the current user pick Online, Idle, Do Not Disturb or Invisible.
/// With [onEditCustomStatus], also offers their custom status.
Future<void> showPresenceStatusSheet(
  BuildContext context, {
  VoidCallback? onEditCustomStatus,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Status'),
    builder: (_, _) =>
        PresenceStatusSheet(onEditCustomStatus: onEditCustomStatus),
  );
}

class PresenceStatusSheet extends ConsumerWidget {
  const PresenceStatusSheet({this.onEditCustomStatus, super.key});

  final VoidCallback? onEditCustomStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final current =
        ref.watch(presenceSettingsProvider).valueOrNull?.status ??
        PresenceStatus.online;
    final onEditCustomStatus = this.onEditCustomStatus;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in PresenceStatus.values)
              _SheetRow(
                key: ValueKey('presence-option-${status.value}'),
                leading: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: PresenceIndicator(
                      status: status,
                      borderColor: c.panel,
                      size: 18,
                    ),
                  ),
                ),
                title: status.label,
                subtitle: status.description,
                selected: status == current,
                onPressed: () {
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Container(height: 1, color: c.lineSoft),
              ),
              _SheetRow(
                key: const ValueKey('presence-custom-status'),
                leading: const SettingsIconTile(
                  icon: Icons.add_reaction_outlined,
                ),
                title: tr('Set custom status'),
                onPressed: () {
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

/// A row of the status sheet: leading, title and subtitle, and a check
/// when [selected].
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.leading,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.selected = false,
    super.key,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      selected: selected,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      onPressed: onPressed,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? c.raised
                : hovered
                ? c.ink.withValues(alpha: 0.04)
                : c.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 20, color: c.accent),
            ],
          ),
        );
      },
    );
  }
}
