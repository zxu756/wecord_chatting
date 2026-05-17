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
    Map<String, dynamic>? attachment,
    String? replyToMessageId,
    DateTime? createdAt,
    DateTime? editedAt,
    DateTime? recalledAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      body: body ?? this.body,
      attachment: attachment ?? this.attachment,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      recalledAt: recalledAt ?? this.recalledAt,
    );
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
