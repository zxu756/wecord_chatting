import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/offline_session.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/offline/sqlite_chat_cache.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';

import 'chat_thread_screen_test.dart' as thread_test;
import 'paged_chat_fakes.dart';

Map<String, dynamic> _conversationRow(String id, String title) {
  return {
    'id': id,
    'type': 'direct',
    'title': title,
    'unread_count': 0,
    'last_message_at': '2026-05-18T04:30:00.000Z',
  };
}

/// [PagedChatsRepository] with conversation rows too.
class _ListRepository extends PagedChatsRepository
    implements ConversationRowsSource {
  var conversationRows = <Map<String, dynamic>>[];
  Completer<void>? listGate;

  @override
  Future<List<Map<String, dynamic>>> listConversationRows() async {
    if (listGate case final gate?) {
      await gate.future;
    }
    if (offline) {
      throw StateError('offline');
    }
    return conversationRows;
  }
}

Future<void> _settle() async {
  for (var turn = 0; turn < 20; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('KeyValueChatCache', () {
    test('keeps each user\'s rows apart and wipes them all', () async {
      final cache = KeyValueChatCache.memory();
      await cache.writeConversations('user-1', [_conversationRow('c1', 'A')]);
      await cache.writeMessages('user-1', 'c1', [messageRow(1)]);
      await cache.writeOutbox('user-1', [
        {'client_id': 'x'},
      ]);

      expect(await cache.readConversations('user-1'), hasLength(1));
      expect(await cache.readConversations('user-2'), isNull);
      expect(await cache.readMessages('user-2', 'c1'), isEmpty);
      expect(await cache.readOutbox('user-1'), hasLength(1));

      await cache.writeOutbox('user-1', const []);
      expect(await cache.readOutbox('user-1'), isEmpty);

      await cache.clear();
      expect(await cache.readConversations('user-1'), isNull);
      expect(await cache.readMessages('user-1', 'c1'), isEmpty);
    });

    test('keeps a conversation\'s newest messages', () async {
      final cache = KeyValueChatCache.memory();
      await cache.writeMessages('user-1', 'c1', [
        for (var index = 0; index < 150; index++) messageRow(index),
      ]);

      final rows = await cache.readMessages('user-1', 'c1');
      expect(rows, hasLength(cachedMessagesPerConversation));
      expect(rows.first['body'], 'Message 50');
      expect(rows.last['body'], 'Message 149');
    });
  });

  group('SqliteChatCache', () {
    late SqliteChatCache cache;

    setUp(() async {
      sqfliteFfiInit();
      cache = await SqliteChatCache.open(
        inMemoryDatabasePath,
        cipher: sessionLocalCipher,
        factory: databaseFactoryFfi,
      );
    });

    tearDown(() => cache.close());

    test('stores conversations, messages and the outbox per user', () async {
      await cache.writeConversations('user-1', [
        _conversationRow('c2', 'Second'),
        _conversationRow('c1', 'First'),
      ]);
      // Written newest last; read oldest first.
      await cache.writeMessages('user-1', 'c1', [
        messageRow(2),
        messageRow(1),
        messageRow(3),
      ]);
      await cache.writeOutbox('user-1', [
        OutboxEntry(
          clientId: 'client-1',
          conversationId: 'c1',
          body: 'Waiting',
          createdAt: DateTime.utc(2026),
        ).toJson(),
      ]);

      final conversations = await cache.readConversations('user-1');
      expect(
        [for (final row in conversations!) row['title']],
        ['Second', 'First'],
      );
      final messages = await cache.readMessages('user-1', 'c1');
      expect(
        [for (final row in messages) row['body']],
        ['Message 1', 'Message 2', 'Message 3'],
      );
      final outbox = await cache.readOutbox('user-1');
      expect(OutboxEntry.fromJson(outbox.single).body, 'Waiting');
      expect(await cache.readConversations('user-2'), isNull);

      // A rewrite replaces what was there.
      await cache.writeMessages('user-1', 'c1', [messageRow(9)]);
      expect(await cache.readMessages('user-1', 'c1'), hasLength(1));

      await cache.clear();
      expect(await cache.readConversations('user-1'), isNull);
      expect(await cache.readMessages('user-1', 'c1'), isEmpty);
      expect(await cache.readOutbox('user-1'), isEmpty);
    });

    test('keeps the newest messages of long conversations', () async {
      await cache.writeMessages('user-1', 'c1', [
        for (var index = 0; index < 130; index++) messageRow(index),
      ]);
      final rows = await cache.readMessages('user-1', 'c1');
      expect(rows, hasLength(cachedMessagesPerConversation));
      expect(rows.first['body'], 'Message 30');
    });
  });

  group('offline chats', () {
    late _ListRepository repository;
    late KeyValueChatCache cache;
    late StreamController<bool> connectivity;
    late thread_test.FakeAuthRepository auth;
    late ProviderContainer container;

    setUp(() {
      repository = _ListRepository();
      cache = KeyValueChatCache.memory();
      connectivity = StreamController<bool>.broadcast();
      auth = thread_test.FakeAuthRepository()
        ..user = const AuthUser(id: 'user-1');
      container = ProviderContainer(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          chatCacheProvider.overrideWithValue(cache),
          authRepositoryProvider.overrideWithValue(auth),
          deviceConnectivityProvider.overrideWith((ref) => connectivity.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await connectivity.close();
    });

    test('a chat opens with its cached messages, then syncs', () async {
      await cache.writeMessages('user-1', 'conversation-1', [
        for (var index = 0; index < 40; index++) messageRow(index),
      ]);
      // On the server since: message 5 was deleted and 40–44 are new.
      repository.rows = [
        for (var index = 0; index < 45; index++)
          if (index != 5) messageRow(index),
      ];
      final gate = repository.gate = Completer<void>();
      final subscription = container.listen(
        chatThreadProvider('conversation-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      final cached = await container.read(
        chatThreadProvider('conversation-1').future,
      );
      expect(cached.isFromCache, isTrue);
      expect(cached.messages, hasLength(40));

      gate.complete();
      repository.gate = null;
      await _settle();

      final synced = container
          .read(chatThreadProvider('conversation-1'))
          .value!;
      expect(synced.isFromCache, isFalse);
      expect(synced.messages, hasLength(44));
      expect(synced.messages.any((m) => m.id == 'message-0005'), isFalse);
      expect(synced.messages.last.body, 'Message 44');
      expect(synced.hasOlder, isFalse);

      // The synced messages are cached again.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final rows = await cache.readMessages('user-1', 'conversation-1');
      expect(rows, hasLength(44));
    });

    test('offline, the cache stays; back online, it syncs', () async {
      await cache.writeMessages('user-1', 'conversation-1', [
        for (var index = 0; index < 10; index++) messageRow(index),
      ]);
      repository
        ..offline = true
        ..rows = [for (var index = 0; index < 12; index++) messageRow(index)];
      final subscription = container.listen(
        chatThreadProvider('conversation-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      container.listen(reconnectCountProvider, (_, _) {});
      connectivity.add(false);

      await container.read(chatThreadProvider('conversation-1').future);
      await _settle();
      var data = container.read(chatThreadProvider('conversation-1')).value!;
      expect(data.isFromCache, isTrue);
      expect(data.messages, hasLength(10));

      repository.offline = false;
      connectivity.add(true);
      await _settle();

      data = container.read(chatThreadProvider('conversation-1')).value!;
      expect(data.isFromCache, isFalse);
      expect(data.messages, hasLength(12));
    });

    test(
      'the conversation list shows the cached list until the server answers',
      () async {
        await cache.writeConversations('user-1', [
          _conversationRow('c1', 'Cached Ada'),
        ]);
        repository.conversationRows = [
          _conversationRow('c1', 'Fresh Ada'),
          _conversationRow('c2', 'Fresh Grace'),
        ];
        final gate = repository.listGate = Completer<void>();
        final subscription = container.listen(conversationsProvider, (_, _) {});
        addTearDown(subscription.close);

        final first = await container.read(conversationsProvider.future);
        expect([for (final c in first) c.title], ['Cached Ada']);

        gate.complete();
        await _settle();

        final fresh = container.read(conversationsProvider).value!;
        expect([for (final c in fresh) c.title], ['Fresh Ada', 'Fresh Grace']);
        final cachedRows = await cache.readConversations('user-1');
        expect(cachedRows, hasLength(2));
      },
    );

    test('signing out wipes the offline copy', () async {
      await cache.writeConversations('user-1', [_conversationRow('c1', 'A')]);
      await cache.writeMessages('user-1', 'c1', [messageRow(1)]);
      final authChanges = StreamController<AuthUser?>.broadcast();
      addTearDown(authChanges.close);
      final guarded = ProviderContainer(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          chatCacheProvider.overrideWithValue(cache),
          authRepositoryProvider.overrideWithValue(auth),
          authStateProvider.overrideWith((ref) => authChanges.stream),
        ],
      );
      addTearDown(guarded.dispose);
      guarded.listen(offlineSessionGuardProvider, (_, _) {});

      authChanges.add(const AuthUser(id: 'user-1'));
      await _settle();
      expect(await cache.readConversations('user-1'), isNotNull);

      authChanges.add(null);
      await _settle();
      expect(await cache.readConversations('user-1'), isNull);
      expect(await cache.readMessages('user-1', 'c1'), isEmpty);
    });
  });
}
