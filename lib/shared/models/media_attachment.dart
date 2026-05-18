import 'package:wecord/shared/models/message.dart';

class ConversationMediaItem {
  const ConversationMediaItem({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.body,
    required this.createdAt,
    this.attachment,
  });

  factory ConversationMediaItem.fromJson(Map<String, dynamic> json) {
    return ConversationMediaItem(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String,
      type: MessageType.fromJson(json['type'] as String),
      body: json['body'] as String? ?? '',
      attachment: json['attachment'] as Map<String, dynamic>?,
      createdAt: _parseTimestamp(json['created_at']),
    );
  }

  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final MessageType type;
  final String body;
  final Map<String, dynamic>? attachment;
  final DateTime createdAt;

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
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}
