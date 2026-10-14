/// Someone banned from a circle, as moderators see them.
class CircleBan {
  const CircleBan({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.createdAt,
    this.avatarUrl,
    this.reason,
    this.bannedByName,
  });

  factory CircleBan.fromJson(Map<String, dynamic> json) {
    return CircleBan(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      reason: json['reason'] as String?,
      bannedByName: json['banned_by_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? reason;

  /// Who banned them, when that member is still known.
  final String? bannedByName;
  final DateTime createdAt;

  /// The name shown in the list: display name, then username.
  String get name {
    final displayName = this.displayName.trim();
    return displayName.isEmpty ? username : displayName;
  }
}
