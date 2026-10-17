import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import 'chain_fakes.dart';

ChatMessage chainMessage() {
  return ChatMessage(
    id: 'chain-message',
    conversationId: 'conversation-1',
    senderId: 'user-2',
    type: MessageType.text,
    body: '\u{1F517} Saturday hike sign-up',
    createdAt: DateTime.utc(2026, 10, 18, 9),
    attachment: const {
      'kind': 'chain',
      'chain_id': 'chain-1',
      'title': 'Saturday hike sign-up',
    },
  );
}

class _World {
  _World({this.type = ConversationType.group}) {
    chats.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: type,
        unreadCount: 0,
        title: 'Hike club',
      ),
    ];
  }

  final ConversationType type;
  final chats = chat_fakes.FakeChatsRepository();
  final chain = FakeChainRepository();

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        chainRepositoryProvider.overrideWithValue(chain),
        settingsRepositoryProvider.overrideWithValue(
          chat_fakes.FakeSettingsRepository(),
        ),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}

void main() {
  testWidgets('a chain message is the live numbered list, not text', (
    tester,
  ) async {
    final world = _World();
    world.chain
      ..add('user-2', 'Ada', 'bring snacks')
      ..add('user-3', 'Bob');
    world.chats.messages = [chainMessage()];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('chain-card-chain-1')), findsOneWidget);
    expect(find.text('Saturday hike sign-up'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('2 joined'), findsOneWidget);
    // The text of the message is not drawn next to the card.
    expect(find.textContaining('\u{1F517}'), findsNothing);

    // Somebody joins: the card changes, and no message is added.
    world.chain
      ..add('user-4', 'Cy')
      ..touch();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('3 joined'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-card-chain-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the attach menu of a group has Chain and it opens the form', (
    tester,
  ) async {
    final world = _World();
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-chain-entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-chain-entry')));
    await tester.pumpAndSettle();
    expect(find.text('New chain'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-title-field')), findsOneWidget);
  });

  testWidgets('a circle channel has Chain too', (tester) async {
    final world = _World(type: ConversationType.channel);
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-chain-entry')), findsOneWidget);
  });

  testWidgets('a direct chat has no Chain', (tester) async {
    final world = _World(type: ConversationType.direct);
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.text('Create poll'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-chain-entry')), findsNothing);
  });
}
