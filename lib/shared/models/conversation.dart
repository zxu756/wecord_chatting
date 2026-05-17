const _sentinel = Object();

enum ConversationType {
  direct,
  group,
  channel;

  factory ConversationType.fromJson(String value) {
    return switch (value) {
      'direct' => ConversationType.direct,
      'group' => ConversationType.group,
      'channel' => ConversationType.channel,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unknown conversation type',
      ),
    };
  }

  String toJson() {
    return switch (this) {
      ConversationType.direct => 'direct',
      ConversationType.group => 'group',
      ConversationType.channel => 'channel',
    };
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.type,
    required this.unreadCount,
    this.title,
    this.avatarUrl,
    this.lastMessageBody,
    this.lastMessageAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      type: ConversationType.fromJson(json['type'] as String),
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      lastMessageBody: json['last_message_body'] as String?,
      lastMessageAt: _parseOptionalTimestamp(json['last_message_at']),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  final int unreadCount;

  Map<String, dynamic> toJson() {
    return {'type': type.toJson(), 'title': title, 'avatar_url': avatarUrl};
  }

  ConversationSummary copyWith({
    String? id,
    ConversationType? type,
    Object? title = _sentinel,
    Object? avatarUrl = _sentinel,
    Object? lastMessageBody = _sentinel,
    Object? lastMessageAt = _sentinel,
    int? unreadCount,
  }) {
    return ConversationSummary(
      id: id ?? this.id,
      type: type ?? this.type,
      title: identical(title, _sentinel) ? this.title : title as String?,
      avatarUrl: identical(avatarUrl, _sentinel)
          ? this.avatarUrl
          : avatarUrl as String?,
      lastMessageBody: identical(lastMessageBody, _sentinel)
          ? this.lastMessageBody
          : lastMessageBody as String?,
      lastMessageAt: identical(lastMessageAt, _sentinel)
          ? this.lastMessageAt
          : lastMessageAt as DateTime?,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
