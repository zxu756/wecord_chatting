import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The LiveKit data topic watching together travels on (E4).
const watchTopic = 'wecord.watch';

/// Longest link accepted, in characters.
const maxWatchUrlChars = 2048;

/// Longest title accepted, in characters.
const maxWatchTitleChars = 80;

/// A packet bigger than this (in bytes) is dropped unread.
const maxWatchPacketBytes = maxWatchUrlChars * 3 + 1024;

/// The longest position a packet may claim (48 hours).
const maxWatchPositionMs = 48 * 60 * 60 * 1000;

/// How far apart this device and the host's position may drift before this
/// device seeks. Bigger gaps are corrected, smaller ones are left alone so
/// the picture does not stutter.
const watchDriftTolerance = Duration(seconds: 1);

/// How often the host repeats where they are.
const watchHeartbeat = Duration(seconds: 4);

/// How long watching goes on without hearing the host before it ends.
const watchHostTimeout = Duration(seconds: 20);

/// The longest a message is assumed to have been on its way. Clocks of two
/// devices differ, so the sender's time is only used within this window.
const watchMaxTransit = Duration(seconds: 2);

// ------------------------------------------------------------------- links --

/// What kind of media a link is, which decides how it plays.
enum WatchLinkKind {
  /// A video file (MP4, MOV, WebM) played by the app.
  video,

  /// An HLS stream (.m3u8) played by the app. Browsers other than Safari
  /// often can not play it.
  hls,

  /// An audio file (MP3, M4A…) played by the app: listening together.
  audio,

  /// Any other web page (YouTube, Bilibili…). It opens in the browser and
  /// can not be kept in step.
  webPage,
}

const _videoExtensions = {'mp4', 'm4v', 'mov', 'webm'};
const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wav',
  'flac',
};

/// A link that passed [parseWatchLink].
@immutable
class WatchLink {
  const WatchLink({required this.uri, required this.kind});

  final Uri uri;
  final WatchLinkKind kind;

  /// The app plays it and keeps everyone's position together.
  bool get synced => kind != WatchLinkKind.webPage;

  bool get isAudio => kind == WatchLinkKind.audio;

  /// The address as it is sent.
  String get text => uri.toString();

  /// A name for it when the host gave none: the file's name, or the site.
  String get fallbackTitle {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    if (synced && segments.isNotEmpty) {
      var raw = segments.last;
      try {
        raw = Uri.decodeComponent(raw);
      } on ArgumentError {
        // Not valid percent-encoding: the name stays as it is.
      }
      final name = tidyWatchTitle(raw);
      if (name.isNotEmpty) {
        return name;
      }
    }
    return uri.host;
  }

  @override
  bool operator ==(Object other) =>
      other is WatchLink && other.uri == uri && other.kind == kind;

  @override
  int get hashCode => Object.hash(uri, kind);
}

/// Why a link was not accepted.
enum WatchLinkProblem {
  empty,

  /// Not a web address.
  invalid,

  /// Only `https` links are accepted.
  notHttps,
  tooLong,

  /// Points at this device or a private network, which no one else can
  /// reach and which should not be probed.
  privateAddress,
}

/// The result of [parseWatchLink]: a [link] or the [problem].
@immutable
class WatchLinkResult {
  const WatchLinkResult.ok(WatchLink this.link) : problem = null;
  const WatchLinkResult.problem(WatchLinkProblem this.problem) : link = null;

  final WatchLink? link;
  final WatchLinkProblem? problem;
}

/// Checks what the person typed or a packet carried: only `https` links to
/// public hosts, no credentials in the address.
WatchLinkResult parseWatchLink(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const WatchLinkResult.problem(WatchLinkProblem.empty);
  }
  if (text.length > maxWatchUrlChars) {
    return const WatchLinkResult.problem(WatchLinkProblem.tooLong);
  }
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return const WatchLinkResult.problem(WatchLinkProblem.invalid);
  }
  if (!uri.hasScheme || uri.host.isEmpty) {
    return const WatchLinkResult.problem(WatchLinkProblem.invalid);
  }
  if (uri.scheme.toLowerCase() != 'https') {
    final scheme = uri.scheme.toLowerCase();
    return WatchLinkResult.problem(
      scheme == 'http' ? WatchLinkProblem.notHttps : WatchLinkProblem.invalid,
    );
  }
  if (uri.userInfo.isNotEmpty) {
    return const WatchLinkResult.problem(WatchLinkProblem.invalid);
  }
  if (_isPrivateHost(uri.host)) {
    return const WatchLinkResult.problem(WatchLinkProblem.privateAddress);
  }
  final normal = uri.removeFragment();
  if (normal.toString().length > maxWatchUrlChars) {
    return const WatchLinkResult.problem(WatchLinkProblem.tooLong);
  }
  return WatchLinkResult.ok(WatchLink(uri: normal, kind: _kindOf(normal)));
}

