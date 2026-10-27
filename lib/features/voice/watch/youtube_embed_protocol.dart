import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The origin YouTube's privacy-enhanced embedded player runs on; messages
/// are only sent to and accepted from it.
const youtubeEmbedOrigin = 'https://www.youtube-nocookie.com';

/// The messages YouTube's embedded player speaks with the page around it
/// (`enablejsapi=1`): the same ones its own IFrame API script sends. Kept
/// apart from the web-only code so they can be tested anywhere.
String youtubeListeningMessage() =>
    jsonEncode({'event': 'listening', 'id': 1, 'channel': 'widget'});

/// A command for the player: `playVideo`, `pauseVideo`, `seekTo`, `mute`,
/// `unMute`.
String youtubeCommandMessage(String func, [List<Object?> args = const []]) =>
    jsonEncode({'event': 'command', 'func': func, 'args': args});

/// What the player told the page.
@immutable
class YoutubeInfo {
  const YoutubeInfo({
    this.ready = false,
    this.currentTime,
    this.duration,
    this.playerState,
  });

  /// The player has loaded.
  final bool ready;

  /// Seconds into the video.
  final double? currentTime;
  final double? duration;

  /// -1 not started, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
  final int? playerState;

  static const stateEnded = 0;
  static const statePlaying = 1;
  static const statePaused = 2;
  static const stateBuffering = 3;
}

/// The player's message in [data] (a JSON string), or null when it is not
/// one of the few that matter.
YoutubeInfo? parseYoutubeMessage(Object? data) {
  if (data is! String || data.length > 20000) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  switch (decoded['event']) {
    case 'onReady':
      return const YoutubeInfo(ready: true);
    case 'onStateChange':
      final state = decoded['info'];
      return state is int ? YoutubeInfo(playerState: state) : null;
    case 'infoDelivery' || 'initialDelivery':
      final info = decoded['info'];
      if (info is! Map) {
        return null;
      }
      final time = info['currentTime'];
      final duration = info['duration'];
      final state = info['playerState'];
      if (time == null && duration == null && state == null) {
        return null;
      }
      return YoutubeInfo(
        currentTime: time is num ? time.toDouble() : null,
        duration: duration is num && duration > 0 ? duration.toDouble() : null,
        playerState: state is int ? state : null,
      );
  }
  return null;
}
