import 'package:wecord/features/file_preview/cache_layout.dart';
import 'package:wecord/features/storage/disk_cache_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/storage/disk_cache_web.dart'
    as platform;

/// What a file kept on disk is.
enum DiskKind {
  /// A whole file, picture, video or voice message that was downloaded.
  download,

  /// A rendered thumbnail of a PDF or a video.
  thumbnail,

  /// A queued attachment that is still waiting to be sent. Not a cache:
  /// it is not cleared.
  unsent,
}

/// One thing on disk: a downloaded file's folder, a thumbnail, a queued
/// attachment.
class DiskEntry {
  DiskEntry({
    required this.kind,
    required this.path,
    required this.bytes,
    required this.lastUsed,
    this.objectKey,
    String? conversationId,
  }) : conversationId =
           conversationId ??
           (objectKey == null ? null : conversationOfObjectKey(objectKey));

  final DiskKind kind;

  /// Where it is (a folder for a download, a file otherwise).
  final String path;
  final int bytes;

  /// When it was last opened, or else when it was written.
  final DateTime lastUsed;

  /// The `bucket/path` of the stored object it came from, when known.
  final String? objectKey;

  /// The chat it belongs to, when its object's path says.
  final String? conversationId;
}

/// The files the app keeps on iOS and macOS, for the storage page. On the web
/// there are none (the browser keeps what it fetched on its own).
abstract interface class DiskCache {
  /// Whether this platform keeps files at all.
  bool get available;

  Future<List<DiskEntry>> list();

  /// Deletes [entries]; returns how many bytes that freed. Queued
  /// attachments are never deleted.
  Future<int> remove(Iterable<DiskEntry> entries);

  /// Deletes what was kept of the stored object [key] (`bucket/path`): its
  /// downloaded file and thumbnail.
  Future<void> removeObject(String key);
}

DiskCache createDiskCache() => platform.openPlatformDiskCache();

/// How much the browser lets this site keep, and how much it does.
class BrowserEstimate {
  const BrowserEstimate({required this.usage, required this.quota});

  final int usage;
  final int quota;
}

/// The browser's storage estimate (`navigator.storage.estimate()`); null
/// when this is not a browser or it does not say.
Future<BrowserEstimate?> browserStorageEstimate() =>
    platform.estimatePlatformBrowserStorage();

/// Keeps nothing: the web, and tests that do not care.
class NoDiskCache implements DiskCache {
  const NoDiskCache();

  @override
  bool get available => false;

  @override
  Future<List<DiskEntry>> list() async => const [];

  @override
  Future<int> remove(Iterable<DiskEntry> entries) async => 0;

  @override
  Future<void> removeObject(String key) async {}
}