WatchLinkKind _kindOf(Uri uri) {
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (dot > slash && dot < path.length - 1) {
    final extension = path.substring(dot + 1);
    if (extension == 'm3u8') {
      return WatchLinkKind.hls;
    }
    if (_videoExtensions.contains(extension)) {
      return WatchLinkKind.video;
    }
    if (_audioExtensions.contains(extension)) {
      return WatchLinkKind.audio;
    }
  }
  return WatchLinkKind.webPage;
}

bool _isPrivateHost(String rawHost) {
  final host = rawHost.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.lan') ||
      host.endsWith('.home.arpa')) {
    return true;
  }
  // Any IPv6 address written out: private ranges are not worth sorting
  // from public ones for a movie link.
  if (host.contains(':')) {
    return true;
  }
  final parts = host.split('.');
  final numeric = parts.length == 4 && parts.every(_isDecimalByte);
  if (numeric) {
    final a = int.parse(parts[0]);
    final b = int.parse(parts[1]);
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        a >= 224;
  }
  // A name with no dot is a machine on someone's own network. A host that
  // is all digits and dots in any other way (2130706433, 0x7f.1) is a
  // disguised address.
  if (parts.length < 2) {
    return true;
  }
  if (parts.every((part) => RegExp(r'^(0x[0-9a-f]+|\d+)$').hasMatch(part))) {
    return true;
  }
  return false;
}

bool _isDecimalByte(String part) {
  final value = int.tryParse(part);
  return value != null &&
      value >= 0 &&
      value <= 255 &&
      RegExp(r'^\d{1,3}$').hasMatch(part);
}

// ----------------------------------------------------------------- packets --

/// Why the host sent a [WatchSyncPacket].
enum WatchCause {
  play('play'),
  pause('pause'),
  seek('seek'),

  /// The repeated "this is where I am".
  beat('beat');

  const WatchCause(this.code);

  final String code;

  static WatchCause? byCode(Object? code) {
    for (final cause in values) {
      if (cause.code == code) {
        return cause;
      }
    }
    return null;
  }
}

/// What a data message on [watchTopic] says.
sealed class WatchPacket {
  const WatchPacket();
}

/// The host starts watching [link], or says again what is on (when someone
/// joins, or asks). [id] names this showing, [seq] numbers the host's
/// packets so a late one is not mistaken for a new one, [sentAt] is the
/// host's clock.
class WatchStartPacket extends WatchPacket {
  const WatchStartPacket({
    required this.id,
    required this.link,
    required this.title,
    required this.positionMs,
    required this.playing,
    required this.seq,
    required this.sentAt,
  });

  final String id;
  final WatchLink link;
  final String title;
  final int positionMs;
  final bool playing;
  final int seq;
  final DateTime sentAt;
}

/// The host plays, pauses or seeks, or repeats where they are.
class WatchSyncPacket extends WatchPacket {
  const WatchSyncPacket({
    required this.id,
    required this.cause,
    required this.positionMs,
    required this.playing,
    required this.seq,
    required this.sentAt,
  });

  final String id;
  final WatchCause cause;
  final int positionMs;
  final bool playing;
  final int seq;
  final DateTime sentAt;
}

/// The host stops watching together.
class WatchEndPacket extends WatchPacket {
  const WatchEndPacket({required this.id, required this.seq});

  final String id;
  final int seq;
}

/// Somebody who does not know what is on asks the host to say it again.
class WatchAskPacket extends WatchPacket {
  const WatchAskPacket();
}

List<int> encodeWatchStart({
  required String id,
  required WatchLink link,
  required String title,
  required int positionMs,
  required bool playing,
  required int seq,
  required DateTime sentAt,
}) {
  return utf8.encode(
    jsonEncode({
      'v': 1,
      'k': 's',
      'id': id,
      'u': link.text,
      't': tidyWatchTitle(title),
      'p': positionMs.clamp(0, maxWatchPositionMs),
      'r': playing ? 1 : 0,
      'n': seq,
      'ts': sentAt.millisecondsSinceEpoch,
    }),
  );
}

List<int> encodeWatchSync({
  required String id,
  required WatchCause cause,
  required int positionMs,
  required bool playing,
  required int seq,
  required DateTime sentAt,
}) {
  return utf8.encode(
    jsonEncode({
      'v': 1,
      'k': 'y',
      'id': id,
      'c': cause.code,
      'p': positionMs.clamp(0, maxWatchPositionMs),
      'r': playing ? 1 : 0,
      'n': seq,
      'ts': sentAt.millisecondsSinceEpoch,
    }),
  );
}

