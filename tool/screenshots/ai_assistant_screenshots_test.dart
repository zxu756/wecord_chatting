// Renders the WeCord AI assistant (answers in a group chat, the Ask sheet) and
// "Extract to-dos" (picking messages, the review sheet, Make tasks, the group
// owner's switch) on a phone and a desktop, light and dark, with real fonts,
// and writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/ai_assistant_screenshots_test.dart \
//     --dart-define=AI_ASSISTANT_SCREENS_DIR=build/ai-assistant
//
// Chinese with --dart-define=PHONE_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/accessibility/ai_assistant_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'AI_ASSISTANT_SCREENS_DIR',
  defaultValue: 'build/ai-assistant',
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

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
    Future<void> Function(WidgetTester tester, PhoneWorld world) open, {
    bool phoneOnly = false,
  }) {
    for (final variant in _variants) {
      if (phoneOnly && variant.desktop) {
        continue;
      }
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          await open(tester, world);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  final byName = {
    for (final screen in aiAssistantA11yScreens) screen.name: screen.open,
  };
  screen('thread', byName['ai-assistant-thread']!);
  screen('ask-sheet', byName['ai-assistant-ask-sheet']!);
  screen('ask-about-message', byName['ai-assistant-ask-about-message']!);
  screen('extract-selection', byName['extract-selection']!);
  screen('extract-review', byName['extract-review-sheet']!);
  screen('make-tasks', byName['ai-make-tasks-sheet']!);
  screen('group-switch', byName['ai-assistant-group-switch']!);
}
