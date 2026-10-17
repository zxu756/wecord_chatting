import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "#channel · Circle", the thread or group title, or null for a direct
/// message (the sender says it all).
String? conversationPlaceLabel(
  ConversationSummary? conversation,
  Map<String, CircleSummary> circles,
) {
  if (conversation == null) {
    return null;
  }
  final title = conversation.title?.trim();
  final circleName = circles[conversation.circleId]?.name;
  return switch (conversation.type) {
    ConversationType.direct => null,
    ConversationType.group => title,
    ConversationType.channel => [
      if (title != null && title.isNotEmpty) '#$title',
      ?circleName,
    ].join(' · '),
    ConversationType.thread => [
      if (title != null && title.isNotEmpty) title,
      ?circleName,
    ].join(' · '),
  };
}

/// Opens [conversationId] scrolled to [messageId] (when there is one): in
/// its circle or among the direct messages, wherever it lives. [conversation]
/// is the list's entry for it, when the list has it.
void openMessage(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  String? messageId,
  ConversationSummary? conversation,
}) {
  if (conversation != null && messageId != null) {
    openConversationAtMessage(
      context,
      ref,
      conversation: conversation,
      messageId: messageId,
    );
  } else if (conversation != null) {
    openConversation(context, conversation);
  } else {
    if (messageId != null) {
      ref.read(pendingMessageJumpProvider.notifier).state = MessageJump(
        conversationId: conversationId,
        messageId: messageId,
      );
    }
    openPage(context, '${ChatsScreen.path}/$conversationId');
  }
}

/// The message as one line of text for lists.
String laterPreview({
  required String conversationId,
  required String body,
  required MessageType type,
}) {
  return pinnedMessagePreview(
    ChatMessage(
      id: '',
      conversationId: conversationId,
      senderId: '',
      type: type,
      body: body,
      createdAt: clock.now(),
    ),
  );
}

/// A white card on the paper page: reminders, saved messages. Tapping it
/// (when [onPressed] is set) opens what it is about.
class LaterCard extends StatelessWidget {
  const LaterCard({
    required this.child,
    this.onPressed,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// An accent edge, as for unread notifications.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    return WeCordPressable(
      onPressed: onPressed,
      shape: shape,
      pressedScale: onPressed == null ? 1 : 0.98,
      mergeSemantics: false,
      builder: (context, states) {
        final hovered =
            onPressed != null &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: highlighted
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// The small round badge on an avatar.
class LaterAvatarBadge extends StatelessWidget {
  const LaterAvatarBadge({required this.color, required this.icon, super.key});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: c.panel, width: 2.5),
      ),
      child: Icon(icon, size: 11, color: Colors.white),
    );
  }
}

/// The message in a quiet box, or "Message unavailable" in its place.
class LaterMessagePreview extends StatelessWidget {
  const LaterMessagePreview({
    required this.available,
    required this.text,
    super.key,
  });

  final bool available;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: available
          ? Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.ink, height: 1.45),
            )
          : Row(
              children: [
                Icon(Icons.block_rounded, size: 16, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Message unavailable'),
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: c.muted,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A reminder in Notifications: due (with Jump and Dismiss) or upcoming
/// (with Cancel).
class ReminderCard extends ConsumerWidget {
  const ReminderCard({
    required this.id,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.preview,
    required this.available,
    required this.at,
    required this.upcoming,
    required this.place,
    required this.onJump,
    required this.onDismiss,
    super.key,
  });

  final String id;
  final String senderName;
  final String? senderAvatarUrl;
  final String preview;
  final bool available;
  final DateTime at;
  final bool upcoming;
  final String? place;
  final VoidCallback onJump;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final time = describeWhen(
      localizations,
      at.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final name = senderName.isEmpty ? tr('Message') : senderName;
    return LaterCard(
      key: ValueKey('reminder-$id'),
      highlighted: !upcoming,
      onPressed: onJump,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: senderAvatarUrl,
            badge: LaterAvatarBadge(
              color: upcoming ? c.faint : c.warning,
              icon: Icons.alarm_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (senderName.isNotEmpty) ...[
                              TextSpan(
                                text: senderName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: ' '),
                            ],
                            TextSpan(
                              text: upcoming
                                  ? tr('Reminder set')
                                  : tr('Reminder'),
                              style: senderName.isEmpty
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : null,
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (!upcoming) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (upcoming)
                  Text(
                    tr('Reminds you {time}', {'time': time}),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                if (place != null && place!.isNotEmpty)
                  Text(
                    place!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                const SizedBox(height: 8),
                LaterMessagePreview(available: available, text: preview),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (!upcoming && available)
                      WeCordButton(
                        key: ValueKey('reminder-jump-$id'),
                        label: tr('Jump'),
                        size: WeCordButtonSize.small,
                        variant: WeCordButtonVariant.secondary,
                        onPressed: onJump,
                      ),
                    WeCordButton(
                      key: ValueKey('reminder-dismiss-$id'),
                      label: upcoming ? tr('Cancel reminder') : tr('Dismiss'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
