import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_rewrite_sheet.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'ai_chat_app.dart';
import 'ai_fakes.dart';

/// The rewrite sheet opened over a button, with what it hands back.
class _SheetHost {
  _SheetHost(this.ai, {this.draft = 'helo wrld, how are u'});

  final FakeAiRepository ai;
  final String draft;
  final replaced = <String>[];
  final inserted = <String>[];

  Widget build() {
    return ProviderScope(
      overrides: [aiRepositoryProvider.overrideWithValue(ai)],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  showAiRewriteSheet(
                    context,
                    draft: draft,
                    onReplace: replaced.add,
                    onInsertBelow: inserted.add,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(build());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('the rewrite sheet', () {
    testWidgets('lists the actions for a draft', (tester) async {
      final host = _SheetHost(FakeAiRepository());
      await host.open(tester);
      expect(find.text('Rewrite with AI'), findsOneWidget);
      expect(find.text('helo wrld, how are u'), findsOneWidget);
      for (final label in [
        'Fix spelling & grammar',
        'Make it shorter',
        'Make it more polite / friendly',
        'Make it more formal',
        'Translate to…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('previews the result, then replaces the draft', (tester) async {
      final ai = FakeAiRepository()
        ..gate = Completer<void>()
        ..rewritten = 'Hello world, how are you?';
      final host = _SheetHost(ai);
      await host.open(tester);

      await tester.tap(find.text('Fix spelling & grammar'));
      await tester.pump();
      expect(find.text('Working on it…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      ai.gate!.complete();
      await tester.pumpAndSettle();
      expect(ai.rewriteCalls.single.mode, AiRewriteMode.fix);
      expect(ai.rewriteCalls.single.text, 'helo wrld, how are u');
      expect(find.text('Hello world, how are you?'), findsOneWidget);
      // Nothing changes until a choice is made.
      expect(host.replaced, isEmpty);
      expect(host.inserted, isEmpty);

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(host.replaced, ['Hello world, how are you?']);
      expect(host.inserted, isEmpty);
      expect(find.text('Rewrite with AI'), findsNothing);
    });

    testWidgets('can insert the result below the draft', (tester) async {
      final host = _SheetHost(FakeAiRepository());
      await host.open(tester);
      await tester.tap(find.text('Make it shorter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert below'));
      await tester.pumpAndSettle();
      expect(host.inserted, ['Polished text.']);
      expect(host.replaced, isEmpty);
    });

    testWidgets('cancel leaves the draft alone', (tester) async {
      final host = _SheetHost(FakeAiRepository());
      await host.open(tester);
      await tester.tap(find.text('Make it more formal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(host.replaced, isEmpty);
      expect(host.inserted, isEmpty);
      expect(find.text('Rewrite with AI'), findsNothing);
    });

    testWidgets('translates into a chosen language', (tester) async {
      final ai = FakeAiRepository()..rewritten = 'こんにちは';
      final host = _SheetHost(ai, draft: 'hello');
      await host.open(tester);
      await tester.tap(find.text('Translate to…'));
      await tester.pumpAndSettle();
      for (final label in [
        'English',
        'Chinese',
        'Japanese',
        'Korean',
        'Spanish',
        'French',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Japanese'));
      await tester.pumpAndSettle();
      expect(ai.rewriteCalls.single.mode, AiRewriteMode.translate);
      expect(ai.rewriteCalls.single.target, AiLanguage.japanese);
      expect(find.text('こんにちは'), findsOneWidget);
    });

    testWidgets('asks for a draft first when the field is empty', (
      tester,
    ) async {
      final host = _SheetHost(FakeAiRepository(), draft: '   ');
      await host.open(tester);
      expect(
        find.text('Write a message first, then use AI to polish it.'),
        findsOneWidget,
      );
      expect(find.text('Fix spelling & grammar'), findsNothing);
    });

    testWidgets('refuses a draft that is too long', (tester) async {
      final host = _SheetHost(
        FakeAiRepository(),
        draft: 'x' * (aiMaxDraftLength + 1),
      );
      await host.open(tester);
      expect(
        find.text('This message is too long for AI to rewrite.'),
        findsOneWidget,
      );
    });

    for (final (name, error, message, retry) in <(String, Object, String, bool)>[
      (
        'not configured',
        const AiNotConfiguredException(),
        "AI features aren't set up on this server yet.",
        false,
      ),
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
      testWidgets('shows an error: $name', (tester) async {
        final ai = FakeAiRepository()..error = error;
        final host = _SheetHost(ai);
        await host.open(tester);
        await tester.tap(find.text('Make it shorter'));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ai-rewrite-retry')),
          retry ? findsOneWidget : findsNothing,
        );
        expect(host.replaced, isEmpty);

        if (retry) {
          ai.error = null;
          await tester.tap(find.byKey(const ValueKey('ai-rewrite-retry')));
          await tester.pumpAndSettle();
          expect(find.text('Polished text.'), findsOneWidget);
          expect(ai.rewriteCalls, hasLength(2));
        }
      });
    }
  });

  group('in the composer', () {
    void useDesktopSize(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 900);
      addTearDown(tester.view.reset);
    }

    String draft(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
        .controller!
        .text;

    testWidgets('the AI button rewrites the draft and never sends', (
      tester,
    ) async {
      useDesktopSize(tester);
      final harness = AiChatHarness(
        FakeAiRepository()..rewritten = 'Hello, how are you?',
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hello how r u',
      );
      await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix spelling & grammar'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, how are you?'), findsOneWidget);
      // Still the old draft until Replace.
      expect(draft(tester), 'hello how r u');

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(draft(tester), 'Hello, how are you?');
      expect(harness.chats.sentMessages, isEmpty);
    });

    testWidgets('Insert below adds the result on a new line', (tester) async {
      useDesktopSize(tester);
      final harness = AiChatHarness(FakeAiRepository()..rewritten = 'Hola');
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Hello',
      );
      await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Translate to…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert below'));
      await tester.pumpAndSettle();
      expect(draft(tester), 'Hello\nHola');
      expect(harness.chats.sentMessages, isEmpty);
    });

    testWidgets('Ctrl+Shift+E opens the sheet from the message field', (
      tester,
    ) async {
      useDesktopSize(tester);
      final harness = AiChatHarness(FakeAiRepository());
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-composer-field')));
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'teh draft',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Rewrite with AI'), findsOneWidget);
      expect(find.text('teh draft'), findsWidgets);
    });

    testWidgets('no AI button when AI is not set up', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..statusError = const AiNotConfiguredException();
      await tester.pumpWidget(AiChatHarness(ai).build());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsNothing);
    });

    testWidgets('no AI button when the user switched AI off', (tester) async {
      useDesktopSize(tester);
      await tester.pumpWidget(
        AiChatHarness(
          FakeAiRepository(),
          enabledStore: InMemoryAiEnabledStore(false),
        ).build(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsNothing);
    });

    testWidgets('on a phone the button appears once there is a draft', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AiChatHarness(FakeAiRepository()).build());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hi',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsOneWidget);
    });
  });
}
