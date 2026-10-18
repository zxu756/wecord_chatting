// Renders privacy permissions 2.0 and new-login alerts (the Privacy & Safety
// groups and pickers, the group invitation and Security cards in
// Notifications, "Not me" and the password sheet) on a phone (390x844) and a
// 1280x800 desktop with real fonts, for eyeballing. Not part of `flutter
// test`; run it with:
//
//   flutter test tool/screenshots/privacy2_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/privacy2
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (file names
// end in -light or -dark) and --dart-define=PHONE_SCREENS_ZH=true for
// Chinese.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/accessibility/privacy2_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/privacy2',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');
const _zh = bool.fromEnvironment('PHONE_SCREENS_ZH');

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '$_outputDir/$name-${_dark ? 'dark' : 'light'}${_zh ? '-zh' : ''}.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final screen in privacy2A11yScreens) {
    testWidgets(screen.name, (tester) async {
      if (screen.desktop) {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      }
      try {
        usePhoneViewport(tester, screen.viewport);
        final world = PhoneWorld();
        await screen.open(tester, world);
        await shoot(
          tester,
          screen.desktop ? screen.name : 'phone-${screen.name}',
        );
        await world.close(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
