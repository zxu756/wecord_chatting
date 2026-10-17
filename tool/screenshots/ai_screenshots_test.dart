// Renders the AI features (catch-up summary, rewriting in the composer,
// translating a message, the settings and the circle switch) on a phone
// (390x844) and a 1440x900 desktop with real fonts and a fake AI answer,
// for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/ai_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/ai/light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/ai/ai_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/ai/light',
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

FakeAiRepository _fakeAi() {
  return FakeAiRepository()
    ..statusValue = const AiStatus(dailyLimit: 50, used: 12)
    ..summary = const AiSummary(
      text:
          '- Bart asked whether you had read the release notes and said they '
          'are long.\n'
          '- Grace moved the trailhead to the north lot for Saturday.\n'
          '- Still open: who is driving, reply needed before Friday.',
      messageCount: 128,
      summarizedCount: 128,
      firstMessageId: 'm1',
    )
    ..rewritten =
        'Hello! How are you? I wanted to check whether you can '
        'join us on Saturday.'
    ..translated = 'Aussi ceci : le sentier est fermé le samedi.';
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
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      FakeAiRepository ai,
      bool desktop,
    )
    open, {
    bool phone = true,
    bool desktop = true,
  }) {
    PhoneWorld worldWith(FakeAiRepository ai) {
      return PhoneWorld()
        ..extraOverrides = [
          aiRepositoryProvider.overrideWithValue(ai),
          aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
        ];
    }

    if (phone) {
      testWidgets('phone $name', (tester) async {
        usePhoneViewport(tester, notchedPhone);
        final ai = _fakeAi();
        await open(tester, worldWith(ai), ai, false);
        await shoot(tester, 'phone-$name');
      });
    }
    if (desktop) {
      testWidgets('desktop $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, _desktop);
          final ai = _fakeAi();
          await open(tester, worldWith(ai), ai, true);
          await shoot(tester, 'desktop-$name');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openThread(WidgetTester tester, PhoneWorld world) async {
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

  Future<void> openMessageMenu(
    WidgetTester tester,
    String text,
    bool desktop,
  ) async {
    final message = find.textContaining(text, findRichText: true).first;
    if (desktop) {
      await tester.tap(message, buttons: kSecondaryButton);
    } else {
      await tester.longPress(message);
    }
    await settle(tester);
  }

  screen('catch-up-offer', (tester, world, ai, desktop) async {
    await openThread(tester, world);
  });

  screen('catch-up-summary', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await tester.tap(find.byKey(const ValueKey('ai-catch-up-summarize')));
    await settle(tester);
  });

  screen('catch-up-limit-reached', (tester, world, ai, desktop) async {
    ai.error = const AiLimitReachedException(limit: 50, used: 50);
    await openThread(tester, world);
    await tester.tap(find.byKey(const ValueKey('ai-catch-up-summarize')));
    await settle(tester);
  });

  screen('rewrite-actions', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'hey hows it goin, can u come saturday',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
  });

  screen('rewrite-preview', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'hey hows it goin, can u come saturday',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-rewrite-polite')));
    await settle(tester);
  });

  screen('rewrite-translate-languages', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'See you on Saturday!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-rewrite-translate')));
    await settle(tester);
  });

  screen('translate-menu', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await openMessageMenu(tester, 'Also this', desktop);
  });

  screen('translate-result', (tester, world, ai, desktop) async {
    await openThread(tester, world);
    await openMessageMenu(tester, 'Also this', desktop);
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await settle(tester);
  });

  screen('settings-ai', (tester, world, ai, desktop) async {
    await world.open(tester, '/me');
    if (desktop) {
      await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
    } else {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ai-enabled-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await settle(tester);
  });

  screen('settings-ai-not-configured', (tester, world, ai, desktop) async {
    ai.statusError = const AiNotConfiguredException();
    await world.open(tester, '/me');
    if (desktop) {
      await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
    } else {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ai-enabled-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await settle(tester);
  });

  screen('circle-ai-switch', (tester, world, ai, desktop) async {
    await pumpStandalone(
      tester,
      world,
      const CircleSettingsScreen(circleId: 'circle-1'),
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('circle-ai-switch'))),
      alignment: 0.3,
    );
    await settle(tester);
  });
}
