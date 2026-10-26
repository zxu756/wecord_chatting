import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/message_components.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/profile.dart';

const _sentinel = Object();

/// Where a message stands with the circle's AI guard (see
/// `202610170090_ai_guard.sql`). Messages of everyone else are never in
/// these states for the people who see them, except moderators.
enum MessageReviewState {
  /// Waiting for the AI's check.
  checking,

  /// The AI flagged it; hidden until a moderator decides.
  held,

  /// A moderator removed it; stays hidden from everyone but its author and
  /// the moderators.
  removed;

  static MessageReviewState? maybeFromJson(Object? value) {
    return switch (value) {
      'checking' => MessageReviewState.checking,
      'held' => MessageReviewState.held,
      'removed' => MessageReviewState.removed,
      _ => null,
    };
  }
}

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
    this.senderCircleAvatarUrl,
    this.senderRoleColor,
    this.threadSummary,
    this.pollResults,
    this.webhookId,
    this.webhookName,
    this.webhookAvatarUrl,
    this.crosspost,
    this.publishedAt,
    this.interaction,
    this.aiReply,
    this.clientId,
    this.attachmentGroupId,
    this.album,
    this.expiresAt,
    this.reviewState,
    this.silent = false,
    this.autoReply = false,
    this.components,
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
      senderCircleAvatarUrl: json['sender_circle_avatar'] as String?,
      senderRoleColor: (json['sender_role_color'] as num?)?.toInt(),
      threadSummary: MessageThreadSummary.maybeFromJson(json['thread_summary']),
      pollResults: PollResults.maybeFromJson(json['poll_results']),
      webhookId: json['webhook_id'] as String?,
      webhookName: json['webhook_name'] as String?,
      webhookAvatarUrl: json['webhook_avatar_url'] as String?,
      crosspost: MessageCrosspost.maybeFromJson(json['crosspost']),
      publishedAt: _parseOptionalTimestamp(json['published_at']),
      interaction: MessageInteraction.maybeFromJson(json['interaction']),
      aiReply: MessageAiReply.maybeFromJson(json['ai_reply']),
      clientId: json['client_id'] as String?,
      attachmentGroupId: json['attachment_group_id'] as String?,
      expiresAt: _parseOptionalTimestamp(json['expires_at']),
      reviewState: MessageReviewState.maybeFromJson(json['review_state']),
      silent: json['silent'] == true,
      autoReply: json['auto_reply'] == true,
      components: MessageComponents.maybeFromJson(json['components']),
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

  /// The sender's avatar for this circle in circle channel threads, shown
  /// instead of their usual one.
  final String? senderCircleAvatarUrl;

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

  /// A copy of a message published in an announcement channel this
  /// channel follows.
  final MessageCrosspost? crosspost;

  /// When this announcement was published to the channels following it.
  final DateTime? publishedAt;

  bool get isPublished => publishedAt != null;

  /// A bot's answer to a member's slash command.
  final MessageInteraction? interaction;

  /// Set by the server on an answer from the WeCord AI assistant: who asked
  /// and what kind of answer it is. Null on every other message.
  final MessageAiReply? aiReply;

  /// The id the sender's app gave the message when it was written, so a
  /// send retried from the outbox is stored once.
  final String? clientId;

  /// When a disappearing message is deleted; null for messages that stay.
  final DateTime? expiresAt;

  /// Set while the circle's AI guard checks or holds the message: only its
  /// author and moderators see it then. Null for every message others see.
  final MessageReviewState? reviewState;

  /// Sent without a push: nobody's device was told about it.
  final bool silent;

  /// The server sent it for an away person (A8).
  final bool autoReply;

  /// The buttons, links and lists a bot put on its message (I1); null on every
  /// other message.
  final MessageComponents? components;

  /// Whether the message disappears after a while.
  bool get isDisappearing => expiresAt != null;

  /// A round video message (A13), shown as a circle without a bubble. A
  /// view-once one is shown by the view-once viewer instead.
  bool get isVideoNote => !isViewOnce && fileAttachment?.isVideoNote == true;

  /// A photo or video its recipients can open once.
  bool get isViewOnce {
    final value = attachment;
    return (type == MessageType.image || type == MessageType.file) &&
        value != null &&
        value['view_once'] == true;
  }

  /// For a "turned disappearing messages on/off" system line, the timer in
  /// seconds (0 when it was turned off); null for any other message.
  int? get disappearingNoticeSeconds {
    final value = attachment;
    if (type != MessageType.system ||
        value == null ||
        value['kind'] != 'disappearing') {
      return null;
    }
    return (value['seconds'] as num?)?.toInt() ?? 0;
  }

  /// Shared by the messages of one album (pictures, videos and files sent
  /// together); null for messages sent on their own.
  final String? attachmentGroupId;

  /// For the first message of an album, every message of it in order
  /// (itself included). Set by the chat when it lays the list out; never
  /// stored.
  final List<ChatMessage>? album;

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
        ? tr('Message deleted by a moderator')
        : tr('Message deleted');
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

  /// A file or video; null for other messages and malformed attachments.
  FileAttachment? get fileAttachment {
    if (type != MessageType.file) {
      return null;
    }
    return FileAttachment.maybeFromJson(attachment);
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
    Object? senderCircleAvatarUrl = _sentinel,
    Object? senderRoleColor = _sentinel,
    Object? threadSummary = _sentinel,
    Object? pollResults = _sentinel,
    Object? webhookId = _sentinel,
    Object? webhookName = _sentinel,
    Object? webhookAvatarUrl = _sentinel,
    Object? publishedAt = _sentinel,
    Object? album = _sentinel,
    Object? expiresAt = _sentinel,
    Object? reviewState = _sentinel,
    Object? components = _sentinel,
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
      senderCircleAvatarUrl: identical(senderCircleAvatarUrl, _sentinel)
          ? this.senderCircleAvatarUrl
          : senderCircleAvatarUrl as String?,
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
      crosspost: crosspost,
      interaction: interaction,
      aiReply: aiReply,
      clientId: clientId,
      attachmentGroupId: attachmentGroupId,
      album: identical(album, _sentinel)
          ? this.album
          : album as List<ChatMessage>?,
      publishedAt: identical(publishedAt, _sentinel)
          ? this.publishedAt
          : publishedAt as DateTime?,
      expiresAt: identical(expiresAt, _sentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      reviewState: identical(reviewState, _sentinel)
          ? this.reviewState
          : reviewState as MessageReviewState?,
      silent: silent,
      autoReply: autoReply,
      components: identical(components, _sentinel)
          ? this.components
          : components as MessageComponents?,
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
    this.roleId,
    this.color,
    this.userIds = const [],
  });

  /// `@here`: [userIds] are the members this app sees online when it is
  /// sent. Only older servers use them; newer ones work out who is online
  /// from presence heartbeats (202610160038) and ignore the list.
  const MessageMention.here({
    required this.start,
    required this.end,
    this.userIds = const [],
  }) : userId = '',
       displayName = 'here',
       kind = kindHere,
       roleId = null,
       color = null;

  /// A mention of every member holding [roleId].
  const MessageMention.role({
    required String this.roleId,
    required this.displayName,
    required this.start,
    required this.end,
    this.color,
  }) : userId = '',
       kind = kindRole,
       userIds = const [];

  factory MessageMention.fromJson(Map<String, dynamic> json) {
    return MessageMention(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? 'user',
      roleId: json['role_id'] as String?,
      color: (json['color'] as num?)?.toInt(),
    );
  }

  static const kindHere = 'here';
  static const kindRole = 'role';

  /// The mentioned user; empty for `@here` and role mentions.
  final String userId;
  final String displayName;
  final int start;
  final int end;

  /// `user`, `all`, `here` or `role`.
  final String kind;

  /// The mentioned role, for role mentions.
  final String? roleId;

  /// The role's colour as 0xRRGGBB, for role mentions of coloured roles.
  final int? color;
  final List<String> userIds;

  bool get isHere => kind == kindHere;

  bool get isRole => kind == kindRole;

  Map<String, dynamic> toJson() {
    return {
      if (!isHere && !isRole) 'user_id': userId,
      'display_name': displayName,
      'start': start,
      'end': end,
      'kind': kind,
      if (isRole) 'role_id': roleId,
      if (isHere) 'user_ids': userIds,
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
    this.quote,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> json) {
    return ReplyPreview(
      messageId: json['message_id'] as String,
      senderName: json['sender_name'] as String,
      body: json['body'] as String,
      type: MessageType.fromJson(json['type'] as String),
      quote: ReplyQuote.maybeFromJson(json['quote']),
    );
  }

  final String messageId;
  final String senderName;
  final String body;
  final MessageType type;

  /// The part of the message the reply answers, when the sender picked one.
  /// The server checked that it is in the message.
  final ReplyQuote? quote;

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_name': senderName,
      'body': body,
      'type': type.toJson(),
      if (quote != null) 'quote': quote!.toJson(),
    };
  }
}

