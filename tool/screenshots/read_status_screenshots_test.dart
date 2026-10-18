// Renders the group read list ("N read", the list sheet, "Remind unread"),
// the read receipts switch and the "Reminder" card on a phone and a desktop,
// light and dark, with real fonts, and writes PNGs for eyeballing. Not part
// of `flutter test`; run it with:
//
//   flutter test tool/screenshots/read_status_screenshots_test.dart \
//     --dart-define=READ_STATUS_SCREENS_DIR=build/read-status
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
import 'package:wecord/features/chats/read_status/read_reminder_notices.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/accessibility/read_status_a11y_screens.dart';
import '../../test/features/chats/read_status/read_status_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'READ_STATUS_SCREENS_DIR',
  defaultValue: 'build/read-status',
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

  Future<void> openGroup(
    WidgetTester tester,
    PhoneWorld world, {
    bool reminded = false,
    ReadStatusProblem? listProblem,
  }) async {
    readStatusWorld(world, reminded: reminded, listProblem: listProblem);
    await world.open(
      tester,
      '${ChatsScreen.path}/group-1',
      extra: ChatThreadRouteExtra(
        title: groupDetail.title,
        type: ConversationType.group,
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

  screen('group-read-count', (tester, world) => openGroup(tester, world));

  screen('message-menu', (tester, world) async {
    await openGroup(tester, world);
    final message = find.text(
      'Meet at the north lot at 7:30. Bring layers and water, please.',
    );
    if (debugDefaultTargetPlatformOverride == TargetPlatform.macOS) {
      await tester.tap(message, buttons: kSecondaryButton);
    } else {
      await tester.longPress(message);
    }
    await settle(tester);
  });

  screen('read-status-sheet', (tester, world) async {
    await openGroup(tester, world);
    await tester.tap(find.byKey(const ValueKey('group-read-count')));
    await settle(tester);
  });

  screen('read-status-sheet-unread-tab', (tester, world) async {
    await openGroup(tester, world);
    await tester.tap(find.byKey(const ValueKey('group-read-count')));
    await settle(tester);
    final tab = find.byKey(const ValueKey('read-status-tab-unread'));
    if (tab.evaluate().isNotEmpty) {
      await tester.tap(tab);
      await settle(tester);
    }
  });

  screen('read-status-sheet-reminded', (tester, world) async {
    await openGroup(tester, world, reminded: true);
    await tester.tap(find.byKey(const ValueKey('group-read-count')));
    await settle(tester);
  });

  screen('read-status-receipts-off', (tester, world) async {
    await openGroup(tester, world, listProblem: ReadStatusProblem.receiptsOff);
    await tester.tap(find.byKey(const ValueKey('group-read-count')));
    await settle(tester);
  });

  screen('privacy-read-receipts', (tester, world) async {
    readStatusWorld(world);
    await world.open(tester, '/me');
    if (debugDefaultTargetPlatformOverride == TargetPlatform.macOS) {
      await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
      await settle(tester);
    }
    final row = find.byKey(const ValueKey('read-receipts-row'));
    await scrollIntoView(tester, row);
  });

  screen('notifications-read-reminder', (tester, world) async {
    readStatusWorld(world);
    world.extraOverrides = [
      ...world.extraOverrides,
      readReminderNoticesRepositoryProvider.overrideWithValue(
        FakeReadReminderNoticesRepository([
          ReadReminderNotice(
            id: 'n1',
            messageId: 'g1',
            conversationId: 'group-1',
            senderName: bart.displayName,
            body:
                'Meet at the north lot at 7:30. Bring layers and water, please.',
            type: MessageType.text,
            createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
          ),
        ]),
      ),
    ];
    await world.open(tester, '/notifications');
    final chip = find.byKey(const ValueKey('inbox-filter-reminders'));
    await tester.ensureVisible(chip);
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
  });
}
