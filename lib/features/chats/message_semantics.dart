import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/video_note/video_note_bubble.dart'
    show videoNoteLength;
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/moments/moment_card_view.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/ui/ui.dart';
import 'package:wecord/shared/ui/spoken.dart';

/// What a screen reader says for a picture in a message: a readable file
/// name when there is one, otherwise "Image from {sender}".
String messageImageDescription(String path, String senderName, {String? alt}) {
  // What the sender wrote about the picture beats a guess from its name.
  if (alt != null && alt.trim().isNotEmpty) {
    return tr('Image: {name}', {'name': _oneLine(alt)});
  }
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final readable = stem.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  // Generated names (uuids, hashes, camera counters) say nothing.
  final letters = RegExp(r'[A-Za-zÀ-ɏ一-鿿]').allMatches(readable);
  final looksGenerated =
      RegExp(r'^[0-9a-fA-F ]{12,}$').hasMatch(readable) ||
      RegExp(
        r'^(IMG|DSC|PXL|image|photo|file)?\s*\d+$',
        caseSensitive: false,
      ).hasMatch(readable) ||
      letters.length < 3;
  if (looksGenerated) {
    return tr('Image from {name}', {'name': senderName});
  }
  return tr('Image: {name}', {'name': readable});
}

String _oneLine(String text) =>
    text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

/// A message's content in words: its text, or what it holds ("Voice
/// message", "File: plan.pdf", "Poll: …").
String messageSpokenContent(ChatMessage message, {required String senderName}) {
  if (message.recalledAt != null) {
    return message.deletedLabel;
  }
  if (message.isViewOnce) {
    // Not the file's name, which would give the picture away.
    return message.type == MessageType.image
        ? tr('View-once photo')
        : tr('View-once video');
  }
  final body = message.body.trim();
  final text = switch (message.type) {
    MessageType.text when gifUrlIn(body) != null => tr('GIF'),
    MessageType.text when message.chatHistoryCard != null =>
      message.chatHistoryCard!.heading,
    MessageType.text when message.contactCard != null =>
      message.contactCard!.heading,
    MessageType.text when message.momentCardPostId != null => tr('Moment'),
    MessageType.text when message.storyRef != null => tr(
      'Reply to a daily: {text}',
      {'text': _oneLine(plainTextFromMarkdown(body))},
    ),
    MessageType.text => _oneLine(plainTextFromMarkdown(body)),
    MessageType.image => [
      messageImageDescription(
        message.imageAttachment?.path ?? '',
        senderName,
        alt: message.imageAttachment?.alt,
      ),
      if (body.isNotEmpty) plainTextFromMarkdown(body),
    ].join(', '),
    MessageType.file when message.isVideoNote => [
      (message.fileAttachment?.videoNoteMs ?? 0) > 0
          ? tr('Video message, {time}', {
              'time': videoNoteLength(message.fileAttachment!.videoNoteMs!),
            })
          : tr('Video message'),
      if (body.isNotEmpty) plainTextFromMarkdown(body),
    ].join(', '),
    MessageType.file => [
      tr('File: {name}', {'name': message.fileAttachment?.name ?? tr('File')}),
      if (body.isNotEmpty) plainTextFromMarkdown(body),
    ].join(', '),
    MessageType.voice => tr('Voice message'),
    MessageType.poll => pollPreviewText(body),
    MessageType.sticker => stickerPreviewText(body),
    MessageType.system => body,
  };
  final album = message.album;
  final attachments = album != null && album.length > 1
      ? tr('{count} attachments', {'count': album.length})
      : null;
  final reply = message.replyPreview;
  return spokenList([
    if (reply != null) tr('Reply to {name}', {'name': reply.senderName}),
    text,
    attachments,
    if (message.editedAt != null) tr('edited'),
  ]);
}

