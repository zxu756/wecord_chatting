import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/l10n/zh/zh.dart';

/// Guards the Chinese interface against English slipping in.
///
/// translations_test.dart checks the plain `tr('…')` calls. This file covers
/// what that one cannot see:
///  * `trIn('context', '…')`, which looks up `context|…` first;
///  * labels that reach `tr(label)` through a variable (enum fields, tuples);
///  * user-facing text that skips `tr` altogether: `Text('…')`, `tooltip: '…'`,
///    `label: '…'`, `semanticsLabel: '…'` and similar.
///
/// A string that is meant to stay English goes in [_intentionallyEnglish]
/// with the reason, never silently into the source.

/// Brand names, product names, file extensions and the like: shown as-is in
/// every language.
const _intentionallyEnglish = <String>{
  'WeCord',
  'GIF',
  'PNG',
  'JPG',
  'PDF',
  'GIPHY',
  'Powered by GIPHY',
  'Apple Maps',
  'Google Maps',
  'Webhook',
  'AutoMod',
  'TOTP',
  'Markdown',
};

/// A string literal found in a source file.
class _Literal {
  _Literal({
    required this.file,
    required this.line,
    required this.value,
    required this.before,
    required this.interpolated,
  });

  final String file;
  final int line;

  /// The text, with each `$x` / `${…}` replaced by `{}`.
  final String value;

  /// The code between the previous literal (or the file start) and this one.
  final String before;
  final bool interpolated;

  String get where => '$file:$line';
}

/// Every string literal in [source], adjacent literals joined. Comments are
/// skipped; interpolations become `{}`.
List<_Literal> _literals(String file, String source) {
  final result = <_Literal>[];
  var index = 0;
  var lastEnd = 0;
  var line = 1;
  var countedTo = 0;

  int lineAt(int offset) {
    for (var i = countedTo; i < offset; i++) {
      if (source.codeUnitAt(i) == 10) {
        line++;
      }
    }
    countedTo = offset;
    return line;
  }

  while (index < source.length) {
    final char = source[index];
    if (char == '/' && index + 1 < source.length) {
      if (source[index + 1] == '/') {
        final end = source.indexOf('\n', index);
        index = end == -1 ? source.length : end;
        continue;
      }
      if (source[index + 1] == '*') {
        final end = source.indexOf('*/', index + 2);
        index = end == -1 ? source.length : end + 2;
        continue;
      }
    }
    var raw = false;
    var quoteAt = index;
    if (char == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"') &&
        (index == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[index - 1]))) {
      raw = true;
      quoteAt = index + 1;
    }
    if (source[quoteAt] != "'" && source[quoteAt] != '"') {
      index++;
      continue;
    }
    // A (possibly adjacent) literal run.
    final start = index;
    final buffer = StringBuffer();
    var interpolated = false;
    var cursor = quoteAt;
    var isRaw = raw;
    while (true) {
      final read = _readString(source, cursor, isRaw);
      buffer.write(read.value);
      interpolated = interpolated || read.interpolated;
      cursor = read.end;
      var next = cursor;
      while (next < source.length && ' \n\r\t'.contains(source[next])) {
        next++;
      }
      if (next >= source.length) {
        break;
      }
      var nextRaw = false;
      var nextQuote = next;
      if (source[next] == 'r' &&
          next + 1 < source.length &&
          (source[next + 1] == "'" || source[next + 1] == '"')) {
        nextRaw = true;
        nextQuote = next + 1;
      }
      if (source[nextQuote] == "'" || source[nextQuote] == '"') {
        cursor = nextQuote;
        isRaw = nextRaw;
        continue;
      }
      break;
    }
    result.add(
      _Literal(
        file: file,
        line: lineAt(start),
        value: buffer.toString(),
        before: source.substring(lastEnd, start),
        interpolated: interpolated,
      ),
    );
    index = cursor;
    lastEnd = cursor;
  }
  return result;
}

