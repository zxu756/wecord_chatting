import 'package:flutter/foundation.dart';

/// One word or phrase the speech recognizer heard, with where it sits in the
/// video's sound.
@immutable
class SpokenSegment {
  const SpokenSegment({
    required this.start,
    required this.duration,
    required this.text,
  });

  final Duration start;
  final Duration duration;
  final String text;

  Duration get end => start + duration;
}

/// One line of captions, shown from [start] until [end].
@immutable
class CaptionCue {
  const CaptionCue({
    required this.start,
    required this.end,
    required this.text,
  });

  factory CaptionCue.fromJson(Map<String, dynamic> json) {
    return CaptionCue(
      start: Duration(milliseconds: (json['s'] as num).toInt()),
      end: Duration(milliseconds: (json['e'] as num).toInt()),
      text: json['t'] as String,
    );
  }

  final Duration start;
  final Duration end;
  final String text;

  Map<String, Object?> toJson() => {
    's': start.inMilliseconds,
    'e': end.inMilliseconds,
    't': text,
  };
}

/// The captions of a video, made on this device from its sound.
@immutable
class VideoCaptions {
  const VideoCaptions({
    required this.cues,
    required this.savedAt,
    this.locale = '',
  });

  /// Reads captions written by [toJson]; null when [json] is not that.
  static VideoCaptions? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final cues = json['c'];
    if (cues is! List) {
      return null;
    }
    try {
      final at = json['at'];
      return VideoCaptions(
        cues: [
          for (final cue in cues)
            CaptionCue.fromJson(Map<String, dynamic>.from(cue as Map)),
        ],
        locale: json['l'] as String? ?? '',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          at is int ? at : 0,
          isUtc: true,
        ),
      );
    } on Object {
      return null;
    }
  }

  final List<CaptionCue> cues;
  final String locale;
  final DateTime savedAt;

  bool get isEmpty => cues.isEmpty;

  /// The line to show at [position]; null between lines.
  CaptionCue? at(Duration position) {
    // Cues are in order and few hundred at most: a binary search is plenty.
    var low = 0;
    var high = cues.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final cue = cues[middle];
      if (position < cue.start) {
        high = middle - 1;
      } else if (position >= cue.end) {
        low = middle + 1;
      } else {
        return cue;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'c': [for (final cue in cues) cue.toJson()],
    'l': locale,
    'at': savedAt.millisecondsSinceEpoch,
  };
}

/// Longest line of captions, in "units": a Latin letter is one, a Chinese,
/// Japanese or Korean character two (they are about twice as wide).
const captionLineUnits = 40;

/// A pause this long between words starts a new line.
const captionPause = Duration(milliseconds: 900);

/// A finished line stays up this long after its last word, if there is room
/// before the next line.
const captionHold = Duration(milliseconds: 500);

bool _isWide(int rune) =>
    (rune >= 0x2E80 && rune <= 0x9FFF) ||
    (rune >= 0xAC00 && rune <= 0xD7AF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFF00 && rune <= 0xFFEF);

int _units(String text) =>
    text.runes.fold(0, (sum, rune) => sum + (_isWide(rune) ? 2 : 1));

bool _endsSentence(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) {
    return false;
  }
  return '.!?。！？…'.contains(trimmed[trimmed.length - 1]);
}

/// Joins [next] to [text]: with a space between words, none between
/// Chinese, Japanese or Korean characters.
String _join(String text, String next) {
  if (text.isEmpty) {
    return next;
  }
  final last = text.runes.last;
  final first = next.runes.first;
  return _isWide(last) || _isWide(first) ? '$text$next' : '$text $next';
}

/// Groups what the recognizer heard into lines of captions: a new line at a
/// pause, after a sentence that has some length, or when the line would be
/// too long.
List<CaptionCue> cuesFromSegments(
  List<SpokenSegment> segments, {
  int lineUnits = captionLineUnits,
}) {
  final spoken = [
    for (final segment in segments)
      if (segment.text.trim().isNotEmpty)
        SpokenSegment(
          start: segment.start,
          duration: segment.duration,
          text: segment.text.trim(),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final lines = <({Duration start, Duration end, String text})>[];
  Duration? start;
  var end = Duration.zero;
  var text = '';

  void finish() {
    if (start != null && text.isNotEmpty) {
      lines.add((start: start!, end: end, text: text));
    }
    start = null;
    text = '';
  }

  for (final segment in spoken) {
    if (start != null) {
      final gap = segment.start - end;
      final tooLong = _units(_join(text, segment.text)) > lineUnits;
      final sentenceDone = _endsSentence(text) && _units(text) >= 12;
      if (gap >= captionPause || tooLong || sentenceDone) {
        finish();
      }
    }
    start ??= segment.start;
    text = _join(text, segment.text);
    end = segment.end;
  }
  finish();

  return [
    for (final (index, line) in lines.indexed)
      CaptionCue(
        start: line.start,
        end: () {
          final held = line.end + captionHold;
          if (index + 1 < lines.length && held > lines[index + 1].start) {
            return lines[index + 1].start;
          }
          return held;
        }(),
        text: line.text,
      ),
  ];
}
