// Renders edit history (the tappable "edited" mark and the history sheet) on a
// phone and a desktop, light and dark, with real fonts, and writes PNGs for
// eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/edit_history_screenshots_test.dart \
//     --dart-define=EDIT_HISTORY_SCREENS_DIR=build/edit-history
//
// Chinese with --dart-define=PHONE_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/chats/edit_history/edit_history_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'EDIT_HISTORY_SCREENS_DIR',
  defaultValue: 'build/edit-history',
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

  Future<void> openThread(
    WidgetTester tester,
    PhoneWorld world, {
    bool withHistory = true,
  }) async {
    final now = DateTime.now();
    world.chats.messages = [
      phoneMessage('m0', bart, 'Anyone up for lunch?', minutesAgo: 130),
      phoneMessage(
        'm1',
        me,
        'Lunch at 1pm, the new ramen place',
        minutesAgo: 120,
        editedAt: now.subtract(const Duration(minutes: 40)),
      ),
      phoneMessage('m2', bart, 'Sounds good', minutesAgo: 30),
    ];
    world.extraOverrides = [
      editHistoryOverride(
        FakeEditHistoryRepository({
          if (withHistory)
            'm1': [
              editVersion(
                3,
                'Lunch at 12:30, the new ramen place',
                now.subtract(const Duration(minutes: 75)),
              ),
              editVersion(
                2,
                'Lunch at noon at the ramen place',
                now.subtract(const Duration(minutes: 100)),
              ),
              editVersion(
                1,
                'Lunch today?',
                now.subtract(const Duration(minutes: 120)),
              ),
            ],
        }),
      ),
    ];
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    for (final variant in _variants) {
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

  screen('edited-mark', (tester, world) => openThread(tester, world));

  screen('history-sheet', (tester, world) async {
    await openThread(tester, world);
    await tester.tap(find.byKey(const ValueKey('edited-marker')));
    await settle(tester);
  });

  screen('history-sheet-none-kept', (tester, world) async {
    await openThread(tester, world, withHistory: false);
    await tester.tap(find.byKey(const ValueKey('edited-marker')));
    await settle(tester);
  });

  screen('message-menu', (tester, world) async {
    await openThread(tester, world);
    // Desktop: right-click; phone: long press.
    if (debugDefaultTargetPlatformOverride == TargetPlatform.macOS) {
      await tester.tap(
        find.text('Lunch at 1pm, the new ramen place'),
        buttons: kSecondaryButton,
      );
    } else {
      await tester.longPress(find.text('Lunch at 1pm, the new ramen place'));
    }
    await settle(tester);
  });

  Future<void> openWindow(
    WidgetTester tester,
    PhoneWorld world, {
    bool picker = false,
  }) async {
    await pumpStandalone(
      tester,
      world,
      const CircleSettingsScreen(circleId: 'circle-1'),
      extraOverrides: [editWindowOverride(FakeEditWindowRepository(3600))],
    );
    final row = find.byKey(const ValueKey('circle-edit-window'));
    await tester.dragUntilVisible(
      row,
      find.byType(Scrollable).first,
      const Offset(0, -150),
    );
    await tester.ensureVisible(row);
    await settle(tester);
    if (picker) {
      await tester.tap(row);
      await settle(tester);
    }
  }

  screen('circle-edit-window', (tester, world) => openWindow(tester, world));
  screen(
    'circle-edit-window-picker',
    (tester, world) => openWindow(tester, world, picker: true),
  );
}
