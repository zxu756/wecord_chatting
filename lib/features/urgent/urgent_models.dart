import 'package:wecord/shared/models/message.dart';

/// An urgent message waiting for the current user to confirm it
/// (list_my_pending_urgents, migration 202610240410).
class PendingUrgent {
  const PendingUrgent({
    required this.urgentId,
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.createdAt,
    this.senderAvatarUrl,
  });

  factory PendingUrgent.fromJson(Map<String, dynamic> json) {
    return PendingUrgent(
      urgentId: json['urgent_id'] as String,
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      body: json['body'] as String? ?? '',
      type: MessageType.fromJson(json['type'] as String? ?? 'text'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String urgentId;
  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String body;
  final MessageType type;

  /// When the message was made urgent.
  final DateTime createdAt;
}

/// One person a message was made urgent for, as its sender sees them.
class UrgentRecipient {
  const UrgentRecipient({
    required this.userId,
    required this.name,
    required this.urgentAt,
    this.avatarUrl,
    this.ackedAt,
  });

  factory UrgentRecipient.fromJson(Map<String, dynamic> json) {
    return UrgentRecipient(
      userId: json['user_id'] as String,
      name: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      urgentAt: DateTime.parse(json['urgent_at'] as String),
      ackedAt: json['acked_at'] == null
          ? null
          : DateTime.parse(json['acked_at'] as String),
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime urgentAt;
  final DateTime? ackedAt;

  bool get confirmed => ackedAt != null;
}

/// How many times the current user made a message urgent in the last 24
/// hours, and how many they may.
class UrgentQuota {
  const UrgentQuota({required this.used, required this.allowed});

  const UrgentQuota.unknown() : used = 0, allowed = 5;

  final int used;
  final int allowed;

  int get remaining => (allowed - used).clamp(0, allowed);
}

/// A sender whose urgent messages the current user turned off.
class MutedUrgentSender {
  const MutedUrgentSender({
    required this.senderId,
    required this.name,
    this.avatarUrl,
  });

  factory MutedUrgentSender.fromJson(Map<String, dynamic> json) {
    return MutedUrgentSender(
      senderId: json['sender_id'] as String,
      name: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String senderId;
  final String name;
  final String? avatarUrl;
}

/// Where a group's announcement stands when it asks for a confirmation
/// (get_announcement_ack_state, migration 202610240420).
class AnnouncementAckState {
  const AnnouncementAckState({
    required this.requiresAck,
    required this.total,
    required this.acked,
    required this.iAcked,
    required this.canManage,
    this.nextReminderAt,
  });

  factory AnnouncementAckState.fromJson(Map<String, dynamic> json) {
    return AnnouncementAckState(
      requiresAck: json['requires_ack'] as bool? ?? false,
      total: (json['total'] as num?)?.toInt() ?? 0,
      acked: (json['acked'] as num?)?.toInt() ?? 0,
      iAcked: json['i_acked'] as bool? ?? false,
      canManage: json['can_manage'] as bool? ?? false,
      nextReminderAt: json['next_reminder_at'] == null
          ? null
          : DateTime.parse(json['next_reminder_at'] as String),
    );
  }

  static const none = AnnouncementAckState(
    requiresAck: false,
    total: 0,
    acked: 0,
    iAcked: false,
    canManage: false,
  );

  final bool requiresAck;
  final int total;
  final int acked;
  final bool iAcked;
  final bool canManage;

  /// When the owner or an admin may remind again; null: now.
  final DateTime? nextReminderAt;

  int get waiting => (total - acked).clamp(0, total);
}

/// A member in the owner's confirmation list.
class AnnouncementAckMember {
  const AnnouncementAckMember({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.ackedAt,
  });

  factory AnnouncementAckMember.fromJson(Map<String, dynamic> json) {
    return AnnouncementAckMember(
      userId: json['user_id'] as String,
      name: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      ackedAt: json['acked_at'] == null
          ? null
          : DateTime.parse(json['acked_at'] as String),
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime? ackedAt;

  bool get confirmed => ackedAt != null;
}

/// A group announcement waiting for the current user's confirmation.
class PendingAnnouncementAck {
  const PendingAnnouncementAck({
    required this.conversationId,
    required this.title,
    required this.announcement,
    this.updatedAt,
    this.askedByName,
    this.askedByAvatarUrl,
  });

  factory PendingAnnouncementAck.fromJson(Map<String, dynamic> json) {
    return PendingAnnouncementAck(
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? '',
      announcement: json['announcement'] as String? ?? '',
      updatedAt: json['announcement_updated_at'] == null
          ? null
          : DateTime.parse(json['announcement_updated_at'] as String),
      askedByName: json['asked_by_name'] as String?,
      askedByAvatarUrl: json['asked_by_avatar_url'] as String?,
    );
  }

  final String conversationId;
  final String title;
  final String announcement;
  final DateTime? updatedAt;
  final String? askedByName;
  final String? askedByAvatarUrl;
}

/// Why an urgent or confirmation call was refused.
enum UrgentProblem {
  /// Five times in 24 hours, or a reminder too soon after the last.
  rateLimited,

  /// Nobody could be made urgent: blocked, turned off, or already urgent.
  nobodyToUrgent,
  tooManyPeople,
  unavailable,
  emptyAnnouncement,
  nobodyToRemind,
  other,
}

class UrgentException implements Exception {
  const UrgentException(this.problem);

  final UrgentProblem problem;

  @override
  String toString() => 'UrgentException($problem)';
}
