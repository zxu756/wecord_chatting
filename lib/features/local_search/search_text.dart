import 'package:wecord/features/search/search_query.dart';

/// [text] folded so that the same words compare equal however they were
/// typed: lower case, and full-width letters, digits and punctuation (as
/// Chinese keyboards often type them) as their ordinary forms. Chinese is
/// matched by the characters themselves: a search for 北京 finds every text
/// holding those two characters in a row, with or without spaces between
/// words, which is what a character-by-character (n-gram) index would find.
String foldSearchText(String text) {
  var plain = true;
  for (final unit in text.codeUnits) {
    if ((unit >= 0xFF01 && unit <= 0xFF5E) || unit == 0x3000) {
      plain = false;
      break;
    }
  }
  if (plain) {
    return text.toLowerCase();
  }
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit >= 0xFF01 && unit <= 0xFF5E) {
      buffer.writeCharCode(unit - 0xFEE0);
    } else if (unit == 0x3000) {
      buffer.writeCharCode(0x20);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString().toLowerCase();
}

/// The bit of a `has:` kind in [IndexedMessage.hasMask].
int hasBit(SearchHas kind) => 1 << kind.index;

/// Which `has:` kinds a cached message row has.
int hasMaskOfRow(Map<String, dynamic> row) {
  var mask = 0;
  final type = row['type'];
  final attachment = row['attachment'];
  final mime = attachment is Map ? attachment['mime_type'] : null;
  final kind = attachment is Map ? attachment['kind'] : null;
  switch (type) {
    case 'image':
      mask |= hasBit(SearchHas.image);
    case 'file':
      mask |=
          kind == 'video' || (mime is String && mime.startsWith('video/'))
          ? hasBit(SearchHas.video)
          : hasBit(SearchHas.file);
    case 'voice':
      mask |= hasBit(SearchHas.voice);
    case 'poll':
      mask |= hasBit(SearchHas.poll);
    case 'sticker':
      mask |= hasBit(SearchHas.sticker);
  }
  final body = row['body'];
  if (body is String &&
      (body.contains('http://') || body.contains('https://'))) {
    mask |= hasBit(SearchHas.link);
  }
  return mask;
}

/// Whether a cached message row is no longer to be shown anywhere offline:
/// deleted (recalled), held back or removed by the circle's AI guard,
/// expired, or a photo or video that can be opened once.
bool rowIsRetired(Map<String, dynamic> row, DateTime now) {
  if (row['recalled_at'] != null || row['review_state'] != null) {
    return true;
  }
  final expires = row['expires_at'];
  if (expires is String) {
    final at = DateTime.tryParse(expires);
    if (at != null && !at.isAfter(now)) {
      return true;
    }
  }
  final attachment = row['attachment'];
  return attachment is Map && attachment['view_once'] == true;
}

/// What a cached message row can be found by: its text, and for a file its
/// name. Null when the message must not be searchable: [rowIsRetired], or
/// without words (system notices, stickers, polls).
String? searchableTextOfRow(Map<String, dynamic> row, DateTime now) {
  if (rowIsRetired(row, now)) {
    return null;
  }
  final attachment = row['attachment'];
  final type = row['type'];
  if (type != 'text' && type != 'image' && type != 'file' && type != 'voice') {
    return null;
  }
  final parts = <String>[];
  final body = row['body'];
  if (body is String && body.trim().isNotEmpty) {
    parts.add(body.trim());
  }
  if (type == 'file' && attachment is Map) {
    final name = attachment['name'];
    if (name is String && name.trim().isNotEmpty) {
      parts.add(name.trim());
    }
  }
  return parts.isEmpty ? null : parts.join('\n');
}