/// A piece of text picked from the message a reply answers (A9).
class ReplyQuote {
  const ReplyQuote({required this.text, this.start, this.end});

  /// The longest quote the server keeps.
  static const maxLength = 500;

  /// Null unless [value] is an object with some text.
  static ReplyQuote? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final text = value['text'];
    if (text is! String || text.isEmpty) {
      return null;
    }
    final start = value['start'];
    final end = value['end'];
    return ReplyQuote(
      text: text,
      start: start is int ? start : null,
      end: end is int ? end : null,
    );
  }

  final String text;

  /// Where the text starts and ends in the message body (UTF-16 offsets),
  /// when known. Checked against the body before it is used.
  final int? start;
  final int? end;

  Map<String, dynamic> toJson() {
    return {'text': text, 'start': ?start, 'end': ?end};
  }

  /// Where the quote sits in [body], or null when it is not there.
  (int, int)? locateIn(String body) {
    final from = start;
    final to = end;
    if (from != null &&
        to != null &&
        from >= 0 &&
        to <= body.length &&
        from < to &&
        body.substring(from, to) == text) {
      return (from, to);
    }
    final index = body.indexOf(text);
    return index < 0 ? null : (index, index + text.length);
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
    this.blurhash,
    this.alt,
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
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      blurhash: json['blurhash'] as String?,
      alt: cleanImageAlt(json['alt']),
    );
  }

  final String bucket;
  final String path;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;

  /// A BlurHash of the picture, drawn while it loads (see blurhash.dart).
  final String? blurhash;

  /// What the picture shows, in the sender's words, for people who can't see
  /// it (read by screen readers; shown behind the "ALT" mark). Null when the
  /// sender wrote none.
  final String? alt;

  Map<String, dynamic> toJson() {
    return {
      'kind': 'image',
      'bucket': bucket,
      'path': path,
      'mime_type': mimeType,
      'size': size,
      'width': width,
      'height': height,
      if (blurhash != null) 'blurhash': blurhash,
      'alt': ?cleanImageAlt(alt),
    };
  }
}

