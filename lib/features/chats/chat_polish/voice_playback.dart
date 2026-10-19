// What the voice message players share (A10): the speed, which message is
// playing, which have been heard, where each was left, and the hand-over to
// the next one.
//
// Each player ([VoiceMessagePlayer]) owns its audio; this is only what they
// agree on. One message plays at a time: a player that starts tells the
// others to stop. When one ends, the next voice message from someone else
// that has not been played is asked to start (if its player is on screen)
// and so the chat can be listened to like a call-in show, with the speed kept
// from one message to the next.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/shared/models/message.dart';

/// The speeds a voice message can be played at.
const voiceSpeeds = <double>[1, 1.5, 2];

/// "1×", "1.5×", "2×".
String voiceSpeedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.round()}×' : '$speed×';

/// The speed after [speed] when the speed button is pressed: 1, 1.5, 2, 1.
double nextVoiceSpeed(double speed) {
  final index = voiceSpeeds.indexOf(speed);
  return voiceSpeeds[(index + 1) % voiceSpeeds.length];
}

/// The speed voice messages play at, from the speed button; it stays for the
/// next message.
final voicePlaybackSpeedProvider = NotifierProvider<VoicePlaybackSpeed, double>(
  VoicePlaybackSpeed.new,
);

class VoicePlaybackSpeed extends Notifier<double> {
  @override
  double build() => 1;

  void cycle() => state = nextVoiceSpeed(state);
}

/// A player asked to start by the one before it.
class VoiceAutoplayRequest {
  const VoiceAutoplayRequest(this.messageId, this.serial);

  final String messageId;

  /// Makes two requests for the same message different.
  final int serial;
}

class VoicePlayback {
  const VoicePlayback({
    this.playingId,
    this.heard = const {},
    this.positions = const {},
    this.request,
  });

  /// The message being played now, if any.
  final String? playingId;

  /// Messages played to the end (or started) in this session.
  final Set<String> heard;

  /// Where a paused message was left.
  final Map<String, Duration> positions;

  final VoiceAutoplayRequest? request;
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackNotifier, VoicePlayback>(
      VoicePlaybackNotifier.new,
    );

class VoicePlaybackNotifier extends Notifier<VoicePlayback> {
  var _serial = 0;

  @override
  VoicePlayback build() => const VoicePlayback();

  VoicePlayback _with({
    String? playingId,
    bool clearPlaying = false,
    Set<String>? heard,
    Map<String, Duration>? positions,
    VoiceAutoplayRequest? request,
    bool clearRequest = false,
  }) => VoicePlayback(
    playingId: clearPlaying ? null : (playingId ?? state.playingId),
    heard: heard ?? state.heard,
    positions: positions ?? state.positions,
    request: clearRequest ? null : (request ?? state.request),
  );

  /// [messageId] started playing: any other stops, and it counts as heard.
  void started(String messageId) {
    state = _with(
      playingId: messageId,
      heard: {...state.heard, messageId},
      clearRequest: state.request?.messageId == messageId,
    );
  }

  /// [messageId] was paused at [position].
  void paused(String messageId, Duration position) {
    state = _with(
      clearPlaying: state.playingId == messageId,
      positions: {...state.positions, messageId: position},
    );
  }

  /// [messageId] played to the end.
  void finished(String messageId) {
    final positions = {...state.positions}..remove(messageId);
    state = _with(
      clearPlaying: state.playingId == messageId,
      heard: {...state.heard, messageId},
      positions: positions,
    );
  }

  /// Asks the player of [messageId] to start.
  void requestPlay(String messageId) {
    state = _with(request: VoiceAutoplayRequest(messageId, ++_serial));
  }

  /// The request was taken up (or cannot be).
  void clearRequest() {
    if (state.request != null) {
      state = _with(clearRequest: true);
    }
  }
}

/// The first voice message after [afterId] in [messages] (oldest first) that
/// someone else sent and that is not in [heard]; null when there is none.
/// Messages being sent, deleted or in review do not count.
String? nextUnheardVoiceMessageId(
  List<ChatMessage> messages,
  String afterId,
  Set<String> heard, {
  required String? currentUserId,
}) {
  final index = messages.indexWhere((message) => message.id == afterId);
  if (index < 0) {
    return null;
  }
  for (var next = index + 1; next < messages.length; next++) {
    final message = messages[next];
    if (message.type != MessageType.voice ||
        message.recalledAt != null ||
        message.reviewState != null ||
        message.senderId == currentUserId ||
        heard.contains(message.id) ||
        isPendingMessageId(message.id)) {
      continue;
    }
    return message.id;
  }
  return null;
}
