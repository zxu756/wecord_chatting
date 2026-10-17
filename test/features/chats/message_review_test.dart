import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_review_mark.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../ai/ai_chat_app.dart';
import '../ai/ai_fakes.dart';

ChatMessage _message(
  String id,
  String sender,
  String body,
  int minute, {
  MessageReviewState? state,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: sender,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.utc(2026, 5, 18, 4, minute),
    reviewState: state,
  );
}

Widget _mark(MessageReviewState state, {bool isOwn = true, ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? WeCordTheme.light(),
    home: Scaffold(
      body: Center(
        child: MessageReviewMark(state: state, isOwn: isOwn),
      ),
    ),
  );
}

void main() {
  group('the model', () {
    Map<String, dynamic> row(Object? reviewState) => {
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'hello',
      'created_at': '2026-05-18T04:00:00Z',
      'review_state': reviewState,
    };

    test('reads where the AI guard has the message', () {
      expect(ChatMessage.fromJson(row(null)).reviewState, isNull);
      expect(
        ChatMessage.fromJson(row('checking')).reviewState,
        MessageReviewState.checking,
      );
      expect(
        ChatMessage.fromJson(row('held')).reviewState,
        MessageReviewState.held,
      );
      expect(
        ChatMessage.fromJson(row('removed')).reviewState,
        MessageReviewState.removed,
      );
      expect(ChatMessage.fromJson(row('mystery')).reviewState, isNull);
    });

    test('copyWith keeps it, and clears it when released', () {
      final held = ChatMessage.fromJson(row('held'));
      expect(
        held.copyWith(body: 'edited').reviewState,
        MessageReviewState.held,
      );
      expect(held.copyWith(reviewState: null).reviewState, isNull);
    });
  });

  group('the line under a message', () {
    testWidgets('says Checking… while the AI looks', (tester) async {
      await tester.pumpWidget(_mark(MessageReviewState.checking));
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(MessageReviewMark)),
        matchesSemantics(
          label: 'Checking…',
          hint: 'Only you and moderators can see this until it is checked.',
        ),
      );
    });

    testWidgets('says Held for review once the AI flagged it', (tester) async {
      await tester.pumpWidget(_mark(MessageReviewState.held));
      expect(find.text('Held for review'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('tells the author when a moderator removed it', (tester) async {
      await tester.pumpWidget(_mark(MessageReviewState.removed));
      expect(find.text('Removed by a moderator'), findsOneWidget);
    });

    testWidgets('a moderator reading someone else\'s message', (tester) async {
      await tester.pumpWidget(_mark(MessageReviewState.held, isOwn: false));
      expect(find.text('Held for review'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(MessageReviewMark)),
        matchesSemantics(
          label: 'Held for review',
          hint: 'Only moderators and its author can see this.',
        ),
      );
    });

    testWidgets('works in the dark theme', (tester) async {
      await tester.pumpWidget(
        _mark(MessageReviewState.held, theme: WeCordTheme.dark()),
      );
      expect(find.text('Held for review'), findsOneWidget);
    });
  });

  group('in the chat', () {
    testWidgets('the author sees Checking… and Held for review under their '
        'own messages, and nothing under released ones', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = AiChatHarness(
        FakeAiRepository(),
        messages: [
          _message('message-1', 'user-2', 'Welcome!', 1),
          _message(
            'message-2',
            'user-1',
            'My first message',
            2,
            state: MessageReviewState.held,
          ),
          _message(
            'message-3',
            'user-1',
            'And my second',
            3,
            state: MessageReviewState.checking,
          ),
          _message('message-4', 'user-1', 'Released one', 4),
        ],
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(find.text('My first message'), findsOneWidget);
      expect(find.text('Held for review'), findsOneWidget);
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-review-held')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('message-review-checking')),
        findsOneWidget,
      );
      expect(find.byType(MessageReviewMark), findsNWidgets(2));
    });

    testWidgets('releasing the message clears the line', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = AiChatHarness(
        FakeAiRepository(),
        messages: [
          _message('message-1', 'user-2', 'Welcome!', 1),
          _message(
            'message-2',
            'user-1',
            'My first message',
            2,
            state: MessageReviewState.checking,
          ),
        ],
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      expect(find.text('Checking…'), findsOneWidget);

      harness.chats.messages = [
        _message('message-1', 'user-2', 'Welcome!', 1),
        _message('message-2', 'user-1', 'My first message', 2),
      ];
      harness.chats.emitMessageChange();
      await tester.pumpAndSettle();

      expect(find.text('My first message'), findsOneWidget);
      expect(find.text('Checking…'), findsNothing);
      expect(find.byType(MessageReviewMark), findsNothing);
    });
  });
}
