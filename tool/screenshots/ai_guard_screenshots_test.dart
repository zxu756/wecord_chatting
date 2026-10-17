// Renders the AI guard screens (its setting, the Review queue, the author's
// "Checking…" / "Held for review" line and the moderators' badge) on a phone
// and a desktop, light and dark, with real fonts, and writes PNGs for
// eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/ai_guard_screenshots_test.dart \
//     --dart-define=AI_GUARD_SCREENS_DIR=build/ai-guard
//
// Pick screens with --dart-define=AI_GUARD_ONLY=settings,review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/features/circles/ai_guard_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'AI_GUARD_SCREENS_DIR',
  defaultValue: 'build/ai-guard',
);
const _only = String.fromEnvironment('AI_GUARD_ONLY');

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

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String group,
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _Variant variant,
    )
    open, {
    Map<String, dynamic>? guard,
  }) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          final rpc = FakeGuardRpc()
            ..results['get_circle_ai_guard'] = guard ?? guardJson(enabled: true)
            ..results['count_message_reviews'] = 3
            ..results['list_message_reviews'] = [
              reviewJson(
                body:
                    'FREE crypto giveaway!! Claim 2 BTC now at '
                    'btc-claim.example/win before it ends',
                reason: 'Promotes a giveaway with a suspicious link',
              ),
              reviewJson(
                id: 'message-2',
                state: 'flagged',
                verdict: 'harassment',
                reason: 'Insults another member',
                body: 'Nobody asked for your opinion, you clown.',
              ),
              reviewJson(
                id: 'message-3',
                verdict: 'scam',
                reason: 'Asks for a password',
                body:
                    'Hi, I am from support. Send me your password to keep '
                    'your account safe.',
              ),
            ];
          world.extraOverrides = [
            circleAiGuardRepositoryProvider.overrideWithValue(
              CircleAiGuardRepository(rpc),
            ),
          ];
          await open(tester, world, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  /// Opens the circle menu and taps [item], on the phone sheet or the
  /// desktop panel.
  Future<void> openFromMenu(
    WidgetTester tester,
    PhoneWorld world,
    String item,
  ) async {
    await world.open(tester, '/circles/circle-1');
    await settle(tester);
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    await tester.tap(find.text(item).last);
    await settle(tester);
  }

  screen('settings', 'guard1-settings', (tester, world, variant) async {
    await openFromMenu(tester, world, 'AI guard');
  });

  screen('settings', 'guard2-settings-off', (tester, world, variant) async {
    await openFromMenu(tester, world, 'AI guard');
  }, guard: guardJson());

  screen(
    'settings',
    'guard3-settings-messages-flag',
    (tester, world, variant) async {
      await openFromMenu(tester, world, 'AI guard');
    },
    guard: guardJson(
      enabled: true,
      rule: 'message_count',
      count: 10,
      action: 'flag',
    ),
  );

  screen('settings', 'guard4-settings-ai-off', (tester, world, variant) async {
    await openFromMenu(tester, world, 'AI guard');
  }, guard: guardJson(enabled: true, circleAi: false));

  screen('review', 'guard5-review', (tester, world, variant) async {
    await openFromMenu(tester, world, 'Review');
  });

  screen('menu', 'guard6-circle-home', (tester, world, variant) async {
    await world.open(tester, '/circles/circle-1');
  });

  screen('menu', 'guard7-circle-menu', (tester, world, variant) async {
    await world.open(tester, '/circles/circle-1');
    await settle(tester);
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
  });

  screen('author', 'guard8-author-state', (tester, world, variant) async {
    world.chats.messages = [
      phoneMessage('g1', bart, 'Welcome to the circle!', minutesAgo: 30),
      phoneMessage(
        'g2',
        me,
        'Hi all, happy to join. Anyone playing tonight?',
        minutesAgo: 3,
      ).copyWith(reviewState: MessageReviewState.held),
      phoneMessage(
        'g3',
        me,
        'Any events this week?',
        minutesAgo: 0,
      ).copyWith(reviewState: MessageReviewState.checking),
    ];
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  });
}
