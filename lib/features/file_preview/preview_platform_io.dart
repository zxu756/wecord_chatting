// The viewer's file system side on iOS and macOS (and other dart:io
// platforms): the download cache, local images and videos.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/file_preview/cache_layout.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/web_share.dart';

FileFetcher createFileFetcher(http.Client client) => IoFileFetcher(client);

ImageProvider localFileImage(String path) => FileImage(File(path));

VideoPlayerController localVideoController(String path) =>
    VideoPlayerController.file(File(path));

Future<Uint8List> readLocalBytes(String path) => File(path).readAsBytes();

/// Browsers only.
Future<void> triggerBrowserDownload(Uri url, String name) async {
  throw UnsupportedError('Browser downloads are web only');
}

/// Browsers only.
Future<Uint8List?> captureWebVideoPoster(Uri url, int maxSize) async => null;

/// Browsers only: the native share sheet covers sharing here.
WebShare createWebShare() => const UnavailableWebShare();

String _hash(String value) => cacheHash(value);

Future<Directory> _cacheRoot(String name) async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory('${base.path}/$name');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Reads a rendered thumbnail kept on disk.
Future<Uint8List?> readThumbnail(String key) async {
  try {
    final file = File(
      '${(await _cacheRoot(thumbnailsFolder)).path}/${_hash(key)}.png',
    );
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  } on Object {
    // A missing cache folder just means no thumbnail yet.
  }
  return null;
}

Future<void> writeThumbnail(String key, Uint8List bytes) async {
  try {
    final dir = await _cacheRoot(thumbnailsFolder);
    await File('${dir.path}/${_hash(key)}.png').writeAsBytes(bytes);
    // Which stored object it shows, for the storage page.
    await File('${dir.path}/${_hash(key)}.key').writeAsString(key);
  } on Object {
    // Thumbnails are best effort.
  }
}

/// Keeps each file as `wecord_files/<hash of bucket/path>/<its name>`, so
/// Quick Look and share sheets see the real name and extension. A folder's
/// modification time marks when it was last used.
class IoFileFetcher implements FileFetcher {
  IoFileFetcher(
    this._client, {
    Future<Directory> Function()? root,
    this.maxBytes = maxFileCacheBytes,
  }) : _root = root ?? (() => _cacheRoot(downloadsFolder));

  final http.Client _client;
  final Future<Directory> Function() _root;
  final int maxBytes;
  final _inFlight = <String, Future<String>>{};

  @override
  bool get cachesOnDisk => true;

  Future<File> _target(PreviewFile file) async {
    final root = await _root();
    return File('${root.path}/${_hash(file.key)}/${_safeName(file.name)}');
  }

  @override
  Future<String?> cachedPath(PreviewFile file) async {
    final target = await _target(file);
    if (!await target.exists()) {
      return null;
    }
    // A partial or stale copy isn't trusted.
    if (file.size > 0 && await target.length() != file.size) {
      return null;
    }
    unawaited(_touch(target.parent, file.key));
    return target.path;
  }

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final cached = await cachedPath(file);
    if (cached != null) {
      onProgress?.call(file.size, file.size);
      return cached;
    }
    final running = _inFlight[file.key];
    if (running != null) {
      return running;
    }
    final future = _download(file, url, onProgress, cancel);
    _inFlight[file.key] = future;
    try {
      return await future;
    } finally {
      unawaited(_inFlight.remove(file.key));
    }
  }

  Future<String> _download(
    PreviewFile file,
    Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  ) async {
    final target = await _target(file);
    await target.parent.create(recursive: true);
    final partial = File('${target.path}.part');
    final response = await _client.send(http.Request('GET', await url()));
    if (response.statusCode != 200) {
      throw FileDownloadException(response.statusCode);
    }
    final total = response.contentLength ?? (file.size > 0 ? file.size : null);
    final sink = partial.openWrite();
    var received = 0;
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) {
          done.completeError(error, stack);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: true,
    );
    cancel?.onCancel(() {
      unawaited(subscription.cancel());
      if (!done.isCompleted) {
        done.completeError(const FetchCancelledException());
      }
    });
    try {
      await done.future;
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
    await partial.rename(target.path);
    unawaited(_touch(target.parent, file.key));
    unawaited(evict());
    return target.path;
  }

  @override
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final cached = await cachedPath(file);
    final fitsWhole = maxBytes == null || file.size <= maxBytes;
    if (cached != null || fitsWhole) {
      // Small enough: keep the whole file, read it from the cache.
      final path =
          cached ??
          await download(
            file,
            url: url,
            onProgress: onProgress,
            cancel: cancel,
          );
      final local = File(path);
      if (maxBytes == null || await local.length() <= maxBytes) {
        return FileBytes(await local.readAsBytes(), truncated: false);
      }
      final handle = await local.open();
      try {
        return FileBytes(await handle.read(maxBytes), truncated: true);
      } finally {
        await handle.close();
      }
    }
    // Only the beginning of a large file; not cached.
    return streamBytes(
      _client,
      await url(),
      maxBytes: maxBytes,
      onProgress: onProgress,
      cancel: cancel,
      knownSize: file.size,
    );
  }

  Future<void> _touch(Directory dir, String key) async {
    try {
      await File('${dir.path}/$usedMarkerName').writeAsString('');
      final marker = File('${dir.path}/$keyMarkerName');
      if (!await marker.exists()) {
        await marker.writeAsString(key);
      }
    } on Object {
      // Only affects eviction order and the storage page.
    }
  }

  /// Deletes the least recently used files until the cache fits.
  Future<void> evict() async {
    try {
      final root = await _root();
      final entries = <({Directory dir, DateTime used, int size})>[];
      var total = 0;
      await for (final entity in root.list()) {
        if (entity is! Directory) {
          continue;
        }
        var size = 0;
        DateTime? used;
        await for (final file in entity.list()) {
          if (file is! File) {
            continue;
          }
          final stat = await file.stat();
          if (file.path.endsWith('/$usedMarkerName')) {
            used = stat.modified;
          } else if (file.path.endsWith('/$keyMarkerName')) {
            continue;
          } else {
            size += stat.size;
            used ??= stat.modified;
          }
        }
        total += size;
        entries.add((dir: entity, used: used ?? DateTime(2000), size: size));
      }
      if (total <= maxBytes) {
        return;
      }
      entries.sort((a, b) => a.used.compareTo(b.used));
      for (final entry in entries) {
        if (total <= maxBytes) {
          break;
        }
        if (_inFlight.keys.any((key) => entry.dir.path.endsWith(_hash(key)))) {
          continue;
        }
        await entry.dir.delete(recursive: true);
        total -= entry.size;
      }
    } on Object {
      // Eviction is best effort.
    }
  }
}

String _safeName(String name) {
  final cleaned = name
      .split('/')
      .last
      .replaceAll(RegExp(r'[\\:*?"<>|\x00-\x1F]'), '_')
      .trim();
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'file'
      : cleaned;
}
