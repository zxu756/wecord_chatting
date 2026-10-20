import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/file_preview/cache_layout.dart';
import 'package:wecord/features/storage/disk_cache.dart';

DiskCache openPlatformDiskCache() => IoDiskCache(
  cacheRoot: getApplicationCacheDirectory,
  supportRoot: getApplicationSupportDirectory,
);

/// The browser only.
Future<BrowserEstimate?> estimatePlatformBrowserStorage() async => null;

/// Reads the folders `preview_platform_io.dart` and the outbox fill (see
/// `cache_layout.dart`): downloaded files and thumbnails in the cache
/// folder, queued attachments in the support folder.
class IoDiskCache implements DiskCache {
  IoDiskCache({required this.cacheRoot, required this.supportRoot});

  final Future<Directory> Function() cacheRoot;
  final Future<Directory> Function() supportRoot;

  @override
  bool get available => true;

  Future<Directory?> _folder(
    Future<Directory> Function() root,
    String name,
  ) async {
    try {
      final directory = Directory('${(await root()).path}/$name');
      return await directory.exists() ? directory : null;
    } on Object {
      return null;
    }
  }

  static Future<String?> _readMarker(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? (await file.readAsString()).trim() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<DiskEntry>> list() async {
    final entries = <DiskEntry>[];
    final downloads = await _folder(cacheRoot, downloadsFolder);
    if (downloads != null) {
      await for (final entity in downloads.list()) {
        if (entity is! Directory) {
          continue;
        }
        var bytes = 0;
        DateTime? used;
        DateTime? written;
        await for (final file in entity.list()) {
          if (file is! File) {
            continue;
          }
          final stat = await file.stat();
          if (file.path.endsWith('/$usedMarkerName')) {
            used = stat.modified;
          } else if (!file.path.endsWith('/$keyMarkerName')) {
            // The two markers are bookkeeping, not the file.
            bytes += stat.size;
            written ??= stat.modified;
          }
        }
        entries.add(
          DiskEntry(
            kind: DiskKind.download,
            path: entity.path,
            bytes: bytes,
            lastUsed: used ?? written ?? DateTime.fromMillisecondsSinceEpoch(0),
            objectKey: await _readMarker('${entity.path}/$keyMarkerName'),
          ),
        );
      }
    }
    final thumbnails = await _folder(cacheRoot, thumbnailsFolder);
    if (thumbnails != null) {
      await for (final entity in thumbnails.list()) {
        if (entity is! File || !entity.path.endsWith('.png')) {
          continue;
        }
        final stat = await entity.stat();
        final markerPath =
            '${entity.path.substring(0, entity.path.length - 4)}.key';
        final marker = File(markerPath);
        entries.add(
          DiskEntry(
            kind: DiskKind.thumbnail,
            path: entity.path,
            bytes:
                stat.size + (await marker.exists() ? await marker.length() : 0),
            lastUsed: stat.modified,
            objectKey: await _readMarker(markerPath),
          ),
        );
      }
    }
    final unsent = await _folder(supportRoot, 'outbox_media');
    if (unsent != null) {
      await for (final entity in unsent.list()) {
        if (entity is! File) {
          continue;
        }
        final stat = await entity.stat();
        entries.add(
          DiskEntry(
            kind: DiskKind.unsent,
            path: entity.path,
            bytes: stat.size,
            lastUsed: stat.modified,
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<int> remove(Iterable<DiskEntry> entries) async {
    var freed = 0;
    for (final entry in entries) {
      if (entry.kind == DiskKind.unsent) {
        continue;
      }
      try {
        if (entry.kind == DiskKind.thumbnail) {
          final base = entry.path.substring(0, entry.path.length - 4);
          await _delete(File('$base.key'));
          await _delete(File(entry.path));
        } else {
          final directory = Directory(entry.path);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        }
        freed += entry.bytes;
      } on Object {
        // Busy or already gone: left for the next time.
      }
    }
    return freed;
  }

  static Future<void> _delete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> removeObject(String key) async {
    try {
      final downloads = await _folder(cacheRoot, downloadsFolder);
      if (downloads != null) {
        final directory = Directory('${downloads.path}/${cacheHash(key)}');
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
      final thumbnails = await _folder(cacheRoot, thumbnailsFolder);
      if (thumbnails != null) {
        final base =
            '${thumbnails.path}/${cacheHash('$thumbnailKeyPrefix$key')}';
        await _delete(File('$base.png'));
        await _delete(File('$base.key'));
      }
    } on Object {
      // Already gone.
    }
  }
}
