const _sentinel = Object();

enum MessageType {
  text,
  image,
  file,
  voice;

  factory MessageType.fromJson(String value) {
    return switch (value) {
      'text' => MessageType.text,
      'image' => MessageType.image,
      'file' => MessageType.file,
      'voice' => MessageType.voice,
      _ => throw ArgumentError.value(value, 'value', 'Unknown message type'),
    };
  }

  String toJson() {
    return switch (this) {
      MessageType.text => 'text',
      MessageType.image => 'image',
      MessageType.file => 'file',
      MessageType.voice => 'voice',
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.body,
    required this.createdAt,
    this.attachment,
    this.replyToMessageId,
    this.replyPreview,
    this.forwardPreview,
    this.editedAt,
    this.recalledAt,
    this.mentions = const <MessageMention>[],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      type: MessageType.fromJson(json['type'] as String),
      body: json['body'] as String,
      attachment: json['attachment'] as Map<String, dynamic>?,
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyPreview: json['reply_preview'] == null
          ? null
          : ReplyPreview.fromJson(
              json['reply_preview'] as Map<String, dynamic>,
            ),
      forwardPreview: json['forwarded_from'] == null
          ? null
          : ForwardPreview.fromJson(
              json['forwarded_from'] as Map<String, dynamic>,
            ),
      createdAt: _parseTimestamp(json['created_at']),
      editedAt: _parseOptionalTimestamp(json['edited_at']),
      recalledAt: _parseOptionalTimestamp(json['recalled_at']),
      mentions: _parseMentions(json['mentions']),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String body;
  final Map<String, dynamic>? attachment;
  final String? replyToMessageId;
  final ReplyPreview? replyPreview;
  final ForwardPreview? forwardPreview;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? recalledAt;
  final List<MessageMention> mentions;

  ImageAttachment? get imageAttachment {
    final value = attachment;
    if (type != MessageType.image || value == null) {
      return null;
    }
    return ImageAttachment.fromJson(value);
  }

  VoiceAttachment? get voiceAttachment {
    final value = attachment;
    if (type != MessageType.voice || value == null) {
      return null;
    }
    return VoiceAttachment.fromJson(value);
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'type': type.toJson(),
      'body': body,
      'attachment': attachment,
      'reply_to_message_id': replyToMessageId,
      'reply_preview': replyPreview?.toJson(),
      if (forwardPreview != null) 'forwarded_from': forwardPreview?.toJson(),
      if (mentions.isNotEmpty)
        'mentions': mentions.map((mention) => mention.toJson()).toList(),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageType? type,
    String? body,
    Object? attachment = _sentinel,
    Object? replyToMessageId = _sentinel,
    Object? replyPreview = _sentinel,
    Object? forwardPreview = _sentinel,
    DateTime? createdAt,
    Object? editedAt = _sentinel,
    Object? recalledAt = _sentinel,
    List<MessageMention>? mentions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      body: body ?? this.body,
      attachment: identical(attachment, _sentinel)
          ? this.attachment
          : attachment as Map<String, dynamic>?,
      replyToMessageId: identical(replyToMessageId, _sentinel)
          ? this.replyToMessageId
          : replyToMessageId as String?,
      replyPreview: identical(replyPreview, _sentinel)
          ? this.replyPreview
          : replyPreview as ReplyPreview?,
      forwardPreview: identical(forwardPreview, _sentinel)
          ? this.forwardPreview
          : forwardPreview as ForwardPreview?,
      createdAt: createdAt ?? this.createdAt,
      editedAt: identical(editedAt, _sentinel)
          ? this.editedAt
          : editedAt as DateTime?,
      recalledAt: identical(recalledAt, _sentinel)
          ? this.recalledAt
          : recalledAt as DateTime?,
      mentions: mentions ?? this.mentions,
    );
  }
}

class MessageMention {
  const MessageMention({
    required this.userId,
    required this.displayName,
    required this.start,
    required this.end,
    this.kind = 'user',
  });

  factory MessageMention.fromJson(Map<String, dynamic> json) {
    return MessageMention(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? 'user',
    );
  }

  final String userId;
  final String displayName;
  final int start;
  final int end;
  final String kind;

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'start': start,
      'end': end,
      'kind': kind,
    };
  }
}

class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.body,
    required this.type,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> json) {
    return ReplyPreview(
      messageId: json['message_id'] as String,
      senderName: json['sender_name'] as String,
      body: json['body'] as String,
      type: MessageType.fromJson(json['type'] as String),
    );
  }

  final String messageId;
  final String senderName;
  final String body;
  final MessageType type;

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_name': senderName,
      'body': body,
      'type': type.toJson(),
    };
  }
}

class ForwardPreview {
  const ForwardPreview({
    required this.messageId,
    required this.senderName,
    required this.type,
    required this.body,
  });

  factory ForwardPreview.fromJson(Map<String, dynamic> json) {
    return ForwardPreview(
      messageId: json['message_id'] as String,
      senderName: json['sender_name'] as String,
      type: MessageType.fromJson(json['type'] as String),
      body: json['body'] as String,
    );
  }

  final String messageId;
  final String senderName;
  final MessageType type;
  final String body;

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_name': senderName,
      'type': type.toJson(),
      'body': body,
    };
  }
}

class ImageAttachment {
  const ImageAttachment({
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
  });

  factory ImageAttachment.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'image') {
      throw ArgumentError.value(json['kind'], 'kind', 'Expected image');
    }
    return ImageAttachment(
      bucket: json['bucket'] as String,
      path: json['path'] as String,
      mimeType: json['mime_type'] as String,
      size: json['size'] as int,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  final String bucket;
  final String path;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() {
    return {
      'kind': 'image',
      'bucket': bucket,
      'path': path,
      'mime_type': mimeType,
      'size': size,
      'width': width,
      'height': height,
    };
  }
}

class VoiceAttachment {
  const VoiceAttachment({
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.size,
    required this.durationMs,
  });

  factory VoiceAttachment.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'voice') {
      throw ArgumentError.value(json['kind'], 'kind', 'Expected voice');
    }
    return VoiceAttachment(
      bucket: json['bucket'] as String,
      path: json['path'] as String,
      mimeType: json['mime_type'] as String,
      size: json['size'] as int,
      durationMs: json['duration_ms'] as int,
    );
  }

  final String bucket;
  final String path;
  final String mimeType;
  final int size;
  final int durationMs;

  Map<String, dynamic> toJson() {
    return {
      'kind': 'voice',
      'bucket': bucket,
      'path': path,
      'mime_type': mimeType,
      'size': size,
      'duration_ms': durationMs,
    };
  }
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}

List<MessageMention> _parseMentions(Object? value) {
  if (value is! List) {
    return const <MessageMention>[];
  }
  final mentions = <MessageMention>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, dynamic>.from(item);
    final userId = json['user_id'];
    final start = json['start'];
    final end = json['end'];
    if (userId is! String || userId.isEmpty || start is! num || end is! num) {
      continue;
    }
    mentions.add(MessageMention.fromJson(json));
  }
  return mentions;
}
