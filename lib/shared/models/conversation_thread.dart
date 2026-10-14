import 'package:wecord/shared/l10n/l10n.dart';

/// A thread: a side conversation (its own conversation, type `thread`)
/// branching off a channel or group, usually from a root message.
class ConversationThread {
  const ConversationThread({
    required this.id,
    required this.conversationId,
    required this.parentConversationId,
    required this.title,
    required this.createdAt,
    this.rootMessageId,
    this.createdBy,
    this.archivedAt,
    this.lastMessageAt,
    this.replyCount = 0,
    this.unreadCount = 0,
    this.canManage = false,
  });

  factory ConversationThread.fromJson(Map<String, dynamic> json) {
    return ConversationThread(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      parentConversationId: json['parent_conversation_id'] as String,
      rootMessageId: json['root_message_id'] as String?,
      title: json['title'] as String? ?? tr('Thread'),
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      archivedAt: _parseOptionalTimestamp(json['archived_at']),
      lastMessageAt: _parseOptionalTimestamp(json['last_message_at']),
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      canManage: json['can_manage'] == true,
    );
  }

  /// Longest thread title the server accepts.
  static const maxTitleLength = 100;

  /// Root text shortened to this many characters suggests the title.
  static const suggestedTitleLength = 40;

  final String id;
  final String conversationId;
  final String parentConversationId;
  final String? rootMessageId;
  final String title;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? archivedAt;
  final DateTime? lastMessageAt;
  final int replyCount;
  final int unreadCount;

  /// The current user may archive and unarchive it.
  final bool canManage;

  bool get isArchived => archivedAt != null;
}

/// The thread hanging off a root message, as `messages.thread_summary`
/// reports it.
class MessageThreadSummary {
  const MessageThreadSummary({
    required this.threadId,
    required this.conversationId,
    required this.title,
    this.replyCount = 0,
    this.lastReplyAt,
    this.unreadCount = 0,
    this.archivedAt,
  });

  static MessageThreadSummary? maybeFromJson(Object? json) {
    if (json is! Map ||
        json['thread_id'] is! String ||
        json['conversation_id'] is! String) {
      return null;
    }
    return MessageThreadSummary(
      threadId: json['thread_id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? tr('Thread'),
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      lastReplyAt: _parseOptionalTimestamp(json['last_reply_at']),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      archivedAt: _parseOptionalTimestamp(json['archived_at']),
    );
  }

  final String threadId;
  final String conversationId;
  final String title;
  final int replyCount;
  final DateTime? lastReplyAt;
  final int unreadCount;
  final DateTime? archivedAt;
}

/// What it takes to open a thread: its conversation and title.
class ThreadTarget {
  const ThreadTarget({
    required this.conversationId,
    required this.title,
    this.threadId,
  });

  final String conversationId;
  final String title;
  final String? threadId;
}

/// A title suggested from the root message text: whitespace collapsed and
/// cut at [ConversationThread.suggestedTitleLength] characters.
String suggestedThreadTitle(String text) {
  final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final characters = collapsed.runes.toList();
  if (characters.length <= ConversationThread.suggestedTitleLength) {
    return collapsed;
  }
  return '${String.fromCharCodes(characters.take(ConversationThread.suggestedTitleLength)).trimRight()}…';
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
