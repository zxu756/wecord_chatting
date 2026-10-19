import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ask/ask_controller.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/search_results.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the person is asking about, in words: the circle's or chat's name, or
/// "all your chats".
String askScopeName(MessageSearchScope scope) => switch (scope) {
  EverywhereScope() => tr('all your chats'),
  CircleScope(:final name) =>
    name != null && name.trim().isNotEmpty ? name.trim() : tr('this circle'),
  ConversationScope(:final title) =>
    title != null && title.trim().isNotEmpty ? title.trim() : tr('this chat'),
};

/// The body of Search while "Ask AI" is on: ask a question about the chats in
/// [scope], read the answer, and open any message it was based on. The
/// question is typed in Search's own box and sent by [onAsk].
class AskAiPanel extends ConsumerWidget {
  const AskAiPanel({
    required this.question,
    required this.scope,
    required this.onAsk,
    required this.onAskEverywhere,
    required this.onPickExample,
    super.key,
  });

  /// What is in the search box now.
  final String question;
  final MessageSearchScope scope;

  /// Sends [question].
  final VoidCallback onAsk;

  /// Asks the same question in all chats.
  final VoidCallback onAskEverywhere;

  /// Puts an example in the box and asks it.
  final ValueChanged<String> onPickExample;

  static List<String> examples() => [
    tr('Where are we meeting on Saturday?'),
    tr('Who said they would bring snacks?'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(askControllerProvider);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    final loading = state.phase == AskPhase.loading;

    final Widget body = switch (state.phase) {
      AskPhase.idle => _AskIntro(scope: scope, onPickExample: onPickExample),
      AskPhase.loading => const _AskLoading(),
      AskPhase.answered when state.answer?.isUsable == true => _AskAnswerView(
        state: state,
      ),
      AskPhase.answered => _AskNotFound(
        reason: state.answer?.reason ?? AskNotFoundReason.noMatches,
        scope: state.scope,
        onAskEverywhere: onAskEverywhere,
        onRetry: onAsk,
      ),
      AskPhase.failed => _AskFailed(error: state.error, onRetry: onAsk),
    };

    return ListView(
      key: const ValueKey('ask-panel'),
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
      children: [
        WeCordButton(
          key: const ValueKey('ask-submit'),
          label: tr('Ask'),
          icon: Icons.auto_awesome_rounded,
          variant: WeCordButtonVariant.accent,
          expand: true,
          loading: loading,
          onPressed: question.trim().isEmpty || loading ? null : onAsk,
        ),
        body,
      ],
    );
  }
}

class _AskIntro extends StatelessWidget {
  const _AskIntro({required this.scope, required this.onPickExample});

  final MessageSearchScope scope;
  final ValueChanged<String> onPickExample;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('ask-intro'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            child: SettingsIconTile(
              icon: Icons.auto_awesome_rounded,
              tone: SettingsTone.accent,
              size: 56,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              tr('Ask about your chats'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'WeCord AI looks through the messages you can see, then answers using only what it finds, and shows you the messages it used.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            tr('Looking in {place}', {'place': askScopeName(scope)}),
            key: const ValueKey('ask-scope-note'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: c.ink,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Only the messages that match your question are sent to the AI provider.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.subtle, height: 1.4),
          ),
          const SizedBox(height: 18),
          for (final (index, example) in AskAiPanel.examples().indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AskExample(
                key: ValueKey('ask-example-$index'),
                text: example,
                onPressed: () => onPickExample(example),
              ),
            ),
        ],
      ),
    );
  }
}

/// A question to try: tap to ask it. Wraps at large text sizes.
class _AskExample extends StatelessWidget {
  const _AskExample({required this.text, required this.onPressed, super.key});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    const radius = BorderRadius.all(Radius.circular(14));
    return WeCordPressable(
      onPressed: onPressed,
      pressedScale: 1,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      semanticLabel: text,
      hint: tr('Asks this question'),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              c.ink.withValues(alpha: hovered ? 0.035 : 0),
              c.panel,
            ),
            borderRadius: radius,
          ),
          child: Row(
            children: [
              Icon(Icons.north_east_rounded, size: 16, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14.5, height: 1.35, color: c.ink),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AskLoading extends StatelessWidget {
  const _AskLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('ask-loading'),
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.muted),
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              tr('Looking through your messages…'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// "[1]" and "[2]" in an answer are accent-colored so they read as pointers to
/// the cards below.
List<InlineSpan> answerSpans(String text, TextStyle base, TextStyle marker) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in RegExp(r'\[(\d{1,2})\]').allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: marker));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return spans;
}

