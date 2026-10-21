// Renders member titles and honors (the Honors page, the member list with
// titles, the title dialog, a channel with titles) on a phone (390x844, or 360x640 with PHONE_SCREENS_NARROW)
// and a 1280x800 desktop with real fonts, for eyeballing. Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/member_honors_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/member_honors
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (file names
// end in -light or -dark), --dart-define=PHONE_SCREENS_ZH=true for Chinese
// and --dart-define=PHONE_SCREENS_SCALE=2.0 for large text.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/accessibility/member_honors_a11y_screens.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/member_honors',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');
const _zh = bool.fromEnvironment('PHONE_SCREENS_ZH');
const _narrow = bool.fromEnvironment('PHONE_SCREENS_NARROW');
final _scale = double.parse(
  const String.fromEnvironment('PHONE_SCREENS_SCALE', defaultValue: '1'),
);
const _only = String.fromEnvironment('PHONE_SCREENS_ONLY');

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
        '$_outputDir/$name-${_dark ? 'dark' : 'light'}'
        '${_zh ? '-zh' : ''}${_narrow ? '-narrow' : ''}'
        '${_scale == 1 ? '' : '-${_scale}x'}.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final only = _only.isEmpty ? null : _only.split(',').toSet();
  for (final screen in memberHonorsA11yScreens) {
    if (only != null && !only.contains(screen.name)) {
      continue;
    }
    // A narrow phone is only about the phone screens.
    if (_narrow && screen.desktop) {
      continue;
    }
    testWidgets(screen.name, (tester) async {
      if (screen.desktop) {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      }
      try {
        final base = _narrow && !screen.desktop ? smallPhone : screen.viewport;
        usePhoneViewport(
          tester,
          PhoneViewport(
            name: base.name,
            size: base.size,
            devicePixelRatio: base.devicePixelRatio,
            topInset: base.topInset,
            bottomInset: base.bottomInset,
            textScale: _scale,
          ),
        );
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
