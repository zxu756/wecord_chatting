// Renders the "Share to WeCord" page (phone, iPad and desktop widths) with
// real fonts and writes PNGs, for eyeballing it. Not part of `flutter test`;
// run it with:
//
//   flutter test tool/screenshots/platforms_screenshots_test.dart \
//     --dart-define=PLATFORMS_SCREENS_DIR=/some/output/dir
//
// Without PLATFORMS_SCREENS_DIR the PNGs go to build/platforms. Add
// --dart-define=PHONE_SCREENS_DARK=true for the dark theme (the file names
// then end in -dark) and --dart-define=PHONE_SCREENS_ZH=true for Chinese
// (-zh).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/share_target/shared_content.dart';

import '../../test/features/share_target/share_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PLATFORMS_SCREENS_DIR',
  defaultValue: 'build/platforms',
);

const _suffix =
    '${bool.fromEnvironment('PHONE_SCREENS_DARK') ? '-dark' : '-light'}'
    '${bool.fromEnvironment('PHONE_SCREENS_ZH') ? '-zh' : ''}';

const _desktop = PhoneViewport(
  name: '1440x900',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

const _ipad = PhoneViewport(
  name: '1024x1366',
  size: Size(1024, 1366),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);

SharedContent _shared() {
  return SharedContent(
    title: 'How to make a good cup of tea',
    url: 'https://example.com/tea',
    files: [
      sharedFile('tea-menu.pdf', bytes: List.filled(240000, 0)),
      sharedFile('photo.jpg', mimeType: 'image/jpeg', bytes: [1, 2, 3]),
    ],
    skippedFiles: 2,
  );
}

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name$_suffix.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(
    String name,
    PhoneViewport viewport,
    SharedContent? content, {
    TargetPlatform platform = TargetPlatform.android,
    bool fail = false,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      usePhoneViewport(tester, viewport);
      final world = PhoneWorld()
        ..extraOverrides = shareOverrides(FakeShareTargetGateway(content));
      await world.open(tester, '/share');
      if (fail) {
        world.chats.sendError = StateError('down');
        await tester.tap(find.byKey(const ValueKey('share-target-dm-1')));
        await settle(tester);
      }
      await shoot(tester, name);
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  screen('share-phone', notchedPhone, _shared());
  screen('share-phone-failed', notchedPhone, _shared(), fail: true);
  screen('share-phone-empty', notchedPhone, null);
  screen('share-ipad', _ipad, _shared(), platform: TargetPlatform.iOS);
  screen(
    'share-desktop',
    _desktop,
    _shared(),
    platform: TargetPlatform.windows,
  );
}
