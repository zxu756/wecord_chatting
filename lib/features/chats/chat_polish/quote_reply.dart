// Replying to a part of a message (A9).
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * [quoteReplyAction] adds "Reply to part of text" to the message menu
//    (registered in message_actions_registrations.dart). It opens a sheet
//    with the message's text to select from; "Reply" then starts an ordinary
//    reply whose quote is that selection.
//  * The page reads the pick through [replyQuoteRequestProvider] when its
//    reply starts, keeps it with the reply and sends it in the reply preview
//    (`reply_preview.quote`). The server checks that the text is in the
//    message (migration 202610240500).
//  * Bubbles show the quote instead of the start of the message, and tapping
//    it jumps to the message ([MessageJumpScope]).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A pick waiting for the reply to start: the message and the part of its
/// text.
class ReplyQuoteRequest {
  const ReplyQuoteRequest({required this.messageId, required this.quote});

  final String messageId;
  final ReplyQuote quote;
}

/// Set by the menu entry just before it starts the reply; the page takes it
/// (and clears it) when the reply starts.
final replyQuoteRequestProvider =
    NotifierProvider<ReplyQuoteRequestNotifier, ReplyQuoteRequest?>(
      ReplyQuoteRequestNotifier.new,
    );

class ReplyQuoteRequestNotifier extends Notifier<ReplyQuoteRequest?> {
  @override
  ReplyQuoteRequest? build() => null;

  void request(ReplyQuoteRequest request) => state = request;

  void clear() {
    if (state != null) {
      state = null;
    }
  }
}

/// The quote for the selection [start]..[end] of [body]: trimmed of spaces
/// at both ends, cut at [ReplyQuote.maxLength] (never in the middle of a
/// character made of two UTF-16 units). Null when nothing but space is
/// selected.
ReplyQuote? quoteFromSelection(String body, int start, int end) {
  var from = start < end ? start : end;
  var to = start < end ? end : start;
  if (from < 0 || to > body.length || from == to) {
    return null;
  }
  while (from < to && _isSpace(body.codeUnitAt(from))) {
    from++;
  }
  while (to > from && _isSpace(body.codeUnitAt(to - 1))) {
    to--;
  }
  if (to - from > ReplyQuote.maxLength) {
    to = from + ReplyQuote.maxLength;
    // Do not end between the two halves of an emoji.
    if (to < body.length && _isHighSurrogate(body.codeUnitAt(to - 1))) {
      to--;
    }
  }
  if (from >= to) {
    return null;
  }
  return ReplyQuote(text: body.substring(from, to), start: from, end: to);
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0xA0;

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

/// "Reply to part of text" in the message menu, between Reply (100) and Copy
/// (200).
final quoteReplyAction = MessageActionContribution(
  id: 'quote-reply',
  order: 150,
  build: (ctx) => [
    if (ctx.canCompose &&
        !ctx.isRecalled &&
        !ctx.isPending &&
        ctx.message.type == MessageType.text &&
        ctx.message.body.trim().length > 1)
      MessageAction(
        key: const ValueKey('message-action-quote-reply'),
        icon: Icons.format_quote_rounded,
        label: tr('Reply to part of text'),
        onSelected: () => unawaited(_replyToPart(ctx)),
      ),
  ],
);

Future<void> _replyToPart(MessageActionContext ctx) async {
  final container = ctx.container;
  final message = ctx.message;
  final quote = await showQuotePicker(ctx.context, message);
  // Dismissed: nothing happens. "Reply" without a selection never gets here.
  if (quote == null) {
    return;
  }
  container
      .read(replyQuoteRequestProvider.notifier)
      .request(ReplyQuoteRequest(messageId: message.id, quote: quote));
  ctx.onReply(message);
}

/// Opens the text of [message] to select a part of; the quote picked, or
/// null when the sheet was dismissed.
Future<ReplyQuote?> showQuotePicker(BuildContext context, ChatMessage message) {
  return showWeCordSheet<ReplyQuote>(
    context,
    title: tr('Reply to part of text'),
    builder: (context, _) => QuotePickerView(body: message.body),
  );
}

/// The content of the quote sheet: the message's text, selectable, and a
/// Reply button that is on once something is selected.
class QuotePickerView extends StatefulWidget {
  const QuotePickerView({required this.body, super.key});

  final String body;

  @override
  State<QuotePickerView> createState() => _QuotePickerViewState();
}

class _QuotePickerViewState extends State<QuotePickerView> {
  ReplyQuote? _quote;

  void _selectionChanged(TextSelection selection, SelectionChangedCause? _) {
    final quote = selection.isValid && !selection.isCollapsed
        ? quoteFromSelection(widget.body, selection.start, selection.end)
        : null;
    if (quote?.text != _quote?.text || quote?.start != _quote?.start) {
      setState(() => _quote = quote);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                tr('Select the words you are answering.'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    widget.body,
                    key: const ValueKey('quote-picker-text'),
                    onSelectionChanged: _selectionChanged,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.45,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: WeCordButton(
                key: const ValueKey('quote-picker-reply'),
                label: tr('Reply'),
                onPressed: _quote == null
                    ? null
                    : () => Navigator.of(context).pop(_quote),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a quoted reply inside a bubble calls to show the message it came
/// from. Provided by the message list; null elsewhere (the quote then is
/// not tappable).
class MessageJumpScope extends InheritedWidget {
  const MessageJumpScope({
    required this.onJump,
    required super.child,
    super.key,
  });

  final Future<void> Function(String messageId) onJump;

  static Future<void> Function(String messageId)? maybeOf(
    BuildContext context,
  ) => context.getInheritedWidgetOfExactType<MessageJumpScope>()?.onJump;

  @override
  bool updateShouldNotify(MessageJumpScope oldWidget) => false;
}
