import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/sqlite_chat_cache.dart';
import 'package:wecord/features/file_preview/cache_layout.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/disk_cache_io.dart';
import 'package:wecord/features/storage/local_storage_service.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

const _chatA = '11111111-1111-4111-8111-111111111111';
const _chatB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _row(
  String id,
  String conversationId, {
  String? expiresAt,
  Map<String, dynamic>? attachment,
  String? recalledAt,
}) {
  return {
    'id': id,
    'conversation_id': conversationId,
    'created_at': '2026-10-01T08:00:00.000Z',
    'body': 'Hello $id',
    'expires_at': expiresAt,
    'recalled_at': recalledAt,
    'attachment': attachment,
  };
}

Map<String, dynamic> _image(String conversationId, String name) => {
  'kind': 'image',
  'bucket': 'chat-images',
  'path': '$conversationId/$name.jpg',
  'mime_type': 'image/jpeg',
  'size': 10,
};

/// A downloaded file as the viewer keeps it on disk.
Future<Directory> _download(
  Directory cache,
  String key, {
  required int bytes,
  DateTime? used,
  bool withKey = true,
}) async {
  final directory = Directory(
    '${cache.path}/$downloadsFolder/${cacheHash(key)}',
  );
  await directory.create(recursive: true);
  await File('${directory.path}/photo.jpg').writeAsBytes(Uint8List(bytes));
  final marker = File('${directory.path}/$usedMarkerName');
  await marker.writeAsString('');
  if (used != null) {
    await marker.setLastModified(used);
  }
  if (withKey) {
    await File('${directory.path}/$keyMarkerName').writeAsString(key);
  }
  return directory;
}

