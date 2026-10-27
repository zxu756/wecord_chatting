import 'package:wecord/shared/models/profile.dart';

class GroupMember {
  const GroupMember({
    required this.profile,
    required this.role,
    this.nickname,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      role: json['role'] as String,
      nickname: json['circle_nickname'] as String?,
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? ''),
    );
  }

  final Profile profile;
  final String role;

  /// The member's circle nickname when the conversation is a circle channel.
  final String? nickname;

  /// When they joined, when the source said (the members are listed in this
  /// order, so the next page continues from the last one).
  final DateTime? joinedAt;
}

/// Where the next page of a big group's members starts: after this member in
/// joining order.
class GroupMembersCursor {
  const GroupMembersCursor({required this.joinedAt, required this.userId});

  final DateTime joinedAt;
  final String userId;

  /// The cursor after [member], or null when it has no joining time.
  static GroupMembersCursor? after(GroupMember member) {
    final joinedAt = member.joinedAt;
    if (joinedAt == null) {
      return null;
    }
    return GroupMembersCursor(joinedAt: joinedAt, userId: member.profile.id);
  }
}

class GroupDetail {
  const GroupDetail({
    required this.conversationId,
    required this.title,
    required this.members,
    this.avatarUrl,
    this.announcement = '',
    this.announcementUpdatedAt,
    this.announcementUpdatedBy,
    this.currentUserRole,
    this.totalMemberCount,
    this.moreMembersAfter,
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;
  final String announcement;
  final DateTime? announcementUpdatedAt;
  final String? announcementUpdatedBy;
  final String? currentUserRole;

  /// The members that were loaded: all of them for a small group, the first
  /// page (and the current user) for a big one.
  final List<GroupMember> members;

  /// How many members the group has, when more than [members] were loaded.
  final int? totalMemberCount;

  /// Where the rest of a big group's members continue; null when [members]
  /// is everyone.
  final GroupMembersCursor? moreMembersAfter;

  int get memberCount {
    final total = totalMemberCount;
    return total != null && total > members.length ? total : members.length;
  }

  bool get hasMoreMembers => moreMembersAfter != null;

  bool get canManageGroup =>
      currentUserRole == 'owner' || currentUserRole == 'admin';
}
