// How bot components plug into the chat page (see "Chat page extension points"
// in docs/design/wecord-design-language.md). Nothing here edits a chat page
// file:
//
//  * [botComponentsFooterEntry] draws the buttons, links and lists of a bot's
//    message inside its bubble, after the text;
//  * [botPrivateRepliesFooterEntry] draws what a bot said only to you about
//    that message ("Only you can see this") under it.
// Both are listed in bubble_footer_registrations.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_author.dart' show MessageBotTag;
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/interactions/components_view.dart';
import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The buttons and lists of a bot's message, inside the bubble after its text.
final botComponentsFooterEntry = BubbleFooterEntry.inside(
  id: 'bot-components',
  order: 150,
  build: (ctx) {
    final components = ctx.message.components;
    if (components == null || ctx.isRecalled) {
      return const [];
    }
    return [
      MessageComponentsView(
        components: components,
        targetId: ctx.message.id,
        botName:
            ctx.message.senderNickname ?? ctx.message.sender?.displayName ?? '',
      ),
    ];
  },
);

/// A bot's private replies about this message, under the bubble.
final botPrivateRepliesFooterEntry = BubbleFooterEntry.below(
  id: 'bot-private-replies',
  order: 160,
  build: (ctx) {
    if (ctx.message.components == null || ctx.isRecalled) {
      return null;
    }
    return PrivateRepliesView(
      conversationId: ctx.message.conversationId,
      messageId: ctx.message.id,
    );
  },
);

/// The private replies of bots to the person, about [messageId].
class PrivateRepliesView extends ConsumerWidget {
  const PrivateRepliesView({
    required this.conversationId,
    required this.messageId,
    super.key,
  });

  final String conversationId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(ephemeralRepliesProvider(conversationId)).value;
    final mine = [
      if (replies != null)
        for (final reply in replies)
          if (reply.messageId == messageId) reply,
    ];
    if (mine.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('bot-private-replies'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final reply in mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: PrivateReplyCard(
              reply: reply,
              conversationId: conversationId,
            ),
          ),
      ],
    );
  }
}

/// One private reply: who said it, that only you see it, the text, its own
/// buttons, and a way to dismiss it.
class PrivateReplyCard extends ConsumerWidget {
  const PrivateReplyCard({
    required this.reply,
    required this.conversationId,
    super.key,
  });

  final EphemeralReply reply;
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final components = reply.components;
    return Container(
      key: ValueKey('private-reply-${reply.id}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 14, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tr('Only you can see this'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.muted,
                      ),
                    ),
                    Text(
                      '· ${reply.botName}',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    const MessageBotTag(),
                  ],
                ),
              ),
              WeCordIconButton(
                key: ValueKey('private-reply-dismiss-${reply.id}'),
                icon: Icons.close_rounded,
                tooltip: tr('Dismiss'),
                variant: WeCordButtonVariant.ghost,
                size: 32,
                iconSize: 16,
                onPressed: () => _dismiss(context, ref),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: MessageMarkdownText(body: reply.body, color: c.ink),
          ),
          if (components != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: MessageComponentsView(
                components: components,
                targetId: reply.id,
                botName: reply.botName,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(interactionsRepositoryProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await repository.dismissEphemeral(reply.id);
      // A delete is not always announced; look again.
      ref.invalidate(ephemeralRepliesProvider(conversationId));
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not dismiss this. Try again.'))),
      );
    }
  }
}
