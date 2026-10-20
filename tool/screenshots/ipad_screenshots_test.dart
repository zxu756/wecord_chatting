// Renders the app at iPad sizes with real fonts and writes PNGs, for
// eyeballing the tablet layouts: 1024x1366 portrait (desktop layout from 840
// wide), 1366x1024 landscape, 834x1194 (an iPad Air / 11" Pro in portrait,
// between the phone and desktop layouts) and 507x1366 (a Split View window).
// Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/ipad_screenshots_test.dart \
//     --dart-define=IPAD_SCREENS_DIR=/some/output/dir
//
// Without IPAD_SCREENS_DIR the PNGs go to build/ipad-screens.
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (the file
// names then end in -dark) and --dart-define=PHONE_SCREENS_ZH=true for
// Chinese (-zh).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'IPAD_SCREENS_DIR',
  defaultValue: 'build/ipad-screens',
);

const _suffix =
    '${bool.fromEnvironment('PHONE_SCREENS_DARK') ? '-dark' : '-light'}'
    '${bool.fromEnvironment('PHONE_SCREENS_ZH') ? '-zh' : ''}';

// iPad safe areas: a 24 pt status bar and a 20 pt home indicator.
const _portrait = PhoneViewport(
  name: '1024x1366',
  size: Size(1024, 1366),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);
const _landscape = PhoneViewport(
  name: '1366x1024',
  size: Size(1366, 1024),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);
const _airPortrait = PhoneViewport(
  name: '834x1194',
  size: Size(834, 1194),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);
const _splitView = PhoneViewport(
  name: '507x1366',
  size: Size(507, 1366),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
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
    PhoneViewport viewport,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    testWidgets('$name at $viewport', (tester) async {
      // An iPad: touch first, Cmd shortcuts, trackpad hover.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      usePhoneViewport(tester, viewport);
      final world = PhoneWorld();
      await open(tester, world);
      await shoot(tester, name);
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  Future<void> home(WidgetTester tester, PhoneWorld world) =>
      world.open(tester, '/home');

  Future<void> directMessage(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  Future<void> circle(WidgetTester tester, PhoneWorld world) =>
      world.open(tester, '/circles/circle-1');

  Future<void> settings(WidgetTester tester, PhoneWorld world) =>
      world.open(tester, '/me');

  Future<void> notifications(WidgetTester tester, PhoneWorld world) =>
      world.open(tester, '/notifications');

  for (final (label, viewport) in [
    ('portrait', _portrait),
    ('landscape', _landscape),
    ('air-portrait', _airPortrait),
    ('split-view', _splitView),
  ]) {
    screen('ipad-$label-home', viewport, home);
    screen('ipad-$label-direct-message', viewport, directMessage);
    screen('ipad-$label-circle', viewport, circle);
    screen('ipad-$label-settings', viewport, settings);
    screen('ipad-$label-notifications', viewport, notifications);
  }
}
