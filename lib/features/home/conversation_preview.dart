import 'package:flutter/material.dart';
import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/chats/media_send/album_label.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/spoken.dart';

// The server's call notices: "Ada started a call." while it runs, then
// "Ada started a call that lasted 5 minutes." once it ends.
final _callStarted = RegExp(r'^(.+) started a call\.$');
final _callEnded = RegExp(r' started a call that lasted .+\.$');

/// One line about a conversation's latest message: its [text], and an
/// [icon] for photos, GIFs, voice messages, videos, files and calls.
typedef ConversationPreview = ({IconData? icon, String text});

/// One line about [conversation]'s latest message for conversation lists:
/// plain text without markdown, a small icon and a label for images, GIFs,
/// voice messages, files and calls, a label for polls and stickers, and
/// "You: …" for the user's own messages. Null when the conversation has no
/// messages yet.
ConversationPreview? conversationPreview(
  ConversationSummary conversation, {
  String? currentUserId,
}) {
  final body = conversation.lastMessageBody?.trim() ?? '';
  final type = conversation.lastMessageType;
  if (body.isEmpty && (type == null || type == MessageType.text)) {
    return null;
  }
  // The server sends this for recalled messages, whatever their type.
  if (body == 'Message deleted') {
    return (icon: null, text: tr('Message deleted'));
  }
  final album = conversation.lastMessageAlbum;
  final (IconData? icon, String text) = switch (type ?? MessageType.text) {
    // Pictures, videos and files sent together read as one message.
    MessageType.image || MessageType.file when album != null => (
      album.images + album.videos > 0
          ? Icons.photo_library_outlined
          : Icons.attach_file_rounded,
      conversationAlbumLabel(album),
    ),
    MessageType.text when gifUrlIn(body) != null => (
      Icons.gif_box_outlined,
      tr('GIF'),
    ),
    MessageType.text => (null, plainTextFromMarkdown(body)),
    MessageType.image => (Icons.image_outlined, tr('Image')),
    MessageType.voice => (Icons.mic_none_rounded, tr('Voice message')),
    MessageType.file when conversation.lastMessageIsVideo => (
      Icons.videocam_outlined,
      tr('Video'),
    ),
    MessageType.file => (Icons.attach_file_rounded, tr('File')),
    MessageType.poll => (null, pollPreviewText(body)),
    MessageType.sticker => (null, stickerPreviewText(body)),
    MessageType.system => _systemPreview(body),
  };
  final own =
      currentUserId != null &&
      type != MessageType.system &&
      conversation.lastMessageWebhookName == null &&
      conversation.lastMessageSenderId == currentUserId;
  return (
    icon: icon,
    text: own ? tr('You: {message}', {'message': text}) : text,
  );
}

/// The text of [conversationPreview] alone.
String? conversationPreviewText(
  ConversationSummary conversation, {
  String? currentUserId,
}) => conversationPreview(conversation, currentUserId: currentUserId)?.text;

(IconData?, String) _systemPreview(String body) {
  if (_callEnded.hasMatch(body)) {
    return (Icons.call_outlined, tr('Call ended'));
  }
  if (_callStarted.firstMatch(body) case final match?) {
    return (
      Icons.call_outlined,
      tr('{name} started a call', {'name': match.group(1)}),
    );
  }
  return (null, body);
}

/// How long ago [time] was, as briefly as a conversation list shows it:
/// "now", "5m", "3h", "9d", "1mo", "2y".
String compactAge(DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) {
    return tr('now');
  }
  if (elapsed.inHours < 1) {
    return tr('{count}m', {'count': elapsed.inMinutes});
  }
  if (elapsed.inDays < 1) {
    return tr('{count}h', {'count': elapsed.inHours});
  }
  if (elapsed.inDays < 30) {
    return tr('{count}d', {'count': elapsed.inDays});
  }
  if (elapsed.inDays < 365) {
    return tr('{count}mo', {'count': elapsed.inDays ~/ 30});
  }
  return tr('{count}y', {'count': elapsed.inDays ~/ 365});
}

/// What a screen reader says about a conversation row, in one go: the
/// name, who is online (direct messages), unread count, pinned and muted
/// markers, when the last message came and what it says (or the unsent
/// draft).
String conversationRowLabel(
  ConversationSummary conversation, {
  required String title,
  required String? preview,
  PresenceStatus? presence,
  String? draft,
  DateTime? now,
}) {
  final unreadCount = conversation.unreadCount;
  final lastMessageAt = conversation.lastMessageAt;
  final isDirect =
      conversation.type == ConversationType.direct &&
      !conversation.isNoteToSelf;
  return spokenList([
    title,
    if (isDirect)
      presence == null || presence == PresenceStatus.invisible
          ? tr('Offline')
          : presence.label,
    if (unreadCount > 0)
      tr('{count} unread', {'count': unreadCount})
    else if (conversation.isMarkedUnread)
      tr('Unread'),
    if (conversation.pinnedAt != null) tr('Pinned'),
    if (conversation.isMuted) tr('Muted'),
    if (lastMessageAt != null) spokenAge(lastMessageAt, now: now),
    if (draft != null && draft.trim().isNotEmpty)
      '${tr('Draft')}: ${draft.trim()}'
    else if (preview != null && preview.trim().isNotEmpty)
      preview.trim(),
  ]);
}
