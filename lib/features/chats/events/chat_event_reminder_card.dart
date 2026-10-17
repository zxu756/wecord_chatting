import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/events/chat_event_format.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/ui/ui.dart';

/// An inbox card for an event that is about to start: its title, when it
/// starts and how soon. Unread ones have an accent edge.
class ChatEventReminderCard extends ConsumerWidget {
  const ChatEventReminderCard({
    required this.reminder,
    required this.onPressed,
    super.key,
  });

  final ChatEventReminder reminder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final start = reminder.startsAt.toLocal();
    final over = !now.isBefore(start);
    final when =
        '${chatEventDayLabel(start, now)} · ${formatClock(start, use24Hour: use24Hour)}';
    final soon = over
        ? tr('Starting now')
        : tr('Starts {when}', {'when': relativeTimeText(start, now)});
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    return WeCordPressable(
      key: ValueKey('inbox-event-${reminder.id}'),
      shape: shape,
      pressedScale: 0.98,
      semanticLabel: tr('Event reminder: {title}, {when}, {soon}', {
        'title': reminder.title,
        'when': when,
        'soon': soon,
      }),
      excludeSemantics: true,
      hint: tr('Opens the chat'),
      onPressed: onPressed,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: reminder.isUnread
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              SettingsIconTile(
                icon: Icons.event_rounded,
                tone: SettingsTone.warning,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$soon · $when',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.warningText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
