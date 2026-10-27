import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L5 (docs/wasm-report.md): the web app compiles with `flutter build web
/// --wasm`, and these checks keep the source in the shape that needs. They
/// cannot compile for wasm themselves; `flutter build web --wasm` is the real
/// test, and the report says how it was run.
void main() {
  final files = [
    for (final root in ['lib', 'tool/web_bench'])
      if (Directory(root).existsSync())
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
  ];

  List<String> offenders(Pattern pattern) => [
    for (final file in files)
      if (file.readAsStringSync().contains(pattern)) file.path,
  ];

  test('no old browser libraries (they do not exist in a wasm build)', () {
    expect(
      offenders(
        RegExp(
          r'''import\s+['"](dart:html|dart:js|dart:js_util|dart:indexed_db|dart:svg|dart:web_audio|dart:web_gl|package:js/[^'"]*)['"]''',
        ),
      ),
      isEmpty,
      reason: 'use package:web with dart:js_interop instead',
    );
  });

  test('conditional imports ask for js_interop, not html', () {
    // `dart.library.html` and `dart.library.js` are false when compiling to
    // wasm, so a conditional import on them silently picks the non-web stub.
    expect(
      offenders(RegExp(r'dart\.library\.(html|js|js_util)\b')),
      isEmpty,
      reason: 'use dart.library.js_interop, which is true in JS and wasm',
    );
  });
}
