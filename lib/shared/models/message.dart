import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/profile.dart';

const _sentinel = Object();

enum MessageType {
  text,
  image,
  file,
  voice,
  system,
  poll,
  sticker;

  factory MessageType.fromJson(String value) {
    return switch (value) {
      'text' => MessageType.text,
      'image' => MessageType.image,
      'file' => MessageType.file,
      'voice' => MessageType.voice,
      'system' => MessageType.system,
      'poll' => MessageType.poll,
      'sticker' => MessageType.sticker,
      _ => throw ArgumentError.value(value, 'value', 'Unknown message type'),
    };
  }

  String toJson() {
    return switch (this) {
      MessageType.text => 'text',
      MessageType.image => 'image',
      MessageType.file => 'file',
      MessageType.voice => 'voice',
      MessageType.system => 'system',
      MessageType.poll => 'poll',
      MessageType.sticker => 'sticker',
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
    this.recalledBy,
    this.mentions = const <MessageMention>[],
    this.reactions = const <MessageReaction>[],
    this.isPinned = false,
    this.suppressEmbeds = false,
    this.sender,
    this.senderNickname,
    this.senderRoleColor,
    this.threadSummary,
    this.pollResults,
    this.webhookId,
    this.webhookName,
    this.webhookAvatarUrl,
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
      recalledBy: json['recalled_by'] as String?,
      mentions: _parseMentions(json['mentions']),
      reactions: _parseReactions(json['reactions']),
      isPinned: json['is_pinned'] == true,
      suppressEmbeds: json['suppress_embeds'] == true,
      sender: json['sender'] is Map<String, dynamic>
          ? Profile.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      senderNickname: json['sender_nickname'] as String?,
      senderRoleColor: (json['sender_role_color'] as num?)?.toInt(),
      threadSummary: MessageThreadSummary.maybeFromJson(json['thread_summary']),
      pollResults: PollResults.maybeFromJson(json['poll_results']),
      webhookId: json['webhook_id'] as String?,
      webhookName: json['webhook_name'] as String?,
      webhookAvatarUrl: json['webhook_avatar_url'] as String?,
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

  /// Who deleted the message: the sender, or a moderator.
  final String? recalledBy;
  final List<MessageMention> mentions;
  final List<MessageReaction> reactions;
  final bool isPinned;

  /// The sender hid the link preview under this message.
  final bool suppressEmbeds;

  /// The sender's profile, when the thread query embeds it.
  final Profile? sender;

  /// The sender's circle nickname in circle channel threads.
  final String? senderNickname;

  /// The colour (0xRRGGBB) of the sender's highest coloured circle role in
  /// circle channel threads.
  final int? senderRoleColor;

  /// The thread started from this message, if any.
  final MessageThreadSummary? threadSummary;

  /// Votes on a poll message, when the thread query includes them.
  final PollResults? pollResults;

  /// The webhook that posted this message; null once it is deleted.
  final String? webhookId;

  /// The name a webhook posted this message under. Set on every webhook
  /// message (also after the webhook is deleted), so it marks them.
  final String? webhookName;
  final String? webhookAvatarUrl;

  /// Posted through a webhook: shown under the webhook's name, not as a
  /// message of [senderId] (the webhook's creator).
  bool get isWebhook => webhookName != null;

  /// Deleted by someone other than its sender (a moderator).
  bool get isDeletedByModerator {
    return recalledAt != null && recalledBy != null && recalledBy != senderId;
  }

  /// "Message deleted", or "Message deleted by a moderator".
  String get deletedLabel {
    return isDeletedByModerator
        ? 'Message deleted by a moderator'
        : 'Message deleted';
  }

  /// Whether [userId] wrote this message themselves (webhook messages are
  /// nobody's own).
  bool isSentBy(String? userId) {
    return userId != null && senderId == userId && !isWebhook;
  }

  /// Who the message reads as being from, for grouping consecutive
  /// messages.
  String get authorKey {
    return isWebhook ? 'webhook:${webhookId ?? ''}:$webhookName' : senderId;
  }

  /// For a "X pinned a message" system notice, the id of the pinned message.
  String? get pinnedMessageId {
    final value = attachment;
    if (type != MessageType.system || value == null) {
      return null;
    }
    if (value['kind'] != 'pin') {
      return null;
    }
    return value['message_id'] as String?;
  }

  ImageAttachment? get imageAttachment {
    final value = attachment;
    if (type != MessageType.image || value == null) {
      return null;
    }
    return ImageAttachment.fromJson(value);
  }

  PollAttachment? get pollAttachment {
    if (type != MessageType.poll) {
      return null;
    }
    return PollAttachment.maybeFromJson(attachment);
  }

  StickerAttachment? get stickerAttachment {
    if (type != MessageType.sticker) {
      return null;
    }
    return StickerAttachment.maybeFromJson(attachment);
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
    Object? recalledBy = _sentinel,
    List<MessageMention>? mentions,
    List<MessageReaction>? reactions,
    bool? isPinned,
    bool? suppressEmbeds,
    Object? sender = _sentinel,
    Object? senderNickname = _sentinel,
    Object? senderRoleColor = _sentinel,
    Object? threadSummary = _sentinel,
    Object? pollResults = _sentinel,
    Object? webhookId = _sentinel,
    Object? webhookName = _sentinel,
    Object? webhookAvatarUrl = _sentinel,
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
      recalledBy: identical(recalledBy, _sentinel)
          ? this.recalledBy
          : recalledBy as String?,
      mentions: mentions ?? this.mentions,
      reactions: reactions ?? this.reactions,
      isPinned: isPinned ?? this.isPinned,
      suppressEmbeds: suppressEmbeds ?? this.suppressEmbeds,
      sender: identical(sender, _sentinel) ? this.sender : sender as Profile?,
      senderNickname: identical(senderNickname, _sentinel)
          ? this.senderNickname
          : senderNickname as String?,
      senderRoleColor: identical(senderRoleColor, _sentinel)
          ? this.senderRoleColor
          : senderRoleColor as int?,
      threadSummary: identical(threadSummary, _sentinel)
          ? this.threadSummary
          : threadSummary as MessageThreadSummary?,
      pollResults: identical(pollResults, _sentinel)
          ? this.pollResults
          : pollResults as PollResults?,
      webhookId: identical(webhookId, _sentinel)
          ? this.webhookId
          : webhookId as String?,
      webhookName: identical(webhookName, _sentinel)
          ? this.webhookName
          : webhookName as String?,
      webhookAvatarUrl: identical(webhookAvatarUrl, _sentinel)
          ? this.webhookAvatarUrl
          : webhookAvatarUrl as String?,
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

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.count,
    this.reactedByMe = false,
    this.customName,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
      reactedByMe: json['reacted_by_me'] == true,
      customName: json['custom_name'] as String?,
    );
  }

  /// A unicode emoji, or `custom:<uuid>` for a circle's custom emoji.
  final String emoji;
  final int count;
  final bool reactedByMe;

  /// A custom emoji's name, while it exists.
  final String? customName;

  /// The custom emoji's id, for `custom:<uuid>` reactions.
  String? get customEmojiId => customReactionEmojiId(emoji);
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

List<MessageReaction> _parseReactions(Object? value) {
  if (value is! List) {
    return const <MessageReaction>[];
  }
  final reactions = <MessageReaction>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, dynamic>.from(item);
    final emoji = json['emoji'];
    final count = json['count'];
    if (emoji is! String || emoji.isEmpty || count is! num || count <= 0) {
      continue;
    }
    reactions.add(MessageReaction.fromJson(json));
  }
  return reactions;
}
