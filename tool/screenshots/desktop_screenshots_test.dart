// Renders the desktop shell at 1440x900 with real fonts and writes PNGs,
// for eyeballing the wide layout. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/desktop_screenshots_test.dart \
//     --dart-define=DESKTOP_SCREENS_DIR=/some/output/dir
//
// Without DESKTOP_SCREENS_DIR the PNGs go to build/desktop-screens.
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (the file
// names then end in -dark) and --dart-define=PHONE_SCREENS_ZH=true for
// Chinese (-zh).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/shell/quick_switcher.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'DESKTOP_SCREENS_DIR',
  defaultValue: 'build/desktop-screens',
);

const _suffix =
    '${bool.fromEnvironment('PHONE_SCREENS_DARK') ? '-dark' : '-light'}'
    '${bool.fromEnvironment('PHONE_SCREENS_ZH') ? '-zh' : ''}';

const desktop = PhoneViewport(
  name: '1440x900',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

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
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    testWidgets(name, (tester) async {
      // A desktop platform: pointer hover, Ctrl K hints.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      usePhoneViewport(tester, desktop);
      final world = PhoneWorld();
      await open(tester, world);
      await shoot(tester, name);
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  screen('d1-home-friends', (tester, world) async {
    await world.open(tester, '/home');
  });

  screen('d2-direct-message', (tester, world) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  });

  screen('d3-circle', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });

  screen('d4-notifications', (tester, world) async {
    await world.open(tester, '/notifications');
  });

  screen('d5-quick-switcher', (tester, world) async {
    await world.open(tester, '/home');
    final context = tester.element(find.byKey(const ValueKey('home-search')));
    showQuickSwitcher(context);
  });

  screen('d6-sign-in', (tester, world) async {
    world.auth.user = null;
    await pumpStandalone(tester, world, const AuthScreen());
  });
}