({String value, bool interpolated, int end}) _readString(
  String source,
  int quoteAt,
  bool raw,
) {
  final quote = source[quoteAt];
  final triple = source.startsWith(quote * 3, quoteAt);
  var index = quoteAt + (triple ? 3 : 1);
  final buffer = StringBuffer();
  var interpolated = false;
  while (index < source.length) {
    final char = source[index];
    if (triple ? source.startsWith(quote * 3, index) : char == quote) {
      index += triple ? 3 : 1;
      return (value: buffer.toString(), interpolated: interpolated, end: index);
    }
    if (!raw && char == r'\' && index + 1 < source.length) {
      final next = source[index + 1];
      buffer.write(switch (next) {
        'n' => '\n',
        't' => '\t',
        _ => next,
      });
      index += 2;
      continue;
    }
    if (!raw && char == r'$' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '{') {
        var depth = 0;
        var i = index + 1;
        while (i < source.length) {
          if (source[i] == '{') {
            depth++;
          } else if (source[i] == '}') {
            depth--;
            if (depth == 0) {
              break;
            }
          } else if (source[i] == "'" || source[i] == '"') {
            i = _readString(source, i, false).end - 1;
          }
          i++;
        }
        interpolated = true;
        buffer.write('{}');
        index = i + 1;
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(next)) {
        var i = index + 1;
        while (i < source.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(source[i])) {
          i++;
        }
        interpolated = true;
        buffer.write('{}');
        index = i;
        continue;
      }
    }
    buffer.write(char);
    index++;
  }
  return (value: buffer.toString(), interpolated: interpolated, end: index);
}

List<_Literal> _allLiterals() {
  final all = <_Literal>[];
  final files = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.contains('/l10n/zh/'))
        entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    all.addAll(_literals(file.path, file.readAsStringSync()));
  }
  return all;
}

final _trCall = RegExp(r'(?<![A-Za-z0-9_$.])tr\(\s*$');
final _trInContext = RegExp(r'(?<![A-Za-z0-9_$.])trIn\(\s*$');

/// English that [literal] carries, ignoring placeholders, or null when there
/// is nothing a reader would need translated (punctuation, handles, counts).
bool _hasWords(String text) {
  final stripped = text
      .replaceAll('{}', ' ')
      .replaceAll(RegExp(r'https?://'), ' ');
  return RegExp(r'[A-Za-z]{2}').hasMatch(stripped);
}

