// Q&A posts in the chat page (C9).
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * [qaSolvedHeaderAction] adds "Mark as solved" / "Reopen question" to the
//    More menu of a Q&A post, for the asker and the channel's moderators. It
//    also watches the post's state, which keeps it loaded and rebuilds the
//    page when it arrives; the two entries below only read it.
//  * [qaAcceptAnswerAction] adds "Accept as answer" / "Remove accepted
//    answer" (which opens the question again) to a reply's menu.
//  * [qaAcceptedFooterEntry] marks the accepted answer under its bubble.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/circles/channel_types/channel_types_repository.dart';
import 'package:wecord/features/circles/channel_types/qa_models.dart';
import 'package:wecord/features/circles/channel_types/qa_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// The state of the Q&A post [conversationId] if some page already loaded it;
/// null for everything else, and it never starts a load.
QaPostState? knownQaPostState(
  ProviderContainer container,
  String conversationId,
) {
  final provider = qaPostStateProvider(conversationId);
  if (!container.exists(provider)) {
    return null;
  }
  return container.read(provider).value;
}

/// "Mark as solved" / "Reopen question" in the More menu of a Q&A post.
final qaSolvedHeaderAction = HeaderActionContribution(
  id: 'qa-solved',
  order: 1160,
  build: (ctx) {
    if (!ctx.forumPost || ctx.circleId == null || ctx.threadId == null) {
      return null;
    }
    final state = ctx.ref.watch(qaPostStateProvider(ctx.conversationId)).value;
    if (state == null || !state.canMark) {
      return null;
    }
    return ChatThreadAction(
      id: 'qa-solved',
      tooltip: state.solved ? tr('Reopen question') : tr('Mark as solved'),
      icon: state.solved
          ? Icons.help_outline_rounded
          : Icons.check_circle_outline_rounded,
      menuOnly: true,
      onPressed: () => unawaited(
        _change(
          ctx.context,
          ctx.ref.read(channelTypesRepositoryProvider),
          () => ctx.ref.invalidate(qaPostStateProvider(ctx.conversationId)),
          state.solved
              ? (repository) => repository.reopen(state.threadId)
              : (repository) => repository.markSolved(state.threadId),
          done: state.solved
              ? tr('Question reopened.')
              : tr('Marked as solved.'),
          failed: state.solved
              ? tr('Could not reopen the question. Try again.')
              : tr('Could not mark the question solved. Try again.'),
        ),
      ),
    );
  },
);

/// "Accept as answer" / "Remove accepted answer" in a reply's menu.
final qaAcceptAnswerAction = MessageActionContribution(
  id: 'qa-accept-answer',
  order: 360,
  build: (ctx) {
    final message = ctx.message;
    if (ctx.circleId == null ||
        ctx.isPending ||
        ctx.isRecalled ||
        message.type == MessageType.system ||
        message.reviewState != null) {
      return const [];
    }
    final state = knownQaPostState(ctx.container, message.conversationId);
    if (state == null ||
        !state.canMark ||
        state.openingMessageId == message.id) {
      return const [];
    }
    final accepted = state.isAnswer(message.id);
    final container = ctx.container;
    final context = ctx.context;
    return [
      MessageAction(
        key: const ValueKey('qa-accept-answer-action'),
        icon: accepted
            ? Icons.remove_done_rounded
            : Icons.check_circle_outline_rounded,
        label: accepted ? tr('Remove accepted answer') : tr('Accept as answer'),
        onSelected: () => unawaited(
          _change(
            context,
            container.read(channelTypesRepositoryProvider),
            () => container.invalidate(
              qaPostStateProvider(message.conversationId),
            ),
            accepted
                // Taking the answer off opens the question again.
                ? (repository) => repository.reopen(state.threadId)
                : (repository) => repository.markSolved(
                    state.threadId,
                    answerMessageId: message.id,
                  ),
            done: accepted ? tr('Question reopened.') : tr('Answer accepted.'),
            failed: tr('Could not change the accepted answer. Try again.'),
          ),
        ),
      ),
    ];
  },
);

/// "Accepted answer" under the answer the asker picked. The slot is only there
/// on a page whose post state is loaded (the header action above keeps it
/// loaded), and it watches the state itself, so the mark appears and goes
/// without the message list being rebuilt.
const qaAcceptedFooterEntry = BubbleFooterEntry.below(
  id: 'qa-accepted-answer',
  order: 460,
  build: _acceptedSlot,
  wrap: BubbleFooterWrap.plain,
  cardGap: 0,
);

Widget? _acceptedSlot(BubbleFooterContext ctx) {
  if (ctx.isRecalled) {
    return null;
  }
  final container = ProviderScope.containerOf(ctx.context, listen: false);
  if (!container.exists(qaPostStateProvider(ctx.message.conversationId))) {
    return null;
  }
  return QaAcceptedAnswerSlot(
    conversationId: ctx.message.conversationId,
    messageId: ctx.message.id,
  );
}

/// The accepted-answer mark of one message, or nothing.
class QaAcceptedAnswerSlot extends ConsumerWidget {
  const QaAcceptedAnswerSlot({
    required this.conversationId,
    required this.messageId,
    super.key,
  });

  final String conversationId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qaPostStateProvider(conversationId)).value;
    if (state == null || !state.isAnswer(messageId)) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: QaAcceptedAnswerMark(),
    );
  }
}

Future<void> _change(
  BuildContext context,
  ChannelTypesRepository repository,
  VoidCallback refresh,
  Future<QaPostState?> Function(ChannelTypesRepository repository) run, {
  required String done,
  required String failed,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await run(repository);
    refresh();
    messenger?.showSnackBar(SnackBar(content: Text(done)));
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }
}
