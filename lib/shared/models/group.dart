import 'package:wecord/shared/models/profile.dart';

class GroupMember {
  const GroupMember({required this.profile, required this.role});

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      role: json['role'] as String,
    );
  }

  final Profile profile;
  final String role;
}

class GroupDetail {
  const GroupDetail({
    required this.conversationId,
    required this.title,
    required this.members,
    this.avatarUrl,
    this.announcement = '',
    this.currentUserRole,
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;
  final String announcement;
  final String? currentUserRole;
  final List<GroupMember> members;

  int get memberCount => members.length;

  bool get canManageGroup =>
      currentUserRole == 'owner' || currentUserRole == 'admin';
}
