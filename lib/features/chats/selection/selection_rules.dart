import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/shared/models/message.dart';

/// What the selection bar may do with a set of messages. The server
/// decides in the end (it refuses what forward_message, recall_message and
/// save_message refuse); these rules keep the bar from offering what would
/// fail.

/// Whether [message] can go into a forward, one by one or merged: not
/// deleted, expired or waiting for review, not a poll, sticker or system
/// line, and not view-once media.
bool canForwardMessage(ChatMessage message, {DateTime? now}) {
  if (message.recalledAt != null ||
      message.reviewState != null ||
      message.isViewOnce ||
      isPendingMessageId(message.id)) {
    return false;
  }
  final expiresAt = message.expiresAt;
  if (expiresAt != null && !expiresAt.isAfter(now ?? DateTime.now())) {
    return false;
  }
  return switch (message.type) {
    MessageType.system || MessageType.poll || MessageType.sticker => false,
    _ => true,
  };
}

/// Whether [message] can be saved for later.
bool canSaveMessage(ChatMessage message) {
  return message.recalledAt == null &&
      message.type != MessageType.system &&
      !isPendingMessageId(message.id);
}

/// The text of [message] a copy takes: its words, or null for messages
/// that are not text (pictures, files, voice messages, cards).
String? copyTextOf(ChatMessage message) {
  if (message.type != MessageType.text || message.recalledAt != null) {
    return null;
  }
  final attachment = message.attachment;
  if (attachment != null && attachment['kind'] is String) {
    // Note, task, list, chat history and contact cards.
    return null;
  }
  final body = message.body.trim();
  if (body.isEmpty) {
    return null;
  }
  return body;
}

/// What copying [messages] (oldest first) puts on the clipboard: the
/// text of one message as it is (like the message menu's Copy); the text of
/// several as "Name: text" lines. Null when none of them is text.
String? copyTextOfSelection(
  List<ChatMessage> messages, {
  required String Function(ChatMessage message) nameOf,
}) {
  final lines = <String>[];
  for (final message in messages) {
    final text = copyTextOf(message);
    if (text != null) {
      lines.add(text);
    }
  }
  if (lines.isEmpty) {
    return null;
  }
  if (messages.length == 1) {
    return lines.single;
  }
  return [
    for (final message in messages)
      if (copyTextOf(message) case final text?) '${nameOf(message)}: $text',
  ].join('\n');
}

/// Whether every message in [messages] can be deleted by the current user:
/// their own, or any when [canModerate] says they moderate the chat (the
/// same rule as the message menu's Delete).
bool canDeleteSelection(
  List<ChatMessage> messages, {
  required String? currentUserId,
  required bool Function(ChatMessage message) canModerate,
}) {
  if (messages.isEmpty) {
    return false;
  }
  return messages.every(
    (message) =>
        message.recalledAt == null &&
        message.type != MessageType.system &&
        !isPendingMessageId(message.id) &&
        (message.isSentBy(currentUserId) || canModerate(message)),
  );
}
