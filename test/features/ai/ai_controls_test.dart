import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'ai_chat_app.dart';
import 'ai_fakes.dart';

Widget _scope(FakeAiRepository ai, Widget child, {AiEnabledStore? store}) {
  return ProviderScope(
    overrides: [
      aiRepositoryProvider.overrideWithValue(ai),
      aiEnabledStoreProvider.overrideWithValue(
        store ?? InMemoryAiEnabledStore(),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('Settings → AI', () {
    testWidgets('shows the switch on and today\'s use when configured', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();

      expect(find.text('AI features'), findsOneWidget);
      expect(find.text('3 of 50 requests used today'), findsOneWidget);
      final switchRow = tester.widget<WeCordSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('ai-enabled-switch')),
          matching: find.byType(WeCordSwitch),
        ),
      );
      expect(switchRow.value, isTrue);
    });

    testWidgets('says when the daily limit is used up', (tester) async {
      final ai = FakeAiRepository()
        ..statusValue = const AiStatus(dailyLimit: 20, used: 20);
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "You've used all 20 AI requests for today. It resets tomorrow.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('explains when the server has no AI and turns the switch off', (
      tester,
    ) async {
      final ai = FakeAiRepository()
        ..statusError = const AiNotConfiguredException();
      await tester.pumpWidget(_scope(ai, const AiSettingsGroup()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("AI isn't set up on this server yet."),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ai-usage-row')), findsNothing);
      final switchWidget = tester.widget<WeCordSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('ai-enabled-switch')),
          matching: find.byType(WeCordSwitch),
        ),
      );
      expect(switchWidget.value, isFalse);
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('the switch is remembered', (tester) async {
      final store = InMemoryAiEnabledStore();
      final ai = FakeAiRepository();
      await tester.pumpWidget(
        _scope(ai, const AiSettingsGroup(), store: store),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai-enabled-switch')));
      await tester.pumpAndSettle();
      expect(await store.load(), isFalse);

      await tester.tap(find.byKey(const ValueKey('ai-enabled-switch')));
      await tester.pumpAndSettle();
      expect(await store.load(), isTrue);
    });

    testWidgets('phone settings list the AI group', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld()
        ..extraOverrides = [
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
          aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
        ];
      await world.open(tester, '/me');
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ai-enabled-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('ai-enabled-switch')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('the desktop settings window has an AI page', (tester) async {
      usePhoneViewport(
        tester,
        const PhoneViewport(
          name: '1280x800',
          size: Size(1280, 800),
          devicePixelRatio: 1,
        ),
      );
      final world = PhoneWorld()
        ..extraOverrides = [
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
          aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
        ];
      await world.open(tester, '/me');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ai-enabled-switch')), findsOneWidget);
      expect(find.text('3 of 50 requests used today'), findsOneWidget);
      await world.close(tester);
    });
  });

  group('the circle switch', () {
    testWidgets('turns AI off for the circle', (tester) async {
      final ai = FakeAiRepository();
      await tester.pumpWidget(
        _scope(ai, const CircleAiSwitch(circleId: 'circle-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allow AI features in this circle'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('circle-ai-switch')));
      await tester.pumpAndSettle();
      expect(ai.circleSwitchCalls, [('circle-1', false)]);
      final switchWidget = tester.widget<WeCordSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('circle-ai-switch')),
          matching: find.byType(WeCordSwitch),
        ),
      );
      expect(switchWidget.value, isFalse);

      await tester.tap(find.byKey(const ValueKey('circle-ai-switch')));
      await tester.pumpAndSettle();
      expect(ai.circleSwitchCalls.last, ('circle-1', true));
    });

    testWidgets('shows an error and keeps the old value when it fails', (
      tester,
    ) async {
      final ai = FakeAiRepository()
        ..circleSwitchError = Exception('not allowed');
      await tester.pumpWidget(
        _scope(ai, const CircleAiSwitch(circleId: 'circle-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('circle-ai-switch')));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't update AI features. Try again."),
        findsOneWidget,
      );
      final switchWidget = tester.widget<WeCordSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('circle-ai-switch')),
          matching: find.byType(WeCordSwitch),
        ),
      );
      expect(switchWidget.value, isTrue);
    });

    testWidgets('circle settings show it to managers only', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final owner = PhoneWorld()
        ..extraOverrides = [
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
        ];
      await pumpStandalone(
        tester,
        owner,
        const CircleSettingsScreen(circleId: 'circle-1'),
      );
      expect(find.byKey(const ValueKey('circle-ai-switch')), findsOneWidget);
      await owner.close(tester);

      final member = PhoneWorld();
      member.circles.detail = circleDetailWith(
        channelId: 'ch-general',
        permissions: 1,
      );
      await pumpStandalone(
        tester,
        member,
        const CircleSettingsScreen(circleId: 'circle-1'),
        extraOverrides: [
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
        ],
      );
      expect(find.byKey(const ValueKey('circle-ai-switch')), findsNothing);
      await member.close(tester);
    });
  });

  group('in a circle that turned AI off', () {
    void useDesktopSize(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 900);
      addTearDown(tester.view.reset);
    }

    testWidgets('chats offer no AI', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..disabledCircles.add('circle-1');
      await tester.pumpWidget(
        AiChatHarness(
          ai,
          unread: 30,
          type: ConversationType.channel,
          circleId: 'circle-1',
        ).build(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsNothing);
      expect(find.byTooltip('Summarize'), findsNothing);
      expect(find.text('30 unread messages'), findsNothing);
    });

    testWidgets('chats in other circles still do', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..disabledCircles.add('circle-2');
      await tester.pumpWidget(
        AiChatHarness(
          ai,
          unread: 30,
          type: ConversationType.channel,
          circleId: 'circle-1',
        ).build(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsOneWidget);
      expect(find.text('30 unread messages'), findsOneWidget);
    });
  });
}
