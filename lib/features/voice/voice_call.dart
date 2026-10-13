import 'package:flutter/widgets.dart';

/// How well the current user's connection to the voice server works.
enum VoiceConnectionQuality { unknown, lost, poor, good, excellent }

/// One person in a connected voice call, as the media connection sees it.
@immutable
class VoiceCallParticipant {
  const VoiceCallParticipant({
    required this.userId,
    required this.name,
    this.isLocal = false,
    this.isSpeaking = false,
    this.microphoneEnabled = false,
    this.cameraEnabled = false,
    this.screenShareEnabled = false,
    this.cameraView,
    this.screenView,
  });

  /// The participant identity, which is their user id.
  final String userId;
  final String name;
  final bool isLocal;
  final bool isSpeaking;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool screenShareEnabled;

  /// Builds the camera video while [cameraEnabled]; null without video.
  final WidgetBuilder? cameraView;

  /// Builds the shared screen while [screenShareEnabled].
  final WidgetBuilder? screenView;
}

/// A live connection to a voice channel's media room.
abstract interface class VoiceCall implements Listenable {
  /// Everyone in the room, the current user first.
  List<VoiceCallParticipant> get participants;

  VoiceConnectionQuality get quality;

  /// Completes when the room disconnects on its own (network loss, kicked
  /// by the server), not after [disconnect].
  Future<void> get disconnected;

  Future<void> setMicrophoneEnabled(bool enabled);

  Future<void> setCameraEnabled(bool enabled);

  /// Starts sharing [sourceId] (a screen or window on desktop; browsers
  /// ask themselves when it is null), or stops sharing.
  Future<void> setScreenShareEnabled(bool enabled, {String? sourceId});

  /// Stops (or resumes) hearing everyone else.
  Future<void> setRemoteAudioEnabled(bool enabled);

  Future<void> disconnect();
}

/// Opens [VoiceCall]s. The app uses LiveKit; tests use fakes.
abstract interface class VoiceCallConnector {
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
  });
}

/// What to share, as picked by the user.
class VoiceScreenSource {
  const VoiceScreenSource({this.sourceId});

  /// A desktop screen or window id; null lets the browser ask.
  final String? sourceId;
}

/// Asks which screen to share; null when cancelled.
typedef VoiceScreenSourcePicker =
    Future<VoiceScreenSource?> Function(BuildContext context);

/// Whether this platform can share its screen: browsers and macOS (iOS
/// would need a Broadcast Extension).
bool voiceScreenShareSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return isWeb || platform == TargetPlatform.macOS;
}
