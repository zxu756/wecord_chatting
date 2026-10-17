import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/merged_forward/chat_history_screen.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';

import '../../file_preview/file_preview_fakes.dart';
import '../chat_thread_screen_test.dart' as thread_test;
import '../emoji_fixtures.dart';
import 'merged_forward_fakes.dart';

void main() {
  group('models', () {
    test('a card reads its title, count and first lines', () {
      final card = ChatHistoryCard.maybeFromAttachment({
        'kind': 'chat_history',
        'title': 'Climbing crew',
        'count': 7,
        'preview': [
          {'name': 'Ada', 'kind': 'text', 'text': 'Meet at 7?'},
          {'name': 'Bart', 'kind': 'image', 'text': ''},
          {'name': 'Bart', 'kind': 'file', 'text': 'plan.pdf'},
          {'name': 'Cy', 'kind': 'voice', 'text': ''},
          {'name': 'Cy', 'kind': 'video', 'text': ''},
        ],
      })!;
      expect(card.title, 'Climbing crew');
      expect(card.count, 7);
      expect(card.heading, 'Chat history: Climbing crew');
      expect(card.preview.map((line) => line.summary), [
        'Meet at 7?',
        '[Photo]',
        '[File] plan.pdf',
        '[Voice message]',
        '[Video]',
      ]);
    });

    test('anything else is not a card', () {
      expect(ChatHistoryCard.maybeFromAttachment(null), isNull);
      expect(
        ChatHistoryCard.maybeFromAttachment({'kind': 'note', 'title': 'x'}),
        isNull,
      );
      expect(
        chatHistoryMessage()
            .copyWith(recalledAt: DateTime.utc(2026))
            .chatHistoryCard,
        isNull,
      );
      expect(chatHistoryMessage().chatHistoryCard?.count, 5);
    });

    test('a card without a title falls back to Chat', () {
      final card = ChatHistoryCard.maybeFromAttachment({
        'kind': 'chat_history',
        'count': 2,
      })!;
      expect(card.heading, 'Chat history: Chat');
    });

    test('items read their sender, time, attachment and nested history', () {
      final bundle = ChatHistoryBundle.fromJson({
        'title': 'Outer',
        'items': [
          ...bundleItemJson(),
          {
            'message_id': 'src-5',
            'sender_id': 'user-2',
            'sender_name': 'Ada',
            'created_at': '2026-05-18T09:00:00+00:00',
            'type': 'text',
            'body': 'Chat history: Inner',
            'attachment': {
              'kind': 'chat_history',
              'title': 'Inner',
              'count': 2,
            },
            'nested': {
              'title': 'Inner',
              'count': 2,
              'items': [bundleItemJson().first],
            },
          },
        ],
      });
      expect(bundle.items, hasLength(5));
      expect(bundle.items[0].senderName, 'Ada');
      expect(bundle.items[0].summary, 'Meet at 7?');
      expect(bundle.items[2].image?.path, 'src/pic.png');
      expect(bundle.items[2].summary, '[Photo]');
      expect(bundle.items[3].file?.name, 'plan.pdf');
      expect(bundle.items[3].summary, '[File] plan.pdf');
      final nested = bundle.items[4];
      expect(nested.history?.title, 'Inner');
      expect(nested.summary, '[Chat history]');
      expect(nested.nested?.items.single.body, 'Meet at 7?');
    });

    test('unknown types and broken items do not throw', () {
      final bundle = ChatHistoryBundle.fromJson({
        'items': [
          {'type': 'hologram', 'body': 'x'},
          'not an item',
          {
            'type': 'image',
            'attachment': {'kind': 'image'},
          },
        ],
      });
      expect(bundle.items, hasLength(2));
      expect(bundle.items.first.type, MessageType.text);
      expect(bundle.items.last.image, isNull);
    });
  });

  group('in a chat', () {
    late thread_test.FakeChatsRepository chats;
    late FakeMergedForwardRepository merged;

    setUp(() {
      merged = FakeMergedForwardRepository(
        bundles: {
          'history-1': ChatHistoryBundle.fromJson({
            'title': 'Climbing crew',
            'items': bundleItemJson(),
          }),
        },
      );
      chats = thread_test.FakeChatsRepository()
        ..messages = [chatHistoryMessage()];
    });

    Widget app() {
      return ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(chats),
          mergedForwardRepositoryProvider.overrideWithValue(merged),
          onlineUserIdsProvider.overrideWith(
            (ref) => const Stream<Set<String>>.empty(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            thread_test.FakeSettingsRepository(),
          ),
          ...filePreviewOverrides(),
          chatImageProviderFactoryProvider.overrideWithValue(
            (url) => MemoryImage(partyParrotPng),
          ),
          authRepositoryProvider.overrideWithValue(
            thread_test.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
        child: const MaterialApp(
          home: ChatThreadScreen(
            conversationId: 'conversation-1',
            title: 'Ada Lovelace',
          ),
        ),
      );
    }

    testWidgets('a merged forward shows as a card with its first lines', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Chat history: Climbing crew'), findsOneWidget);
      expect(find.text('Ada: Meet at 7?'), findsOneWidget);
      expect(find.text('Bart: Works for me'), findsOneWidget);
      expect(find.text('Ada: [Photo]'), findsOneWidget);
      expect(find.text('Bart: [File] plan.pdf'), findsOneWidget);
      expect(find.text('5 messages'), findsOneWidget);
    });

    testWidgets('only the first four lines show', (tester) async {
      chats.messages = [
        chatHistoryMessage(
          preview: [
            for (var i = 1; i <= 6; i++)
              {'name': 'Ada', 'kind': 'text', 'text': 'line $i'},
          ],
          count: 6,
        ),
      ];
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Ada: line 4'), findsOneWidget);
      expect(find.text('Ada: line 5'), findsNothing);
    });

    testWidgets('tapping it opens the messages, read only', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('chat-history-card-history-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-history-screen')), findsOneWidget);
      // The title, the count and each message with its sender.
      expect(find.text('Chat history: Climbing crew'), findsWidgets);
      expect(find.text('4 messages'), findsOneWidget);
      expect(find.text('Meet at 7?'), findsOneWidget);
      expect(find.text('Works for me'), findsOneWidget);
      expect(find.text('Ada'), findsWidgets);
      expect(find.text('Bart'), findsWidgets);
      // A picture tile and a file card, which open.
      expect(find.byType(MediaTile), findsOneWidget);
      expect(find.text('plan.pdf'), findsWidgets);
      // Nothing to reply to, react to or send from here.
      expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);

      await tester.tap(find.byType(MediaTile));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsOneWidget);
    });

    testWidgets('Back returns to the chat', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('chat-history-card-history-1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat-history-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-history-screen')), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
    });

    testWidgets('a history that cannot be loaded says so and retries', (
      tester,
    ) async {
      merged.bundles.clear();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('chat-history-card-history-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load the chat history.'), findsOneWidget);
      merged.bundles['history-1'] = ChatHistoryBundle.fromJson({
        'title': 'Climbing crew',
        'items': bundleItemJson(),
      });
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Meet at 7?'), findsOneWidget);
    });

    testWidgets('a deleted chat history is just a deleted message', (
      tester,
    ) async {
      chats.messages = [
        chatHistoryMessage().copyWith(
          recalledAt: DateTime.utc(2026, 5, 18, 5),
          body: '',
          attachment: null,
        ),
      ];
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Message deleted'), findsOneWidget);
      expect(find.byType(ChatHistoryScreen), findsNothing);
    });
  });

  group('nested histories', () {
    testWidgets('a history inside a history opens one level deeper', (
      tester,
    ) async {
      final bundle = ChatHistoryBundle.fromJson({
        'title': 'Outer',
        'items': [
          {
            'message_id': 'o1',
            'sender_id': 'user-2',
            'sender_name': 'Ada',
            'created_at': '2026-05-18T09:00:00+00:00',
            'type': 'text',
            'body': 'Chat history: Inner',
            'attachment': {
              'kind': 'chat_history',
              'title': 'Inner',
              'count': 2,
            },
            'nested': {
              'title': 'Inner',
              'count': 2,
              'items': [
                {
                  'message_id': 'i1',
                  'sender_id': 'user-3',
                  'sender_name': 'Bart',
                  'created_at': '2026-05-17T09:00:00+00:00',
                  'type': 'text',
                  'body': 'deep inside',
                },
                {
                  'message_id': 'i2',
                  'sender_id': 'user-3',
                  'sender_name': 'Bart',
                  'created_at': '2026-05-17T09:01:00+00:00',
                  'type': 'text',
                  'body': 'Chat history: Innermost',
                  'attachment': {
                    'kind': 'chat_history',
                    'title': 'Innermost',
                    'count': 9,
                  },
                },
              ],
            },
          },
        ],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(
              thread_test.FakeChatsRepository(),
            ),
            ...filePreviewOverrides(),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openChatHistory(
                  context,
                  messageId: 'outer',
                  title: 'Outer',
                  bundle: bundle,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Chat history: Outer'), findsOneWidget);
      // The inner card shows the first lines of what it holds.
      expect(find.text('Bart: deep inside'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-history-card-o1')));
      await tester.pumpAndSettle();

      expect(find.text('Chat history: Inner'), findsWidgets);
      expect(find.text('deep inside'), findsOneWidget);
      // What the inner one held itself is a line that does not open.
      expect(find.text('Chat history: Innermost'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-history-card-i2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-history-card-i2')));
      await tester.pumpAndSettle();
      expect(find.text('Chat history: Inner'), findsWidgets);
      // It did not open anything: the inner page is still on top, and the
      // outer one is behind it.
      expect(find.byType(ChatHistoryScreen), findsOneWidget);
      expect(
        find.byType(ChatHistoryScreen, skipOffstage: false),
        findsNWidgets(2),
      );
    });
  });
}
