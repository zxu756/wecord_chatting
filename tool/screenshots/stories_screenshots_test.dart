// Renders the Daily (the friends row with rings, watching a friend's daily
// and my own, who viewed, reporting, posting, close friends, a reply in a
// chat and the desktop sidebar) on a phone and a desktop, light and dark,
// with real fonts, and writes PNGs for eyeballing. Not part of `flutter
// test`; run it with:
//
//   flutter test tool/screenshots/stories_screenshots_test.dart \
//     --dart-define=STORIES_DIR=build/stories
//
// Chinese with --dart-define=STORIES_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../test/accessibility/stories_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'STORIES_DIR',
  defaultValue: 'build/stories',
);
const _zh = bool.fromEnvironment('STORIES_ZH');

void main() {
  setUpAll(loadScreenshotFonts);

  for (final dark in [false, true]) {
    for (final screen in storiesA11yScreens) {
      final suffix = dark ? 'dark' : 'light';
      final language = _zh ? '-zh' : '';
      testWidgets('${screen.name} $suffix$language', (tester) async {
        if (screen.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, screen.viewport);
          final world = PhoneWorld()
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          await screen.open(tester, world);
          // The app follows its language setting (English here); switch the
          // strings and rebuild.
          if (_zh) {
            AppStrings.isChinese = true;
            addTearDown(() => AppStrings.isChinese = false);
            await tester.pumpWidget(const SizedBox());
            await screen.open(
              tester,
              PhoneWorld()..themeMode = world.themeMode,
            );
          }
          await settle(tester);
          final renderView = tester.binding.renderViews.first;
          final layer = renderView.debugLayer! as OffsetLayer;
          await tester.runAsync(() async {
            final image = await layer.toImage(renderView.paintBounds);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '$_outputDir/${screen.name}-$suffix$language.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
