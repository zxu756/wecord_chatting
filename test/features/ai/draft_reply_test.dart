import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_repository.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_sheet.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import 'ai_chat_app.dart';
import 'ai_fakes.dart';
import 'draft_reply_fakes.dart';

class _SheetHost {
  _SheetHost(this.repository, {this.initialIntent = ''});

  final FakeDraftReplyRepository repository;
  final String initialIntent;
  final used = <(String, String)>[];

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          draftReplyRepositoryProvider.overrideWithValue(repository),
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    showDraftReplySheet(
                      context,
                      conversationId: 'conversation-1',
                      initialIntent: initialIntent,
                      onUse: (reply, intent) => used.add((reply, intent)),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('the Help me reply sheet', () {
    testWidgets('asks nothing until Suggest replies is tapped', (tester) async {
      final repository = FakeDraftReplyRepository();
      await _SheetHost(repository).open(tester);
      expect(find.text('Help me reply'), findsOneWidget);
      expect(
        find.textContaining('Reads the last 20 messages you can see'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
    });

    testWidgets('lists the replies and hands the picked one back', (
      tester,
    ) async {
      final repository = FakeDraftReplyRepository()..gate = Completer<void>();
      final host = _SheetHost(repository);
      await host.open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('draft-reply-intent')),
        'say yes to Friday',
      );
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pump();
      expect(find.text('Working on it…'), findsOneWidget);

      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(repository.calls.single.conversationId, 'conversation-1');
      expect(repository.calls.single.intent, 'say yes to Friday');
      // The app's language, as the fallback.
      expect(repository.calls.single.lang, AiLanguage.appLanguage);
      for (final reply in repository.replies) {
        expect(find.text(reply), findsOneWidget, reason: reply);
      }
      expect(
        find.text('Written by AI. Nothing is sent until you send it.'),
        findsOneWidget,
      );
      expect(host.used, isEmpty);

      await tester.tap(find.byKey(const ValueKey('draft-reply-use-1')));
      await tester.pumpAndSettle();
      expect(host.used, [(repository.replies[1], 'say yes to Friday')]);
      expect(find.text('Help me reply'), findsNothing);
    });

    testWidgets('starts from what is already in the box', (tester) async {
      final repository = FakeDraftReplyRepository();
      await _SheetHost(
        repository,
        initialIntent: 'tell her I am late',
      ).open(tester);
      expect(find.text('tell her I am late'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      expect(repository.calls.single.intent, 'tell her I am late');
    });

    testWidgets('Try again asks again and Back returns to the note', (
      tester,
    ) async {
      final repository = FakeDraftReplyRepository();
      await _SheetHost(repository).open(tester);
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-again')));
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(2));
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-reply-intent')), findsOneWidget);
    });

    testWidgets('says so when there is nothing to reply to', (tester) async {
      final repository = FakeDraftReplyRepository()..replies = const [];
      await _SheetHost(repository).open(tester);
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-reply-nothing')), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-reply-use-0')), findsNothing);
    });

    for (final (name, error, message, retry) in [
      (
        'the limit',
        const AiLimitReachedException(limit: 50, used: 50),
        "You've reached today's AI limit of 50 requests. It resets tomorrow.",
        false,
      ),
      (
        'a locked chat',
        const AiChatLockedException(),
        "AI doesn't read chats you've locked.",
        false,
      ),
      (
        'AI off in the circle',
        const AiDisabledInCircleException(),
        'AI features are turned off in this circle.',
        false,
      ),
      (
        'AI off for the person',
        const AiTurnedOffException(),
        'AI features are turned off. You can turn them on in Settings.',
        false,
      ),
      (
        'a busy provider',
        const AiBusyException(),
        'AI is busy right now. Try again in a little while.',
        true,
      ),
      (
        'a failure',
        const AiFailedException(),
        'Something went wrong. Try again.',
        true,
      ),
    ]) {
      testWidgets('shows an error: $name', (tester) async {
        final repository = FakeDraftReplyRepository()..error = error;
        await _SheetHost(repository).open(tester);
        await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(
          find.byKey(const ValueKey('draft-reply-again')),
          retry ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const ValueKey('draft-reply-back')), findsOneWidget);
      });
    }

    test('the function\'s chat_locked answer is its own error', () {
      expect(
        aiExceptionFor(403, {'error': 'chat_locked'}),
        isA<AiChatLockedException>(),
      );
    });
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

    AiChatHarness harness(FakeDraftReplyRepository repository) => AiChatHarness(
      FakeAiRepository(),
      extraOverrides: [
        draftReplyRepositoryProvider.overrideWithValue(repository),
        voiceMessageRecorderProvider.overrideWithValue(
          chat_fakes.FakeVoiceMessageRecorder(),
        ),
      ],
    );

    testWidgets('the sparkle menu fills the box and never sends', (
      tester,
    ) async {
      useDesktopSize(tester);
      final repository = FakeDraftReplyRepository();
      final h = harness(repository);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();

      // An empty box: the sparkle button still offers Help me reply.
      await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Write a message first, then use AI to polish it.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-reply-intent')), findsOneWidget);
      expect(repository.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      expect(repository.calls.single.conversationId, 'conversation-1');
      expect(repository.calls.single.intent, '');
      // The box stays as it was until a reply is picked.
      expect(draft(tester), '');

      await tester.tap(find.byKey(const ValueKey('draft-reply-use-0')));
      await tester.pumpAndSettle();
      expect(draft(tester), 'Sure, Friday works!');
      expect(h.chats.sentMessages, isEmpty);
    });

    testWidgets('a draft in the box is the note, and the reply replaces it', (
      tester,
    ) async {
      useDesktopSize(tester);
      final repository = FakeDraftReplyRepository();
      final h = harness(repository);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'say yes',
      );
      await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      expect(repository.calls.single.intent, 'say yes');
      await tester.tap(find.byKey(const ValueKey('draft-reply-use-2')));
      await tester.pumpAndSettle();
      expect(draft(tester), 'Can we make it Saturday instead?');
      expect(h.chats.sentMessages, isEmpty);
    });

    testWidgets('a draft that was edited out of the note stays', (
      tester,
    ) async {
      useDesktopSize(tester);
      final repository = FakeDraftReplyRepository();
      final h = harness(repository);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'half a thought',
      );
      await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('draft-reply-intent')),
        'accept the invitation',
      );
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-use-0')));
      await tester.pumpAndSettle();
      expect(draft(tester), 'half a thought\nSure, Friday works!');
    });

    testWidgets('on a phone the plus menu has Help me reply for an empty box', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      final repository = FakeDraftReplyRepository();
      final h = harness(repository);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-ai-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('composer-draft-reply-entry')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-reply-use-1')));
      await tester.pumpAndSettle();
      expect(draft(tester), repository.replies[1]);
      expect(h.chats.sentMessages, isEmpty);
    });

    testWidgets('no entry when AI is not set up or is switched off', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      final off = AiChatHarness(
        FakeAiRepository(),
        enabledStore: InMemoryAiEnabledStore(false),
      );
      await tester.pumpWidget(off.build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-draft-reply-entry')),
        findsNothing,
      );
    });
  });
}
