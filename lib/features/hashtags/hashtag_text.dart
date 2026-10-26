/// Reading topics (#话题) out of text.
///
/// The rules are the ones of the database (hashtags_from_text and
/// hashtag_clean, migration 202610280700) and are kept equal by the shared
/// cases in test/fixtures/hashtag_cases.json:
///  * a tag starts with # (or the full-width ＃) that is not glued to a
///    letter, digit, underscore, / & = ? or another hash (so C#, a#b and web
///    addresses like https://x.com/#top are not tags);
///  * it is 1 to 30 characters of letters, digits, underscores and CJK text.
///    Spaces, punctuation (ASCII and CJK), @ and # end it. A longer word is
///    not a tag, and a tag of digits only (#1) is not one;
///  * it is lower-cased, and a text has at most [maxHashtags] of them.
library;

/// The most tags a post carries.
const int maxHashtags = 10;

/// The longest tag, in characters.
const int maxHashtagLength = 30;

/// One tag found in a text: where it is (the # included) and its clean form.
class HashtagSpan {
  const HashtagSpan({
    required this.start,
    required this.end,
    required this.tag,
  });

  /// Index of the # in the text (UTF-16 code units).
  final int start;

  /// Index after the last character of the tag.
  final int end;

  /// The clean, lower-case tag, without the #.
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is HashtagSpan &&
      other.start == start &&
      other.end == end &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(start, end, tag);

  @override
  String toString() => 'HashtagSpan($start, $end, $tag)';
}

bool _isHash(int rune) => rune == 0x23 || rune == 0xFF03;

bool _isTagChar(int r) {
  // White space, no-break and zero-width spaces, line and paragraph breaks,
  // ideographic space and the byte order mark.
  if ((r >= 0x09 && r <= 0x0D) || r == 0x20 || r == 0x85 || r == 0xA0) {
    return false;
  }
  if (r >= 0x200B && r <= 0x200F) return false;
  if (r >= 0x2028 && r <= 0x202F) return false;
  if (r == 0x3000 || r == 0xFEFF) return false;
  // # and ＃ and @.
  if (_isHash(r) || r == 0x40) return false;
  // ASCII punctuation except the underscore.
  if (r >= 0x21 && r <= 0x2F) return false;
  if (r >= 0x3A && r <= 0x40) return false;
  if (r >= 0x5B && r <= 0x5E) return false;
  if (r == 0x60) return false;
  if (r >= 0x7B && r <= 0x7E) return false;
  // The usual CJK punctuation.
  return !_cjkPunctuation.contains(r);
}

final Set<int> _cjkPunctuation = '，。！？、；：“”‘’（）【】《》〈〉「」『』…·～￥'.runes.toSet();

/// Characters that, right before a #, make it part of something else (C#,
/// a#b, an address).
bool _blocksHash(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0x30 && r <= 0x39) ||
    r == 0x5F ||
    r == 0x2F ||
    r == 0x26 ||
    r == 0x3D ||
    r == 0x3F ||
    _isHash(r);

final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// One tag cleaned up: no leading hash, lower case, or null when it is not a
/// valid tag.
String? cleanHashtag(String? input) {
  var tag = (input ?? '').trim().toLowerCase();
  var start = 0;
  while (start < tag.length && _isHash(tag.codeUnitAt(start))) {
    start++;
  }
  tag = tag.substring(start);
  final runes = tag.runes.toList();
  if (runes.isEmpty || runes.length > maxHashtagLength) return null;
  if (!runes.every(_isTagChar)) return null;
  if (_digitsOnly.hasMatch(tag)) return null;
  return tag;
}

/// A list of tags cleaned: invalid ones dropped, repeats folded, the first
/// ones kept ([limit] at most).
List<String> cleanHashtagList(Iterable<String> input, {int limit = 10}) {
  final result = <String>[];
  for (final raw in input) {
    final tag = cleanHashtag(raw);
    if (tag == null || result.contains(tag)) continue;
    result.add(tag);
    if (result.length >= limit) break;
  }
  return result;
}

/// Every tag in [text], with its place, in order. Repeats are kept (every
/// place is a link); use [extractHashtags] for the distinct list.
List<HashtagSpan> hashtagSpans(String? text, {int limit = maxHashtags}) {
  if (text == null || text.isEmpty) return const [];
  if (!text.contains('#') && !text.contains('＃')) return const [];
  final spans = <HashtagSpan>[];
  final distinct = <String>{};
  var i = 0;
  while (i < text.length) {
    final unit = text.codeUnitAt(i);
    if (!_isHash(unit)) {
      i++;
      continue;
    }
    // The character before, which may be the second half of a surrogate pair.
    var blocked = false;
    if (i > 0) {
      var before = text.codeUnitAt(i - 1);
      if (before >= 0xDC00 && before <= 0xDFFF && i > 1) {
        final high = text.codeUnitAt(i - 2);
        if (high >= 0xD800 && high <= 0xDBFF) {
          before = 0x10000 + ((high - 0xD800) << 10) + (before - 0xDC00);
        }
      }
      blocked = _blocksHash(before);
    }
    if (blocked) {
      i++;
      continue;
    }
    var j = i + 1;
    var length = 0;
    while (j < text.length) {
      final rune = _runeAt(text, j);
      if (!_isTagChar(rune)) break;
      j += rune > 0xFFFF ? 2 : 1;
      length++;
    }
    if (length < 1 || length > maxHashtagLength) {
      i = j > i + 1 ? j : i + 1;
      continue;
    }
    final tag = cleanHashtag(text.substring(i + 1, j));
    if (tag != null) {
      if (distinct.add(tag) && distinct.length > limit) {
        break;
      }
      spans.add(HashtagSpan(start: i, end: j, tag: tag));
    }
    i = j;
  }
  return spans;
}

int _runeAt(String text, int index) {
  final unit = text.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
    final low = text.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return unit;
}

/// The distinct tags written in [text], in order (ten at most), the same
/// list the database keeps for a post.
List<String> extractHashtags(String? text) {
  final result = <String>[];
  for (final span in hashtagSpans(text)) {
    if (!result.contains(span.tag)) result.add(span.tag);
    if (result.length >= maxHashtags) break;
  }
  return result;
}
