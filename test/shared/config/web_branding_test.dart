import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Width and height from a PNG file's IHDR chunk.
(int, int) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: '$path is not a PNG');
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  test('the manifest names the app and lists its icons', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['name'], 'WeCord');
    expect(manifest['short_name'], 'WeCord');
    expect(manifest['description'], contains('WeCord'));
    expect(manifest['start_url'], '/');

    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
    expect(icons.map((icon) => icon['purpose']).toSet(), {'any', 'maskable'});
    for (final icon in icons) {
      final size = int.parse((icon['sizes'] as String).split('x').first);
      expect(_pngSize('web/${icon['src']}'), (size, size), reason: '$icon');
    }
  });

  test('the page links the favicons and the Apple touch icon', () {
    final html = File('web/index.html').readAsStringSync();

    expect(html, contains('href="icons/apple-touch-icon.png"'));
    expect(_pngSize('web/icons/apple-touch-icon.png'), (180, 180));
    expect(html, contains('href="favicon.png"'));
    expect(_pngSize('web/favicon.png'), (32, 32));
    expect(html, contains('href="icons/favicon-16.png"'));
    expect(_pngSize('web/icons/favicon-16.png'), (16, 16));
    expect(html, contains('<title>WeCord'));
    expect(File('tool/generate_web_icons.py').existsSync(), isTrue);
  });
}
