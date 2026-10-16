import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/shared/models/voice.dart';

/// A voice repository whose server state lives in memory.
class FakeVoiceRepository implements VoiceRepository {
  /// What `list_voice_states` returns, per circle.
  final states = <String, List<VoiceMemberState>>{};

  /// Thrown by [fetchConnectionDetails], e.g. [VoiceNotConfiguredException].
  Object? tokenError;
  Object? joinError;

  /// What [updateVoiceState] answers (false: the server dropped us).
  bool updateResult = true;

  final tokenRequests = <String>[];
  final joined = <String>[];
  final updates = <({bool mute, bool deaf, bool video, bool screen})>[];
  var leaves = 0;
  final _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  /// What `get_own_voice_state` returns.
  OwnVoiceState ownState = const OwnVoiceState();

  /// What the token answers about server mute and deafen.
  bool tokenServerMute = false;
  bool tokenServerDeaf = false;

  /// What the token answers about a stage: whether the channel is one and
  /// whether the current user speaks on it.
  bool tokenStage = false;
  bool tokenStageSpeaker = false;

  /// Moderation calls, like `mute:user-2:true` or `move:user-2:ch-stage`.
  final moderation = <String>[];

  /// Rooms asked to follow the database, as `channel:user`.
  final enforced = <String>[];

  /// User limits by channel id, per circle.
  final userLimits = <String, Map<String, int>>{};
  final setLimits = <String, int>{};

  @override
  Future<void> setServerMute({
    required String circleId,
    required String userId,
    required bool muted,
  }) async {
    moderation.add('mute:$userId:$muted');
  }

  @override
  Future<void> setServerDeaf({
    required String circleId,
    required String userId,
    required bool deafened,
  }) async {
    moderation.add('deafen:$userId:$deafened');
  }

  @override
  Future<String?> disconnectMember({
    required String circleId,
    required String userId,
  }) async {
    moderation.add('disconnect:$userId');
    return _channelOf(circleId, userId);
  }

  @override
  Future<String?> moveMember({
    required String circleId,
    required String userId,
    required String channelId,
  }) async {
    moderation.add('move:$userId:$channelId');
    return _channelOf(circleId, userId);
  }

  String? _channelOf(String circleId, String userId) {
    for (final state in states[circleId] ?? const <VoiceMemberState>[]) {
      if (state.userId == userId) {
        return state.channelId;
      }
    }
    return null;
  }

  @override
  Future<void> enforceVoiceState({
    required String channelId,
    required String userId,
  }) async {
    enforced.add('$channelId:$userId');
  }

  @override
  Future<OwnVoiceState> fetchOwnVoiceState() async => ownState;

  @override
  Stream<void> ownVoiceStateChanges() => _changes.stream;

  @override
  Future<Map<String, int>> listUserLimits(String circleId) async {
    return userLimits[circleId] ?? const {};
  }

  @override
  Future<void> setUserLimit({
    required String channelId,
    required int limit,
  }) async {
    setLimits[channelId] = limit;
  }

  @override
  Future<VoiceConnectionDetails> fetchConnectionDetails(
    String channelId,
  ) async {
    tokenRequests.add(channelId);
    final error = tokenError;
    if (error != null) {
      throw error;
    }
    return VoiceConnectionDetails(
      url: 'wss://voice.test',
      token: 'token',
      serverMute: tokenServerMute,
      serverDeaf: tokenServerDeaf,
      stage: tokenStage,
      stageSpeaker: tokenStageSpeaker,
    );
  }

  @override
  Future<void> joinVoiceState(String channelId) async {
    final error = joinError;
    if (error != null) {
      throw error;
    }
    joined.add(channelId);
  }

