import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';

// The server's call notices: "Ada started a call." while it runs, then
// "Ada started a call that lasted 5 minutes." once it ends.
final _callStarted = RegExp(r'^(.+) started a call\.$');
final _callEnded = RegExp(r' started a call that lasted .+\.$');

/// One line about [conversation]'s latest message for conversation lists:
/// plain text without markdown, a label for images, GIFs, voice messages,
/// files, polls, stickers and calls, and "You: …" for the user's own messages.
/// Null when the conversation has no messages yet.
String? conversationPreviewText(
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
    return tr('Message deleted');
  }
  final text = switch (type ?? MessageType.text) {
    MessageType.text when gifUrlIn(body) != null => tr('[GIF]'),
    MessageType.text => plainTextFromMarkdown(body),
    MessageType.image => tr('[Image]'),
    MessageType.voice => tr('[Voice]'),
    MessageType.file => tr('[File]'),
    MessageType.poll => pollPreviewText(body),
    MessageType.sticker => stickerPreviewText(body),
    MessageType.system => _systemPreview(body),
  };
  final own =
      currentUserId != null &&
      type != MessageType.system &&
      conversation.lastMessageWebhookName == null &&
      conversation.lastMessageSenderId == currentUserId;
  return own ? tr('You: {message}', {'message': text}) : text;
}

String _systemPreview(String body) {
  if (_callEnded.hasMatch(body)) {
    return tr('Call ended');
  }
  if (_callStarted.firstMatch(body) case final match?) {
    return tr('{name} started a call', {'name': match.group(1)});
  }
  return body;
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