class _AskAnswerView extends ConsumerWidget {
  const _AskAnswerView({required this.state});

  final AskState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final answer = state.answer!;
    return Column(
      key: const ValueKey('ask-answer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
          child: Text(
            state.question,
            key: const ValueKey('ask-question'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: c.muted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: c.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        trIn('ask', 'Answer'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.accentText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText.rich(
                key: const ValueKey('ask-answer-text'),
                TextSpan(
                  style: TextStyle(fontSize: 15.5, height: 1.5, color: c.ink),
                  children: answerSpans(
                    answer.answer!,
                    TextStyle(fontSize: 15.5, height: 1.5, color: c.ink),
                    TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.accentText,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr('AI can make mistakes. Check the messages it used.'),
                style: TextStyle(fontSize: 12.5, color: c.subtle, height: 1.35),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Semantics(
            header: true,
            child: Text(
              tr('Messages used'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ),
        ),
        for (final source in answer.sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AskSourceCard(source: source),
          ),
      ],
    );
  }
}

/// A message an answer is based on: tap to open it in its chat.
class AskSourceCard extends ConsumerWidget {
  const AskSourceCard({required this.source, super.key});

  final AskSource source;

  void _open(BuildContext context, WidgetRef ref) {
    final conversation =
        source.place?.toSummary() ??
        ConversationSummary(
          id: source.conversationId,
          type: ConversationType.direct,
          unreadCount: 0,
        );
    openConversationAtMessage(
      context,
      ref,
      conversation: conversation,
      messageId: source.messageId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final place = source.place?.label;
    final time = searchHitTime(source.createdAt);
    final sender = source.sender.isEmpty ? tr('Someone') : source.sender;
    final where = place == null || place.isEmpty ? sender : '$sender · $place';
    const radius = BorderRadius.all(Radius.circular(14));
    return WeCordPressable(
      key: ValueKey('ask-source-${source.n}'),
      onPressed: () => _open(context, ref),
      pressedScale: 1,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      semanticLabel: tr('Source {n}: {where}, {time}. {text}', {
        'n': source.n,
        'where': where,
        'time': time,
        'text': source.snippet,
      }),
      hint: tr('Opens the message in its chat'),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              c.ink.withValues(alpha: hovered ? 0.035 : 0),
              c.panel,
            ),
            borderRadius: radius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${source.n}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.accentText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      where,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(time, style: TextStyle(fontSize: 12, color: c.subtle)),
                    if (source.snippet.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        source.snippet,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.faint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AskNotFound extends StatelessWidget {
  const _AskNotFound({
    required this.reason,
    required this.scope,
    required this.onAskEverywhere,
    required this.onRetry,
  });

  final AskNotFoundReason reason;
  final MessageSearchScope scope;
  final VoidCallback onAskEverywhere;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final widerHelps =
        scope is! EverywhereScope &&
        (reason == AskNotFoundReason.noMatches ||
            reason == AskNotFoundReason.notInMessages);
    final text = switch (reason) {
      AskNotFoundReason.noMatches => tr(
        'No messages matched your question. Try other words.',
      ),
      AskNotFoundReason.notInMessages => tr(
        "The messages I found don't answer that, so I won't guess.",
      ),
      AskNotFoundReason.sourcesChanged => tr(
        'Some messages changed while I was reading. Ask again.',
      ),
      AskNotFoundReason.noKeywords => tr(
        'Add a few more words about what you want to find.',
      ),
    };
    return KeyedSubtree(
      key: const ValueKey('ask-not-found'),
      child: SearchHint(
        icon: Icons.search_off_rounded,
        title: tr("Couldn't find an answer in your messages"),
        text: text,
        action: widerHelps
            ? WeCordButton(
                key: const ValueKey('ask-everywhere'),
                label: tr('Ask in all your chats'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: onAskEverywhere,
              )
            : reason == AskNotFoundReason.sourcesChanged
            ? WeCordButton(
                key: const ValueKey('ask-retry'),
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }
}

class _AskFailed extends StatelessWidget {
  const _AskFailed({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final noRetry =
        error is AiNotConfiguredException ||
        error is AiDisabledInCircleException ||
        error is AiTurnedOffException ||
        error is AiLimitReachedException;
    return KeyedSubtree(
      key: const ValueKey('ask-failed'),
      child: SearchHint(
        icon: Icons.error_outline_rounded,
        title: tr("Couldn't get an answer"),
        text: aiErrorMessage(error ?? const AiFailedException()),
        action: noRetry
            ? null
            : WeCordButton(
                key: const ValueKey('ask-retry'),
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: onRetry,
              ),
      ),
    );
  }
}
