// Renders the privacy and chat additions (disappearing messages, view-once
// media, devices, polls, double-tap reactions, profile visibility) on a
// phone (390x844) and a 1440x900 desktop with real fonts, for eyeballing.
// Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/privacy_more_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/privacy-more
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (file names
// end in -light or -dark).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/disappearing_messages.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/privacy-more',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');

const _desktop = PhoneViewport(
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
      final file = File('$_outputDir/$name-${_dark ? 'dark' : 'light'}.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// Shoots [name] on the phone and the desktop, as `phone-<name>` and
  /// `desktop-<name>`.
  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world, bool desktop)
    open, {
    bool phone = true,
    bool desktop = true,
  }) {
    if (phone) {
      testWidgets('phone $name', (tester) async {
        usePhoneViewport(tester, notchedPhone);
        final world = PhoneWorld();
        await open(tester, world, false);
        await shoot(tester, 'phone-$name');
      });
    }
    if (desktop) {
      testWidgets('desktop $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, _desktop);
          final world = PhoneWorld();
          await open(tester, world, true);
          await shoot(tester, 'desktop-$name');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(
    WidgetTester tester,
    PhoneWorld world, {
    List<ChatMessage>? messages,
  }) async {
    world.chats.messages = messages ?? richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  // 1. Disappearing messages.
  List<ChatMessage> disappearingMessages() {
    final now = DateTime.now().toUtc();
    return [
      phoneMessage(
        'n1',
        bart,
        'Bartholomew set messages to disappear after 24 hours.',
        minutesAgo: 30,
        type: MessageType.system,
        attachment: const {
          'kind': 'disappearing',
          'seconds': 86400,
          'actor_name': 'Bartholomew',
        },
      ),
      phoneMessage('d1', bart, 'This one is gone by tomorrow.', minutesAgo: 20)
          .copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 40))),
      phoneMessage('d2', me, 'Good, nothing to keep here.', minutesAgo: 10)
          .copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 50))),
      phoneMessage('d3', bart, 'Photos too?', minutesAgo: 3)
          .copyWith(expiresAt: now.add(const Duration(hours: 23, minutes: 57))),
    ];
  }

  List<Override> timerOverrides(int? seconds) => [
    disappearingRepositoryProvider.overrideWithValue(_FixedTimer(seconds)),
  ];

  screen('disappearing-thread', (tester, world, desktop) async {
    world.extraOverrides = timerOverrides(86400);
    await openDirect(tester, world, messages: disappearingMessages());
  });

  screen('disappearing-sheet', (tester, world, desktop) async {
    world.extraOverrides = timerOverrides(604800);
    await openDirect(tester, world, messages: disappearingMessages());
    if (desktop) {
      await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    } else {
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Disappearing messages'));
    }
  });

  // MARKER: more screens
}

class _FixedTimer implements DisappearingRepository {
  _FixedTimer(this.seconds);

  int? seconds;

  @override
  Future<int?> timer(String conversationId) async => seconds;

  @override
  Future<void> setTimer(String conversationId, int? value) async {
    seconds = value;
  }
}
