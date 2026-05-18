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
    this.editedAt,
    this.recalledAt,
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
      createdAt: _parseTimestamp(json['created_at']),
      editedAt: _parseOptionalTimestamp(json['edited_at']),
      recalledAt: _parseOptionalTimestamp(json['recalled_at']),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String body;
  final Map<String, dynamic>? attachment;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? recalledAt;

  ImageAttachment? get imageAttachment {
    final value = attachment;
    if (type != MessageType.image || value == null) {
      return null;
    }
    return ImageAttachment.fromJson(value);
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'type': type.toJson(),
      'body': body,
      'attachment': attachment,
      'reply_to_message_id': replyToMessageId,
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
    DateTime? createdAt,
    Object? editedAt = _sentinel,
    Object? recalledAt = _sentinel,
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
      createdAt: createdAt ?? this.createdAt,
      editedAt: identical(editedAt, _sentinel)
          ? this.editedAt
          : editedAt as DateTime?,
      recalledAt: identical(recalledAt, _sentinel)
          ? this.recalledAt
          : recalledAt as DateTime?,
    );
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

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
