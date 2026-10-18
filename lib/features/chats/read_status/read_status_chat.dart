// How the group read list plugs into the chat page (see "Chat page extension
// points" in docs/design/wecord-design-language.md):
//
//  * [readStatusFooterEntry] is a bubble footer entry: under the user's newest
//    message in a group, a gray "3 read" that opens the list. The count comes
//    with the footer context (BubbleFooterContext.groupReadCount), worked out
//    with "Read" by latestOutgoingReadStateOf in thread/thread_layout.dart:
//    a direct chat keeps the built-in "Read"
//    (thread/registry/bubble_footer_builtin.dart), a group never says "Read";
//  * [messageInfoAction] adds "Message info" to the message menu of the user's
//    own messages in a group. That is also how screen readers and keyboards
//    reach the list: the count is plain text inside the message, read with it,
//    like "Read" always was.
//
// Both are registered in thread/registry/*_registrations.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/read_status/read_status_sheet.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether [conversationId] is a group (not a direct chat, channel, thread or
/// the note to self): the only place a message has a read list.
final isGroupConversationProvider = Provider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) {
  final summary = ref
      .watch(chatConversationSummaryProvider(conversationId))
      .value;
  return summary != null &&
      summary.type == ConversationType.group &&
      !summary.isNoteToSelf;
});

/// "3 read" under the user's newest message in a group, after the direct
/// chat's "Read" (600). Nothing until someone has read it.
const readStatusFooterEntry = BubbleFooterEntry.below(
  id: 'read-status',
  order: 650,
  build: _readStatusFooter,
);

Widget? _readStatusFooter(BubbleFooterContext ctx) {
  final message = ctx.message;
  if (ctx.groupReadCount <= 0 ||
      !ctx.isCurrentUser ||
      ctx.isRecalled ||
      ctx.cards ||
      message.type == MessageType.system ||
      message.reviewState != null) {
    return null;
  }
  return GroupReadCount(message: message, count: ctx.groupReadCount);
}

/// The gray "3 read" pill. Tapping it opens the list. For screen readers it is
/// plain text inside the message (it reads with it); the list is reached
/// through "Message info" in the message menu.
class GroupReadCount extends StatelessWidget {
  const GroupReadCount({required this.message, required this.count, super.key});

  final ChatMessage message;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 2, top: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: WallpaperPill(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('group-read-count'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => unawaited(showReadStatusSheet(context, message)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all_rounded, size: 14, color: c.muted),
                    const SizedBox(width: 4),
                    Text(
                      tr('{count} read', {'count': count}),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Message info" in the message menu, between Edit history (650) and Create
/// task (700): the user's own messages in a group.
final messageInfoAction = MessageActionContribution(
  id: 'message-info',
  order: 660,
  build: (ctx) => [
    if (ctx.isCurrentUser &&
        !ctx.isRecalled &&
        !ctx.isPending &&
        ctx.message.type != MessageType.system &&
        ctx.message.reviewState == null &&
        ctx.container.read(
          isGroupConversationProvider(ctx.message.conversationId),
        ))
      MessageAction(
        key: const ValueKey('message-action-message-info'),
        icon: Icons.info_outline_rounded,
        label: tr('Message info'),
        onSelected: () =>
            unawaited(showReadStatusSheet(ctx.context, ctx.message)),
      ),
  ],
);
