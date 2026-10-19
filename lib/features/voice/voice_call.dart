import 'package:flutter/widgets.dart';
import 'package:wecord/features/voice/background/video_background.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';

/// How well the current user's connection to the voice server works.
enum VoiceConnectionQuality { unknown, lost, poor, good, excellent }

/// Which noise suppression a call's microphone uses while the setting is on.
enum VoiceNoiseMode {
  /// What the platform provides (WebRTC / Apple voice processing).
  standard,

  /// LiveKit's AI noise filter (Krisp).
  ai,
}

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
    this.captionsHost = false,
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

  /// The voice server's signed token says this person may turn captions on
  /// (E1). Nobody in the room can fake it; see [captionHostAttribute].
  final bool captionsHost;
}

/// The LiveKit participant attribute (set by the `livekit-token` function,
/// in the signed token) that marks someone who may turn captions on.
const captionHostAttribute = 'cap';

/// A data message someone in the room sent: [senderId] is the identity the
/// voice server vouches for, whatever the message says.
@immutable
class VoiceDataMessage {
  const VoiceDataMessage({
    required this.senderId,
    required this.topic,
    required this.data,
  });

  final String senderId;
  final String topic;
  final List<int> data;
}

/// A live connection to a voice channel's media room.
abstract interface class VoiceCall implements Listenable {
  /// Everyone in the room, the current user first.
  List<VoiceCallParticipant> get participants;

  VoiceConnectionQuality get quality;

  /// The noise suppression in use. It can fall back to
  /// [VoiceNoiseMode.standard] during the call if the AI filter stops
  /// working.
  VoiceNoiseMode get noiseMode;

  /// Completes when the room disconnects on its own (network loss, kicked
  /// by the server), not after [disconnect].
  Future<void> get disconnected;

  /// Reactions other people in the room send. Your own are not repeated
  /// here (the session shows them as it sends them).
  Stream<VoiceReaction> get reactions;

  /// Sends [emoji] (one of [callReactionEmojis]) to everyone in the room.
  Future<void> sendReaction(String emoji);

  /// Data messages other people in the room send, other than reactions
  /// (captions, E1). Your own are not repeated here.
  Stream<VoiceDataMessage> get dataMessages;

  /// Sends [data] to everyone in the room under [topic]. [reliable] false is
  /// for messages that may be lost (a caption still being spoken).
  Future<void> publishData(
    List<int> data, {
    required String topic,
    bool reliable = true,
  });

  Future<void> setMicrophoneEnabled(bool enabled);

  /// Starts or stops the camera. With [VideoBackgroundSupport.inApp] blur on,
  /// throws [BackgroundBlurUnavailable] (and leaves the camera off) when the
  /// blur can't start, rather than send the camera unblurred.
  Future<void> setCameraEnabled(bool enabled);

  /// How the camera's background can be blurred on this device; `none`
  /// hides the option.
  VideoBackgroundSupport get backgroundSupport;

  /// Whether the background is blurred: WeCord's own blur is on, or (with
  /// the system's effect) the user has it on.
  bool get backgroundBlur;

  /// Blurs the camera's background, or stops. For
  /// [VideoBackgroundSupport.inApp]; it applies from the next camera start
  /// when the camera is off. Throws [BackgroundBlurUnavailable] when the
  /// blur can't start.
  Future<void> setBackgroundBlur(bool enabled);

  /// Opens the system's video effects, where the user switches the blur
  /// ([VideoBackgroundSupport.system]).
  Future<void> showSystemVideoEffects();

  /// Starts sharing [sourceId] (a screen or window on desktop; browsers
  /// ask themselves when it is null), or stops sharing.
  Future<void> setScreenShareEnabled(bool enabled, {String? sourceId});

  /// Stops (or resumes) hearing everyone else.
  Future<void> setRemoteAudioEnabled(bool enabled);

  /// Audio only (E6): stops receiving everyone else's camera and screen
  /// share, which saves data on a poor connection, or receives them again.
  /// Applies to people who start video later too. Your own camera is not
  /// affected.
  Future<void> setAudioOnly(bool enabled);

  /// Restarts the microphone with [audio]'s processing.
  Future<void> setAudioProcessing(VoiceAudioProcessing audio);

  /// How loud each other participant plays, by user id: 1 is as sent, up
  /// to 2; missing ids play at 1. Applies to people joining later too.
  Future<void> setUserVolumes(Map<String, double> volumes);

  Future<void> disconnect();
}

/// Opens [VoiceCall]s. The app uses LiveKit; tests use fakes.
abstract interface class VoiceCallConnector {
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
    VoiceAudioProcessing audio = const VoiceAudioProcessing(),
    Map<String, double> userVolumes = const {},
  });

  /// Whether this device (or browser) can run the AI noise filter. Whether
  /// the server allows it is only known once a call connects.
  Future<bool> aiNoiseSupported();
}

/// How the microphone is cleaned up before it is sent, where the platform
/// supports it.
@immutable
class VoiceAudioProcessing {
  const VoiceAudioProcessing({
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.keepMicrophoneOpen = false,
  });

  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;

  /// Keeps capturing while muted, so push to talk starts instantly.
  final bool keepMicrophoneOpen;

  @override
  bool operator ==(Object other) {
    return other is VoiceAudioProcessing &&
        other.noiseSuppression == noiseSuppression &&
        other.echoCancellation == echoCancellation &&
        other.autoGainControl == autoGainControl &&
        other.keepMicrophoneOpen == keepMicrophoneOpen;
  }

  @override
  int get hashCode => Object.hash(
    noiseSuppression,
    echoCancellation,
    autoGainControl,
    keepMicrophoneOpen,
  );
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
