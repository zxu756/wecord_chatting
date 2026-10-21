import 'package:flutter/foundation.dart' show immutable;
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/message.dart';

const _sentinel = Object();

enum ConversationType {
  direct,
  group,
  channel,

  /// A thread of a channel or group; see `conversation_threads`.
  thread;

  factory ConversationType.fromJson(String value) {
    return switch (value) {
      'direct' => ConversationType.direct,
      'group' => ConversationType.group,
      'channel' => ConversationType.channel,
      'thread' => ConversationType.thread,
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
      ConversationType.thread => 'thread',
    };
  }
}

/// What the latest album of a conversation holds: pictures, videos and
/// files, as the server counts them (`last_message_album`).
@immutable
class ConversationAlbum {
  const ConversationAlbum({this.images = 0, this.videos = 0, this.files = 0});

  /// Reads the server's `{"images": 2, "videos": 1, "files": 0}`; null for
  /// anything else.
  static ConversationAlbum? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    final album = ConversationAlbum(
      images: count('images'),
      videos: count('videos'),
      files: count('files'),
    );
    return album.total >= 2 ? album : null;
  }

  final int images;
  final int videos;
  final int files;

  int get total => images + videos + files;

  @override
  bool operator ==(Object other) =>
      other is ConversationAlbum &&
      other.images == images &&
      other.videos == videos &&
      other.files == files;

  @override
  int get hashCode => Object.hash(images, videos, files);
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.type,
    required this.unreadCount,
    this.title,
    this.avatarUrl,
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.lastMessageType,
    this.lastMessageWebhookName,
    this.lastMessageAttachmentKind,
    this.lastMessageAlbum,
    this.pinnedAt,
    this.mutedUntil,
    this.isMuted = false,
    this.isMarkedUnread = false,
    this.memberCount = 0,
    this.mentionedUserIds = const <String>{},
    this.announcement = '',
    this.announcementUpdatedAt,
    this.announcementUpdatedBy,
    this.circleId,
    this.circleNotificationLevel,
    this.circleMutedUntil,
    this.directUserId,
    this.directCustomStatus,
    this.parentConversationId,
    this.parentTitle,
    this.threadId,
    this.threadArchivedAt,
    this.threadLastActivityAt,
    this.canSendMessages = true,
    this.slowmodeSeconds = 0,
    this.isNoteToSelf = false,
    this.isLocked = false,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      type: ConversationType.fromJson(json['type'] as String),
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      lastMessageBody: json['last_message_body'] as String?,
      lastMessageSenderId: json['last_message_sender_id'] as String?,
      lastMessageAt: _parseOptionalTimestamp(json['last_message_at']),
      lastMessageType: json['last_message_type'] == null
          ? null
          : MessageType.fromJson(json['last_message_type'] as String),
      lastMessageWebhookName: json['last_message_webhook_name'] as String?,
      lastMessageAttachmentKind:
          json['last_message_attachment_kind'] as String?,
      lastMessageAlbum: ConversationAlbum.maybeFromJson(
        json['last_message_album'],
      ),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      pinnedAt: _parseOptionalTimestamp(json['pinned_at']),
      mutedUntil: _parseOptionalTimestamp(json['muted_until']),
      isMuted: json['is_muted'] as bool? ?? false,
      isMarkedUnread: json['is_marked_unread'] as bool? ?? false,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      mentionedUserIds:
          (json['mentioned_user_ids'] as List<dynamic>?)
              ?.whereType<String>()
              .toSet() ??
          const <String>{},
      announcement: json['announcement'] as String? ?? '',
      announcementUpdatedAt: _parseOptionalTimestamp(
        json['announcement_updated_at'],
      ),
      announcementUpdatedBy: json['announcement_updated_by'] as String?,
      circleId: json['circle_id'] as String?,
      circleNotificationLevel: json['circle_notification_level'] == null
          ? null
          : CircleNotificationLevel.fromJson(
              json['circle_notification_level'] as String,
            ),
      circleMutedUntil: _parseOptionalTimestamp(json['circle_muted_until']),
      directUserId: json['direct_user_id'] as String?,
      directCustomStatus: CustomStatus.maybeFromJson(
        json['direct_custom_status'],
      ),
      parentConversationId: json['parent_conversation_id'] as String?,
      parentTitle: json['parent_title'] as String?,
      threadId: json['thread_id'] as String?,
      threadArchivedAt: _parseOptionalTimestamp(json['thread_archived_at']),
      threadLastActivityAt: _parseOptionalTimestamp(
        json['thread_last_activity_at'],
      ),
      canSendMessages: json['can_send_messages'] as bool? ?? true,
      slowmodeSeconds: (json['slowmode_seconds'] as num?)?.toInt() ?? 0,
      isNoteToSelf: json['is_note_to_self'] as bool? ?? false,
    );
  }

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final String? lastMessageBody;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final MessageType? lastMessageType;

  /// The webhook name the latest message was posted under, if a webhook
  /// posted it (then it is not the sender's own message).
  final String? lastMessageWebhookName;

  /// What a file message carries: 'video' or 'file' (null for other
  /// messages, and from servers that don't say).
  final String? lastMessageAttachmentKind;

  /// What the latest message's album holds, when the latest message is one
  /// of two or more sent together (null for other messages, and from
  /// servers that don't say).
  final ConversationAlbum? lastMessageAlbum;

  /// Whether the latest message is a video file.
  bool get lastMessageIsVideo =>
      lastMessageType == MessageType.file &&
      lastMessageAttachmentKind == 'video';
  final int unreadCount;
  final DateTime? pinnedAt;
  final DateTime? mutedUntil;
  final bool isMuted;
  final bool isMarkedUnread;
  final int memberCount;
  final Set<String> mentionedUserIds;
  final String announcement;
  final DateTime? announcementUpdatedAt;
  final String? announcementUpdatedBy;

  /// The circle a channel conversation belongs to; null otherwise.
  final String? circleId;

  /// The current user's notification level for [circleId]'s channels.
  final CircleNotificationLevel? circleNotificationLevel;

  /// When the current user's mute of [circleId] ends, if muted.
  final DateTime? circleMutedUntil;

  /// The other member of a direct conversation; null otherwise.
  final String? directUserId;

  /// [directUserId]'s custom status, if they have one.
  final CustomStatus? directCustomStatus;

  /// For a thread: the channel or group it belongs to, and that
  /// conversation's title.
  final String? parentConversationId;
  final String? parentTitle;

  /// For a thread: its `conversation_threads` id, when it was archived and
  /// its latest message (or creation) time.
  final String? threadId;
  final DateTime? threadArchivedAt;
  final DateTime? threadLastActivityAt;

  /// False in circle channels (and their threads) where the current user
  /// lacks send_messages.
  final bool canSendMessages;

  /// The channel's slowmode for the current user, in seconds; 0 when off,
  /// exempt, or not a circle channel.
  final int slowmodeSeconds;

  /// The user's note to self (文件传输助手): a direct chat with nobody else,
  /// listed first. Never unread, never receipted, never pushed.
  final bool isNoteToSelf;

  /// The person locked this chat on their devices (app lock and chat lock,
  /// G2). Set by the app, never by the server: lists show "Locked chat" in
  /// place of the latest message.
  final bool isLocked;

  bool get isThread => type == ConversationType.thread;

  /// A direct or group chat, listed under direct messages.
  bool get isDirectMessage =>
      type == ConversationType.direct || type == ConversationType.group;

  Map<String, dynamic> toJson() {
    return {'type': type.toJson(), 'title': title, 'avatar_url': avatarUrl};
  }

  ConversationSummary copyWith({
    String? id,
    ConversationType? type,
    Object? title = _sentinel,
    Object? avatarUrl = _sentinel,
    Object? lastMessageBody = _sentinel,
    Object? lastMessageSenderId = _sentinel,
    Object? lastMessageAt = _sentinel,
    Object? lastMessageType = _sentinel,
    Object? lastMessageWebhookName = _sentinel,
    Object? lastMessageAttachmentKind = _sentinel,
    Object? lastMessageAlbum = _sentinel,
    int? unreadCount,
    Object? pinnedAt = _sentinel,
    Object? mutedUntil = _sentinel,
    bool? isMuted,
    bool? isMarkedUnread,
    int? memberCount,
    Set<String>? mentionedUserIds,
    String? announcement,
    Object? announcementUpdatedAt = _sentinel,
    Object? announcementUpdatedBy = _sentinel,
    Object? circleId = _sentinel,
    Object? circleNotificationLevel = _sentinel,
    Object? circleMutedUntil = _sentinel,
    Object? directUserId = _sentinel,
    Object? directCustomStatus = _sentinel,
    bool? isLocked,
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
      lastMessageSenderId: identical(lastMessageSenderId, _sentinel)
          ? this.lastMessageSenderId
          : lastMessageSenderId as String?,
      lastMessageAt: identical(lastMessageAt, _sentinel)
          ? this.lastMessageAt
          : lastMessageAt as DateTime?,
      lastMessageType: identical(lastMessageType, _sentinel)
          ? this.lastMessageType
          : lastMessageType as MessageType?,
      lastMessageWebhookName: identical(lastMessageWebhookName, _sentinel)
          ? this.lastMessageWebhookName
          : lastMessageWebhookName as String?,
      lastMessageAttachmentKind: identical(lastMessageAttachmentKind, _sentinel)
          ? this.lastMessageAttachmentKind
          : lastMessageAttachmentKind as String?,
      lastMessageAlbum: identical(lastMessageAlbum, _sentinel)
          ? this.lastMessageAlbum
          : lastMessageAlbum as ConversationAlbum?,
      unreadCount: unreadCount ?? this.unreadCount,
      pinnedAt: identical(pinnedAt, _sentinel)
          ? this.pinnedAt
          : pinnedAt as DateTime?,
      mutedUntil: identical(mutedUntil, _sentinel)
          ? this.mutedUntil
          : mutedUntil as DateTime?,
      isMuted: isMuted ?? this.isMuted,
      isMarkedUnread: isMarkedUnread ?? this.isMarkedUnread,
      memberCount: memberCount ?? this.memberCount,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
      announcement: announcement ?? this.announcement,
      announcementUpdatedAt: identical(announcementUpdatedAt, _sentinel)
          ? this.announcementUpdatedAt
          : announcementUpdatedAt as DateTime?,
      announcementUpdatedBy: identical(announcementUpdatedBy, _sentinel)
          ? this.announcementUpdatedBy
          : announcementUpdatedBy as String?,
      circleId: identical(circleId, _sentinel)
          ? this.circleId
          : circleId as String?,
      circleNotificationLevel: identical(circleNotificationLevel, _sentinel)
          ? this.circleNotificationLevel
          : circleNotificationLevel as CircleNotificationLevel?,
      circleMutedUntil: identical(circleMutedUntil, _sentinel)
          ? this.circleMutedUntil
          : circleMutedUntil as DateTime?,
      directUserId: identical(directUserId, _sentinel)
          ? this.directUserId
          : directUserId as String?,
      directCustomStatus: identical(directCustomStatus, _sentinel)
          ? this.directCustomStatus
          : directCustomStatus as CustomStatus?,
      parentConversationId: parentConversationId,
      parentTitle: parentTitle,
      threadId: threadId,
      threadArchivedAt: threadArchivedAt,
      threadLastActivityAt: threadLastActivityAt,
      canSendMessages: canSendMessages,
      slowmodeSeconds: slowmodeSeconds,
      isNoteToSelf: isNoteToSelf,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
