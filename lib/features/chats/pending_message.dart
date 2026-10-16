import 'package:flutter/material.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A message the server has not stored yet: the bubble, faded and without
/// its actions, over "Sending…" or "Failed — tap to retry".
class PendingMessageFrame extends StatelessWidget {
  const PendingMessageFrame({
    required this.entry,
    required this.onRetry,
    required this.onDiscard,
    required this.child,
    this.alignEnd = true,
    super.key,
  });

  final OutboxEntry entry;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final Widget child;

  /// Own messages sit on the right in bubble chats.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final failed = entry.state == OutboxState.failed;
    final status = failed
        ? WeCordPressable(
            key: ValueKey('pending-retry-${entry.clientId}'),
            onPressed: onRetry,
            onLongPress: onDiscard,
            semanticLabel: tr('Failed — tap to retry'),
            builder: (context, states) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
                const SizedBox(width: 4),
                Text(
                  tr('Failed — tap to retry'),
                  style: TextStyle(
                    color: c.dangerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        : Row(
            key: ValueKey('pending-sending-${entry.clientId}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: c.faint),
              const SizedBox(width: 4),
              Text(
                tr('Sending…'),
                style: TextStyle(
                  color: c.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Attachments show their own progress, cancel and retry buttons, so
        // they stay at full strength and tappable.
        if (entry.media != null)
          child
        else
          IgnorePointer(
            child: Opacity(opacity: failed ? 0.55 : 0.7, child: child),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: status,
        ),
      ],
    );
  }
}
