import 'dart:convert';

import 'package:crypto/crypto.dart';

/// How the downloaded-file cache is laid out on disk (iOS and macOS), shared
/// by the code that fills it (`preview_platform_io.dart`) and the storage
/// page that measures and empties it (`lib/features/storage/`).

/// Whole downloaded files: `wecord_files/<hash of the object key>/<name>`.
const downloadsFolder = 'wecord_files';

/// Rendered thumbnails of PDFs and videos: `wecord_thumbs/<hash>.png`.
const thumbnailsFolder = 'wecord_thumbs';

/// Beside a downloaded file: its modification time says when it was last
/// used (the eviction order).
const usedMarkerName = '.used';

/// Beside a downloaded file: the `bucket/path` it was downloaded from, so
/// the storage page can tell which chat it belongs to.
const keyMarkerName = '.key';

/// The prefix of a thumbnail's cache key, before the object's key.
const thumbnailKeyPrefix = 'v1:';

/// The folder or file name a cache key is kept under.
String cacheHash(String key) => sha1.convert(utf8.encode(key)).toString();

/// The conversation a stored object belongs to. Attachments are stored
/// under a folder named after their conversation (`chat-images/<id>/...`);
/// null for anything else (a path of another shape).
String? conversationOfObjectKey(String key) {
  var rest = key.startsWith(thumbnailKeyPrefix)
      ? key.substring(thumbnailKeyPrefix.length)
      : key;
  final slash = rest.indexOf('/');
  if (slash <= 0) {
    return null;
  }
  final bucket = rest.substring(0, slash);
  if (bucket != 'chat-images' &&
      bucket != 'chat-files' &&
      bucket != 'voice-messages') {
    return null;
  }
  rest = rest.substring(slash + 1);
  final end = rest.indexOf('/');
  if (end <= 0) {
    return null;
  }
  final folder = rest.substring(0, end);
  return _uuid.hasMatch(folder) ? folder : null;
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