void main() {
  late Directory root;
  late Directory cacheDir;
  late Directory supportDir;
  late KeyValueChatCache chatCache;
  late InMemoryTranscriptCache transcripts;
  late InMemoryImageTextCache imageTexts;
  late InMemoryWallpaperPhotoStore wallpapers;
  late DateTime now;

  LocalStorageService service({String? user = 'user-1'}) {
    return LocalStorageService(
      userId: () => user,
      chatCache: chatCache,
      disk: IoDiskCache(
        cacheRoot: () async => cacheDir,
        supportRoot: () async => supportDir,
      ),
      transcripts: transcripts,
      imageTexts: imageTexts,
      wallpapers: wallpapers,
      clock: () => now,
      browserEstimate: () async => null,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wecord-storage-test');
    cacheDir = await Directory('${root.path}/cache').create();
    supportDir = await Directory('${root.path}/support').create();
    chatCache = KeyValueChatCache.memory();
    transcripts = InMemoryTranscriptCache();
    imageTexts = InMemoryImageTextCache();
    wallpapers = InMemoryWallpaperPhotoStore();
    now = DateTime.utc(2026, 10, 20, 12);
  });

  tearDown(() => root.delete(recursive: true));

  test('works out which chat a stored object belongs to', () {
    expect(conversationOfObjectKey('chat-images/$_chatA/16-photo.jpg'), _chatA);
    expect(
      conversationOfObjectKey('v1:chat-files/$_chatB/16-report.pdf'),
      _chatB,
    );
    expect(conversationOfObjectKey('avatars/$_chatA/a.png'), isNull);
    expect(conversationOfObjectKey('chat-files/not-an-id/a.png'), isNull);
    expect(conversationOfObjectKey('chat-files'), isNull);
  });

  group('measure', () {
    test('counts every kind of data and groups it by chat', () async {
      await chatCache.writeConversations('user-1', [
        {'id': _chatA, 'title': 'A'},
      ]);
      await chatCache.writeMessages('user-1', _chatA, [_row('m1', _chatA)]);
      await chatCache.writeMessages('user-1', _chatB, [
        _row('m2', _chatB),
        _row('m3', _chatB),
      ]);
      await chatCache.writeOutbox('user-1', [
        {'client_id': 'waiting'},
      ]);
      await _download(cacheDir, 'chat-images/$_chatA/one.jpg', bytes: 5000);
      await _download(
        cacheDir,
        'chat-files/old.bin',
        bytes: 700,
        withKey: false,
      );
      final thumbs = Directory('${cacheDir.path}/$thumbnailsFolder')
        ..createSync(recursive: true);
      final thumbKey = 'v1:chat-files/$_chatB/report.pdf';
      File(
        '${thumbs.path}/${cacheHash(thumbKey)}.png',
      ).writeAsBytesSync(Uint8List(300));
      File(
        '${thumbs.path}/${cacheHash(thumbKey)}.key',
      ).writeAsStringSync(thumbKey);
      final outbox = Directory('${supportDir.path}/outbox_media')
        ..createSync(recursive: true);
      File('${outbox.path}/client-1').writeAsBytesSync(Uint8List(900));
      await transcripts.write(
        'm9',
        CachedTranscript(
          text: 'hello there',
          engine: TranscribeEngine.onDevice,
          savedAt: now,
        ),
      );
      await imageTexts.write(
        'm:m1',
        CachedImageText(text: 'text on a sign', savedAt: now),
      );
      await wallpapers.write('w/1.jpg', Uint8List(2000));

      final report = await service().measure();

      expect(report.of(StorageCategory.downloads), 5700);
      expect(report.of(StorageCategory.thumbnails), greaterThan(300));
      expect(report.of(StorageCategory.unsent), 900);
      expect(report.of(StorageCategory.wallpapers), 2000);
      expect(report.of(StorageCategory.texts), greaterThan(0));
      expect(report.of(StorageCategory.messages), greaterThan(0));
      // The outbox is not part of what messages take: it can't be cleared.
      final sizes = await chatCache.measure('user-1');
      expect(report.of(StorageCategory.messages), sizes.clearable);
      expect(report.unassignedFileBytes, 700);
      // Chat B: two cached messages and a thumbnail; chat A: one message
      // and a picture. Largest first.
      expect(
        [for (final chat in report.conversations) chat.conversationId],
        [_chatA, _chatB],
      );
      expect(report.conversations.first.fileBytes, 5000);
      expect(report.conversations.last.messageBytes, greaterThan(0));
      expect(report.clearable, report.total - 900);
      expect(report.hasClearable, isTrue);
    });

    test('is empty when nothing is kept', () async {
      final report = await service().measure();
      expect(report.total, 0);
      expect(report.conversations, isEmpty);
      expect(report.hasClearable, isFalse);
    });

    test('does not count other users\' chats', () async {
      await chatCache.writeMessages('user-2', _chatA, [_row('m1', _chatA)]);
      final report = await service().measure();
      expect(report.of(StorageCategory.messages), 0);
    });
  });

  group('clearing', () {
    setUp(() async {
      await chatCache.writeConversations('user-1', [
        {'id': _chatA, 'title': 'A'},
      ]);
      await chatCache.writeMessages('user-1', _chatA, [_row('m1', _chatA)]);
      await chatCache.writeOutbox('user-1', [
        {'client_id': 'waiting'},
      ]);
      await _download(cacheDir, 'chat-images/$_chatA/one.jpg', bytes: 5000);
      final outbox = Directory('${supportDir.path}/outbox_media')
        ..createSync(recursive: true);
      File('${outbox.path}/client-1').writeAsBytesSync(Uint8List(900));
    });

    test('cached messages go but the outbox stays', () async {
      final freed = await service().clearCategory(StorageCategory.messages);
      expect(freed, greaterThan(0));
      expect(await chatCache.readConversations('user-1'), isNull);
      expect(await chatCache.readMessages('user-1', _chatA), isEmpty);
      expect(await chatCache.readOutbox('user-1'), hasLength(1));
    });

    test('downloaded files go, queued attachments never', () async {
      final freed = await service().clearCategory(StorageCategory.downloads);
      expect(freed, 5000);
      final report = await service().measure();
      expect(report.of(StorageCategory.downloads), 0);
      expect(report.of(StorageCategory.unsent), 900);

      await service().clearAll();
      final after = await service().measure();
      expect(after.of(StorageCategory.unsent), 900);
      expect(after.clearable, 0);
    });

    test('clear all empties every cache and says how much it freed', () async {
      await transcripts.write(
        'm9',
        CachedTranscript(
          text: 'hello',
          engine: TranscribeEngine.onDevice,
          savedAt: now,
        ),
      );
      await wallpapers.write('w.jpg', Uint8List(40));
      final before = await service().measure();
      final freed = await service().clearAll();
      expect(freed, before.clearable);
      final after = await service().measure();
      expect(after.total, 900);
    });

    test('one chat: its messages, texts and files, not the others', () async {
      await chatCache.writeMessages('user-1', _chatB, [_row('m2', _chatB)]);
      await _download(cacheDir, 'chat-images/$_chatB/two.jpg', bytes: 1000);
      await chatCache.writeMessages('user-1', _chatA, [
        _row('m1', _chatA, attachment: _image(_chatA, 'one')),
      ]);
      await imageTexts.write(
        'm:m1',
        CachedImageText(text: 'sign', savedAt: now),
      );
      await transcripts.write(
        'm1',
        CachedTranscript(
          text: 'words',
          engine: TranscribeEngine.onDevice,
          savedAt: now,
        ),
      );

      await service().clearConversation(_chatA);

      expect(await chatCache.readMessages('user-1', _chatA), isEmpty);
      expect(await chatCache.readMessages('user-1', _chatB), hasLength(1));
      expect(await imageTexts.read('m:m1'), isNull);
      expect(await transcripts.read('m1'), isNull);
      final report = await service().measure();
      expect(report.of(StorageCategory.downloads), 1000);
    });
  });

  group('auto clean', () {
    test('removes what has not been opened for the period', () async {
      await _download(
        cacheDir,
        'chat-images/$_chatA/old.jpg',
        bytes: 1000,
        used: now.subtract(const Duration(days: 45)),
      );
      await _download(
        cacheDir,
        'chat-images/$_chatA/fresh.jpg',
        bytes: 2000,
        used: now.subtract(const Duration(days: 2)),
      );
      await imageTexts.write(
        'm:old',
        CachedImageText(
          text: 'old',
          savedAt: now.subtract(const Duration(days: 60)),
        ),
      );
      await imageTexts.write(
        'm:new',
        CachedImageText(text: 'new', savedAt: now),
      );
      await chatCache.writeMessages('user-1', _chatA, [_row('m1', _chatA)]);

      final freed = await service().cleanOlderThan(const Duration(days: 30));

      expect(freed, greaterThan(1000));
      final report = await service().measure();
      expect(report.of(StorageCategory.downloads), 2000);
      expect(await imageTexts.read('m:old'), isNull);
      expect(await imageTexts.read('m:new'), isNotNull);
      // Messages stay.
      expect(await chatCache.readMessages('user-1', _chatA), hasLength(1));
    });

    test('never touches attachments waiting to be sent', () async {
      final outbox = Directory('${supportDir.path}/outbox_media')
        ..createSync(recursive: true);
      final file = File('${outbox.path}/client-1')
        ..writeAsBytesSync(Uint8List(10));
      file.setLastModifiedSync(now.subtract(const Duration(days: 400)));
      await service().cleanOlderThan(const Duration(days: 1));
      expect(file.existsSync(), isTrue);
    });
  });

  group('forgetting a message', () {
    test('drops its texts, file and preview', () async {
      final attachment = _image(_chatA, 'one');
      final key = 'chat-images/${attachment['path']}';
      await _download(cacheDir, key, bytes: 1000);
      final thumbs = Directory('${cacheDir.path}/$thumbnailsFolder')
        ..createSync(recursive: true);
      File(
        '${thumbs.path}/${cacheHash('$thumbnailKeyPrefix$key')}.png',
      ).writeAsBytesSync(Uint8List(50));
      await imageTexts.write(
        'm:m1',
        CachedImageText(text: 'sign', savedAt: now),
      );
      await transcripts.write(
        'm1',
        CachedTranscript(
          text: 'words',
          engine: TranscribeEngine.onDevice,
          savedAt: now,
        ),
      );
      // Another message's file stays.
      await _download(cacheDir, 'chat-images/$_chatA/other.jpg', bytes: 400);

      await service().forgetMessage(_row('m1', _chatA, attachment: attachment));

      expect(await imageTexts.read('m:m1'), isNull);
      expect(await transcripts.read('m1'), isNull);
      final report = await service().measure();
      expect(report.of(StorageCategory.downloads), 400);
      expect(report.of(StorageCategory.thumbnails), 0);
    });

    test(
      'sweeping forgets expired cached messages and what they kept',
      () async {
        final attachment = _image(_chatA, 'gone');
        await _download(
          cacheDir,
          'chat-images/${attachment['path']}',
          bytes: 800,
        );
        await chatCache.writeMessages('user-1', _chatA, [
          _row(
            'expired',
            _chatA,
            attachment: attachment,
            expiresAt: '2026-10-20T11:00:00.000Z',
          ),
          _row('later', _chatA, expiresAt: '2026-10-21T11:00:00.000Z'),
          _row('forever', _chatA),
        ]);

        final swept = await service().sweepExpired();

        expect(swept, 1);
        final left = await chatCache.readMessages('user-1', _chatA);
        expect([for (final row in left) row['id']], ['later', 'forever']);
        expect((await service().measure()).of(StorageCategory.downloads), 0);
      },
    );
  });

  group('SqliteChatCache maintenance', () {
    late SqliteChatCache cache;

    setUp(() async {
      sqfliteFfiInit();
      cache = await SqliteChatCache.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await cache.writeConversations('user-1', [
        {'id': _chatA, 'title': 'A'},
      ]);
      await cache.writeMessages('user-1', _chatA, [
        _row('m1', _chatA),
        _row('m2', _chatA, expiresAt: '2026-10-20T11:00:00.000Z'),
        _row('m3', _chatA, expiresAt: '2026-10-25T11:00:00.000Z'),
      ]);
      await cache.writeMessages('user-1', _chatB, [_row('m4', _chatB)]);
      await cache.writeOutbox('user-1', [
        {'client_id': 'waiting'},
      ]);
    });

    tearDown(() => cache.close());

    test('measures per chat and keeps the outbox apart', () async {
      final sizes = await cache.measure('user-1');
      expect(sizes.messages.keys, {_chatA, _chatB});
      expect(sizes.messages[_chatA]!, greaterThan(sizes.messages[_chatB]!));
      expect(sizes.conversationList, greaterThan(0));
      expect(sizes.outbox, greaterThan(0));
      expect(sizes.clearable, sizes.conversationList + sizes.messagesTotal);
      expect((await cache.measure('user-2')).clearable, 0);
    });

    test('removes some messages of a chat, or all of them', () async {
      await cache.removeMessages('user-1', _chatA, ids: {'m1'});
      expect(
        [
          for (final row in await cache.readMessages('user-1', _chatA))
            row['id'],
        ],
        ['m2', 'm3'],
      );
      await cache.removeMessages('user-1', _chatA);
      expect(await cache.readMessages('user-1', _chatA), isEmpty);
      expect(await cache.readMessages('user-1', _chatB), hasLength(1));
    });

    test('clearing messages keeps the outbox', () async {
      await cache.clearMessages('user-1');
      expect(await cache.readConversations('user-1'), isNull);
      expect(await cache.readMessages('user-1', _chatB), isEmpty);
      expect(await cache.readOutbox('user-1'), hasLength(1));
    });

    test('removes the expired ones and returns them', () async {
      final removed = await cache.removeExpired(
        'user-1',
        DateTime.utc(2026, 10, 20, 12),
      );
      expect([for (final row in removed) row['id']], ['m2']);
      expect(await cache.readMessages('user-1', _chatA), hasLength(2));
    });
  });

  group('KeyValueChatCache maintenance', () {
    test('removes some messages, then the chat when none are left', () async {
      final cache = KeyValueChatCache.memory();
      await cache.writeMessages('user-1', _chatA, [
        _row('m1', _chatA),
        _row('m2', _chatA),
      ]);
      await cache.removeMessages('user-1', _chatA, ids: {'m1'});
      expect(await cache.readMessages('user-1', _chatA), hasLength(1));
      await cache.removeMessages('user-1', _chatA, ids: {'m2'});
      expect((await cache.measure('user-1')).messages, isEmpty);
    });
  });
}
