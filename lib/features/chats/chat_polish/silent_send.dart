// Sending without a push (A9).
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * [silentSendComposerEntry] adds "Send silently" to the composer's "+"
//    menu (composer_menu_registrations.dart): the text in the box is sent
//    like any message, but nobody's device is told about it. The others
//    still see it in the chat, and it counts as unread for them.
//  * [silentFooterEntry] marks your own silent messages under the bubble
//    (bubble_footer_registrations.dart).
//  * The send itself is [SilentMessageSender], which the live repository
//    implements; the page offers the entry only when it does.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// Sends a text message that is not pushed to anybody. Like
/// `OutboxMessageSender`, a repository may or may not be one.
abstract interface class SilentMessageSender {
  /// Returns the stored message's id, or null when AutoMod dropped it
  /// quietly (it then throws when it left a reason). [clientId] makes the
  /// send safe to repeat.
  Future<String?> sendSilentTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions,
  });
}

/// "Send silently" in the "+" menu, after Schedule message (800).
final silentSendComposerEntry = ComposerMenuContribution(
  id: 'send-silently',
  order: 850,
  build: (ctx) {
    final send = ctx.actions.sendSilently;
    if (send == null) {
      return null;
    }
    return GlassMenuEntry(
      key: const ValueKey('composer-send-silently-entry'),
      icon: Icons.notifications_off_outlined,
      label: tr('Send silently'),
      onSelected: () => unawaited(send()),
    );
  },
);

/// "Sent silently" under your own silent messages.
const silentFooterEntry = BubbleFooterEntry.below(
  id: 'silent',
  order: 450,
  build: _silentMark,
  wrap: BubbleFooterWrap.pill,
  cardGap: 4,
);

Widget? _silentMark(BubbleFooterContext ctx) {
  if (!ctx.message.silent || !ctx.isCurrentUser || ctx.isRecalled) {
    return null;
  }
  return const SilentMark();
}

/// The small "Sent silently" label with a bell that is off.
class SilentMark extends StatelessWidget {
  const SilentMark({super.key});

  @override
  Widget build(BuildContext context) {
    final tint = context.tokens.colors.subtle;
    final label = tr('Sent silently');
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('silent-mark'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined, size: 12, color: tint),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
