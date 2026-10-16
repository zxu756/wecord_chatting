import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_catch_up.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import '../file_preview/file_preview_fakes.dart';
import 'ai_fakes.dart';

Widget _card(
  AiCatchUpState state, {
  int unread = 24,
  bool recent = false,
  AiSummary? summary,
  Object? error,
  VoidCallback? onSummarize,
  VoidCallback? onJump,
  VoidCallback? onDismiss,
}) {
  return MaterialApp(
    theme: WeCordTheme.light(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: AiCatchUpCard(
          state: state,
          unreadCount: unread,
          recent: recent,
          summary: summary,
          error: error,
          onSummarize: onSummarize,
          onJump: onJump,
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('the catch-up card', () {
    testWidgets('offers a summary with the unread count', (tester) async {
      var summarized = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        _card(
          AiCatchUpState.offer,
          unread: 31,
          onSummarize: () => summarized++,
          onDismiss: () => dismissed++,
        ),
      );
      expect(find.text('31 unread messages'), findsOneWidget);
      await tester.tap(find.text('Summarize what you missed'));
      await tester.tap(find.byTooltip('Dismiss'));
      expect(summarized, 1);
      expect(dismissed, 1);
    });

    testWidgets('shows a spinner while summarizing', (tester) async {
      await tester.pumpWidget(_card(AiCatchUpState.loading));
      expect(find.text('Summarizing…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Summarize what you missed'), findsNothing);
    });

    testWidgets('lists the bullets and jumps to the first unread', (
      tester,
    ) async {
      var jumped = 0;
      await tester.pumpWidget(
        _card(
          AiCatchUpState.done,
          summary: const AiSummary(
            text: '- **Ana** asked about lunch.\n* Ben said noon.\n\n',
            messageCount: 5,
            summarizedCount: 5,
          ),
          onJump: () => jumped++,
        ),
      );
      expect(find.text('What you missed'), findsOneWidget);
      expect(find.text('Ana asked about lunch.'), findsOneWidget);
      expect(find.text('Ben said noon.'), findsOneWidget);
      expect(
        find.text('Written by AI. Check anything important.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Jump to first unread'));
      expect(jumped, 1);
    });

    testWidgets('has no jump for a summary of recent messages', (tester) async {
      await tester.pumpWidget(
        _card(
          AiCatchUpState.done,
          recent: true,
          summary: const AiSummary(
            text: '- Something happened.',
            messageCount: 1,
            summarizedCount: 1,
          ),
        ),
      );
      expect(find.text('Recent messages'), findsOneWidget);
      expect(find.text('Jump to first unread'), findsNothing);
    });

    testWidgets('says when there is nothing to summarize', (tester) async {
      await tester.pumpWidget(_card(AiCatchUpState.empty));
      expect(find.text('Nothing to summarize'), findsOneWidget);
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
        const AiLimitReachedException(limit: 50, used: 50),
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
        'circle switch off',
        const AiDisabledInCircleException(),
        'AI features are turned off in this circle.',
        false,
      ),
      (
        'failed',
        const AiFailedException(),
        'Something went wrong. Try again.',
        true,
      ),
    ]) {
      testWidgets('explains the error: $name', (tester) async {
        await tester.pumpWidget(_card(AiCatchUpState.error, error: error));
        expect(find.text("Couldn't summarize"), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ai-catch-up-retry')),
          retry ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('in a chat', () {
    ChatMessage message(String id, String sender, String body, int minute) {
      return ChatMessage(
        id: id,
        conversationId: 'conversation-1',
        senderId: sender,
        type: MessageType.text,
        body: body,
        createdAt: DateTime.utc(2026, 5, 18, 4, minute),
      );
    }

    Widget app(
      FakeAiRepository ai, {
      int unread = 0,
      AiEnabledStore? enabledStore,
    }) {
      final repository = chat_fakes.FakeChatsRepository()
        ..conversations = [
          ConversationSummary(
            id: 'conversation-1',
            type: ConversationType.direct,
            unreadCount: unread,
          ),
        ]
        ..messages = [
          message('message-1', 'user-1', 'Read already', 1),
          message('message-2', 'user-2', 'First unread', 2),
          message('message-3', 'user-2', 'Second unread', 3),
        ]
        ..readMarkers = const [
          ConversationReadMarker(
            userId: 'user-1',
            lastReadMessageId: 'message-1',
          ),
        ];
      return ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          onlineUserIdsProvider.overrideWith(
            (ref) => const Stream<Set<String>>.empty(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            chat_fakes.FakeSettingsRepository(),
          ),
          ...filePreviewOverrides(),
          authRepositoryProvider.overrideWithValue(
            chat_fakes.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
          aiRepositoryProvider.overrideWithValue(ai),
          aiEnabledStoreProvider.overrideWithValue(
            enabledStore ?? InMemoryAiEnabledStore(),
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const ChatThreadScreen(
            conversationId: 'conversation-1',
            title: 'Ada Lovelace',
          ),
        ),
      );
    }

    void useDesktopSize(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 900);
      addTearDown(tester.view.reset);
    }

    testWidgets('offers a summary from 20 unread and shows it', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository();
      await tester.pumpWidget(app(ai, unread: 24));
      await tester.pumpAndSettle();

      expect(find.text('24 unread messages'), findsOneWidget);
      expect(ai.summarizeCalls, isEmpty);

      await tester.tap(find.text('Summarize what you missed'));
      await tester.pumpAndSettle();

      expect(ai.summarizeCalls.single.conversationId, 'conversation-1');
      // The reader's position from when the chat opened, not now.
      expect(ai.summarizeCalls.single.afterMessageId, 'message-1');
      expect(ai.summarizeCalls.single.recent, isFalse);
      expect(ai.summarizeCalls.single.language, AiLanguage.english);
      expect(find.text('Ana asked about lunch.'), findsOneWidget);
      expect(find.text('Jump to first unread'), findsOneWidget);

      await tester.tap(find.text('Jump to first unread'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Ana asked about lunch.'), findsNothing);
    });

    testWidgets('does not offer under 20 unread, but Summarize still works', (
      tester,
    ) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..gate = Completer<void>();
      await tester.pumpWidget(app(ai, unread: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-catch-up-card')), findsNothing);

      await tester.tap(find.byTooltip('Summarize'));
      await tester.pump();
      expect(find.text('Summarizing…'), findsOneWidget);
      ai.gate!.complete();
      await tester.pumpAndSettle();

      expect(ai.summarizeCalls.single.afterMessageId, 'message-1');
      expect(find.text('Ben suggested noon.'), findsOneWidget);
    });

    testWidgets('shows the spinner while the answer is pending', (
      tester,
    ) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..gate = Completer<void>();
      await tester.pumpWidget(app(ai, unread: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize what you missed'));
      await tester.pump();
      expect(find.text('Summarizing…'), findsOneWidget);
      ai.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Summarizing…'), findsNothing);
      expect(find.text('Ana asked about lunch.'), findsOneWidget);
    });

    testWidgets('shows a limit message and no retry', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..error = const AiLimitReachedException(limit: 50, used: 50);
      await tester.pumpWidget(app(ai, unread: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize what you missed'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "You've reached today's AI limit of 50 requests. It resets tomorrow.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ai-catch-up-retry')), findsNothing);
    });

    testWidgets('retries after a failure', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()..error = const AiFailedException();
      await tester.pumpWidget(app(ai, unread: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize what you missed'));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);

      ai.error = null;
      await tester.tap(find.byKey(const ValueKey('ai-catch-up-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Ana asked about lunch.'), findsOneWidget);
      expect(ai.summarizeCalls, hasLength(2));
    });

    testWidgets('is hidden when the server has no AI set up', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository()
        ..statusError = const AiNotConfiguredException();
      await tester.pumpWidget(app(ai, unread: 30));
      await tester.pumpAndSettle();
      expect(find.text('30 unread messages'), findsNothing);
      expect(find.byTooltip('Summarize'), findsNothing);
    });

    testWidgets('is hidden when the user turned AI off', (tester) async {
      useDesktopSize(tester);
      final ai = FakeAiRepository();
      await tester.pumpWidget(
        app(ai, unread: 30, enabledStore: InMemoryAiEnabledStore(false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('30 unread messages'), findsNothing);
      expect(find.byTooltip('Summarize'), findsNothing);
    });
  });
}
