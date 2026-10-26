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

/// A bot's answer to a slash command: who used which command.
class MessageInteraction {
  const MessageInteraction({
    required this.command,
    required this.userName,
    this.userId,
    this.componentLabel,
  });

  /// Null for anything that is not an interaction object.
  static MessageInteraction? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final command = json['command'];
    final label = json['component_label'];
    final hasCommand = command is String && command.isNotEmpty;
    final hasLabel = label is String && label.isNotEmpty;
    if (!hasCommand && !hasLabel) {
      return null;
    }
    return MessageInteraction(
      command: hasCommand ? command : '',
      componentLabel: hasLabel ? label : null,
      userName: json['user_name'] as String? ?? '',
      userId: json['user_id'] as String?,
    );
  }

  /// The slash command used; empty for the answer to a press on a component.
  final String command;

  /// The button (or list) pressed, for the answer to a press on a component.
  final String? componentLabel;
  final String userName;
  final String? userId;
}

/// What kind of answer the WeCord AI assistant gave.
enum AiReplyKind {
  answer,
  summary,
  translation,
  rewrite,
  todos;

  static AiReplyKind fromJson(Object? value) {
    for (final kind in values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return AiReplyKind.answer;
  }
}

/// The mark on an answer from the WeCord AI assistant (messages.ai_reply):
/// who asked, what kind of answer it is, and for a to-do list the items it
/// found (as the `ai` function wrote them; the app reads them with
/// ExtractedAction.fromJson).
class MessageAiReply {
  const MessageAiReply({
    required this.kind,
    this.requesterId,
    this.requesterName = '',
    this.items = const [],
  });

  /// Null for anything that is not an ai_reply object.
  static MessageAiReply? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final rawItems = json['items'];
    return MessageAiReply(
      kind: AiReplyKind.fromJson(json['kind']),
      requesterId: json['requester_id'] as String?,
      requesterName: json['requester_name'] as String? ?? '',
      items: [
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map) Map<String, dynamic>.from(item),
      ],
    );
  }

  final AiReplyKind kind;
  final String? requesterId;
  final String requesterName;
  final List<Map<String, dynamic>> items;
}
