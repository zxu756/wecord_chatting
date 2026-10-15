import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/message.dart';

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  try {
    return SupabaseInboxRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const UninitializedInboxRepository();
  }
});

/// Why a message is in the inbox.
enum InboxReason {
  mention,

  /// An @all mention.
  mentionAll,

  /// A mention of a role the user has.
  mentionRole,

  /// `@here` while the user was online.
  mentionHere,
  reply;

  factory InboxReason.fromJson(String value) {
    return switch (value) {
      'mention' => InboxReason.mention,
      'mention_all' => InboxReason.mentionAll,
      'mention_role' => InboxReason.mentionRole,
      'mention_here' => InboxReason.mentionHere,
      'reply' => InboxReason.reply,
      _ => throw ArgumentError.value(value, 'value', 'Unknown inbox reason'),
    };
  }
}

/// A recent message that mentions the current user or replies to them.
class InboxItem {
  const InboxItem({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.reason,
    required this.isUnread,
    this.senderAvatarUrl,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    final webhookName = json['webhook_name'] as String?;
    return InboxItem(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: webhookName ?? json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: webhookName == null
          ? json['sender_avatar_url'] as String?
          : null,
      body: json['body'] as String? ?? '',
      type: MessageType.fromJson(json['type'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      reason: InboxReason.fromJson(json['reason'] as String),
      isUnread: json['is_unread'] as bool? ?? false,
    );
  }

  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String body;
  final MessageType type;
  final DateTime createdAt;
  final InboxReason reason;

  /// Sent after the user last read the conversation.
  final bool isUnread;
}

abstract interface class InboxRepository {
  /// Mentions of and replies to the current user from the last 30 days,
  /// newest first.
  Future<List<InboxItem>> listInbox({int limit = 50});
}

class SupabaseInboxRepository implements InboxRepository {
  const SupabaseInboxRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<InboxItem>> listInbox({int limit = 50}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_inbox',
      params: {'p_limit': limit},
    );
    return [
      for (final row in rows) InboxItem.fromJson(row as Map<String, dynamic>),
    ];
  }
}

class UninitializedInboxRepository implements InboxRepository {
  const UninitializedInboxRepository();

  @override
  Future<List<InboxItem>> listInbox({int limit = 50}) async => const [];
}
