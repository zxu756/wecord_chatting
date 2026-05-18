const _sentinel = Object();

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.createdAt,
    required this.updatedAt,
    this.alias,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      alias: json['alias'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? alias;
  final String? avatarUrl;
  final String bio;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayLabel {
    final value = alias?.trim();
    return value == null || value.isEmpty ? displayName : value;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'bio': bio,
    };
  }

  Profile copyWith({
    String? id,
    String? username,
    String? displayName,
    Object? alias = _sentinel,
    Object? avatarUrl = _sentinel,
    String? bio,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      alias: identical(alias, _sentinel) ? this.alias : alias as String?,
      avatarUrl: identical(avatarUrl, _sentinel)
          ? this.avatarUrl
          : avatarUrl as String?,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}
