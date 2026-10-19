import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// The kinds of data the app keeps on this device that the storage page
/// counts and can empty. Everything here can be fetched or made again, which
/// costs data (and, for texts, a little time); [unsent] is the one thing that
/// is not a cache.
enum StorageCategory {
  /// The offline copy of the chat list and of each chat's newest messages.
  messages,

  /// Pictures, videos, voice messages and files that were opened.
  downloads,

  /// Previews of PDFs and videos.
  thumbnails,

  /// Text read from pictures and voice message transcripts.
  texts,

  /// The photos of photo wallpapers.
  wallpapers,

  /// Attachments queued to send. Never cleared.
  unsent;

  /// Whether the storage page may empty it.
  bool get clearable => this != unsent;
}

/// How much one chat takes.
class ConversationStorage {
  const ConversationStorage({
    required this.conversationId,
    this.messageBytes = 0,
    this.fileBytes = 0,
  });

  final String conversationId;

  /// Its cached messages.
  final int messageBytes;

  /// Its downloaded files and previews.
  final int fileBytes;

  int get total => messageBytes + fileBytes;
}

/// What the app keeps on this device, as the storage page shows it.
class StorageReport {
  const StorageReport({
    required this.bytes,
    required this.conversations,
    this.unassignedFileBytes = 0,
    this.browser,
  });

  /// Bytes by category (a category without bytes may be missing).
  final Map<StorageCategory, int> bytes;

  /// The chats that take space, largest first.
  final List<ConversationStorage> conversations;

  /// Downloaded files and previews that are not known to belong to a chat
  /// (kept before the app took note of where they came from).
  final int unassignedFileBytes;

  /// The browser's own count (the web only).
  final BrowserEstimate? browser;

  int of(StorageCategory category) => bytes[category] ?? 0;

  /// Everything the app counts.
  int get total => bytes.values.fold(0, (sum, value) => sum + value);

  /// What "Clear all" would free.
  int get clearable => [
    for (final category in StorageCategory.values)
      if (category.clearable) of(category),
  ].fold(0, (sum, value) => sum + value);

  /// Whether there is anything the page can clear.
  bool get hasClearable => clearable > 0;
}

/// Measures and empties what the app keeps on this device. It only ever
/// touches copies: nothing here changes what the server has.
class LocalStorageService {
  LocalStorageService({
    required this.userId,
    required this.chatCache,
    required this.disk,
    required this.transcripts,
    required this.imageTexts,
    required this.wallpapers,
    DateTime Function()? clock,
    Future<BrowserEstimate?> Function()? browserEstimate,
  }) : _clock = clock ?? DateTime.now,
       _browserEstimate = browserEstimate ?? browserStorageEstimate;

  /// The signed-in user's id, or null when nobody is.
  final String? Function() userId;
  final ChatCache chatCache;
  final DiskCache disk;
  final TranscriptCache transcripts;
  final ImageTextCache imageTexts;
  final WallpaperPhotoStore wallpapers;
  final DateTime Function() _clock;
  final Future<BrowserEstimate?> Function() _browserEstimate;

  Future<T> _safely<T>(Future<T> Function() body, T fallback) async {
    try {
      return await body();
    } on Object {
      // The caches only speed things up: one that cannot be read counts
      // as empty.
      return fallback;
    }
  }

