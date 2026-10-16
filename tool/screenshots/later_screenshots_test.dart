// Renders scheduled messages, reminders and saved messages: the schedule
// sheet, the Scheduled list, the reminder sheet, fired reminders in
// Notifications and the Saved page. Writes PNGs for eyeballing. Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/later_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/later/phone-light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=LATER_DESKTOP=true for the 1440x900 desktop.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/later/later_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/later/phone-light',
);
const _desktop = bool.fromEnvironment('LATER_DESKTOP');

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);
const _wide = PhoneViewport(
  name: 'desktop',
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
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = _desktop
          ? TargetPlatform.macOS
          : TargetPlatform.iOS;
      try {
        usePhoneViewport(tester, _desktop ? _wide : _phone);
        await body(tester);
        await shoot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  ScheduledMessage scheduled(
    String id,
    String body,
    Duration after, {
    bool failed = false,
    String? error,
  }) {
    return ScheduledMessage(
      id: id,
      conversationId: 'dm-1',
      body: body,
      sendAt: DateTime.now().add(after).toUtc(),
      status: failed
          ? ScheduledMessageStatus.failed
          : ScheduledMessageStatus.pending,
      lastError: error,
    );
  }

  Future<void> openChat(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    final world = PhoneWorld()..extraOverrides = overrides;
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  FakeScheduledMessagesRepository queue() => FakeScheduledMessagesRepository([
    scheduled(
      's1',
      'Happy birthday, Bart! Hope the trail run goes well.',
      const Duration(hours: 17, minutes: 30),
    ),
    scheduled('s2', 'Standup notes are in the doc', const Duration(days: 2)),
    scheduled(
      's3',
      'Remember the tripod',
      const Duration(minutes: -12),
      failed: true,
      error: 'automod:Spam',
    ),
  ]);

  List<Override> scheduledOverrides(FakeScheduledMessagesRepository queue) => [
    scheduledMessagesRepositoryProvider.overrideWithValue(queue),
  ];

  screen('s1-composer-banner', (tester) async {
    await openChat(tester, overrides: scheduledOverrides(queue()));
    await tester.enterText(find.byType(TextField).last, 'Running a bit late');
    await tester.pump();
  });

  screen('s2-schedule-sheet', (tester) async {
    await openChat(tester, overrides: scheduledOverrides(queue()));
    await tester.enterText(find.byType(TextField).last, 'Running a bit late');
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('composer-send-button')));
    await settle(tester);
  });

  screen('s3-scheduled-list', (tester) async {
    await openChat(tester, overrides: scheduledOverrides(queue()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scheduled-banner')));
    await settle(tester);
  });

  screen('s4-scheduled-edit', (tester) async {
    await openChat(tester, overrides: scheduledOverrides(queue()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scheduled-banner')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('scheduled-edit-s1')));
    await settle(tester);
  });

  MessageReminder reminder(
    String id,
    Duration after, {
    String body = 'Bring the tripod',
    bool available = true,
  }) {
    return MessageReminder(
      id: id,
      conversationId: 'dm-1',
      messageId: available ? 'm-$id' : null,
      remindAt: DateTime.now().add(after).toUtc(),
      senderId: bart.id,
      senderName: available ? bart.displayName : '',
      body: available ? body : '',
      available: available,
    );
  }

  FakeRemindersRepository reminders() => FakeRemindersRepository([
    reminder('r1', const Duration(minutes: -4)),
    reminder(
      'r2',
      const Duration(minutes: -50),
      body: 'The trailhead moved to the north lot, parking is free until 9.',
    ),
    reminder('r3', const Duration(minutes: -120), available: false),
    reminder('r4', const Duration(hours: 3), body: 'Send Grace the photos'),
  ]);

  screen('r1-remind-sheet', (tester) async {
    await openChat(tester);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('message-remind')));
    await settle(tester);
  });

  screen('r2-message-menu', (tester) async {
    await openChat(tester);
    await tester.longPress(
      find.textContaining('Also this', findRichText: true).first,
    );
    await settle(tester);
  });

  screen('r3-notifications-reminders', (tester) async {
    final world = PhoneWorld()
      ..extraOverrides = [
        remindersRepositoryProvider.overrideWithValue(reminders()),
      ];
    await world.open(tester, '/notifications');
    await settle(tester);
  });

  screen('r4-reminders-filter', (tester) async {
    final world = PhoneWorld()
      ..extraOverrides = [
        remindersRepositoryProvider.overrideWithValue(reminders()),
      ];
    await world.open(tester, '/notifications');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('inbox-filter-reminders')));
    await settle(tester);
  });
}
