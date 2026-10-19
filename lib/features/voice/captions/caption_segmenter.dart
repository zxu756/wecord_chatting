import 'package:flutter/foundation.dart';

/// A stretch of what one person says: [isFinal] ones are settled, the others
/// are still being spoken and will be replaced.
@immutable
class CaptionSegment {
  const CaptionSegment(this.text, {required this.isFinal});

  final String text;
  final bool isFinal;

  @override
  bool operator ==(Object other) =>
      other is CaptionSegment && other.text == text && other.isFinal == isFinal;

  @override
  int get hashCode => Object.hash(text, isFinal);

  @override
  String toString() =>
      'CaptionSegment(${isFinal ? 'final' : 'partial'}: $text)';
}

/// Cuts the recognizer's running text into caption lines.
///
/// A speech recognizer reports everything it heard in a session so far, over
/// and over, changing it as it hears more. Captions want short lines that
/// settle: a line is settled when its speaker pauses for [pause], or when it
/// grows past [maxChars] (then it is cut at the last sentence end, comma or
/// space). Words the recognizer later changes inside a settled line are not
/// taken back.
class CaptionSegmenter {
  CaptionSegmenter({
    this.pause = const Duration(milliseconds: 1200),
    this.maxChars = 100,
  });

  final Duration pause;
  final int maxChars;

  var _committed = '';
  var _full = '';
  var _body = '';
  DateTime? _changedAt;

  /// What is being spoken and not settled yet.
  String get pending => _body;

  static final _sentenceEnd = RegExp(r'[。！？.!?；;，,、]');

  /// The recognizer's text for the session so far. Returns the lines that
  /// settled, then the line still in progress (if it changed).
  List<CaptionSegment> hear(String cumulative, DateTime now) {
    _full = cumulative;
    if (!_full.startsWith(_committed)) {
      // The recognizer rewrote words we had settled: keep what still agrees.
      var common = 0;
      final limit = _committed.length < _full.length
          ? _committed.length
          : _full.length;
      while (common < limit && _committed[common] == _full[common]) {
        common++;
      }
      _committed = _committed.substring(0, common);
    }
    final before = _body;
    _body = _full.substring(_committed.length).trim();
    if (_body != before) {
      _changedAt = now;
    }
    final out = <CaptionSegment>[];
    while (_body.runes.length > maxChars) {
      final cut = _cutPoint(_body);
      _settle(cut, out);
    }
    if (_body.isNotEmpty && _body != before) {
      out.add(CaptionSegment(_body, isFinal: false));
    }
    return out;
  }

  /// Call every so often: settles the line in progress once its speaker has
  /// paused.
  List<CaptionSegment> tick(DateTime now) {
    final changed = _changedAt;
    if (_body.isEmpty || changed == null || now.difference(changed) < pause) {
      return const [];
    }
    final out = <CaptionSegment>[];
    _settle(_body.length, out);
    return out;
  }

  /// The recognition session is over: settles what is left and starts clean
  /// for the next session.
  List<CaptionSegment> finish() {
    final out = <CaptionSegment>[];
    if (_body.isNotEmpty) {
      _settle(_body.length, out);
    }
    _committed = '';
    _full = '';
    _body = '';
    _changedAt = null;
    return out;
  }

  /// Forgets everything without settling it.
  void reset() {
    _committed = '';
    _full = '';
    _body = '';
    _changedAt = null;
  }

  /// Settles the first [length] UTF-16 units of the body as a final line.
  void _settle(int length, List<CaptionSegment> out) {
    final piece = _body.substring(0, length).trim();
    final raw = _full.substring(_committed.length);
    final lead = raw.length - raw.trimLeft().length;
    _committed = _full.substring(0, _committed.length + lead + length);
    _body = _full.substring(_committed.length).trim();
    _changedAt = _body.isEmpty ? null : _changedAt;
    if (piece.isNotEmpty) {
      out.add(CaptionSegment(piece, isFinal: true));
    }
  }

  /// Where to cut [text] (longer than [maxChars]): after the last sentence
  /// end or comma in the first [maxChars] characters, else at the last
  /// space, else at [maxChars].
  int _cutPoint(String text) {
    final limit = _unitsFor(text, maxChars);
    final head = text.substring(0, limit);
    var cut = -1;
    for (final match in _sentenceEnd.allMatches(head)) {
      cut = match.end;
    }
    if (cut < limit ~/ 3) {
      final space = head.lastIndexOf(' ');
      cut = space > limit ~/ 3 ? space : limit;
    }
    return cut;
  }

  /// UTF-16 length of the first [runes] characters of [text].
  static int _unitsFor(String text, int runes) {
    var units = 0;
    var count = 0;
    for (final rune in text.runes) {
      if (count >= runes) break;
      units += rune > 0xFFFF ? 2 : 1;
      count++;
    }
    return units;
  }
}
