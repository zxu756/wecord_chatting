import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Makes what goes into an error report safe to send: no message text, local
/// file names, emails, tokens or other user content. Everything here is a
/// pure function so it can be tested on its own.
///
/// The rule of thumb is to keep what describes the code (a type, a method, a
/// `package:` library, an error code) and to drop whatever could be data.
abstract final class ErrorScrubber {
  static final _jwt = RegExp(
    r'eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.?[A-Za-z0-9_-]*',
  );
  static final _bearer = RegExp(
    r'\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{6,}',
    caseSensitive: false,
  );
  static final _secretAssignment = RegExp(
    r'''\b(api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|password|passwd|authorization|otp|jwt)(["']?\s*[=:]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&)}\]]+)''',
    caseSensitive: false,
  );
  static final _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
  );
  static final _url = RegExp(
    r'''\b([a-zA-Z][a-zA-Z0-9+.\-]*)://([^/\s'")<>?#]*)[^\s'")<>]*''',
  );
  static final _windowsPath = RegExp(r'''\b[A-Za-z]:\\[^\s'")<>]*''');
  static final _unixPath = RegExp(
    r'''(?<![\w:/.\-])(?:/[\w.\-~@+%$ ]*[\w.\-~@+%$]){2,}/?''',
  );
  static final _uuid = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );
  static final _longToken = RegExp(r'\b[A-Za-z0-9+/_\-]{24,}={0,2}');
  static final _phone = RegExp(r'\+?\d[\d ()\-]{7,}\d');
  static final _longNumber = RegExp(r'\d{6,}');
  static final _doubleQuoted = RegExp(r'"[^"\n]*"');
  static final _singleQuoted = RegExp(r"'[^'\n]*'");
  static final _whitespace = RegExp(r'\s+');

  // Dart's own wording around quoted names: these quote code, not data, so
  // they are kept (the rest of a message's quoted text is dropped).
  static final _keepers = <RegExp>[
    RegExp(r"type '([^'\n]{1,80})' is not a subtype of type '([^'\n]{1,80})'"),
    RegExp(
      r"The (?:method|getter|setter) '[A-Za-z_$][\w$]{0,60}' (?:was|were) called on null",
    ),
    RegExp(r"Instance of '[A-Za-z_$][\w$<>?, ]{0,60}'"),
  ];

  static const _placeholder = '\u0000';

  /// The first line of [raw] with data removed, at most [maxLength] long.
  static String message(String raw, {int maxLength = 240}) {
    final line = raw
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return _truncate(_clean(line, quotes: true), maxLength);
  }

  /// Removes tokens, emails, paths and data-like text. With [quotes], quoted
  /// text is dropped too, except Dart's own wording for types and methods.
  /// With [data] false (stack frames, which hold code and not data) only
  /// secrets, emails and places are removed.
  static String _clean(
    String text, {
    required bool quotes,
    bool data = true,
    List<RegExp> keep = const [],
  }) {
    var out = text;
    final kept = <String>[];
    for (final pattern in [if (quotes) ..._keepers, ...keep]) {
      out = out.replaceAllMapped(pattern, (match) {
        kept.add(match.group(0)!);
        return '$_placeholder${kept.length - 1}$_placeholder';
      });
    }
    out = out
        .replaceAll(_jwt, '<token>')
        .replaceAllMapped(_bearer, (m) => '${m.group(1)} <token>')
        .replaceAllMapped(
          _secretAssignment,
          (m) => '${m.group(1)}${m.group(2)}<redacted>',
        )
        .replaceAll(_email, '<email>')
        .replaceAllMapped(_url, (m) {
          final host = m.group(2) ?? '';
          return host.isEmpty ? '<url>' : '${m.group(1)}://$host';
        })
        .replaceAll(_windowsPath, '<path>')
        .replaceAll(_unixPath, '<path>');
    if (data) {
      out = out
          .replaceAll(_uuid, '<id>')
          .replaceAll(_longToken, '<token>')
          .replaceAll(_phone, '<n>')
          .replaceAll(_longNumber, '<n>');
    }
    if (quotes) {
      out = out
          .replaceAll(_doubleQuoted, '"<…>"')
          .replaceAll(_singleQuoted, "'<…>'");
    }
    for (var i = 0; i < kept.length; i++) {
      out = out.replaceAll('$_placeholder$i$_placeholder', kept[i]);
    }
    return out.replaceAll(_whitespace, ' ').trim();
  }

  /// A stack trace safe to send: frames keep their function and a
  /// `package:` or `dart:` library, but never a local path or a file URL,
  /// and the whole is cut to [maxBytes] (UTF-8) on a line boundary.
  static String stack(String raw, {int maxBytes = 8192}) {
    final out = StringBuffer();
    var bytes = 0;
    for (final line in const LineSplitter().convert(raw)) {
      final cleaned = _frame(line);
      if (cleaned.isEmpty) {
        continue;
      }
      final size = utf8.encode(cleaned).length + 1;
      if (bytes + size > maxBytes) {
        break;
      }
      out.writeln(cleaned);
      bytes += size;
    }
    return out.toString().trimRight();
  }

  static final _library = RegExp(r'''(?:package|dart):[^\s)'"]+''');

  static String _frame(String line) {
    if (line.trim().isEmpty) {
      return '';
    }
    // Keep library locations of the app and the SDK; other places (a local
    // file path, a bundle URL) are dropped.
    return _clean(line, quotes: false, data: false, keep: [_library]);
  }

  /// A short, stable name for a problem: the same bug gives the same
  /// fingerprint on every device and build. Digits and line numbers do not
  /// count, so a changed line does not split a bug in two.
  static String fingerprint({
    required String kind,
    required String type,
    required String message,
    String stack = '',
    String discriminator = '',
  }) {
    final frames = <String>[];
    for (final line in const LineSplitter().convert(stack)) {
      final match = RegExp(r'^#\d+\s+(.*?)\s+\(([^)]*)\)\s*$').firstMatch(line);
      if (match == null) {
        continue;
      }
      final location = (match.group(2) ?? '').replaceAll(
        RegExp(r':\d+(:\d+)?$'),
        '',
      );
      frames.add('${match.group(1)}@$location');
      if (frames.length == 5) {
        break;
      }
    }
    final basis = [
      kind,
      type,
      message.replaceAll(RegExp(r'\d+'), 'N'),
      discriminator,
      frames.join('|'),
    ].join('\n');
    return sha1.convert(utf8.encode(basis)).toString().substring(0, 16);
  }

  /// Drops a path to its shape for breadcrumbs and redirects: lowercase
  /// words are kept (`/settings/devices`), anything else (ids, codes, names)
  /// becomes `:id`, and the query string is dropped.
  static String route(String location) {
    final path = location.split('?').first.split('#').first;
    final segments = path.split('/').where((s) => s.isNotEmpty).map((s) {
      return RegExp(r'^[a-z][a-z\-_]{0,23}$').hasMatch(s) ? s : ':id';
    });
    return '/${segments.join('/')}';
  }

  static String _truncate(String text, int maxLength) {
    return text.length <= maxLength
        ? text
        : '${text.substring(0, maxLength - 1)}…';
  }
}
