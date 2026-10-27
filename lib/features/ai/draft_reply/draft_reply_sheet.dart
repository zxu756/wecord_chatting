import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the "Help me reply" sheet (roadmap F6): an optional line about what
/// to say, then two or three replies to pick from. A pick goes to [onUse];
/// the app puts it in the message box and never sends it. [initialIntent] is
/// what is already in the box.
///
/// Nothing is asked of the AI until "Suggest replies" is tapped.
Future<void> showDraftReplySheet(
  BuildContext context, {
  required String conversationId,
  required void Function(String reply, String intent) onUse,
  String initialIntent = '',
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Help me reply'),
    detents: const [0.6, 0.92],
    // Large text needs the room to show "Suggest replies" without scrolling.
    initialDetent: MediaQuery.textScalerOf(context).scale(14) > 14 * 1.25
        ? 0.92
        : 0.75,
    builder: (sheetContext, scrollController) => DraftReplySheet(
      conversationId: conversationId,
      initialIntent: initialIntent,
      onUse: onUse,
      scrollController: scrollController,
    ),
  );
}

enum _Stage { input, working, result, nothing, error }

/// The sheet's content. Keys for tests: `draft-reply-intent`,
/// `draft-reply-suggest`, `draft-reply-option-N`, `draft-reply-use-N`,
/// `draft-reply-again`, `draft-reply-back`, `draft-reply-error`.
class DraftReplySheet extends ConsumerStatefulWidget {
  const DraftReplySheet({
    required this.conversationId,
    required this.onUse,
    this.initialIntent = '',
    this.scrollController,
    super.key,
  });

  final String conversationId;

  /// Called with the picked reply and the note the person had in the sheet
  /// when they picked it.
  final void Function(String reply, String intent) onUse;
  final String initialIntent;
  final ScrollController? scrollController;

  @override
  ConsumerState<DraftReplySheet> createState() => _DraftReplySheetState();
}

class _DraftReplySheetState extends ConsumerState<DraftReplySheet> {
  late final TextEditingController _intent;
  var _stage = _Stage.input;
  var _replies = const <String>[];
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialIntent.trim();
    _intent = TextEditingController(
      text: initial.length > draftReplyMaxIntentLength
          ? initial.substring(0, draftReplyMaxIntentLength)
          : initial,
    );
  }

  @override
  void dispose() {
    _intent.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final generation = ++_generation;
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    try {
      final replies = await ref
          .read(draftReplyRepositoryProvider)
          .suggest(
            conversationId: widget.conversationId,
            intent: _intent.text,
            language: AiLanguage.appLanguage,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _replies = replies;
        _stage = replies.isEmpty ? _Stage.nothing : _Stage.result;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (error is AiNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      setState(() {
        _error = error;
        _stage = _Stage.error;
      });
    }
  }

  void _use(String reply) {
    final intent = _intent.text;
    Navigator.of(context).pop();
    widget.onUse(reply, intent);
  }

  void _backToInput() {
    ++_generation;
    setState(() => _stage = _Stage.input);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final small = TextStyle(fontSize: 12.5, height: 1.35, color: c.subtle);

    final List<Widget> content;
    switch (_stage) {
      case _Stage.input:
        content = [
          WeCordTextField(
            key: const ValueKey('draft-reply-intent'),
            controller: _intent,
            label: tr('What do you want to say? (optional)'),
            hint: tr('Say yes but after 8, ask for the address…'),
            minLines: 2,
            maxLines: 5,
            inputFormatters: [
              LengthLimitingTextInputFormatter(draftReplyMaxIntentLength),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Reads the last {count} messages you can see in this chat. Nothing is posted to the chat: replies only fill your message box.',
              {'count': draftReplyContextMessages},
            ),
            style: small,
          ),
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('draft-reply-suggest'),
            label: tr('Suggest replies'),
            icon: Icons.auto_awesome_rounded,
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => unawaited(_suggest()),
          ),
        ];
      case _Stage.working:
        content = [
          Semantics(
            liveRegion: true,
            label: tr('Working on it…'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr('Working on it…'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ];
      case _Stage.result:
        content = [
          Semantics(
            liveRegion: true,
            child: Text(
              tr('Pick one to put in your message box'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final (index, reply) in _replies.indexed) ...[
            _ReplyCard(index: index, reply: reply, onUse: () => _use(reply)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Text(
            tr('Written by AI. Nothing is sent until you send it.'),
            style: small,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WeCordButton(
                key: const ValueKey('draft-reply-again'),
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => unawaited(_suggest()),
              ),
              WeCordButton(
                key: const ValueKey('draft-reply-back'),
                label: tr('Back'),
                variant: WeCordButtonVariant.ghost,
                onPressed: _backToInput,
              ),
            ],
          ),
        ];
      case _Stage.nothing:
        content = [
          _Note(
            key: const ValueKey('draft-reply-nothing'),
            text: tr(
              "There's nothing to reply to yet. Say what you want to write, then try again.",
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: WeCordButton(
              key: const ValueKey('draft-reply-back'),
              label: tr('Back'),
              variant: WeCordButtonVariant.secondary,
              onPressed: _backToInput,
            ),
          ),
        ];
      case _Stage.error:
        final error = _error ?? const AiFailedException();
        final canRetry =
            error is! AiNotConfiguredException &&
            error is! AiLimitReachedException &&
            error is! AiDisabledInCircleException &&
            error is! AiTurnedOffException &&
            error is! AiChatLockedException &&
            error is! AiRejectedException;
        content = [
          _Note(
            key: const ValueKey('draft-reply-error'),
            text: aiErrorMessage(error),
            isError: true,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canRetry)
                WeCordButton(
                  key: const ValueKey('draft-reply-again'),
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.accent,
                  onPressed: () => unawaited(_suggest()),
                ),
              WeCordButton(
                key: const ValueKey('draft-reply-back'),
                label: tr('Back'),
                variant: WeCordButtonVariant.ghost,
                onPressed: _backToInput,
              ),
            ],
          ),
        ];
    }

    return ListView(
      controller: widget.scrollController,
      shrinkWrap: widget.scrollController == null,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: content,
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.index,
    required this.reply,
    required this.onUse,
  });

  final int index;
  final String reply;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: ValueKey('draft-reply-option-$index'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            reply,
            style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: WeCordButton(
              key: ValueKey('draft-reply-use-$index'),
              label: tr('Use this reply'),
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.small,
              onPressed: onUse,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.isError = false, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? c.dangerSoft : c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: isError ? c.dangerText : c.muted,
          ),
        ),
      ),
    );
  }
}
