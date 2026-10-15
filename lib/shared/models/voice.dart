import 'package:wecord/shared/l10n/l10n.dart';

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
    this.serverMute = false,
    this.serverDeaf = false,
    this.video = false,
    this.screen = false,
    this.stageSpeaker = false,
    this.stageInvited = false,
    this.handRaisedAt,
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
      serverMute: json['server_mute'] == true,
      serverDeaf: json['server_deaf'] == true,
      video: json['video'] == true,
      screen: json['screen'] == true,
      stageSpeaker: json['stage_speaker'] == true,
      stageInvited: json['stage_invited'] == true,
      handRaisedAt: DateTime.tryParse(
        json['hand_raised_at'] as String? ?? '',
      )?.toUtc(),
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

  /// Muted or deafened by a moderator.
  final bool serverMute;
  final bool serverDeaf;
  final bool video;
  final bool screen;

  /// On a stage: one of the speakers (the rest are the audience).
  final bool stageSpeaker;

  /// On a stage: a moderator invited them to speak.
  final bool stageInvited;

  /// On a stage: when they raised their hand to speak; null when it's down.
  final DateTime? handRaisedAt;

  bool get handRaised => handRaisedAt != null;

  /// Nickname, then display name, then username.
  String get name {
    for (final candidate in [nickname, displayName, username]) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return tr('Member');
  }
}

/// Where and how to connect to a voice channel's LiveKit room.
class VoiceConnectionDetails {
  const VoiceConnectionDetails({
    required this.url,
    required this.token,
    this.serverMute = false,
    this.serverDeaf = false,
    this.stage = false,
    this.stageSpeaker = false,
  });

  /// The LiveKit server, `wss://…`.
  final String url;

  /// An access token for the channel's room, valid for an hour.
  final String token;

  /// The current user is server muted or deafened there, so the token
  /// can't publish their microphone.
  final bool serverMute;
  final bool serverDeaf;

  /// A stage channel; unless [stageSpeaker], the token only listens.
  final bool stage;
  final bool stageSpeaker;
}

/// The current user's own voice state (`get_own_voice_state`).
class OwnVoiceState {
  const OwnVoiceState({
    this.channelId,
    this.circleId,
    this.conversationId,
    this.channelName,
    this.serverMute = false,
    this.serverDeaf = false,
    this.disconnected = false,
    this.stage = false,
    this.stageSpeaker = false,
    this.stageInvited = false,
    this.handRaised = false,
  });

  factory OwnVoiceState.fromJson(Map<String, dynamic> json) {
    final state = json['state'] is Map
        ? Map<String, dynamic>.from(json['state'] as Map)
        : null;
    return OwnVoiceState(
      channelId: state?['channel_id'] as String?,
      circleId: state?['circle_id'] as String?,
      conversationId: state?['conversation_id'] as String?,
      channelName: state?['channel_name'] as String?,
      serverMute: state?['server_mute'] == true,
      serverDeaf: state?['server_deaf'] == true,
      disconnected: json['disconnected'] == true,
      stage: state?['channel_kind'] == 'stage',
      stageSpeaker: state?['stage_speaker'] == true,
      stageInvited: state?['stage_invited'] == true,
      handRaised: state?['hand_raised_at'] != null,
    );
  }

  /// The voice channel they are in; null when in none.
  final String? channelId;
  final String? circleId;
  final String? conversationId;
  final String? channelName;
  final bool serverMute;
  final bool serverDeaf;

  /// A moderator disconnected them, and they haven't joined since.
  final bool disconnected;

  /// They are on a stage: a speaker, invited to speak, or with their hand
  /// raised.
  final bool stage;
  final bool stageSpeaker;
  final bool stageInvited;
  final bool handRaised;
}

/// A live stage in a stage channel (`list_stage_instances`).
class StageInstance {
  const StageInstance({
    required this.channelId,
    required this.circleId,
    required this.topic,
    required this.startedAt,
    this.startedBy,
  });

  factory StageInstance.fromJson(Map<String, dynamic> json) {
    return StageInstance(
      channelId: json['channel_id'] as String,
      circleId: json['circle_id'] as String,
      topic: json['topic'] as String? ?? '',
      startedBy: json['started_by'] as String?,
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Longest topic the server accepts.
  static const maxTopicLength = 120;

  final String channelId;
  final String circleId;
  final String topic;
  final String? startedBy;
  final DateTime startedAt;
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
    return username.trim().isEmpty ? tr('Someone') : username;
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
