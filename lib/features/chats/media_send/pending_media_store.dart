import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/pending_media_store_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/chats/media_send/pending_media_store_web.dart'
    as platform;

/// Where the files of attachments wait between "send" and the server
/// having them: the prepared photo, video or file, and a small preview to
/// draw in the chat meanwhile.
///
/// On iOS and macOS the files are kept on disk, so what was queued survives
/// the app being closed (the outbox entry says what each file is). On the
/// web they are held in memory and are gone on reload.
abstract interface class PendingMediaStore {
  /// Whether files outlive the app. The outbox only keeps the entries of
  /// persistent stores across restarts.
  bool get persistent;

  /// Keeps the file [clientId] is sent from. Returns how many bytes it is.
  Future<int> put(String clientId, Stream<List<int>> data);

  /// Keeps a small picture of the file (JPEG or PNG), for the bubble.
  Future<void> putPreview(String clientId, Uint8List bytes);

  /// The file's bytes, in chunks.
  Stream<List<int>> openRead(String clientId);

  Future<int?> length(String clientId);

  Future<Uint8List?> readPreview(String clientId);

  /// Forgets the file and its preview.
  Future<void> delete(String clientId);

  /// Ids of the files kept.
  Future<Set<String>> clientIds();
}

final pendingMediaStoreProvider = Provider<PendingMediaStore>((ref) {
  return platform.createPendingMediaStore();
});

/// Keeps files in memory: the web's store, and the tests'.
class MemoryPendingMediaStore implements PendingMediaStore {
  MemoryPendingMediaStore({this.persistent = false});

  @override
  final bool persistent;

  final _files = <String, Uint8List>{};
  final _previews = <String, Uint8List>{};

  /// Chunk size when a file is read back, so progress moves in steps.
  static const chunkSize = 64 * 1024;

  @override
  Future<int> put(String clientId, Stream<List<int>> data) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    _files[clientId] = bytes;
    return bytes.length;
  }

  @override
  Future<void> putPreview(String clientId, Uint8List bytes) async {
    _previews[clientId] = bytes;
  }

  @override
  Stream<List<int>> openRead(String clientId) async* {
    final bytes = _files[clientId];
    if (bytes == null) {
      throw StateError('No file kept for $clientId');
    }
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize < bytes.length
          ? offset + chunkSize
          : bytes.length;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }

  @override
  Future<int?> length(String clientId) async => _files[clientId]?.length;

  @override
  Future<Uint8List?> readPreview(String clientId) async => _previews[clientId];

  @override
  Future<void> delete(String clientId) async {
    _files.remove(clientId);
    _previews.remove(clientId);
  }

  @override
  Future<Set<String>> clientIds() async => _files.keys.toSet();
}