  @override
  Future<bool> updateVoiceState({
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    updates.add((mute: selfMute, deaf: selfDeaf, video: video, screen: screen));
    return updateResult;
  }

  @override
  Future<void> leaveVoiceState() async {
    leaves++;
  }

  @override
  Future<List<VoiceMemberState>> listVoiceStates(String circleId) async {
    return states[circleId] ?? const [];
  }

  @override
  Stream<void> voiceStateChanges(String circleId) => _changes.stream;

  /// What `list_active_direct_calls` returns.
  List<DirectCall> calls = const [];

  /// Thrown by [startDirectCall], e.g. [VoiceAccessDeniedException].
  Object? startCallError;

  /// What [joinDirectCall] answers (false: the call ended).
  bool rejoinResult = true;

  final startedCalls = <String>[];
  final callTokenRequests = <String>[];
  final rejoinedCalls = <String>[];
  final callUpdates = <String>[];
  final leftCalls = <String>[];
  final declinedCalls = <String>[];

  @override
  Future<String> startDirectCall(String conversationId) async {
    final error = startCallError;
    if (error != null) {
      throw error;
    }
    startedCalls.add(conversationId);
    return 'call-$conversationId';
  }

  @override
  Future<bool> joinDirectCall(String callId) async {
    rejoinedCalls.add(callId);
    return rejoinResult;
  }

  @override
  Future<VoiceConnectionDetails> fetchCallConnectionDetails(
    String callId,
  ) async {
    callTokenRequests.add(callId);
    final error = tokenError;
    if (error != null) {
      throw error;
    }
    return const VoiceConnectionDetails(
      url: 'wss://voice.test',
      token: 'call-token',
    );
  }

  @override
  Future<bool> updateDirectCallState({
    required String callId,
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    callUpdates.add(callId);
    updates.add((mute: selfMute, deaf: selfDeaf, video: video, screen: screen));
    return updateResult;
  }

  @override
  Future<void> leaveDirectCall(String callId) async {
    leftCalls.add(callId);
  }

  @override
  Future<void> declineDirectCall(String callId) async {
    declinedCalls.add(callId);
  }

  @override
  Future<List<DirectCall>> listActiveDirectCalls() async => calls;

  @override
  Stream<void> directCallChanges() => _changes.stream;
}

/// A call whose participants and media flags are set by the test.
class FakeVoiceCall extends ChangeNotifier implements VoiceCall {
  FakeVoiceCall({
    required this.localUserId,
    required this.localName,
    bool microphoneEnabled = true,
  }) : _microphone = microphoneEnabled;

  final String localUserId;
  final String localName;
  bool _microphone;
  bool camera = false;
  String? screenSource;
  bool screen = false;
  bool remoteAudio = true;
  var disconnects = 0;

  /// What the microphone was started or last restarted with.
  VoiceAudioProcessing audio = const VoiceAudioProcessing();

  /// The volumes set for people, by user id.
  Map<String, double> userVolumes = const {};
  final _disconnected = Completer<void>();

  /// Everyone else in the room.
  List<VoiceCallParticipant> remotes = const [];
  bool localSpeaking = false;
  VoiceConnectionQuality connectionQuality = VoiceConnectionQuality.good;
  VoiceNoiseMode mode = VoiceNoiseMode.standard;

  bool get microphone => _microphone;

  /// Simulates the server ending the call.
  void dropConnection() {
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
  }

  void update() => notifyListeners();

  @override
  List<VoiceCallParticipant> get participants => [
    VoiceCallParticipant(
      userId: localUserId,
      name: localName,
      isLocal: true,
      isSpeaking: localSpeaking,
      microphoneEnabled: _microphone,
      cameraEnabled: camera,
      screenShareEnabled: screen,
      cameraView: camera
          ? (context) => const ColoredBox(
              key: ValueKey('fake-local-camera'),
              color: Colors.teal,
            )
          : null,
      screenView: screen
          ? (context) => const ColoredBox(
              key: ValueKey('fake-local-screen'),
              color: Colors.indigo,
            )
          : null,
    ),
    ...remotes,
  ];

  @override
  VoiceConnectionQuality get quality => connectionQuality;

  @override
  VoiceNoiseMode get noiseMode => mode;

  @override
  Future<void> get disconnected => _disconnected.future;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _microphone = enabled;
    notifyListeners();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    camera = enabled;
    notifyListeners();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled, {String? sourceId}) async {
    screen = enabled;
    screenSource = sourceId;
    notifyListeners();
  }

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    remoteAudio = enabled;
    notifyListeners();
  }

  @override
  Future<void> setAudioProcessing(VoiceAudioProcessing audio) async {
    this.audio = audio;
  }

  @override
  Future<void> setUserVolumes(Map<String, double> volumes) async {
    userVolumes = Map.of(volumes);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

class FakeVoiceCallConnector implements VoiceCallConnector {
  FakeVoiceCallConnector({this.localUserId = 'user-1', this.localName = 'Ada'});

  final String localUserId;
  final String localName;
  final calls = <FakeVoiceCall>[];
  Object? error;

  /// Whether the device can run the AI noise filter.
  bool aiNoise = false;

  /// Set before connecting to shape the next call.
  void Function(FakeVoiceCall call)? prepare;

  FakeVoiceCall get last => calls.last;

  @override
  Future<bool> aiNoiseSupported() async => aiNoise;

  @override
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
    VoiceAudioProcessing audio = const VoiceAudioProcessing(),
    Map<String, double> userVolumes = const {},
  }) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    final call = FakeVoiceCall(
      localUserId: localUserId,
      localName: localName,
      microphoneEnabled: microphoneEnabled,
    );
    call
      ..audio = audio
      ..userVolumes = Map.of(userVolumes);
    prepare?.call(call);
    calls.add(call);
    return call;
  }
}

VoiceMemberState voiceMember({
  required String userId,
  required String name,
  String channelId = 'ch-lounge',
  String circleId = 'circle-1',
  bool selfMute = false,
  bool selfDeaf = false,
  bool serverMute = false,
  bool serverDeaf = false,
  bool video = false,
  bool screen = false,
  String? nickname,
  int? roleColor,
  bool stageSpeaker = false,
  bool stageInvited = false,
  DateTime? handRaisedAt,
}) {
  return VoiceMemberState(
    channelId: channelId,
    circleId: circleId,
    userId: userId,
    username: name.toLowerCase().replaceAll(' ', '_'),
    displayName: name,
    nickname: nickname,
    roleColor: roleColor,
    joinedAt: DateTime.utc(2026, 10, 14, 9),
    selfMute: selfMute,
    selfDeaf: selfDeaf,
    serverMute: serverMute,
    serverDeaf: serverDeaf,
    video: video,
    screen: screen,
    stageSpeaker: stageSpeaker,
    stageInvited: stageInvited,
    handRaisedAt: handRaisedAt,
  );
}
