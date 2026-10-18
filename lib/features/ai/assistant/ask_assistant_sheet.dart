import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/assistant/assistant_command.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/thread/thread_text.dart'
    show replyPreviewForMessage, replyPreviewBody;
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the "Ask WeCord AI" sheet: a question and how much of the chat the
/// assistant may read. Sending posts an ordinary message that mentions the
/// assistant (`@WeCord AI /20 …`), as a reply to [replyTo] when given, so
/// everyone sees the question and then the answer. Resolves to true when it
/// was sent.
Future<bool?> showAskAssistantSheet(
  BuildContext context, {
  required String conversationId,
  ChatMessage? replyTo,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Ask WeCord AI'),
    detents: const [0.6, 0.92],
    initialDetent: 0.75,
    builder: (sheetContext, scrollController) => AskAssistantSheet(
      conversationId: conversationId,
      replyTo: replyTo,
      scrollController: scrollController,
    ),
  );
}

/// The sheet's content. Keys for tests: `ask-ai-question`, `ask-ai-range-N`
/// (0, 20, 100), `ask-ai-send`.
class AskAssistantSheet extends ConsumerStatefulWidget {
  const AskAssistantSheet({
    required this.conversationId,
    this.replyTo,
    this.scrollController,
    super.key,
  });

  final String conversationId;
  final ChatMessage? replyTo;
  final ScrollController? scrollController;

  @override
  ConsumerState<AskAssistantSheet> createState() => _AskAssistantSheetState();
}

class _AskAssistantSheetState extends ConsumerState<AskAssistantSheet> {
  final _question = TextEditingController();
  var _range = AssistantRange.thisMessage;
  var _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _question.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _question.text.trim();
    if (question.isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final replyTo = widget.replyTo;
    try {
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
            body: assistantMessageText(_range, question),
            replyToMessageId: replyTo?.id,
            replyPreview: replyTo == null
                ? null
                : replyPreviewForMessage(replyTo),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = errorText(error);
        });
      }
    }
  }

  String get _rangeHint {
    final replying = widget.replyTo != null;
    return switch (_range) {
      AssistantRange.thisMessage =>
        replying
            ? tr('Reads your question and the message you are asking about.')
            : tr('Reads only your question.'),
      AssistantRange.last20 => tr(
        'Also reads the last 20 messages you can see in this chat.',
      ),
      AssistantRange.last100 => tr(
        'Also reads the last 100 messages you can see in this chat.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final replyTo = widget.replyTo;
    final suggestions = [
      tr('Summarize this'),
      tr('List the to-dos'),
      tr('Translate to English'),
      tr('Explain this'),
    ];
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: widget.scrollController == null,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        if (replyTo != null) ...[
          Container(
            key: const ValueKey('ask-ai-quote'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
              border: Border(left: BorderSide(color: c.accent, width: 3)),
            ),
            child: Text(
              replyPreviewBody(replyTo, localized: true),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 1.35, color: c.muted),
            ),
          ),
          const SizedBox(height: 14),
        ],
        WeCordTextField(
          key: const ValueKey('ask-ai-question'),
          controller: _question,
          label: tr('Your question'),
          hint: tr(
            'Summarize the plan, list the to-dos, translate to English…',
          ),
          minLines: 2,
          maxLines: 5,
          inputFormatters: [LengthLimitingTextInputFormatter(600)],
          autofocus: true,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final text in suggestions)
              WeCordChip(
                label: text,
                height: 32,
                onPressed: () {
                  _question.text = text;
                  _question.selection = TextSelection.collapsed(
                    offset: text.length,
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          tr('What can WeCord AI read?'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final range in AssistantRange.values)
              WeCordChip(
                key: ValueKey('ask-ai-range-${range.count}'),
                label: range.label,
                selected: _range == range,
                onPressed: () => setState(() => _range = range),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _rangeHint,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: c.subtle),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Everyone in this chat sees your question and the answer, and can report the answer. WeCord AI only reads what you can see here.',
          ),
          style: TextStyle(fontSize: 12.5, height: 1.35, color: c.subtle),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('ask-ai-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          ),
        const SizedBox(height: 16),
        WeCordButton(
          key: const ValueKey('ask-ai-send'),
          label: tr('Ask WeCord AI'),
          icon: Icons.auto_awesome_rounded,
          expand: true,
          size: WeCordButtonSize.large,
          loading: _sending,
          onPressed: _question.text.trim().isEmpty
              ? null
              : () => unawaited(_send()),
        ),
      ],
    );
  }
}
