import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';

/// The LiveKit data topic Watch Together (E4) travels on. The packets say
/// *what* the room watches and *where* in it: never the media itself.
const watchTopic = 'wecord.watch';

/// No packet is longer than this; longer ones are dropped.
const maxWatchPacketBytes = 2048;

/// How often the host repeats where the playback is while it plays, so a
/// listener who drifts is pulled back and a late joiner is caught up.
const watchPlayingBeat = Duration(seconds: 3);

/// The same while paused (it only keeps late joiners informed).
const watchPausedBeat = Duration(seconds: 10);

/// What a data message on [watchTopic] says.
sealed class WatchPacket {
  const WatchPacket();
}

/// The host starts (or changes) what the room watches, or says it again so
/// someone who just joined catches up: [source] and the playback now.
class WatchStartPacket extends WatchPacket {
  const WatchStartPacket({
    required this.sessionId,
    required this.source,
    required this.title,
    required this.controlOpen,
    required this.position,
    required this.playing,
  });

  final String sessionId;
  final WatchSource source;
  final String title;

  /// Everyone may play, pause and move (not only the host).
  final bool controlOpen;
  final Duration position;
  final bool playing;
}

/// Where the playback is: sent whenever someone who may control plays,
/// pauses or moves, and by the host as a heartbeat.
class WatchStatePacket extends WatchPacket {
  const WatchStatePacket({
    required this.sessionId,
    required this.position,
    required this.playing,
    this.controlOpen,
  });

  final String sessionId;
  final Duration position;
  final bool playing;

  /// Only the host says it; null from anyone else's packet.
  final bool? controlOpen;
}

/// The watching is over.
class WatchStopPacket extends WatchPacket {
  const WatchStopPacket({required this.sessionId});

  final String sessionId;
}

/// Somebody who just joined asks the host to say where things are.
class WatchRequestPacket extends WatchPacket {
  const WatchRequestPacket();
}

enum WatchCueAction { play, pause }

/// "Everyone press play now" or "pause for a moment": for players this
/// device can not control (Bilibili, or YouTube outside the web).
class WatchCuePacket extends WatchPacket {
  const WatchCuePacket({required this.sessionId, required this.action});

  final String sessionId;
  final WatchCueAction action;
}

final _sessionIdPattern = RegExp(r'^[A-Za-z0-9]{6,24}$');

/// The longest position a packet may name (two days).
const _maxPositionMs = 172800000;

List<int> encodeWatchStart(WatchStartPacket packet) => utf8.encode(
  jsonEncode({
    'v': 1,
    'k': 'start',
    'sid': packet.sessionId,
    'src': packet.source.toJson(),
    'ti': tidyWatchTitle(packet.title),
    'o': packet.controlOpen,
    'p': packet.position.inMilliseconds,
    'pl': packet.playing,
  }),
);

List<int> encodeWatchState(WatchStatePacket packet) => utf8.encode(
  jsonEncode({
    'v': 1,
    'k': 'st',
    'sid': packet.sessionId,
    'p': packet.position.inMilliseconds,
    'pl': packet.playing,
    'o': ?packet.controlOpen,
  }),
);

List<int> encodeWatchStop(String sessionId) =>
    utf8.encode(jsonEncode({'v': 1, 'k': 'stop', 'sid': sessionId}));

List<int> encodeWatchRequest() => utf8.encode(jsonEncode({'v': 1, 'k': 'req'}));

List<int> encodeWatchCue(String sessionId, WatchCueAction action) =>
    utf8.encode(
      jsonEncode({'v': 1, 'k': 'cue', 'sid': sessionId, 'a': action.name}),
    );

/// The packet in a received message, or null for anything that is not a
/// well-formed one: wrong version, unknown kind, too big, a source this
/// call may not play (see [WatchSource.fromJson]).
WatchPacket? decodeWatchPacket(
  List<int> data, {
  required String conversationId,
}) {
  if (data.length > maxWatchPacketBytes) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(data));
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['v'] != 1) {
    return null;
  }
  final kind = decoded['k'];
  if (kind == 'req') {
    return const WatchRequestPacket();
  }
  final sid = decoded['sid'];
  if (sid is! String || !_sessionIdPattern.hasMatch(sid)) {
    return null;
  }
  switch (kind) {
    case 'stop':
      return WatchStopPacket(sessionId: sid);
    case 'cue':
      for (final action in WatchCueAction.values) {
        if (action.name == decoded['a']) {
          return WatchCuePacket(sessionId: sid, action: action);
        }
      }
      return null;
    case 'st':
      final position = _position(decoded['p']);
      final playing = decoded['pl'];
      final open = decoded['o'];
      if (position == null ||
          playing is! bool ||
          (open != null && open is! bool)) {
        return null;
      }
      return WatchStatePacket(
        sessionId: sid,
        position: position,
        playing: playing,
        controlOpen: open as bool?,
      );
    case 'start':
      final position = _position(decoded['p']);
      final playing = decoded['pl'];
      final open = decoded['o'];
      final title = decoded['ti'];
      final source = WatchSource.fromJson(
        decoded['src'],
        conversationId: conversationId,
      );
      if (position == null ||
          playing is! bool ||
          open is! bool ||
          title is! String ||
          source == null) {
        return null;
      }
      final tidy = tidyWatchTitle(title);
      return WatchStartPacket(
        sessionId: sid,
        source: source,
        title: tidy.isEmpty ? source.label : tidy,
        controlOpen: open,
        position: position,
        playing: playing,
      );
  }
  return null;
}

Duration? _position(Object? ms) {
  if (ms is! num || ms < 0 || ms > _maxPositionMs) {
    return null;
  }
  return Duration(milliseconds: ms.toInt());
}

/// Allows at most [max] packets from one person in any [window]: a flood of
/// packets can not freeze a call's players.
class WatchRateLimits {
  WatchRateLimits({
    this.max = 30,
    this.window = const Duration(seconds: 4),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int max;
  final Duration window;
  final DateTime Function() _now;
  final _byUser = <String, List<DateTime>>{};

  bool allow(String userId) {
    final now = _now();
    final times = _byUser.putIfAbsent(userId, () => []);
    times.removeWhere((time) => now.difference(time) >= window);
    if (times.length >= max) {
      return false;
    }
    times.add(now);
    return true;
  }

  void clear() => _byUser.clear();
}

/// A new session id: random enough that two hosts starting at once rarely
/// match (and the lower id wins when they do not).
String newWatchSessionId(int Function(int max) nextInt) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return String.fromCharCodes(
    List.generate(12, (_) => alphabet.codeUnitAt(nextInt(alphabet.length))),
  );
}

/// A hint shown to the room after someone's cue.
@immutable
class WatchCueNote {
  const WatchCueNote({
    required this.fromId,
    required this.action,
    required this.at,
  });

  final String fromId;
  final WatchCueAction action;
  final DateTime at;
}
