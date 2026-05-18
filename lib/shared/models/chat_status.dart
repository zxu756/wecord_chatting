class ConversationActivity {
  const ConversationActivity({
    this.onlineUserIds = const {},
    this.typingUserIds = const {},
  });

  final Set<String> onlineUserIds;
  final Set<String> typingUserIds;

  ConversationActivity copyWith({
    Set<String>? onlineUserIds,
    Set<String>? typingUserIds,
  }) {
    return ConversationActivity(
      onlineUserIds: onlineUserIds ?? this.onlineUserIds,
      typingUserIds: typingUserIds ?? this.typingUserIds,
    );
  }
}

class ConversationReadMarker {
  const ConversationReadMarker({
    required this.userId,
    required this.lastReadMessageId,
  });

  factory ConversationReadMarker.fromJson(Map<String, dynamic> json) {
    return ConversationReadMarker(
      userId: json['user_id'] as String,
      lastReadMessageId: json['last_read_message_id'] as String?,
    );
  }

  final String userId;
  final String? lastReadMessageId;
}
