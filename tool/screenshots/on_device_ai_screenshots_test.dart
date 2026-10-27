// Renders Settings → AI → "Prefer on-device AI" on a phone, light and dark,
// with real fonts, and writes PNGs for eyeballing. Not part of `flutter test`;
// run it with:
//
//   flutter test tool/screenshots/on_device_ai_screenshots_test.dart \
//     --dart-define=ON_DEVICE_AI_SCREENS_DIR=build/on-device-ai
//
// Chinese with --dart-define=PHONE_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';

import '../../test/accessibility/on_device_ai_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'ON_DEVICE_AI_SCREENS_DIR',
  defaultValue: 'build/on-device-ai',
);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await settle(tester);
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

  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    for (final dark in const [false, true]) {
      testWidgets('$name ${dark ? 'dark' : 'light'}', (tester) async {
        usePhoneViewport(tester, notchedPhone);
        final world = PhoneWorld()
          ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
        await open(tester, world);
        await shoot(tester, '$name-phone-${dark ? 'dark' : 'light'}');
        await world.close(tester);
      });
    }
  }

  screen('ready', openOnDeviceAiSettings);
  screen(
    'off',
    (tester, world) => openOnDeviceAiSettings(tester, world, prefer: false),
  );
  screen(
    'not-enabled',
    (tester, world) => openOnDeviceAiSettings(
      tester,
      world,
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.notEnabled,
      ),
    ),
  );
  screen(
    'not-eligible',
    (tester, world) => openOnDeviceAiSettings(
      tester,
      world,
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.deviceNotEligible,
      ),
    ),
  );
}
