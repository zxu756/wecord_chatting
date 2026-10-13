/// Someone connected to one of a circle's voice channels, as the server
/// tracks it (`list_voice_states`).
class VoiceMemberState {
  const VoiceMemberState({
    required this.channelId,
    required this.circleId,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.joinedAt,
    this.avatarUrl,
    this.nickname,
    this.roleColor,
    this.selfMute = false,
    this.selfDeaf = false,
    this.video = false,
    this.screen = false,
  });

  factory VoiceMemberState.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : const <String, dynamic>{};
    return VoiceMemberState(
      channelId: json['channel_id'] as String,
      circleId: json['circle_id'] as String,
      userId: json['user_id'] as String,
      username: profile['username'] as String? ?? '',
      displayName: profile['display_name'] as String? ?? '',
      avatarUrl: profile['avatar_url'] as String?,
      nickname: json['nickname'] as String?,
      roleColor: (json['role_color'] as num?)?.toInt(),
      joinedAt:
          DateTime.tryParse(json['joined_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      selfMute: json['self_mute'] == true,
      selfDeaf: json['self_deaf'] == true,
      video: json['video'] == true,
      screen: json['screen'] == true,
    );
  }

  final String channelId;
  final String circleId;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;

  /// Their nickname in the circle, if any.
  final String? nickname;

  /// Their highest coloured role, as 0xRRGGBB.
  final int? roleColor;
  final DateTime joinedAt;
  final bool selfMute;
  final bool selfDeaf;
  final bool video;
  final bool screen;

  /// Nickname, then display name, then username.
  String get name {
    for (final candidate in [nickname, displayName, username]) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return 'Member';
  }
}

/// Where and how to connect to a voice channel's LiveKit room.
class VoiceConnectionDetails {
  const VoiceConnectionDetails({required this.url, required this.token});

  /// The LiveKit server, `wss://…`.
  final String url;

  /// An access token for the channel's room, valid for an hour.
  final String token;
}
