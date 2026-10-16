import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;

/// Reports download progress; [total] is null when the server doesn't say.
typedef DownloadProgress = void Function(int received, int? total);

/// The first bytes of a file, and whether there was more.
class FileBytes {
  const FileBytes(this.bytes, {required this.truncated});

  final Uint8List bytes;
  final bool truncated;
}

/// Lets a running download be stopped (the viewer closed).
class FetchCancel {
  var _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void onCancel(void Function() listener) => _listeners.add(listener);
}

class FetchCancelledException implements Exception {
  const FetchCancelledException();
}

class FileDownloadException implements Exception {
  const FileDownloadException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'FileDownloadException($statusCode)';
}

/// Downloads files for the viewer. On iOS and macOS whole files are kept in
/// the app's cache folder (least recently used first out past
/// [maxFileCacheBytes]) so opening one again is instant; the web keeps
/// nothing itself and relies on the browser's HTTP cache.
abstract interface class FileFetcher {
  /// Whether [download] keeps files on this device.
  bool get cachesOnDisk;

  /// The local copy of [file] if it was downloaded before.
  Future<String?> cachedPath(PreviewFile file);

  /// Downloads [file] (or reuses the cached copy) and returns its local
  /// path. Not available on the web.
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  });

  /// Reads [file], at most [maxBytes] of it.
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  });
}

/// Downloaded files stay until they pass this much in total.
const maxFileCacheBytes = 500 * 1024 * 1024;

final fileFetcherProvider = Provider<FileFetcher>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return platform.createFileFetcher(client);
});

/// Streams [request]'s body, at most [maxBytes], reporting progress.
/// Shared by both platforms.
Future<FileBytes> streamBytes(
  http.Client client,
  Uri url, {
  int? maxBytes,
  DownloadProgress? onProgress,
  FetchCancel? cancel,
  int? knownSize,
}) async {
  final request = http.Request('GET', url);
  if (maxBytes != null && (knownSize == null || knownSize > maxBytes)) {
    request.headers['Range'] = 'bytes=0-${maxBytes - 1}';
  }
  final response = await client.send(request);
  if (response.statusCode != 200 && response.statusCode != 206) {
    throw FileDownloadException(response.statusCode);
  }
  final total = _totalSize(response) ?? knownSize;
  final builder = BytesBuilder(copy: false);
  var truncated = false;
  final done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (chunk) {
      if (maxBytes != null && builder.length + chunk.length > maxBytes) {
        builder.add(chunk.sublist(0, maxBytes - builder.length));
        truncated = true;
        unawaited(subscription.cancel());
        if (!done.isCompleted) {
          done.complete();
        }
        return;
      }
      builder.add(chunk);
      onProgress?.call(builder.length, total);
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
  await done.future;
  if (response.statusCode == 206 && total != null && builder.length < total) {
    truncated = true;
  }
  return FileBytes(builder.takeBytes(), truncated: truncated);
}

/// The whole file's size: Content-Range's total for partial responses,
/// else Content-Length.
int? _totalSize(http.StreamedResponse response) {
  final range = response.headers['content-range'];
  if (range != null) {
    final total = int.tryParse(range.split('/').last.trim());
    if (total != null) {
      return total;
    }
  }
  return response.contentLength;
}