List<int> encodeWatchEnd({required String id, required int seq}) =>
    utf8.encode(jsonEncode({'v': 1, 'k': 'e', 'id': id, 'n': seq}));

List<int> encodeWatchAsk() => utf8.encode(jsonEncode({'v': 1, 'k': 'a'}));

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

/// The packet in a received message, or null for anything that is not a
/// well-formed one: wrong version, unknown kind, too big, a link that is not
/// allowed, numbers out of range.
WatchPacket? decodeWatchPacket(List<int> data) {
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
  if (kind == 'a') {
    return const WatchAskPacket();
  }
  final id = decoded['id'];
  final seq = decoded['n'];
  if (id is! String ||
      !_idPattern.hasMatch(id) ||
      seq is! int ||
      seq < 0 ||
      seq > 0x7fffffff) {
    return null;
  }
  if (kind == 'e') {
    return WatchEndPacket(id: id, seq: seq);
  }
  final position = decoded['p'];
  final playing = decoded['r'];
  final sentAt = decoded['ts'];
  if (position is! int ||
      position < 0 ||
      position > maxWatchPositionMs ||
      (playing != 0 && playing != 1) ||
      sentAt is! int) {
    return null;
  }
  final sent = DateTime.fromMillisecondsSinceEpoch(sentAt);
  switch (kind) {
    case 's':
      final url = decoded['u'];
      final title = decoded['t'];
      if (url is! String || title is! String) {
        return null;
      }
      final result = parseWatchLink(url);
      final link = result.link;
      if (link == null) {
        return null;
      }
      return WatchStartPacket(
        id: id,
        link: link,
        title: tidyWatchTitle(title),
        positionMs: position,
        playing: playing == 1,
        seq: seq,
        sentAt: sent,
      );
    case 'y':
      final cause = WatchCause.byCode(decoded['c']);
      if (cause == null) {
        return null;
      }
      return WatchSyncPacket(
        id: id,
        cause: cause,
        positionMs: position,
        playing: playing == 1,
        seq: seq,
        sentAt: sent,
      );
  }
  return null;
}

final _controlChars = RegExp(
  '[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f-\\u009f'
  '\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]',
);

/// A title with control and direction characters removed, spaces folded and
/// cut to [maxWatchTitleChars].
String tidyWatchTitle(String text) {
  final tidy = text
      .replaceAll(_controlChars, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final runes = tidy.runes;
  if (runes.length <= maxWatchTitleChars) {
    return tidy;
  }
  return String.fromCharCodes(runes.take(maxWatchTitleChars)).trim();
}

/// Allows at most [max] packets from one person in any [window]: a flood
/// can not bury a call.
class WatchRateLimits {
  WatchRateLimits({
    this.max = 20,
    this.window = const Duration(seconds: 5),
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

// -------------------------------------------------------------------- sync --

/// How long a message that was sent at [sent] is taken to have been on its
/// way when it arrived at [received]: the difference, kept between zero and
/// [watchMaxTransit]. The two clocks are not the same clock, so a sender's
/// time that is far off counts for nothing.
Duration watchTransit(DateTime sent, DateTime received) {
  final diff = received.difference(sent);
  if (diff.isNegative) {
    return Duration.zero;
  }
  return diff > watchMaxTransit ? watchMaxTransit : diff;
}

/// Where the host is, as far as this device knows: [positionMs] at [at]
/// (this device's clock), moving on while [playing].
@immutable
class WatchAnchor {
  const WatchAnchor({
    required this.positionMs,
    required this.at,
    required this.playing,
  });

  /// The anchor a message from the host sets, when it arrives at [received].
  factory WatchAnchor.fromPacket({
    required int positionMs,
    required bool playing,
    required DateTime sentAt,
    required DateTime received,
  }) {
    final transit = playing ? watchTransit(sentAt, received) : Duration.zero;
    return WatchAnchor(
      positionMs: positionMs,
      at: received.subtract(transit),
      playing: playing,
    );
  }

  final int positionMs;
  final DateTime at;
  final bool playing;

  /// Where the host should be at [now], kept inside the media when its
  /// [durationMs] is known.
  int expectedMs(DateTime now, {int? durationMs}) {
    var position = positionMs;
    if (playing) {
      final elapsed = now.difference(at).inMilliseconds;
      position += elapsed < 0 ? 0 : elapsed;
    }
    if (durationMs != null && durationMs > 0 && position > durationMs) {
      position = durationMs;
    }
    return position < 0 ? 0 : position;
  }
}

/// Whether this device is far enough from the host to seek.
bool watchNeedsSeek({
  required int localMs,
  required int expectedMs,
  Duration tolerance = watchDriftTolerance,
}) {
  return (localMs - expectedMs).abs() > tolerance.inMilliseconds;
}
