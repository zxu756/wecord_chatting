import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_translation.dart';
import 'package:wecord/features/ai/auto_translate.dart';
import 'package:wecord/features/ai/translate_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import 'ai_chat_app.dart';
import 'ai_fakes.dart';

void main() {
  void useDesktopSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
  }

  final more = find.byKey(const ValueKey('chat-header-more'));

  /// Lets the debounce pass and the answer arrive.
  Future<void> settleTranslations(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
  }

  AiChatHarness harness(
    FakeAiRepository ai, {
    List<String> others = const ['Hola amigos', 'Buenos días'],
    String? circleId,
    AiEnabledStore? store,
  }) {
    return AiChatHarness(
      ai,
      circleId: circleId,
      enabledStore: store,
      messages: [
        for (final (index, text) in others.indexed)
          AiChatHarness.message('message-${index + 1}', 'user-2', text, index),
        AiChatHarness.message('own-message', 'user-1', 'My own words', 50),
      ],
    );
  }

  Future<void> turnOn(WidgetTester tester) async {
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-translate this chat'));
    await tester.pumpAndSettle();
  }

  testWidgets('is off until it is switched on', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository();
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);
    expect(ai.batchCalls, isEmpty);
    expect(find.byKey(const ValueKey('ai-translation')), findsNothing);
  });

  testWidgets('More offers it; switching it on translates the visible '
      'messages of others in one request', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..translations['message-1'] = 'Hello friends'
      ..translations['message-2'] = 'Good morning';
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);

    await turnOn(tester);
    expect(ai.savedPrefs.single.$1, 'conversation-1');
    expect(ai.savedPrefs.single.$2.auto, isTrue);
    await settleTranslations(tester);

    final call = ai.batchCalls.single;
    expect(call.conversationId, 'conversation-1');
    expect(call.messageIds, unorderedEquals(['message-1', 'message-2']));
    expect(call.target, AiLanguage.english);
    expect(call.manual, isFalse);
    expect(find.text('Hello friends'), findsOneWidget);
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Translated to English'), findsNWidgets(2));
    // The originals stay, and own messages are not translated.
    expect(find.text('Hola amigos'), findsOneWidget);
    expect(find.text('My own words'), findsOneWidget);

    // The menu now offers to stop it.
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Stop auto-translating'), findsOneWidget);
  });

  testWidgets('a chat that had it on translates when opened', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);
    expect(ai.batchCalls, hasLength(1));
    expect(find.text('Translated text.'), findsNWidgets(2));
  });

  testWidgets('messages the app can tell need no translation are not asked '
      'for', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(
      harness(
        ai,
        others: const [
          '😀🎉',
          'https://example.com/page',
          '@ana',
          'Hola amigos',
        ],
      ).build(),
    );
    await settleTranslations(tester);
    expect(ai.batchCalls.single.messageIds, ['message-4']);
  });

  testWidgets('Chinese text is not asked for when translating to Chinese', (
    tester,
  ) async {
    useDesktopSize(tester);
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    final ai = FakeAiRepository()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(
      harness(ai, others: const ['你好，今天怎么样', 'Hola amigos']).build(),
    );
    await settleTranslations(tester);
    expect(ai.batchCalls.single.messageIds, ['message-2']);
    expect(ai.batchCalls.single.target, AiLanguage.chinese);
  });

  testWidgets('the person\'s "Translate to" and "Don\'t translate" apply', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..storedSettings = const AiTranslateSettings(
        target: AiLanguage.japanese,
        noTranslate: {AiLanguage.chinese},
      )
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(
      harness(
        ai,
        others: const ['你好，今天怎么样', 'Hola amigos', 'こんにちは、元気ですか'],
      ).build(),
    );
    await settleTranslations(tester);
    expect(ai.batchCalls.single.target, AiLanguage.japanese);
    expect(ai.batchCalls.single.messageIds, ['message-2']);
  });

  testWidgets('only the messages on screen are asked for, 20 at a time', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(
      harness(
        ai,
        others: [for (var i = 0; i < 300; i++) 'Mensaje número $i'],
      ).build(),
    );
    await settleTranslations(tester);
    final asked = [for (final call in ai.batchCalls) ...call.messageIds];
    expect(asked, isNotEmpty);
    expect(asked.length, lessThan(300));
    expect(asked.toSet().length, asked.length, reason: 'nothing twice');
    expect(ai.batchCalls.every((call) => call.messageIds.length <= 20), isTrue);
    // The oldest messages, far above the screen, were never asked for.
    expect(asked, isNot(contains('message-1')));
    expect(asked, isNot(contains('message-2')));
  });

  testWidgets('"Show original" hides it and it stays hidden', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..translations['message-1'] = 'Hello friends'
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai, others: const ['Hola amigos']).build());
    await settleTranslations(tester);
    expect(find.text('Hello friends'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-translation-hide')));
    await settleTranslations(tester);
    expect(find.text('Hello friends'), findsNothing);
    expect(find.text('Hola amigos'), findsOneWidget);
    expect(ai.batchCalls, hasLength(1));
  });

  testWidgets('the message menu knows an auto-translated message', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..translations['message-1'] = 'Hello friends'
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai, others: const ['Hola amigos']).build());
    await settleTranslations(tester);

    await tester.tap(find.text('Hola amigos'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    // Not "Translate": it already is, and the menu hides it again.
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await settleTranslations(tester);
    expect(find.text('Hello friends'), findsNothing);
    expect(ai.batchCalls, hasLength(1));
  });

  testWidgets('Translate from the menu on a translated message still works', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository();
    await tester.pumpWidget(harness(ai, others: const ['Hola amigos']).build());
    await settleTranslations(tester);
    await tester.tap(find.text('Hola amigos'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await settleTranslations(tester);
    expect(find.text('Translated text.'), findsOneWidget);
    // One request, made by hand.
    expect(ai.batchCalls.single.manual, isTrue);
  });

  group('no AI, no translation', () {
    testWidgets('the person switched AI off', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
          auto: true,
        );
      await tester.pumpWidget(
        harness(ai, store: InMemoryAiEnabledStore(false)).build(),
      );
      await settleTranslations(tester);
      expect(ai.batchCalls, isEmpty);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Auto-translate this chat'), findsNothing);
      expect(find.text('Stop auto-translating'), findsNothing);
    });

    testWidgets('the server has no AI', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..statusError = const AiNotConfiguredException()
        ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
          auto: true,
        );
      await tester.pumpWidget(harness(ai).build());
      await settleTranslations(tester);
      expect(ai.batchCalls, isEmpty);
    });

    testWidgets('the circle turned AI off', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..disabledCircles.add('circle-1')
        ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
          auto: true,
        );
      await tester.pumpWidget(harness(ai, circleId: 'circle-1').build());
      await settleTranslations(tester);
      expect(ai.batchCalls, isEmpty);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Auto-translate this chat'), findsNothing);
      expect(find.text('Stop auto-translating'), findsNothing);
    });

    testWidgets('another circle with AI on still translates', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..disabledCircles.add('circle-2')
        ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
          auto: true,
        );
      await tester.pumpWidget(harness(ai, circleId: 'circle-1').build());
      await settleTranslations(tester);
      expect(ai.batchCalls, hasLength(1));
    });
  });

  testWidgets('when the daily limit is reached it says so once and stops', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..batchLimitReached = true
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);

    expect(ai.batchCalls, hasLength(1));
    expect(
      find.text("You've reached today's AI limit. It resets tomorrow."),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(ai.batchCalls, hasLength(1));

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(
      find.text("You've reached today's AI limit. It resets tomorrow."),
      findsNothing,
    );
  });

  testWidgets('a circle that refuses stops auto-translate there', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..error = const AiDisabledInCircleException()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);
    expect(ai.batchCalls, hasLength(1));
    expect(
      find.text('AI features are turned off in this circle.'),
      findsOneWidget,
    );
  });

  testWidgets('a network failure is quiet', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..error = const AiFailedException()
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai).build());
    await settleTranslations(tester);
    expect(find.byKey(const ValueKey('ai-translation-error')), findsNothing);
  });

  testWidgets('switching it off stops asking and hides what was shown', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..translations['message-1'] = 'Hello friends'
      ..conversationPrefs['conversation-1'] = const ConversationTranslatePref(
        auto: true,
      );
    await tester.pumpWidget(harness(ai, others: const ['Hola amigos']).build());
    await settleTranslations(tester);
    expect(find.text('Hello friends'), findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop auto-translating'));
    await settleTranslations(tester);
    expect(ai.savedPrefs.last.$2.auto, isFalse);
    expect(find.text('Hello friends'), findsNothing);
  });

  group('AutoTranslateController', () {
    ProviderContainerHarness harnessFor(FakeAiRepository ai) =>
        ProviderContainerHarness(ai)..fast();

    test('batches 20 at a time and asks for each message once', () async {
      final ai = FakeAiRepository();
      final h = harnessFor(ai);
      for (var i = 0; i < 45; i++) {
        h.controller.request(
          conversationId: 'c1',
          messageId: 'm$i',
          text: 'Hola $i',
          target: AiLanguage.english,
        );
      }
      await h.flush();
      expect(ai.batchCalls.map((c) => c.messageIds.length), [20, 20, 5]);
      // Asking again for what was answered costs nothing.
      for (var i = 0; i < 45; i++) {
        h.controller.request(
          conversationId: 'c1',
          messageId: 'm$i',
          text: 'Hola $i',
          target: AiLanguage.english,
        );
      }
      await h.flush();
      expect(ai.batchCalls, hasLength(3));
      h.dispose();
    });

    test('a message that left the screen first is not asked for', () async {
      final ai = FakeAiRepository();
      final h = harnessFor(ai);
      h.controller
        ..request(
          conversationId: 'c1',
          messageId: 'a',
          text: 'Hola',
          target: AiLanguage.english,
        )
        ..request(
          conversationId: 'c1',
          messageId: 'b',
          text: 'Hola',
          target: AiLanguage.english,
        )
        ..cancel('a');
      await h.flush();
      expect(ai.batchCalls.single.messageIds, ['b']);
      h.dispose();
    });

    test('edited text is asked for again', () async {
      final ai = FakeAiRepository();
      final h = harnessFor(ai);
      h.controller.request(
        conversationId: 'c1',
        messageId: 'a',
        text: 'Hola',
        target: AiLanguage.english,
      );
      await h.flush();
      h.controller.request(
        conversationId: 'c1',
        messageId: 'a',
        text: 'Hola, otra vez',
        target: AiLanguage.english,
      );
      await h.flush();
      expect(ai.batchCalls, hasLength(2));
      h.dispose();
    });

    test('a changed target language is asked for again', () async {
      final ai = FakeAiRepository();
      final h = harnessFor(ai);
      for (final target in [AiLanguage.english, AiLanguage.french]) {
        h.controller.request(
          conversationId: 'c1',
          messageId: 'a',
          text: 'Hola',
          target: target,
        );
        await h.flush();
      }
      expect(ai.batchCalls.map((c) => c.target), [
        AiLanguage.english,
        AiLanguage.french,
      ]);
      h.dispose();
    });

    test('what the server skipped is not asked for again', () async {
      final ai = FakeAiRepository()
        ..skippedMessages['a'] = TranslateSkip.sameLanguage;
      final h = harnessFor(ai);
      for (var round = 0; round < 2; round++) {
        h.controller.request(
          conversationId: 'c1',
          messageId: 'a',
          text: 'Hola',
          target: AiLanguage.english,
        );
        await h.flush();
      }
      expect(ai.batchCalls, hasLength(1));
      h.dispose();
    });

    test('after the limit nothing more is asked in that chat', () async {
      final ai = FakeAiRepository()..batchLimitReached = true;
      final h = harnessFor(ai);
      h.controller.request(
        conversationId: 'c1',
        messageId: 'a',
        text: 'Hola',
        target: AiLanguage.english,
      );
      await h.flush();
      h.controller.request(
        conversationId: 'c1',
        messageId: 'b',
        text: 'Hola',
        target: AiLanguage.english,
      );
      await h.flush();
      expect(ai.batchCalls, hasLength(1));
      // Another chat is not affected.
      h.controller.request(
        conversationId: 'c2',
        messageId: 'c',
        text: 'Hola',
        target: AiLanguage.english,
      );
      await h.flush();
      expect(ai.batchCalls, hasLength(2));
      // Switching it on again starts fresh.
      h.controller.reset('c1');
      h.controller.request(
        conversationId: 'c1',
        messageId: 'd',
        text: 'Hola',
        target: AiLanguage.english,
      );
      await h.flush();
      expect(ai.batchCalls, hasLength(3));
      h.dispose();
    });
  });
}

/// A provider container with the AI fake, to drive the controller alone.
class ProviderContainerHarness {
  ProviderContainerHarness(FakeAiRepository ai)
    : container = ProviderContainer(
        overrides: [
          aiRepositoryProvider.overrideWithValue(ai),
          aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
        ],
      ) {
    // Keep the controllers alive like the app does.
    container
      ..listen(autoTranslateProvider, (_, _) {})
      ..listen(aiTranslationsProvider, (_, _) {});
  }

  final ProviderContainer container;

  void fast() => controller.delay = const Duration(milliseconds: 5);

  AutoTranslateController get controller =>
      container.read(autoTranslateProvider.notifier);

  /// Waits for the delay and for every request that follows.
  Future<void> flush() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  void dispose() => container.dispose();
}
