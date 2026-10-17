import 'dart:convert';

/// An iCalendar (.ics) file with one event, the format every calendar app
/// imports. Times are written in UTC so each calendar shows them in its own
/// zone.
///
/// [remindMinutesBefore] adds an alarm that long before the start.
String buildIcsCalendar({
  required String uid,
  required String title,
  required DateTime start,
  DateTime? end,
  String? description,
  String? location,
  String? url,
  bool cancelled = false,
  int? remindMinutesBefore,
  String productId = '-//WeCord//Calendar//EN',
  DateTime? now,
}) {
  final endsAt = end ?? start.add(const Duration(hours: 1));
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:$productId',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$uid',
    'DTSTAMP:${icsUtc(now ?? DateTime.now())}',
    'DTSTART:${icsUtc(start)}',
    'DTEND:${icsUtc(endsAt)}',
    'SUMMARY:${icsEscape(title)}',
    if (description != null && description.trim().isNotEmpty)
      'DESCRIPTION:${icsEscape(description.trim())}',
    if (location != null && location.trim().isNotEmpty)
      'LOCATION:${icsEscape(location.trim())}',
    if (url != null && url.trim().isNotEmpty) 'URL:${url.trim()}',
    if (cancelled) 'STATUS:CANCELLED',
    if (remindMinutesBefore != null) ...[
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${icsEscape(title)}',
      'TRIGGER:-PT${remindMinutesBefore}M',
      'END:VALARM',
    ],
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.map(icsFold).join('\r\n')}\r\n';
}

/// `20261020T150000Z`.
String icsUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
      'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

/// Escapes text for a property value (RFC 5545 section 3.3.11).
String icsEscape(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r?\n'), r'\n');
}

/// Folds a line to 75 bytes, continuing on lines that start with a space,
/// without splitting a character.
String icsFold(String line) {
  if (utf8.encode(line).length <= 75) {
    return line;
  }
  final out = StringBuffer();
  var lineBytes = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    // Continuation lines carry the leading space.
    if (lineBytes + size > 75) {
      out.write('\r\n ');
      lineBytes = 1;
    }
    out.write(char);
    lineBytes += size;
  }
  return out.toString();
}

/// A file name for [title]: lowercase letters and digits joined by dashes,
/// keeping Chinese characters.
String calendarFileName(String title) {
  final safe = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9一-鿿]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final clipped = safe.length > 40 ? safe.substring(0, 40) : safe;
  return '${clipped.isEmpty ? 'event' : clipped}.ics';
}