  Future<StorageReport> measure() async {
    final user = userId();
    final sizes = user == null
        ? const ChatCacheSizes()
        : await _safely(() => chatCache.measure(user), const ChatCacheSizes());
    final entries = await _safely(disk.list, const <DiskEntry>[]);
    final bytes = <StorageCategory, int>{
      StorageCategory.messages: sizes.clearable,
      StorageCategory.texts:
          await _safely<int>(transcripts.totalBytes, 0) +
          await _safely<int>(imageTexts.totalBytes, 0),
      StorageCategory.wallpapers: await _safely<int>(wallpapers.totalBytes, 0),
    };
    final fileBytes = <String, int>{};
    var unassigned = 0;
    for (final entry in entries) {
      final category = switch (entry.kind) {
        DiskKind.download => StorageCategory.downloads,
        DiskKind.thumbnail => StorageCategory.thumbnails,
        DiskKind.unsent => StorageCategory.unsent,
      };
      bytes[category] = (bytes[category] ?? 0) + entry.bytes;
      if (entry.kind == DiskKind.unsent) {
        continue;
      }
      final conversation = entry.conversationId;
      if (conversation == null) {
        unassigned += entry.bytes;
      } else {
        fileBytes[conversation] = (fileBytes[conversation] ?? 0) + entry.bytes;
      }
    }
    final conversations = [
      for (final id in {...sizes.messages.keys, ...fileBytes.keys})
        ConversationStorage(
          conversationId: id,
          messageBytes: sizes.messages[id] ?? 0,
          fileBytes: fileBytes[id] ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return StorageReport(
      bytes: {
        for (final MapEntry(:key, :value) in bytes.entries)
          if (value > 0) key: value,
      },
      conversations: conversations,
      unassignedFileBytes: unassigned,
      browser: await _safely(_browserEstimate, null),
    );
  }

  /// Empties one category; returns the bytes freed. The conversation list
  /// and cached messages go together (the list shows again once the server
  /// has answered).
  Future<int> clearCategory(StorageCategory category) async {
    switch (category) {
      case StorageCategory.messages:
        final user = userId();
        if (user == null) {
          return 0;
        }
        final sizes = await _safely(
          () => chatCache.measure(user),
          const ChatCacheSizes(),
        );
        await _safely(() => chatCache.clearMessages(user), null);
        return sizes.clearable;
      case StorageCategory.downloads:
        return _removeDisk(DiskKind.download);
      case StorageCategory.thumbnails:
        return _removeDisk(DiskKind.thumbnail);
      case StorageCategory.texts:
        final bytes =
            await _safely<int>(transcripts.totalBytes, 0) +
            await _safely<int>(imageTexts.totalBytes, 0);
        await _safely(transcripts.clear, null);
        await _safely(imageTexts.clear, null);
        return bytes;
      case StorageCategory.wallpapers:
        final bytes = await _safely<int>(wallpapers.totalBytes, 0);
        await _safely(wallpapers.clear, null);
        return bytes;
      case StorageCategory.unsent:
        return 0;
    }
  }

  Future<int> _removeDisk(
    DiskKind kind, {
    bool Function(DiskEntry entry)? where,
  }) async {
    final entries = await _safely(disk.list, const <DiskEntry>[]);
    return disk.remove([
      for (final entry in entries)
        if (entry.kind == kind && (where?.call(entry) ?? true)) entry,
    ]);
  }

  /// Empties every category that can be emptied; returns the bytes freed.
  Future<int> clearAll() async {
    var freed = 0;
    for (final category in StorageCategory.values) {
      if (category.clearable) {
        freed += await clearCategory(category);
      }
    }
    return freed;
  }

  /// Empties what is kept for one chat: its cached messages, the texts read
  /// from them and its downloaded files and previews.
  Future<int> clearConversation(String conversationId) async {
    var freed = 0;
    final user = userId();
    if (user != null) {
      final sizes = await _safely(
        () => chatCache.measure(user),
        const ChatCacheSizes(),
      );
      freed += sizes.messages[conversationId] ?? 0;
      final rows = await _safely(
        () => chatCache.readMessages(user, conversationId),
        const <Map<String, dynamic>>[],
      );
      for (final row in rows) {
        await _forgetTexts(row);
      }
      await _safely(() => chatCache.removeMessages(user, conversationId), null);
    }
    final entries = await _safely(disk.list, const <DiskEntry>[]);
    freed += await disk.remove([
      for (final entry in entries)
        if (entry.kind != DiskKind.unsent &&
            entry.conversationId == conversationId)
          entry,
    ]);
    return freed;
  }

  /// Deletes downloaded files and previews not opened for [maxAge], and
  /// texts read longer ago than that; returns the bytes freed. Messages
  /// stay: they are small and are what the offline view shows.
  Future<int> cleanOlderThan(Duration maxAge) async {
    final cutoff = _clock().subtract(maxAge);
    final entries = await _safely(disk.list, const <DiskEntry>[]);
    var freed = await disk.remove([
      for (final entry in entries)
        if (entry.kind != DiskKind.unsent && entry.lastUsed.isBefore(cutoff))
          entry,
    ]);
    freed += await _safely(() => transcripts.removeOlderThan(cutoff), 0);
    freed += await _safely(() => imageTexts.removeOlderThan(cutoff), 0);
    return freed;
  }

  /// Forgets what is kept for a message: the text read from its picture, its
  /// transcript, and its downloaded file and preview. Used when the message
  /// is recalled, deleted or has expired, so nothing of it outlives it.
  Future<void> forgetMessage(Map<String, dynamic> row) async {
    await _forgetTexts(row);
    final key = objectKeyOfRow(row);
    if (key != null) {
      await _safely(() => disk.removeObject(key), null);
    }
  }

  Future<void> _forgetTexts(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id is String) {
      await _safely(() => transcripts.remove(id), null);
      await _safely(
        () => imageTexts.remove(imageTextKey(messageId: id, storagePath: '')),
        null,
      );
    }
    final attachment = row['attachment'];
    if (attachment is Map) {
      final path = attachment['path'];
      if (path is String) {
        await _safely(
          () => imageTexts.remove(imageTextKey(storagePath: path)),
          null,
        );
      }
    }
  }

  /// Forgets the cached messages that have expired, and what was kept for
  /// them. Returns how many there were.
  Future<int> sweepExpired() async {
    final user = userId();
    if (user == null) {
      return 0;
    }
    final removed = await _safely(
      () => chatCache.removeExpired(user, _clock().toUtc()),
      const <Map<String, dynamic>>[],
    );
    for (final row in removed) {
      await forgetMessage(row);
    }
    return removed.length;
  }
}

/// The `bucket/path` of a message row's attachment, when it has one that is
/// stored (a picture, a file or a voice message).
String? objectKeyOfRow(Map<String, dynamic> row) {
  final attachment = row['attachment'];
  if (attachment is! Map) {
    return null;
  }
  final bucket = attachment['bucket'];
  final path = attachment['path'];
  if (bucket is String && path is String) {
    return '$bucket/$path';
  }
  return null;
}
