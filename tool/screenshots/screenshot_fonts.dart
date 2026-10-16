// Fonts for the screenshot tools (see phone_screenshots_test.dart).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

/// Loads Roboto and the Material icons from the Flutter SDK, so text is not
/// drawn as boxes, plus the system emoji font where there is one.
Future<void> loadScreenshotFonts() async {
  final fonts = _materialFontsDir();
  final roboto = FontLoader('Roboto');
  // The test engine doesn't fall back to other fonts, so Chinese shots
  // draw everything with a font that has both Latin and Chinese.
  const unicodeFont = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  if (const bool.fromEnvironment('PHONE_SCREENS_ZH') &&
      File(unicodeFont).existsSync()) {
    roboto.addFont(_fontData(unicodeFont));
  } else {
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
      roboto.addFont(_fontData('${fonts.path}/Roboto-$weight.ttf'));
    }
    roboto.addFont(_fontData('${fonts.path}/Roboto-Italic.ttf'));
  }
  await roboto.load();

  // The app's own font, and a Chinese font under the names the theme falls
  // back to for characters it lacks.
  final jakarta = FontLoader(WeCordTheme.fontFamily)
    ..addFont(
      _fontData('assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf'),
    );
  await jakarta.load();
  final cjkFont = [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    unicodeFont,
  ].where((path) => File(path).existsSync()).firstOrNull;
  const emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
  for (final family in WeCordTheme.fontFamilyFallback) {
    final file = family.contains('Emoji') ? emojiFont : cjkFont;
    if (file != null && File(file).existsSync()) {
      final fallback = FontLoader(family)..addFont(_fontData(file));
      await fallback.load();
    }
  }

  final icons = FontLoader('MaterialIcons')
    ..addFont(_fontData('${fonts.path}/MaterialIcons-Regular.otf'));
  await icons.load();

  // Code blocks ask for "monospace"; borrow a system mono font.
  const monoFont = '/System/Library/Fonts/Supplemental/Courier New.ttf';
  if (File(monoFont).existsSync()) {
    final mono = FontLoader('monospace')..addFont(_fontData(monoFont));
    await mono.load();
  }

  if (File(emojiFont).existsSync()) {
    final emoji = FontLoader('Apple Color Emoji')
      ..addFont(_fontData(emojiFont));
    await emoji.load();
  }
}

Future<ByteData> _fontData(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.sublistView(bytes);
}

Directory _materialFontsDir() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) {
      return dir;
    }
  }
  // flutter_tester lives under bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final candidate = Directory('${dir.path}/material_fonts');
    if (candidate.existsSync()) {
      return candidate;
    }
    dir = dir.parent;
  }
  throw StateError('Could not find the Flutter SDK material fonts.');
}