/// A message read as one sentence: "{sender}, {time}: {content}, {n}
/// reactions". [content] left out gives only the header, for messages whose
/// pieces (a voice player, a poll) read themselves.
String messageSpokenSummary(
  ChatMessage message, {
  required String senderName,
  bool includeContent = true,
  bool pending = false,
}) {
  final header = spokenList([
    senderName,
    spokenClock(message.createdAt),
    if (pending) tr('Sending'),
    if (message.isPinned) tr('Pinned'),
  ]);
  final reactionCount = message.recalledAt != null
      ? 0
      : message.reactions.fold<int>(0, (sum, r) => sum + r.count);
  final content = includeContent
      ? messageSpokenContent(message, senderName: senderName)
      : '';
  final reactions = reactionCount == 0
      ? null
      : reactionCount == 1
      ? tr('1 reaction')
      : tr('{count} reactions', {'count': reactionCount});
  final thread = message.threadSummary;
  return spokenList([
    content.isEmpty ? header : '$header: $content',
    reactions,
    if (thread != null && thread.replyCount > 0)
      thread.replyCount == 1
          ? tr('1 reply in thread')
          : tr('{count} replies in thread', {'count': thread.replyCount}),
  ]);
}

/// Something a screen reader (or the keyboard) can do with a message.
class MessageSemanticAction {
  const MessageSemanticAction(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

class _OpenMessageMenuIntent extends Intent {
  const _OpenMessageMenuIntent();
}

/// Makes a message one stop for screen readers and the keyboard.
///
/// * It reads as [label] ("Ada, 9:20: see you at 6, 2 reactions"); with
///   [readAsOneNode] the pieces inside are skipped and [actions] (reply,
///   react, copy…) are offered as the screen reader's actions instead, so
///   the message is a single swipe. Without it, [label] is a header and the
///   controls inside (a voice player, poll options, reaction chips) stay
///   separate stops.
/// * It takes keyboard focus (a ring shows it), and the context menu key or
///   Shift+F10 — or Enter on the message itself — opens its menu through
///   [onOpenMenu], with the message's rectangle on screen.
class MessageFrame extends StatefulWidget {
  const MessageFrame({
    required this.label,
    required this.actions,
    required this.onOpenMenu,
    required this.child,
    this.readAsOneNode = true,
    this.enabled = true,
    super.key,
  });

  final String label;
  final List<MessageSemanticAction> actions;
  final ValueChanged<Rect> onOpenMenu;
  final bool readAsOneNode;

  /// False for messages with no menu (still sending, deleted).
  final bool enabled;
  final Widget child;

  @override
  State<MessageFrame> createState() => _MessageFrameState();
}

class _MessageFrameState extends State<MessageFrame> {
  final _focus = FocusNode(debugLabel: 'message');
  var _showRing = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _openMenu() {
    if (!widget.enabled || !mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    widget.onOpenMenu(box.localToGlobal(Offset.zero) & box.size);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Enter on the message itself (not on a link or button inside it).
    if (event is KeyDownEvent &&
        _focus.hasPrimaryFocus &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      _openMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget result = widget.child;
    if (_showRing) {
      result = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WeCordRadii.md),
          border: Border.all(color: c.accent, width: 2),
        ),
        child: result,
      );
    }
    if (widget.enabled) {
      result = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: FocusableActionDetector(
          focusNode: _focus,
          onShowFocusHighlight: (value) => setState(() => _showRing = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.contextMenu):
                _OpenMessageMenuIntent(),
            SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _OpenMessageMenuIntent(),
          },
          actions: {
            _OpenMessageMenuIntent: CallbackAction<_OpenMessageMenuIntent>(
              onInvoke: (_) {
                _openMenu();
                return null;
              },
            ),
          },
          child: result,
        ),
      );
    }
    return Semantics(
      container: true,
      label: widget.label,
      excludeSemantics: widget.readAsOneNode,
      onLongPress: widget.enabled ? _openMenu : null,
      customSemanticsActions: widget.enabled
          ? {
              for (final action in widget.actions)
                CustomSemanticsAction(label: action.label): action.onSelected,
            }
          : null,
      child: result,
    );
  }
}
