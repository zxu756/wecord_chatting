import 'package:wecord/shared/models/message.dart';

/// How many messages a chat loads at a time.
const messagePageSize = 50;

/// A position in a conversation's history: messages are ordered by
/// `created_at`, then by id (two messages may share a time).
class MessageCursor implements Comparable<MessageCursor> {
  const MessageCursor(this.createdAt, this.id, {this.timestamp});

  factory MessageCursor.of(ChatMessage message, {String? timestamp}) {
    return MessageCursor(message.createdAt, message.id, timestamp: timestamp);
  }

  final DateTime createdAt;
  final String id;

  /// `created_at` as the server sent it. Queries use it, since a
  /// [DateTime] on the web keeps only milliseconds and the server keeps
  /// microseconds.
  final String? timestamp;

  /// The time to compare with in queries.
  String get queryTimestamp => timestamp ?? createdAt.toUtc().toIso8601String();

  @override
  int compareTo(MessageCursor other) {
    final byTime = createdAt.compareTo(other.createdAt);
    return byTime != 0 ? byTime : id.compareTo(other.id);
  }

  bool isBefore(MessageCursor other) => compareTo(other) < 0;

  bool isAfter(MessageCursor other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) {
    return other is MessageCursor &&
        other.createdAt == createdAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(createdAt, id);

  @override
  String toString() => 'MessageCursor($createdAt, $id)';
}

/// Orders messages oldest first, as [MessageCursor] does.
int compareMessages(ChatMessage left, ChatMessage right) {
  final byTime = left.createdAt.compareTo(right.createdAt);
  return byTime != 0 ? byTime : left.id.compareTo(right.id);
}

/// What changed in a conversation, from realtime.
enum ThreadEventKind {
  messageInserted,
  messageUpdated,
  messageDeleted,
  reactionsChanged,
  pollVotesChanged,
  pinsChanged,
  membersChanged,
  threadsChanged,

  /// The realtime channel joined again after it dropped: changes made in
  /// between were missed.
  resubscribed,
}

class ThreadEvent {
  const ThreadEvent(this.kind, {this.messageId, this.clientId});

  final ThreadEventKind kind;

  /// The message the change is about, when the event says.
  final String? messageId;

  /// For inserted messages, the id the sender's app gave them.
  final String? clientId;

  @override
  String toString() => 'ThreadEvent($kind, $messageId)';
}

/// Loads a conversation's history in pages, and the changes to it, as raw
/// rows (cached as they are) with their reactions.
abstract interface class MessageHistorySource {
  /// Up to [limit] message rows, oldest first: the newest ones when
  /// neither cursor is given, else the ones just [before] or just [after]
  /// the cursor.
  Future<List<Map<String, dynamic>>> fetchMessageRows(
    String conversationId, {
    MessageCursor? before,
    MessageCursor? after,
    int limit = messagePageSize,
  });

  /// The rows of [messageIds] that still exist, oldest first.
  Future<List<Map<String, dynamic>>> fetchMessageRowsByIds(
    String conversationId,
    List<String> messageIds,
  );

  /// The reactions of [messageIds] (`reactions` as the rows carry them);
  /// messages without any are left out.
  Future<Map<String, List<dynamic>>> fetchReactions(
    String conversationId,
    List<String> messageIds,
  );

  /// Reads a message row as the app shows it.
  ChatMessage messageFromRow(Map<String, dynamic> row);

  Stream<ThreadEvent> threadEvents(String conversationId);
}

/// The conversation list as raw rows, for the offline cache.
abstract interface class ConversationRowsSource {
  Future<List<Map<String, dynamic>>> listConversationRows();
}

/// Sends a text message from the outbox. [clientId] makes the send safe to
/// repeat: the server stores one message per sender and client id.
abstract interface class OutboxMessageSender {
  /// Returns the stored message's id, or null when AutoMod dropped it
  /// quietly (it then throws [AutoModBlockedException] with the reason
  /// when it left one).
  Future<String?> sendQueuedTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions,
  });
}
