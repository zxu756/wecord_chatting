// Small widgets that sit around a message: the thread chip under a thread's
// root message and the "edited" mark after a message's text. They are public
// so the bubble footer registry can build them.
import 'package:flutter/material.dart';
import 'package:wecord/features/chats/thread/thread_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "n replies · time" under a thread's root message; opens the thread.
class ThreadChip extends StatelessWidget {
  const ThreadChip({
    required this.messageId,
    required this.summary,
    required this.onTap,
    super.key,
  });

  final String messageId;
  final MessageThreadSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = summary.unreadCount > 0;
    final replies = switch (summary.replyCount) {
      0 => tr('No replies yet'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final lastReplyAt = summary.lastReplyAt;
    final detail = summary.replyCount > 0 && lastReplyAt != null
        ? '$replies · ${formatThreadActivity(lastReplyAt)}'
        : replies;
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('thread-chip-$messageId'),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 15, color: c.subtle),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  summary.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: unread || summary.replyCount > 0
                        ? c.accentText
                        : c.subtle,
                  ),
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('thread-chip-unread'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The small "edited" after a message's text.
class EditedMarker extends StatelessWidget {
  const EditedMarker({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      tr('edited'),
      style: TextStyle(
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: color,
      ),
    );
  }
}
