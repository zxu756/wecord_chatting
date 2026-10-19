// Renders the admin console's Flags, Notices and Feedback tabs, the Official
// cards in Notifications, the Feedback and help page, the "Please update" page
// and the What's new popup on a phone and a desktop, light and dark, with
// real fonts, and writes PNGs for eyeballing. Not part of `flutter test`; run
// it with:
//
//   flutter test tool/screenshots/admin_ops_screenshots_test.dart \
//     --dart-define=ADMIN_OPS_SCREENS_DIR=build/admin_ops
//
// Chinese with --dart-define=PHONE_SCREENS_ZH=true (files end in -zh).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/accessibility/admin_ops_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'ADMIN_OPS_SCREENS_DIR',
  defaultValue: 'build/admin_ops',
);
const _zh = bool.fromEnvironment('PHONE_SCREENS_ZH');

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final screen in adminOpsA11yScreens) {
    for (final dark in const [false, true]) {
      final label = '${screen.name}-${dark ? 'dark' : 'light'}';
      testWidgets(label, (tester) async {
        if (screen.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, screen.viewport);
          final world = PhoneWorld()
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          await screen.open(tester, world);
          await shoot(tester, '$label${_zh ? '-zh' : ''}');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