void main() {
  test('the scanner joins adjacent literals and skips comments', () {
    final found = _literals('x.dart', r'''
      // tr('in a comment')
      final a = tr('One '
          'two');
      final b = trIn('ctx', 'Three');
      final c = 'Hi $name and ${user.name}';
      final d = r'raw $x';
    ''');
    expect(
      [for (final item in found) item.value],
      [
        'One two',
        'ctx',
        'Three',
        '{}',
        'Hi {} and {}',
        r'raw $x',
      ].where((value) => value != '{}').toList(),
    );
  });

  test('every trIn() string has a Chinese translation', () {
    final missing = <String>{};
    final literals = _allLiterals();
    for (var i = 1; i < literals.length; i++) {
      final literal = literals[i];
      final previous = literals[i - 1];
      if (previous.file != literal.file ||
          !_trInContext.hasMatch(previous.before) ||
          literal.before.trim() != ',') {
        continue;
      }
      // previous is the context, literal is the English.
      final contextual = '${previous.value}|${literal.value}';
      if (!zhStrings.containsKey(contextual) &&
          !zhStrings.containsKey(literal.value)) {
        missing.add('${literal.where}: ${literal.value}');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Missing Chinese for:\n${missing.join('\n')}',
    );
  });

  test('labels passed to tr() through variables are translated', () {
    // Files that call tr(variable) keep the English next to it: enum fields,
    // tuples, maps. Any prose-looking literal in such a file must be a zh key
    // (or a known non-UI string), otherwise the label shows in English.
    final byFile = <String, List<_Literal>>{};
    for (final literal in _allLiterals()) {
      byFile.putIfAbsent(literal.file, () => []).add(literal);
    }
    final dynamicFiles = <String>{
      for (final file in byFile.keys)
        if (!file.endsWith('l10n/l10n.dart') &&
            _dynamicTr.hasMatch(File(file).readAsStringSync()))
          file,
      ..._labelSourceFiles.where(byFile.containsKey),
    };
    expect(dynamicFiles, isNotEmpty);
    final missing = <String>{};
    for (final file in dynamicFiles) {
      final literals = byFile[file]!;
      for (var i = 0; i < literals.length; i++) {
        final literal = literals[i];
        if (literal.interpolated || !_looksLikeLabel(literal.value)) {
          continue;
        }
        if (literal.value.startsWith('Supabase ') ||
            _dynamicLabelIgnored.contains(literal.value) ||
            _intentionallyEnglish.contains(literal.value)) {
          continue;
        }
        // Already inside tr('…') / trIn: covered by the other tests.
        if (_trCall.hasMatch(literal.before) ||
            _trInContext.hasMatch(literal.before) ||
            (i > 0 && _trInContext.hasMatch(literals[i - 1].before))) {
          continue;
        }
        if (!zhStrings.containsKey(literal.value)) {
          missing.add('${literal.where}: ${literal.value}');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Missing Chinese for:\n${missing.join('\n')}',
    );
  });

  test('user-facing text goes through tr()', () {
    final bypasses = <String>{};
    for (final literal in _allLiterals()) {
      if (!_hasWords(literal.value) ||
          _intentionallyEnglish.contains(literal.value)) {
        continue;
      }
      final before = literal.before.trimRight();
      final userFacing = _userFacingBefore.hasMatch(before);
      if (!userFacing) {
        continue;
      }
      // A bare word after `label:` is often an id; prose is what we flag.
      if (!_looksLikeSentence(literal.value)) {
        continue;
      }
      if (_bypassAllowed.contains(literal.value)) {
        continue;
      }
      bypasses.add('${literal.where}: ${literal.value}');
    }
    expect(
      bypasses,
      isEmpty,
      reason:
          'User-facing English that skips tr():\n${bypasses.join('\n')}\n'
          'Wrap it in tr() and add the Chinese in lib/shared/l10n/zh/.',
    );
  });
}

/// A `tr(` call whose first argument is not a literal.
final _dynamicTr = RegExp(r'''(?<![A-Za-z0-9_$.])tr\(\s*(?!r?['"])[A-Za-z_]''');

/// Literals that look like a label or a sentence a reader would see.
bool _looksLikeLabel(String value) =>
    RegExp(
      r'^[A-Z][a-z]+(?:[ \-][A-Za-z\x27,.!?]+)*[.!?…]?$',
    ).hasMatch(value) &&
    value.length > 2;

bool _looksLikeSentence(String value) =>
    RegExp(r'[A-Za-z]{2,}').hasMatch(value.replaceAll('{}', ' '));

/// What comes right before a literal that is shown to the user.
final _userFacingBefore = RegExp(
  r'(?:(?<![A-Za-z0-9_$.])(?:const\s+)?Text\(\s*(?:const\s+)?'
  r'|(?<![A-Za-z0-9_$.])(?:tooltip|label|labelText|hintText|helperText|'
  r'errorText|semanticsLabel|semanticLabel|title|subtitle|message|'
  r'description|hint|placeholder|counterText|prefixText|suffixText|caption|'
  r'buttonLabel|actionLabel|confirmLabel|cancelLabel|emptyTitle|'
  r'emptyMessage|text|body|heading|header|detail|summary|badge|error|content|child)\s*:\s*(?:const\s+)?(?:Text\(\s*(?:const\s+)?)?)$',
);

/// Strings that are not for readers although they sit next to a label.
const _dynamicLabelIgnored = <String>{
  // (Messages starting "Supabase " are thrown when the client is missing;
  // the app always initialises it first, so no reader sees them.)
  // Language names are shown in their own language on purpose.
  'Deutsch',
  'Italiano',
  'Bahasa Indonesia',
  // Server messages the client matches on; shown through errorText().
  'Banned from this circle',
  'Too many',
  'Chain not found',
  'Conversation not found',
};

/// Files whose English labels are handed to tr(variable) in another file.
const _labelSourceFiles = <String>[
  'lib/features/photo_editor/editor_model.dart',
  'lib/features/photo_editor/crop_math.dart',
  'lib/features/discovery/circle_discovery_repository.dart',
  'lib/features/lists/list_models.dart',
  'lib/features/chain/chain_models.dart',
];

/// Prose-looking text next to a label that is not shown as written.
const _bypassAllowed = <String>{
  // The macOS file picker's group name for the sound upload; never displayed.
  'audio',
  // The placeholder row is drawn through noteToSelfTitle().
  'Note to self',
};
