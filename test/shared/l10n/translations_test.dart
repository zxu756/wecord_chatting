import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/l10n/zh/zh.dart';

/// A tr('…') call found in the source.
typedef TrCall = ({String file, int line, String key, String? problem});

/// Every tr(…) call in [source] whose first argument is a string literal
/// (or adjacent literals), with the literal's value. Calls whose first
/// argument isn't a literal are skipped; interpolation is reported.
List<TrCall> findTrCalls(String file, String source) {
  final calls = <TrCall>[];
  final pattern = RegExp(r'(?<![A-Za-z0-9_$.])tr\(');
  for (final match in pattern.allMatches(source)) {
    // Examples in comments aren't calls.
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    if (source.substring(lineStart, match.start).contains('//')) {
      continue;
    }
    var index = match.end;
    final buffer = StringBuffer();
    String? problem;
    var sawLiteral = false;
    while (true) {
      while (index < source.length && ' \n\r\t'.contains(source[index])) {
        index++;
      }
      if (index >= source.length) {
        break;
      }
      var raw = false;
      if (source[index] == 'r' &&
          index + 1 < source.length &&
          (source[index + 1] == "'" || source[index + 1] == '"')) {
        raw = true;
        index++;
      }
      final quote = source[index];
      if (quote != "'" && quote != '"') {
        break;
      }
      if (source.startsWith(quote * 3, index)) {
        problem ??= 'triple-quoted strings are not supported';
        break;
      }
      sawLiteral = true;
      index++;
      while (index < source.length && source[index] != quote) {
        final char = source[index];
        if (!raw && char == r'\') {
          final next = source[index + 1];
          buffer.write(switch (next) {
            'n' => '\n',
            't' => '\t',
            _ => next,
          });
          index += 2;
          continue;
        }
        if (!raw && char == r'$') {
          problem ??= r'uses $ interpolation; pass {placeholders} instead';
        }
        buffer.write(char);
        index++;
      }
      index++;
    }
    if (!sawLiteral) {
      continue;
    }
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    calls.add((
      file: file,
      line: line,
      key: buffer.toString(),
      problem: problem,
    ));
  }
  return calls;
}

Set<String> placeholdersIn(String text) => {
  for (final match in RegExp(r'\{([A-Za-z0-9_]+)\}').allMatches(text))
    match.group(1)!,
};

List<TrCall> allTrCalls() {
  return [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        ...findTrCalls(entity.path, entity.readAsStringSync()),
  ];
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  test('the scanner reads literals, escapes and adjacent strings', () {
    final calls = findTrCalls('x.dart', r'''
      Text(tr('Save'));
      tr("It's {n} items", {'n': 2});
      tr('Remove {name} from '
          'this circle?', {'name': name});
      tr('Don\'t go');
      tr(label);
      tr('Hi $name');
      _tr('nope');
      // tr('in a comment')
    ''');
    expect(
      [for (final call in calls) call.key],
      [
        'Save',
        "It's {n} items",
        'Remove {name} from this circle?',
        "Don't go",
        r'Hi $name',
      ],
    );
    expect(calls.last.problem, isNotNull);
  });

  test('tr fills placeholders and translates in Chinese', () {
    expect(tr('Language'), 'Language');
    expect(tr('Nothing like this {x}', {'x': 3}), 'Nothing like this 3');
    AppStrings.isChinese = true;
    expect(tr('Language'), '语言');
    expect(tr('Untranslated text'), 'Untranslated text');
  });

  test('the device language decides for System', () {
    expect(
      resolvesToChinese(
        AppLanguage.system,
        deviceLocale: const Locale('zh', 'CN'),
      ),
      isTrue,
    );
    expect(
      resolvesToChinese(AppLanguage.system, deviceLocale: const Locale('en')),
      isFalse,
    );
    expect(resolvesToChinese(AppLanguage.chinese), isTrue);
    expect(resolvesToChinese(AppLanguage.english), isFalse);
  });

  test('every tr() string has a Chinese translation', () {
    final calls = allTrCalls();
    final problems = [
      for (final call in calls)
        if (call.problem != null)
          '${call.file}:${call.line}: ${call.problem}: ${call.key}',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));

    final missing = <String>{
      for (final call in calls)
        if (!zhStrings.containsKey(call.key))
          '${call.file}:${call.line}: ${call.key}',
    };
    expect(
      missing,
      isEmpty,
      reason: 'Missing Chinese for:\n${missing.join('\n')}',
    );
  });

  test('text shared by several areas is translated the same way', () {
    final seen = <String, String>{};
    final conflicts = <String>[];
    for (final area in zhAreas) {
      for (final MapEntry(:key, :value) in area.entries) {
        final previous = seen[key];
        if (previous != null && previous != value) {
          conflicts.add('$key => $previous / $value');
        }
        seen[key] = value;
      }
    }
    expect(conflicts, isEmpty, reason: conflicts.join('\n'));
  });

  test('translations keep their placeholders', () {
    final mismatched = [
      for (final MapEntry(:key, :value) in zhStrings.entries)
        if (value.trim().isEmpty ||
            !_sameSet(placeholdersIn(key), placeholdersIn(value)))
          '$key => $value',
    ];
    expect(mismatched, isEmpty, reason: mismatched.join('\n'));
  });
}

bool _sameSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}
