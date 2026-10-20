import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/local_storage_service.dart';
import 'package:wecord/features/storage/storage_providers.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../chats/paged_chat_fakes.dart';

/// Notes which messages the app was told to forget.
class _SpyStorage extends LocalStorageService {
  _SpyStorage()
    : super(
        userId: () => 'user-1',
        chatCache: const NoChatCache(),
        disk: const NoDiskCache(),
        transcripts: InMemoryTranscriptCache(),
        imageTexts: InMemoryImageTextCache(),
        wallpapers: InMemoryWallpaperPhotoStore(),
      );

  final forgotten = <String>[];

  @override
  Future<void> forgetMessage(Map<String, dynamic> row) async {
    forgotten.add(row['id'] as String);
  }
}

Future<void> _settle() async {
  for (var turn = 0; turn < 20; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late PagedChatsRepository repository;
  late KeyValueChatCache cache;
  late _SpyStorage storage;
  late ProviderContainer container;

  setUp(() {
    repository = PagedChatsRepository();
    cache = KeyValueChatCache.memory();
    storage = _SpyStorage();
    final auth = thread_test.FakeAuthRepository()
      ..user = const AuthUser(id: 'user-1');
    container = ProviderContainer(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        chatCacheProvider.overrideWithValue(cache),
        authRepositoryProvider.overrideWithValue(auth),
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  });

  tearDown(() => container.dispose());

  ProviderSubscription<Object?> open() {
    final subscription = container.listen(
      chatThreadProvider('conversation-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    return subscription;
  }

  test('a cached message that has expired is dropped and forgotten', () async {
    final expired = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await cache.writeMessages('user-1', 'conversation-1', [
      messageRow(1),
      {...messageRow(2), 'expires_at': expired.toIso8601String()},
      messageRow(3),
    ]);
    repository.rows = [messageRow(1), messageRow(3)];
    open();

    final data = await container.read(
      chatThreadProvider('conversation-1').future,
    );
    await _settle();

    expect(
      [for (final m in data.messages) m.id],
      ['message-0001', 'message-0003'],
    );
    expect(storage.forgotten, ['message-0002']);
    final rows = await cache.readMessages('user-1', 'conversation-1');
    expect(
      [for (final row in rows) row['id']],
      ['message-0001', 'message-0003'],
    );
  });

  test('a message deleted on the server is forgotten', () async {
    repository.rows = [for (var i = 0; i < 4; i++) messageRow(i)];
    open();
    await container.read(chatThreadProvider('conversation-1').future);

    repository.emit(
      const ThreadEvent(
        ThreadEventKind.messageDeleted,
        messageId: 'message-0002',
      ),
    );
    await _settle();

    expect(storage.forgotten, ['message-0002']);
  });

  test(
    'a recalled message is forgotten once, with its old attachment',
    () async {
      final attachment = {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'conversation-1/one.jpg',
        'mime_type': 'image/jpeg',
        'size': 10,
      };
      repository.rows = [
        messageRow(1),
        messageRow(2, type: 'image', attachment: attachment),
      ];
      open();
      await container.read(chatThreadProvider('conversation-1').future);

      // The server blanks the message and marks it recalled.
      repository.rows = [
        messageRow(1),
        {
          ...messageRow(2),
          'body': '',
          'attachment': null,
          'recalled_at': DateTime.now().toUtc().toIso8601String(),
          'recalled_by': 'user-2',
        },
      ];
      repository.emit(
        const ThreadEvent(
          ThreadEventKind.messageUpdated,
          messageId: 'message-0002',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _settle();

      expect(storage.forgotten, ['message-0002']);
    },
  );

  test('syncing forgets the messages the server no longer has', () async {
    repository.rows = [for (var i = 0; i < 5; i++) messageRow(i)];
    open();
    await container.read(chatThreadProvider('conversation-1').future);
    await _settle();
    expect(storage.forgotten, isEmpty);

    // Message 3 expired and was swept while the app was away.
    repository.rows = [
      for (var i = 0; i < 5; i++)
        if (i != 3) messageRow(i),
    ];
    await container.read(chatThreadProvider('conversation-1').notifier).sync();
    await _settle();

    expect(storage.forgotten, ['message-0003']);
  });
}
