import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

import 'ai_chat_app.dart';
import 'ai_fakes.dart';

void main() {
  void useDesktopSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
  }

  Future<void> openMenu(WidgetTester tester, String text) async {
    await tester.tap(find.text(text), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  AiChatHarness harness(FakeAiRepository ai, {AiEnabledStore? store}) {
    return AiChatHarness(
      ai,
      enabledStore: store,
      messages: [
        AiChatHarness.message('message-1', 'user-2', 'Hola amigos', 1),
        AiChatHarness.message('message-2', 'user-1', 'My own words', 2),
      ],
    );
  }

  testWidgets('Translate shows the text under the message, then hides it', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..gate = Completer<void>()
      ..translated = 'Hello friends';
    await tester.pumpWidget(harness(ai).build());
    await tester.pumpAndSettle();

    await openMenu(tester, 'Hola amigos');
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await tester.pump();
    expect(find.text('Translating…'), findsOneWidget);

    ai.gate!.complete();
    await tester.pumpAndSettle();
    expect(ai.translateCalls.single.text, 'Hola amigos');
    expect(ai.translateCalls.single.target, AiLanguage.english);
    expect(find.text('Hello friends'), findsOneWidget);
    expect(find.text('Translated to English'), findsOneWidget);
    // The original stays.
    expect(find.text('Hola amigos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-translation-hide')));
    await tester.pumpAndSettle();
    expect(find.text('Hello friends'), findsNothing);
    expect(find.text('Hola amigos'), findsOneWidget);
  });

  testWidgets('showing a translation again does not ask the provider again', (
    tester,
  ) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository();
    await tester.pumpWidget(harness(ai).build());
    await tester.pumpAndSettle();

    await openMenu(tester, 'Hola amigos');
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await tester.pumpAndSettle();
    expect(find.text('Translated text.'), findsOneWidget);

    // The menu now offers to hide it.
    await openMenu(tester, 'Hola amigos');
    expect(find.text('Show original'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await tester.pumpAndSettle();
    expect(find.text('Translated text.'), findsNothing);

    await openMenu(tester, 'Hola amigos');
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await tester.pumpAndSettle();
    expect(find.text('Translated text.'), findsOneWidget);
    expect(ai.translateCalls, hasLength(1));
  });

  testWidgets('translates into Chinese when the app is in Chinese', (
    tester,
  ) async {
    useDesktopSize(tester);
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    final ai = FakeAiRepository()..translated = '你好，朋友们';
    await tester.pumpWidget(harness(ai).build());
    await tester.pumpAndSettle();

    await openMenu(tester, 'Hola amigos');
    await tester.tap(find.byKey(const ValueKey('message-translate')));
    await tester.pumpAndSettle();
    expect(ai.translateCalls.single.target, AiLanguage.chinese);
    expect(find.text('你好，朋友们'), findsOneWidget);
    expect(find.text('已翻译为中文'), findsOneWidget);
    expect(find.text('显示原文'), findsOneWidget);
  });

  for (final (name, error, message, retry) in <(String, Object, String, bool)>[
    (
      'limit reached',
      const AiLimitReachedException(limit: 50),
      "You've reached today's AI limit of 50 requests. It resets tomorrow.",
      false,
    ),
    (
      'busy',
      const AiBusyException(),
      'AI is busy right now. Try again in a little while.',
      true,
    ),
    (
      'failed',
      const AiFailedException(),
      'Something went wrong. Try again.',
      true,
    ),
  ]) {
    testWidgets('shows an error under the message: $name', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..error = error;
      await tester.pumpWidget(harness(ai).build());
      await tester.pumpAndSettle();

      await openMenu(tester, 'Hola amigos');
      await tester.tap(find.byKey(const ValueKey('message-translate')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-translation-retry')),
        retry ? findsOneWidget : findsNothing,
      );

      if (retry) {
        ai.error = null;
        await tester.tap(find.byKey(const ValueKey('ai-translation-retry')));
        await tester.pumpAndSettle();
        expect(find.text('Translated text.'), findsOneWidget);
      }
    });
  }

  testWidgets('no Translate when AI is not set up', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository()
      ..statusError = const AiNotConfiguredException();
    await tester.pumpWidget(harness(ai).build());
    await tester.pumpAndSettle();
    await openMenu(tester, 'Hola amigos');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-translate')), findsNothing);
  });

  testWidgets('no Translate when the user switched AI off', (tester) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      harness(FakeAiRepository(), store: InMemoryAiEnabledStore(false)).build(),
    );
    await tester.pumpAndSettle();
    await openMenu(tester, 'Hola amigos');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-translate')), findsNothing);
  });

  testWidgets('only text messages offer Translate', (tester) async {
    useDesktopSize(tester);
    final ai = FakeAiRepository();
    final chat = AiChatHarness(
      ai,
      messages: [
        AiChatHarness.message(
          'message-1',
          'user-2',
          'Hola amigos',
          1,
        ).copyWith(type: MessageType.system),
      ],
    );
    await tester.pumpWidget(chat.build());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-translate')), findsNothing);
  });
}
