import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrangler serves the web build as a single-page app', () {
    // JSONC: drop whole-line comments.
    final source = File('wrangler.jsonc')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final config = jsonDecode(source) as Map<String, dynamic>;

    expect(config['name'], 'wecord');
    expect(config['compatibility_date'], matches(RegExp(r'^\d{4}-\d\d-\d\d$')));
    expect(config['assets'], {
      'directory': './build/web',
      'not_found_handling': 'single-page-application',
    });
    expect(config['routes'], [
      {'pattern': 'wecord.jokebear.fyi', 'custom_domain': true},
    ]);
  });

  test('the deploy script builds from .env without printing it', () {
    final script = File('tool/deploy_web.sh').readAsStringSync();

    expect(script, contains('set -eu'));
    expect(script, contains('if [ ! -f .env ]; then'));
    expect(script, contains('exit 1'));
    expect(
      script,
      contains('flutter build web --release --dart-define-from-file=.env'),
    );
    expect(script, contains('npx wrangler deploy'));
    expect(script, isNot(contains('cat .env')));
    expect(script, isNot(contains('source .env')));
    expect(
      script.indexOf('flutter build web'),
      lessThan(script.indexOf('npx wrangler deploy')),
    );

    final ignored = File('.gitignore').readAsLinesSync();
    expect(ignored, containsAll(['.env', '.wrangler/', 'build/']));
  });
}
