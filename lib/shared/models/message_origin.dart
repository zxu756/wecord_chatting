/// Where a message published from an announcement channel came from: the
/// copy in a following channel links back to it.
class MessageCrosspost {
  const MessageCrosspost({
    required this.sourceMessageId,
    required this.sourceConversationId,
    required this.sourceChannelId,
    required this.sourceCircleId,
    required this.circleName,
    required this.channelName,
    required this.authorName,
    this.authorId,
  });

  /// Null for anything that is not a crosspost object.
  static MessageCrosspost? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final messageId = json['source_message_id'];
    final channelId = json['source_channel_id'];
    final circleId = json['source_circle_id'];
    if (messageId is! String || channelId is! String || circleId is! String) {
      return null;
    }
    return MessageCrosspost(
      sourceMessageId: messageId,
      sourceConversationId: json['source_conversation_id'] as String? ?? '',
      sourceChannelId: channelId,
      sourceCircleId: circleId,
      circleName: json['circle_name'] as String? ?? '',
      channelName: json['channel_name'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      authorId: json['author_id'] as String?,
    );
  }

  final String sourceMessageId;
  final String sourceConversationId;
  final String sourceChannelId;
  final String sourceCircleId;
  final String circleName;
  final String channelName;

  /// Who wrote the original (a member's circle name, or a webhook's).
  final String authorName;

  /// The original's author; null when a webhook posted it.
  final String? authorId;
}
