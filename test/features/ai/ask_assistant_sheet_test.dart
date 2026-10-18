import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/assistant/ask_assistant_sheet.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;

void main() {
  late chat_fakes.FakeChatsRepository chats;
  bool? sent;

  Future<void> open(WidgetTester tester, {ChatMessage? replyTo}) async {
    sent = null;
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatsRepositoryProvider.overrideWithValue(chats)],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    sent = await showAskAssistantSheet(
                      context,
                      conversationId: 'c1',
                      replyTo: replyTo,
                    );
                  },
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

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ask-ai-question')),
        matching: find.byType(EditableText),
      ),
      text,
    );
    await tester.pump();
  }

  setUp(() => chats = chat_fakes.FakeChatsRepository());

  testWidgets('asks nothing until there is a question', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pump();
    expect(chats.sentMessages, isEmpty);
    await type(tester, 'summarize the plan');
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(chats.sentMessages.single.body, '@WeCord AI summarize the plan');
    expect(chats.sentMessages.single.conversationId, 'c1');
    expect(sent, isTrue);
  });

  testWidgets('the person chooses how much of the chat it reads', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Reads only your question.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ask-ai-range-20')));
    await tester.pump();
    expect(
      find.text('Also reads the last 20 messages you can see in this chat.'),
      findsOneWidget,
    );
    await type(tester, 'what did we decide?');
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(
      chats.sentMessages.single.body,
      '@WeCord AI /20 what did we decide?',
    );
  });

  testWidgets('the last 100 messages', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('ask-ai-range-100')));
    await tester.pump();
    await type(tester, 'list the to-dos');
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(chats.sentMessages.single.body, '@WeCord AI /100 list the to-dos');
  });

  testWidgets('a suggestion fills in the question', (tester) async {
    await open(tester);
    await tester.tap(find.text('Translate to English'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(chats.sentMessages.single.body, '@WeCord AI Translate to English');
  });

  testWidgets('asking about a message replies to it', (tester) async {
    await open(
      tester,
      replyTo: ChatMessage(
        id: 'message-9',
        conversationId: 'c1',
        senderId: 'user-2',
        type: MessageType.text,
        body: 'We meet at 7pm at the station',
        createdAt: DateTime(2026, 10, 19),
      ),
    );
    expect(find.byKey(const ValueKey('ask-ai-quote')), findsOneWidget);
    expect(find.text('We meet at 7pm at the station'), findsOneWidget);
    expect(
      find.text('Reads your question and the message you are asking about.'),
      findsOneWidget,
    );
    await type(tester, 'explain');
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(chats.sentReplyToMessageId, 'message-9');
    expect(chats.sentReplyPreview!.messageId, 'message-9');
    expect(chats.sentMessages.single.body, '@WeCord AI explain');
  });

  testWidgets('tells everyone can see it and report the answer', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('can report the answer'), findsOneWidget);
  });

  testWidgets('a refused send stays open and says why', (tester) async {
    chats.sendError = StateError('slow down');
    await open(tester);
    await type(tester, 'hello');
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ask-ai-error')), findsOneWidget);
    expect(sent, isNull);
    chats.sendError = null;
    await tester.tap(find.byKey(const ValueKey('ask-ai-send')));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
    expect(chats.sentMessages, hasLength(1));
  });
}
