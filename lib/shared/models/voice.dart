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

/// Someone in a direct or group call (`list_active_direct_calls`).
class DirectCallParticipant {
  const DirectCallParticipant({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.selfMute = false,
    this.selfDeaf = false,
    this.video = false,
    this.screen = false,
  });

  factory DirectCallParticipant.fromJson(Map<String, dynamic> json) {
    return DirectCallParticipant(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      selfMute: json['self_mute'] == true,
      selfDeaf: json['self_deaf'] == true,
      video: json['video'] == true,
      screen: json['screen'] == true,
    );
  }

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool selfMute;
  final bool selfDeaf;
  final bool video;
  final bool screen;

  /// Display name, then username.
  String get name {
    final displayName = this.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return username.trim().isEmpty ? 'Someone' : username;
  }
}

/// A call going on in one of the current user's direct or group chats.
class DirectCall {
  const DirectCall({
    required this.callId,
    required this.conversationId,
    required this.createdAt,
    this.startedBy,
    this.ringing = false,
    this.participants = const [],
  });

  factory DirectCall.fromJson(Map<String, dynamic> json) {
    final participants = json['participants'];
    return DirectCall(
      callId: json['call_id'] as String,
      conversationId: json['conversation_id'] as String,
      startedBy: json['started_by'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ringing: json['ringing'] == true,
      participants: [
        if (participants is List)
          for (final participant in participants)
            if (participant is Map)
              DirectCallParticipant.fromJson(
                Map<String, dynamic>.from(participant),
              ),
      ],
    );
  }

  final String callId;
  final String conversationId;
  final String? startedBy;
  final DateTime createdAt;

  /// Rings for the current user: it just started and they have neither
  /// joined nor declined it.
  final bool ringing;

  /// Who is in it, in the order they joined.
  final List<DirectCallParticipant> participants;

  /// Who started it, if they are still in it.
  DirectCallParticipant? get caller {
    for (final participant in participants) {
      if (participant.userId == startedBy) {
        return participant;
      }
    }
    return participants.firstOrNull;
  }
}
