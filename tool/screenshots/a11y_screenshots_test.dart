// Renders the main screens at large text sizes (1.6x, 2.0x), in the dark
// theme and with the platform's "Increase contrast" on, with real fonts,
// and writes PNGs for eyeballing clipped text, overflowing rows and weak
// contrast. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/a11y_screenshots_test.dart \
//     --dart-define=A11Y_SCREENS_DIR=build/a11y
//
// Choose the variants with --dart-define=A11Y_VARIANTS=light:2.0,dark:1.6:hc
// (theme:textScale[:hc], comma separated; the default covers 1.6x and 2.0x
// light, 2.0x dark and 2.0x light with high contrast) and a few screens
// with --dart-define=A11Y_ONLY=home,settings.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/accessibility/a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'A11Y_SCREENS_DIR',
  defaultValue: 'build/a11y',
);
const _variants = String.fromEnvironment(
  'A11Y_VARIANTS',
  defaultValue: 'light:1.6,light:2.0,dark:2.0,light:2.0:hc',
);
const _only = String.fromEnvironment('A11Y_ONLY');

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
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

  final only = _only.isEmpty ? null : _only.split(',').toSet();
  for (final variant in _variants.split(',')) {
    final parts = variant.split(':');
    final dark = parts[0] == 'dark';
    final scale = double.parse(parts[1]);
    final highContrast = parts.length > 2 && parts[2] == 'hc';
    final suffix =
        '${dark ? 'dark' : 'light'}-${parts[1]}x'
        '${highContrast ? '-hc' : ''}';
    for (final screen in allA11yScreens) {
      if (only != null && !only.contains(screen.name)) {
        continue;
      }
      // A screen made for one text size is shot at that size only.
      if (screen.viewport.textScale > 1 && screen.viewport.textScale != scale) {
        continue;
      }
      testWidgets('${screen.name} $suffix', (tester) async {
        if (screen.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          final base = screen.viewport;
          usePhoneViewport(
            tester,
            PhoneViewport(
              name: base.name,
              size: base.size,
              devicePixelRatio: base.devicePixelRatio,
              topInset: base.topInset,
              bottomInset: base.bottomInset,
              textScale: scale,
            ),
          );
          if (highContrast) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(highContrast: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
          }
          final world = PhoneWorld()
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          await screen.open(tester, world);
          await shoot(tester, '${screen.name}-$suffix');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
