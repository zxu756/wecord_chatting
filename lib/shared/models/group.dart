import 'package:wecord/shared/models/profile.dart';

class GroupMember {
  const GroupMember({required this.profile, required this.role, this.nickname});

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      role: json['role'] as String,
      nickname: json['circle_nickname'] as String?,
    );
  }

  final Profile profile;
  final String role;

  /// The member's circle nickname when the conversation is a circle channel.
  final String? nickname;
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
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;
  final String announcement;
  final DateTime? announcementUpdatedAt;
  final String? announcementUpdatedBy;
  final String? currentUserRole;
  final List<GroupMember> members;

  int get memberCount => members.length;

  bool get canManageGroup =>
      currentUserRole == 'owner' || currentUserRole == 'admin';
}
