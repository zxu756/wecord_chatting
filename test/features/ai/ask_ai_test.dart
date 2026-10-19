import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/ai/ask/ask_panel.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import 'ask_fakes.dart';

void main() {
  late FakeAskRepository ask;
  late QuietSearchRepository search;
  late ProviderContainer Function() containerOf;

  setUp(() {
    ask = FakeAskRepository();
    search = QuietSearchRepository();
  });

  Future<void> pumpSearch(
    WidgetTester tester, {
    String location = GlobalMessageSearchScreen.path,
    bool aiAvailable = true,
  }) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: GlobalMessageSearchScreen.path,
          builder: (context, state) => GlobalMessageSearchScreen(
            launch: GlobalMessageSearchScreen.launchFrom(
              state.uri.queryParameters,
            ),
          ),
        ),
        GoRoute(
          path: '/chats/:conversationId',
          builder: (context, state) =>
              Text('Thread ${state.pathParameters['conversationId']}'),
        ),
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) =>
              Text('Circle ${state.pathParameters['circleId']}'),
          routes: [
            GoRoute(
              path: 'channels/:conversationId',
              builder: (context, state) =>
                  Text('Channel ${state.pathParameters['conversationId']}'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...askOverrides(ask, search: search, aiSetUp: aiAvailable)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    containerOf = () => ProviderScope.containerOf(
      tester.element(find.byType(GlobalMessageSearchScreen)),
    );
  }

  Future<void> openAsk(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('search-mode-ask')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> typeQuestion(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      text,
    );
    await tester.pump(MessageSearchController.debounce);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ask-submit')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Ask AI is not offered where AI is not set up', (tester) async {
    await pumpSearch(tester, aiAvailable: false);
    expect(find.byKey(const ValueKey('search-mode')), findsNothing);
    expect(find.text('Ask AI'), findsNothing);
  });

  testWidgets('Ask AI is offered when AI is set up and on', (tester) async {
    await pumpSearch(tester);
    expect(find.byKey(const ValueKey('search-mode')), findsOneWidget);
    expect(find.text('Ask AI'), findsOneWidget);
  });

  testWidgets('asking shows what it will look in and some examples', (
    tester,
  ) async {
    await pumpSearch(
      tester,
      location: GlobalMessageSearchScreen.location(
        conversationId: 'conv-plan',
        conversationTitle: 'Weekend plan',
      ),
    );
    await openAsk(tester);

    expect(find.byKey(const ValueKey('ask-intro')), findsOneWidget);
    expect(find.text('Looking in Weekend plan'), findsOneWidget);
    expect(find.text('Ask about Weekend plan'), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-example-0')), findsOneWidget);
    // Nothing is asked until the person asks.
    expect(ask.calls, isEmpty);
    // The Ask button waits for a question.
    await submit(tester);
    expect(ask.calls, isEmpty);
  });

  testWidgets('the default place is everywhere, and says so', (tester) async {
    await pumpSearch(tester);
    await openAsk(tester);
    expect(find.text('Looking in all your chats'), findsOneWidget);
    expect(find.text('Ask about your chats'), findsWidgets);
  });

  testWidgets('a question gets an answer with the messages it used', (
    tester,
  ) async {
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);

    expect(ask.calls.single.question, 'Where is the dinner?');
    expect(ask.calls.single.scope, const EverywhereScope());
    expect(find.byKey(const ValueKey('ask-answer')), findsOneWidget);
    expect(
      find.textContaining('Cy said the dinner is at Haidilao'),
      findsOneWidget,
    );
    expect(find.text('Messages used'), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-source-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-source-2')), findsOneWidget);
    expect(find.textContaining('Cy · Weekend plan'), findsOneWidget);
    expect(find.textContaining('Ada · # general'), findsOneWidget);
    expect(find.text('The dinner is at Haidilao on Friday'), findsOneWidget);
    // No message search ran for the question.
    expect(search.requests, isEmpty);
  });

  testWidgets('the keyboard asks too', (tester) async {
    await pumpSearch(tester);
    await openAsk(tester);
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      'Who is bringing cash?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();
    expect(ask.calls.single.question, 'Who is bringing cash?');
  });

  testWidgets('an example fills the box and asks', (tester) async {
    await pumpSearch(tester);
    await openAsk(tester);
    await tester.tap(find.byKey(const ValueKey('ask-example-0')));
    await tester.pump();
    await tester.pump();
    expect(ask.calls.single.question, 'Where are we meeting on Saturday?');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('message-search-field')),
    );
    expect(field.controller?.text, 'Where are we meeting on Saturday?');
  });

  testWidgets('tapping a source opens the message in its chat', (tester) async {
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('ask-source-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ask-source-2')));
    await tester.pumpAndSettle();
    expect(find.text('Channel conv-general'), findsOneWidget);
  });

  testWidgets('a source is jumped to once its chat opens', (tester) async {
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);
    final container = containerOf();
    await tester.tap(find.byKey(const ValueKey('ask-source-1')));
    await tester.pump();
    final jump = container.read(pendingMessageJumpProvider);
    expect(jump?.messageId, 'm1');
    expect(jump?.conversationId, 'conv-plan');
    await tester.pumpAndSettle();
    expect(find.text('Thread conv-plan'), findsOneWidget);
  });

  testWidgets('the wait is shown, and Ask cannot be pressed twice', (
    tester,
  ) async {
    final gate = Completer<void>();
    ask.gate = gate;
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);
    expect(find.byKey(const ValueKey('ask-loading')), findsOneWidget);
    expect(find.text('Looking through your messages…'), findsOneWidget);
    await submit(tester);
    expect(ask.calls, hasLength(1));
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ask-answer')), findsOneWidget);
  });

  testWidgets('no answer says why, and offers a wider search', (tester) async {
    ask = FakeAskRepository(
      answers: const [
        AskAnswer.notFound(AskNotFoundReason.noMatches),
        AskAnswer.notFound(AskNotFoundReason.notInMessages),
      ],
    );
    await pumpSearch(
      tester,
      location: GlobalMessageSearchScreen.location(
        conversationId: 'conv-plan',
        conversationTitle: 'Weekend plan',
      ),
    );
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);

    expect(find.byKey(const ValueKey('ask-not-found')), findsOneWidget);
    expect(
      find.text("Couldn't find an answer in your messages"),
      findsOneWidget,
    );
    expect(
      find.text('No messages matched your question. Try other words.'),
      findsOneWidget,
    );
    expect(ask.calls.single.scope, isA<ConversationScope>());

    await tester.tap(find.byKey(const ValueKey('ask-everywhere')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(ask.calls, hasLength(2));
    expect(ask.calls.last.scope, const EverywhereScope());
    expect(ask.calls.last.question, 'Where is the dinner?');
    expect(
      find.text("The messages I found don't answer that, so I won't guess."),
      findsOneWidget,
    );
    // Already everywhere: nothing wider to offer.
    expect(find.byKey(const ValueKey('ask-everywhere')), findsNothing);
  });

  testWidgets('messages that changed meanwhile can be asked again', (
    tester,
  ) async {
    ask = FakeAskRepository(
      answers: [
        const AskAnswer.notFound(AskNotFoundReason.sourcesChanged),
        sampleAnswer(),
      ],
    );
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);
    expect(
      find.text('Some messages changed while I was reading. Ask again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ask-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ask-answer')), findsOneWidget);
  });

  testWidgets('a failure is explained, and can be retried', (tester) async {
    ask.error = const AiBusyException();
    await pumpSearch(tester);
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);
    expect(find.byKey(const ValueKey('ask-failed')), findsOneWidget);
    expect(
      find.text('AI is busy right now. Try again in a little while.'),
      findsOneWidget,
    );
    ask.error = null;
    await tester.tap(find.byKey(const ValueKey('ask-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ask-answer')), findsOneWidget);
  });

  testWidgets('the limit and the switches are not retried', (tester) async {
    for (final error in <AiException>[
      const AiLimitReachedException(limit: 50, used: 50),
      const AiTurnedOffException(),
      const AiDisabledInCircleException(),
    ]) {
      ask = FakeAskRepository()..error = error;
      await pumpSearch(tester);
      await openAsk(tester);
      await typeQuestion(tester, 'Where is the dinner?');
      await submit(tester);
      expect(find.byKey(const ValueKey('ask-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('ask-retry')), findsNothing);
    }
  });

  testWidgets('changing the place forgets the answer', (tester) async {
    await pumpSearch(
      tester,
      location: GlobalMessageSearchScreen.location(
        conversationId: 'conv-plan',
        conversationTitle: 'Weekend plan',
      ),
    );
    await openAsk(tester);
    await typeQuestion(tester, 'Where is the dinner?');
    await submit(tester);
    expect(find.byKey(const ValueKey('ask-answer')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-scope-everywhere')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ask-answer')), findsNothing);
    expect(find.byKey(const ValueKey('ask-intro')), findsOneWidget);
    expect(find.text('Looking in all your chats'), findsOneWidget);
  });

  testWidgets('searching and asking keep their own text', (tester) async {
    await pumpSearch(tester);
    await typeQuestion(tester, 'dinner');
    expect(search.requests, isNotEmpty);
    final before = search.requests.length;

    await openAsk(tester);
    final field = find.byKey(const ValueKey('message-search-field'));
    TextField fieldWidget() => tester.widget<TextField>(field);
    expect(fieldWidget().controller?.text, '');
    await typeQuestion(tester, 'Where is the dinner?');
    // Typing a question is not a search.
    expect(search.requests, hasLength(before));

    await tester.tap(find.byKey(const ValueKey('search-mode-search')));
    await tester.pump();
    await tester.pump();
    expect(fieldWidget().controller?.text, 'dinner');
    expect(find.byKey(const ValueKey('ask-panel')), findsNothing);

    await openAsk(tester);
    expect(fieldWidget().controller?.text, 'Where is the dinner?');
  });

  test('citations in an answer are marked for the eye', () {
    final spans = answerSpans(
      'At Haidilao [1]. Ada agreed [2][3].',
      const TextStyle(),
      const TextStyle(fontWeight: FontWeight.bold),
    );
    expect(spans.map((span) => (span as TextSpan).text).toList(), [
      'At Haidilao ',
      '[1]',
      '. Ada agreed ',
      '[2]',
      '[3]',
      '.',
    ]);
    expect(
      answerSpans('No citations', const TextStyle(), const TextStyle()).length,
      1,
    );
  });

  test('the places read as words', () {
    expect(askScopeName(const EverywhereScope()), 'all your chats');
    expect(
      askScopeName(const CircleScope(circleId: 'c', name: 'Hikers')),
      'Hikers',
    );
    expect(askScopeName(const CircleScope(circleId: 'c')), 'this circle');
    expect(
      askScopeName(const ConversationScope(conversationId: 'c', title: ' ')),
      'this chat',
    );
  });

  test('an answer needs words and a source to be shown', () {
    final good = AskAnswer.fromJson({
      'found': true,
      'answer': ' It is Haidilao [1]. ',
      'sources': [
        {
          'n': 1,
          'message_id': 'm1',
          'conversation_id': 'conv-plan',
          'sender': 'Cy',
          'snippet': 'Haidilao',
          'created_at': '2026-10-16T10:05:00Z',
          'place': {'id': 'conv-plan', 'type': 'group', 'title': 'Plan'},
        },
        {'n': 2, 'message_id': 5},
        'junk',
      ],
    });
    expect(good.isUsable, isTrue);
    expect(good.answer, 'It is Haidilao [1].');
    expect(good.sources, hasLength(1));
    expect(good.sources.single.place?.label, 'Plan');

    // An answer with no usable source is not shown as one.
    final unsourced = AskAnswer.fromJson({
      'found': true,
      'answer': 'It is Haidilao.',
      'sources': const [],
    });
    expect(unsourced.isUsable, isFalse);
    expect(unsourced.reason, AskNotFoundReason.noMatches);

    expect(
      AskAnswer.fromJson({
        'found': false,
        'answer': null,
        'reason': 'not_in_messages',
      }).reason,
      AskNotFoundReason.notInMessages,
    );
    expect(
      AskNotFoundReason.fromCode('sources_changed'),
      AskNotFoundReason.sourcesChanged,
    );
    expect(
      AskNotFoundReason.fromCode('no_keywords'),
      AskNotFoundReason.noKeywords,
    );
    expect(AskNotFoundReason.fromCode(null), AskNotFoundReason.noMatches);
  });

  testWidgets('the words are Chinese in a Chinese app', (tester) async {
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    await pumpSearch(tester);
    expect(find.text('问 AI'), findsOneWidget);
    await openAsk(tester);
    expect(find.text('查找范围：你的全部聊天'), findsOneWidget);
    await typeQuestion(tester, '聚餐在哪？');
    await submit(tester);
    expect(find.text('用到的消息'), findsOneWidget);
    expect(find.text('回答'), findsOneWidget);
  });
}
