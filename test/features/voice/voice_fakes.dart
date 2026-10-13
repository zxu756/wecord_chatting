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

  @override
  Future<VoiceConnectionDetails> fetchConnectionDetails(
    String channelId,
  ) async {
    tokenRequests.add(channelId);
    final error = tokenError;
    if (error != null) {
      throw error;
    }
    return const VoiceConnectionDetails(
      url: 'wss://voice.test',
      token: 'token',
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
  final _disconnected = Completer<void>();

  /// Everyone else in the room.
  List<VoiceCallParticipant> remotes = const [];
  bool localSpeaking = false;
  VoiceConnectionQuality connectionQuality = VoiceConnectionQuality.good;

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

  /// Set before connecting to shape the next call.
  void Function(FakeVoiceCall call)? prepare;

  FakeVoiceCall get last => calls.last;

  @override
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
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
  bool video = false,
  bool screen = false,
  String? nickname,
  int? roleColor,
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
    video: video,
    screen: screen,
  );
}
