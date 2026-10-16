// Renders the wide layout's resizable columns and the Density setting with
// real fonts and writes PNGs, at 1440x900 and 1100x800. Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/resizable_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Without PHONE_SCREENS_DIR the PNGs go to build/resizable. Add
// --dart-define=PHONE_SCREENS_DARK=true for the dark theme (file names end
// in -dark instead of -light).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/resizable',
);

const _suffix = bool.fromEnvironment('PHONE_SCREENS_DARK') ? '-dark' : '-light';

const _sizes = [
  PhoneViewport(name: '1440x900', size: Size(1440, 900), devicePixelRatio: 1),
  PhoneViewport(name: '1100x800', size: Size(1100, 800), devicePixelRatio: 1),
];

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
    Future<void> Function(WidgetTester tester, PhoneWorld world) open, {
    PanelLayout? layout,
    WeCordDensity? density,
  }) {
    for (final viewport in _sizes) {
      testWidgets('$name ${viewport.name}', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, viewport);
          final world = PhoneWorld();
          world.panelLayoutStore.layout = layout;
          if (density != null) {
            await world.densityStore.save(density);
          }
          await open(tester, world);
          await shoot(tester, '$name-${viewport.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(WidgetTester tester, PhoneWorld world) async {
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  Future<void> openCircle(WidgetTester tester, PhoneWorld world) =>
      world.open(tester, '/circles/circle-1');

  Future<void> hover(WidgetTester tester, String panel) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(ValueKey('resize-$panel')).first),
    );
    await tester.pump();
  }

  screen('r1-dm-default', openDirect);
  screen(
    'r2-dm-wide-sidebar',
    openDirect,
    layout: const PanelLayout(sidebarWidth: 380, profileWidth: 360),
  );
  screen('r3-dm-hover-divider', (tester, world) async {
    await openDirect(tester, world);
    await hover(tester, 'sidebar');
  });
  screen('r4-circle-default', openCircle);
  screen(
    'r5-circle-members-collapsed',
    openCircle,
    layout: const PanelLayout(membersCollapsed: true),
  );
  screen(
    'r6-circle-wide-sidebar',
    openCircle,
    layout: const PanelLayout(sidebarWidth: 360, membersWidth: 320),
  );
  screen('r7-dm-compact', openDirect, density: WeCordDensity.compact);
  screen('r8-circle-compact', openCircle, density: WeCordDensity.compact);
  screen(
    'r9-circle-comfortable',
    openCircle,
    density: WeCordDensity.comfortable,
  );
  screen('r10-settings-appearance', (tester, world) async {
    await world.open(tester, SettingsScreen.path);
    await tester.tap(find.text('Appearance').first);
  });
}
