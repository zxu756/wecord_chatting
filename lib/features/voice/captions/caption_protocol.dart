import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The LiveKit data topic captions travel on (E1).
const captionTopic = 'wecord.caption';

/// The most characters one caption line carries. Longer ones are cut by the
/// sender and dropped by the receiver.
const maxCaptionChars = 400;

/// What a data message on [captionTopic] says.
sealed class CaptionPacket {
  const CaptionPacket();
}

/// Someone who may turn captions on says they are on ([on]) or off. Sent
/// again every [captionHeartbeat] and when people join, so late joiners see
/// it.
class CaptionControl extends CaptionPacket {
  const CaptionControl({required this.on});

  final bool on;
}

/// A line one person said, as their own device heard it. [id] numbers the
/// speaker's lines: a partial line is replaced by the next packet with the
/// same id, a [final] one settles it. [at] is when the sender heard it.
class CaptionLinePacket extends CaptionPacket {
  const CaptionLinePacket({
    required this.id,
    required this.text,
    required this.at,
    required this.isFinal,
  });

  final int id;
  final String text;
  final DateTime at;
  final bool isFinal;
}

/// The sender's device can not make captions (no speech recognition for the
/// language, or not allowed to listen), or can again ([supported]).
class CaptionSupportPacket extends CaptionPacket {
  const CaptionSupportPacket({required this.supported});

  final bool supported;
}

/// How often whoever turned captions on repeats it.
const captionHeartbeat = Duration(seconds: 20);

/// How long captions stay on without hearing the host again.
const captionHostTimeout = Duration(seconds: 75);

List<int> encodeCaptionControl({required bool on}) =>
    utf8.encode(jsonEncode({'v': 1, 'k': on ? 'on' : 'off'}));

List<int> encodeCaptionSupport({required bool supported}) =>
    utf8.encode(jsonEncode({'v': 1, 'k': supported ? 'ok' : 'no'}));

List<int> encodeCaptionLine({
  required int id,
  required String text,
  required DateTime at,
  required bool isFinal,
}) {
  final chars = text.runes.take(maxCaptionChars);
  return utf8.encode(
    jsonEncode({
      'v': 1,
      'k': isFinal ? 'f' : 'p',
      'i': id,
      't': String.fromCharCodes(chars),
      'ts': at.millisecondsSinceEpoch,
    }),
  );
}

/// The packet in a received message, or null for anything that is not a
/// well-formed one: wrong version, unknown kind, too big, no text.
CaptionPacket? decodeCaptionPacket(List<int> data) {
  if (data.length > maxCaptionChars * 4 + 200) {
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
  switch (decoded['k']) {
    case 'on':
      return const CaptionControl(on: true);
    case 'off':
      return const CaptionControl(on: false);
    case 'ok':
      return const CaptionSupportPacket(supported: true);
    case 'no':
      return const CaptionSupportPacket(supported: false);
    case final String kind when kind == 'p' || kind == 'f':
      final id = decoded['i'];
      final text = decoded['t'];
      final at = decoded['ts'];
      if (id is! int || id < 0 || text is! String || at is! int) {
        return null;
      }
      final tidy = _tidy(text);
      if (tidy.isEmpty || tidy.runes.length > maxCaptionChars) {
        return null;
      }
      return CaptionLinePacket(
        id: id,
        text: tidy,
        at: DateTime.fromMillisecondsSinceEpoch(at),
        isFinal: kind == 'f',
      );
  }
  return null;
}

final _controlChars = RegExp(
  '[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f-\\u009f'
  '\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]',
);

String _tidy(String text) =>
    text.replaceAll(_controlChars, '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Allows at most [max] packets from one person in any [window]: a flood of
/// captions can not bury a call.
class CaptionRateLimits {
  CaptionRateLimits({
    this.max = 24,
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

/// A line of the call's transcript.
@immutable
class CaptionLine {
  const CaptionLine({
    required this.speakerId,
    required this.id,
    required this.text,
    required this.at,
    this.isFinal = true,
  });

  final String speakerId;
  final int id;
  final String text;
  final DateTime at;
  final bool isFinal;

  CaptionLine copyWith({String? text, DateTime? at, bool? isFinal}) {
    return CaptionLine(
      speakerId: speakerId,
      id: id,
      text: text ?? this.text,
      at: at ?? this.at,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}

/// A sender's own clock decides little: the time of a line is when the
/// receiver got it, unless the sender's time is a few seconds earlier (the
/// recognizer hears a sentence before it is final).
DateTime clampCaptionTime(DateTime sent, DateTime received) {
  if (sent.isAfter(received)) {
    return received;
  }
  final earliest = received.subtract(const Duration(seconds: 30));
  return sent.isBefore(earliest) ? earliest : sent;
}
