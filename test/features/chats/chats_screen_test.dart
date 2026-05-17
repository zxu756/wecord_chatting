import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  testWidgets('shows loading and empty states', (tester) async {
    final completer = Completer<List<ConversationSummary>>();
    final repository = FakeChatsRepository()
      ..conversationsFuture = completer.future;

    await tester.pumpWidget(_app(repository));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pump();

    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('renders conversation rows with unread badges', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'See you soon',
          lastMessageAt: DateTime.utc(2026, 5, 18, 4, 30),
          unreadCount: 2,
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.direct,
          title: 'Grace Hopper',
          lastMessageBody: null,
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('See you soon'), findsOneWidget);
    expect(find.text('04:30'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('tapping a conversation passes the title to the thread route', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'See you soon',
          unreadCount: 0,
        ),
      ];
    final router = GoRouter(
      initialLocation: ChatsScreen.path,
      routes: [
        GoRoute(
          path: ChatsScreen.path,
          builder: (context, state) => const ChatsScreen(),
        ),
        GoRoute(
          path: '/chats/:conversationId',
          builder: (context, state) {
            return Text(
              'Thread ${state.pathParameters['conversationId']} ${state.extra}',
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pump();

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conversation-1 Ada Lovelace'), findsOneWidget);
  });
}

Widget _app(FakeChatsRepository repository, {GoRouter? router}) {
  final child = router == null
      ? const MaterialApp(home: ChatsScreen())
      : MaterialApp.router(routerConfig: router);

  return ProviderScope(
    overrides: [chatsRepositoryProvider.overrideWithValue(repository)],
    child: child,
  );
}

class FakeChatsRepository implements ChatsRepository {
  var conversations = <ConversationSummary>[];
  Future<List<ConversationSummary>>? conversationsFuture;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<ConversationSummary>> listConversations() {
    final future = conversationsFuture;
    if (future != null) {
      return future;
    }
    return Future.value(conversations);
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async {
    return 'conversation-for-$otherUserId';
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
  }) async {}

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Stream<void> conversationChanges() => _changes.stream;

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();
}