/// The longest picture description that is kept.
const maxImageAltLength = 1000;

/// [value] as a picture description: trimmed, at most [maxImageAltLength]
/// characters; null when it is not text or holds nothing.
String? cleanImageAlt(Object? value) {
  if (value is! String) {
    return null;
  }
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final runes = text.runes;
  return runes.length <= maxImageAltLength
      ? text
      : String.fromCharCodes(runes.take(maxImageAltLength));
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

/// A file (or video) sent in a chat, stored in the chat-files bucket.
class FileAttachment {
  const FileAttachment({
    required this.bucket,
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
    this.blurhash,
    this.videoNoteMs,
  });

  static FileAttachment? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null || (json['kind'] != 'file' && json['kind'] != 'video')) {
      return null;
    }
    final bucket = json['bucket'];
    final path = json['path'];
    if (bucket is! String || path is! String) {
      return null;
    }
    final name = json['name'];
    return FileAttachment(
      bucket: bucket,
      path: path,
      name: name is String && name.trim().isNotEmpty
          ? name
          : path.split('/').last,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      blurhash: json['blurhash'] as String?,
      videoNoteMs: json['video_note'] == true
          ? (json['duration_ms'] as num?)?.toInt() ?? 0
          : null,
    );
  }

  final String bucket;
  final String path;

  /// The name it had on the sender's device.
  final String name;
  final String mimeType;
  final int size;

  /// For videos sent from this app: the size of the poster frame (the
  /// video's proportions) and a BlurHash of it.
  final int? width;
  final int? height;
  final String? blurhash;

  /// Plays inline instead of showing as a download.
  bool get isVideo => mimeType.startsWith('video/');

  /// For a round video message (A13): how long it runs, in milliseconds.
  /// Null for any other file. It is an ordinary video with this flag, so
  /// every place that knows videos still handles it.
  final int? videoNoteMs;

  /// A round video message: shown as a circle.
  bool get isVideoNote => isVideo && videoNoteMs != null;

  Map<String, dynamic> toJson() {
    return {
      'kind': isVideo ? 'video' : 'file',
      'bucket': bucket,
      'path': path,
      'name': name,
      'mime_type': mimeType,
      'size': size,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (blurhash != null) 'blurhash': blurhash,
      if (videoNoteMs != null) ...{
        'video_note': true,
        'duration_ms': videoNoteMs,
      },
    };
  }
}

/// "512 B", "14 KB", "3.2 MB".
String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).round()} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
