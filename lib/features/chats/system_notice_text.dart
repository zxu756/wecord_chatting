import 'package:wecord/shared/l10n/l10n.dart';

// The server writes some chat lines in English, one text for everybody:
//
//   system notices   "Ada pinned a message."   "Ada started a call."
//                    "Ada joined the circle"
//                    "Ada started a call that lasted 1 hour 5 minutes."
//   card bodies      "Contact card: Ada"   "Chat history: Trip"
//                    "📍 Live location"   "☑ Task" and the like
//
// Cards draw themselves from their attachment, but the body is what the
// conversation list and a reply preview show. These helpers put the known
// ones into the reader's language; any other text is returned as it is.

final _pinned = RegExp(r'^(.+) pinned a message\.$');
final _callStarted = RegExp(r'^(.+) started a call\.$');
final _joinedCircle = RegExp(r'^(.+) joined the circle$');
final _callEnded = RegExp(r'^(.+) started a call that lasted (.+)\.$');
final _hours = RegExp(r'(\d+) hours?');
final _minutes = RegExp(r'(\d+) minutes?');

/// [body] of a system notice in the current language.
String systemNoticeText(String body) {
  if (!AppStrings.isChinese) {
    return body;
  }
  if (_pinned.firstMatch(body) case final match?) {
    return tr('{name} pinned a message', {'name': match.group(1)});
  }
  if (_joinedCircle.firstMatch(body) case final match?) {
    return tr('{name} joined the circle', {'name': match.group(1)});
  }
  if (_callStarted.firstMatch(body) case final match?) {
    return tr('{name} started a call', {'name': match.group(1)});
  }
  if (_callEnded.firstMatch(body) case final match?) {
    return tr('{name} started a call that lasted {length}', {
      'name': match.group(1),
      'length': _callLength(match.group(2)!),
    });
  }
  return body;
}

/// "1 hour 5 minutes" or "a few seconds", as the server writes a call's
/// length.
String _callLength(String english) {
  if (english == 'a few seconds') {
    return tr('a few seconds');
  }
  final parts = <String>[
    if (_hours.firstMatch(english) case final hours?)
      tr('{count} hours', {'count': hours.group(1)}),
    if (_minutes.firstMatch(english) case final minutes?)
      tr('{count} minutes', {'count': minutes.group(1)}),
  ];
  return parts.isEmpty ? english : parts.join(' ');
}

/// [body] of a text message that carries a card, in the current language.
String cardBodyText(String body) {
  if (!AppStrings.isChinese) {
    return body;
  }
  if (body == '📍 Live location') {
    return '📍 ${tr('Live location')}';
  }
  if (body == '[Moment]') {
    return '[${tr('Moment')}]';
  }
  for (final (prefix, key) in const [
    ('Contact card: ', 'Contact card: {name}'),
    ('Chat history: ', 'Chat history: {name}'),
  ]) {
    if (body.startsWith(prefix) && body.length > prefix.length) {
      return tr(key, {'name': body.substring(prefix.length)});
    }
  }
  return body
      .replaceAll(RegExp(r' Untitled note$'), ' ${tr('Untitled note')}')
      .replaceAll(RegExp(r' Untitled list$'), ' ${tr('Untitled list')}');
}
