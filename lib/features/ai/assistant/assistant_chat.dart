// How the WeCord AI assistant plugs into the chat page (see "Chat page
// extension points" in docs/design/wecord-design-language.md). Nothing here
// edits a chat page file:
//
//  * [askAssistantEntry] is a composer "+" menu entry that opens the "Ask
//    WeCord AI" sheet (a question and how much of the chat it may read);
//  * [askAssistantAction] is the message menu's "Ask WeCord AI": the same
//    sheet, as a reply to that message;
//  * [makeTasksAction] is the message menu's "Make tasks" on an AI to-do list
//    (also how screen readers reach the footer's button);
//  * [aiReplyFooterEntry] marks the assistant's answers "AI-generated" and, on
//    a to-do list, offers "Make tasks";
//  * [assistantRequestFooterEntry] tells whoever asked "WeCord AI is
//    thinking…", or why there was no answer.
// Mentioning the assistant is just text, `@WeCord AI /20 …` (see
// assistant_command.dart), so a person can also type it into the composer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/actions/extract_actions_sheet.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/assistant/assistant_command.dart';
import 'package:wecord/features/ai/assistant/ask_assistant_sheet.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The items of an AI answer that lists to-dos.
List<ExtractedAction> aiReplyItems(ChatMessage message) {
  final reply = message.aiReply;
  if (reply == null || reply.kind != AiReplyKind.todos) {
    return const [];
  }
  final now = DateTime.now();
  return [
    for (final item in reply.items)
      ?ExtractedAction.maybeFromJson(item)?.refined(now),
  ];
}

/// Opens the sheet that makes tasks out of the items of the AI answer
/// [message].
Future<bool?> makeTasksFromAiReply(BuildContext context, ChatMessage message) {
  return showExtractActionsSheet(
    context,
    conversationId: message.conversationId,
    preset: aiReplyItems(message),
  );
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> _ask(
  BuildContext context, {
  required String conversationId,
  ChatMessage? replyTo,
}) async {
  final sent = await showAskAssistantSheet(
    context,
    conversationId: conversationId,
    replyTo: replyTo,
  );
  if (sent == true && context.mounted) {
    _toast(context, tr('Sent. WeCord AI will answer in the chat.'));
  }
}

bool _aiOn(ProviderContainer container, String? circleId) =>
    container.read(aiAvailableProvider(circleId));

/// "Ask WeCord AI" in the composer's "+" menu, after Send GIF (1300).
final askAssistantEntry = ComposerMenuContribution(
  id: 'ask-wecord-ai',
  order: 1350,
  build: (ctx) {
    if (!_aiOn(ctx.container, null)) {
      return null;
    }
    return GlassMenuEntry(
      key: const ValueKey('composer-ask-ai-entry'),
      icon: Icons.auto_awesome_rounded,
      label: tr('Ask WeCord AI'),
      onSelected: () =>
          unawaited(_ask(ctx.context, conversationId: ctx.conversationId)),
    );
  },
);

/// "Ask WeCord AI" in the message menu, after Create task (700).
final askAssistantAction = MessageActionContribution(
  id: 'ask-wecord-ai',
  order: 710,
  build: (ctx) {
    final message = ctx.message;
    if (!ctx.canCompose ||
        ctx.isRecalled ||
        ctx.isPending ||
        message.type != MessageType.text ||
        message.aiReply != null ||
        message.body.trim().isEmpty ||
        !_aiOn(ctx.container, ctx.circleId)) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-ask-ai'),
        icon: Icons.auto_awesome_rounded,
        label: tr('Ask WeCord AI'),
        onSelected: () => unawaited(
          _ask(
            ctx.context,
            conversationId: message.conversationId,
            replyTo: message,
          ),
        ),
      ),
    ];
  },
);

/// "Make tasks" on an AI to-do list, before Create task (700).
final makeTasksAction = MessageActionContribution(
  id: 'ai-make-tasks',
  order: 690,
  build: (ctx) {
    if (!ctx.canCompose ||
        ctx.isRecalled ||
        ctx.isPending ||
        aiReplyItems(ctx.message).isEmpty) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-make-tasks'),
        icon: Icons.add_task_rounded,
        label: tr('Make tasks'),
        onSelected: () =>
            unawaited(makeTasksFromAiReply(ctx.context, ctx.message)),
      ),
    ];
  },
);

/// "AI-generated" under every answer of the assistant, with "Make tasks" on a
/// to-do list. Between the read status (650) and the translation.
const aiReplyFooterEntry = BubbleFooterEntry.below(
  id: 'ai-reply',
  order: 640,
  cardGap: 6,
  build: _aiReplyFooter,
);

Widget? _aiReplyFooter(BubbleFooterContext ctx) {
  final reply = ctx.message.aiReply;
  if (reply == null || ctx.isRecalled) {
    return null;
  }
  return AiReplyFooter(message: ctx.message, reply: reply);
}

/// The footer of an AI answer.
class AiReplyFooter extends ConsumerWidget {
  const AiReplyFooter({required this.message, required this.reply, super.key});

  final ChatMessage message;
  final MessageAiReply reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final asked = reply.requesterName.trim();
    final items = aiReplyItems(message);
    final label = asked.isEmpty
        ? tr('AI-generated')
        : tr('AI-generated · asked by {name}', {'name': asked});
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            key: const ValueKey('ai-reply-label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 13, color: c.accentText),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
          if (items.isNotEmpty)
            WeCordChip(
              key: const ValueKey('ai-reply-make-tasks'),
              icon: Icons.add_task_rounded,
              label: tr('Make tasks'),
              height: 30,
              selected: true,
              onPressed: () =>
                  unawaited(makeTasksFromAiReply(context, message)),
            ),
        ],
      ),
    );
  }
}

/// Under a person's own message that asked the assistant: "WeCord AI is
/// thinking…" while it works, and why when there is no answer. Nothing once
/// it answered, or for older messages.
const assistantRequestFooterEntry = BubbleFooterEntry.below(
  id: 'ai-request-status',
  order: 645,
  wrap: BubbleFooterWrap.pill,
  cardGap: 4,
  build: _requestFooter,
);

Widget? _requestFooter(BubbleFooterContext ctx) {
  final message = ctx.message;
  if (!ctx.isCurrentUser ||
      ctx.isRecalled ||
      message.type != MessageType.text ||
      message.aiReply != null ||
      message.reviewState != null ||
      !mentionsAssistant(message.body) ||
      DateTime.now().difference(message.createdAt) > assistantStatusWindow) {
    return null;
  }
  return AssistantRequestStatus(messageId: message.id);
}

/// The state of one request to the assistant.
class AssistantRequestStatus extends ConsumerWidget {
  const AssistantRequestStatus({required this.messageId, super.key});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(assistantJobProvider(messageId)).value;
    if (status == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final noAnswer = status.noAnswerText;
    final text = status.thinking ? tr('WeCord AI is thinking…') : noAnswer;
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        key: const ValueKey('ai-request-status'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.thinking)
            const SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          else
            Icon(Icons.info_outline_rounded, size: 13, color: c.subtle),
          const SizedBox(width: 6),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: TextStyle(fontSize: 11.5, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
