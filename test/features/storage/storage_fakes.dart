import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/storage_providers.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// The files "on disk": [entries], deleted for good when removed.
class FakeDiskCache implements DiskCache {
  FakeDiskCache(List<DiskEntry> entries, {this.available = true})
    : entries = [...entries];

  final List<DiskEntry> entries;

  @override
  final bool available;

  @override
  Future<List<DiskEntry>> list() async => [...entries];

  @override
  Future<int> remove(Iterable<DiskEntry> removed) async {
    var freed = 0;
    for (final entry in removed) {
      if (entry.kind != DiskKind.unsent && entries.remove(entry)) {
        freed += entry.bytes;
      }
    }
    return freed;
  }

  @override
  Future<void> removeObject(String key) async {
    entries.removeWhere((entry) => entry.objectKey == key);
  }
}

/// A message row as the cache keeps it.
Map<String, dynamic> cachedRow(
  String id,
  String conversationId, {
  String body = 'Hello',
  int padding = 0,
}) {
  return {
    'id': id,
    'conversation_id': conversationId,
    'created_at': '2026-10-01T08:00:00.000Z',
    'body': body + ' ' * padding,
  };
}

/// Fills the offline cache so a chat takes about [bytes] bytes.
Future<void> cacheMessagesOf(
  KeyValueChatCache cache,
  String userId,
  String conversationId,
  int bytes,
) {
  return cache.writeMessages(userId, conversationId, [
    cachedRow('$conversationId-1', conversationId, padding: bytes),
  ]);
}

DiskEntry download(
  String name,
  int bytes, {
  String? conversationId,
  DateTime? lastUsed,
}) {
  return DiskEntry(
    kind: DiskKind.download,
    path: '/cache/$name',
    bytes: bytes,
    lastUsed: lastUsed ?? DateTime.utc(2026, 10, 1),
    objectKey: 'chat-files/${conversationId ?? 'x'}/$name',
    conversationId: conversationId,
  );
}

/// What the storage page needs from the device, all in memory.
class StorageWorld {
  StorageWorld({
    this.userId = 'user-1',
    List<DiskEntry> disk = const [],
    bool diskAvailable = true,
    this.browser,
  }) : diskCache = FakeDiskCache(disk, available: diskAvailable);

  final String userId;

  /// What the browser says (the web).
  final BrowserEstimate? browser;
  final cache = KeyValueChatCache.memory();
  final FakeDiskCache diskCache;
  final transcripts = InMemoryTranscriptCache();
  final imageTexts = InMemoryImageTextCache();
  final videoCaptions = InMemoryVideoCaptionCache();
  final wallpapers = InMemoryWallpaperPhotoStore();
  final settings = InMemoryStorageSettingsStore();

  Future<void> addWallpaper(int bytes) =>
      wallpapers.write('w.jpg', Uint8List(bytes));

  List<Override> get overrides => [
    chatCacheProvider.overrideWithValue(cache),
    diskCacheProvider.overrideWithValue(diskCache),
    transcriptCacheProvider.overrideWithValue(transcripts),
    imageTextCacheProvider.overrideWithValue(imageTexts),
    videoCaptionCacheProvider.overrideWithValue(videoCaptions),
    wallpaperPhotoStoreProvider.overrideWithValue(wallpapers),
    storageSettingsStoreProvider.overrideWithValue(settings),
    browserEstimateProvider.overrideWithValue(() async => browser),
  ];
}
