import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';

/// Files in the app's support folder (not the temp folder, which the system
/// may empty), one per queued attachment.
PendingMediaStore createPendingMediaStore() {
  return FilePendingMediaStore(() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/outbox_media');
  });
}

class FilePendingMediaStore implements PendingMediaStore {
  FilePendingMediaStore(this._directory);

  final Future<Directory> Function() _directory;
  Directory? _resolved;

  @override
  bool get persistent => true;

  Future<Directory> _dir() async {
    final existing = _resolved;
    if (existing != null) {
      return existing;
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    return _resolved = directory;
  }

  Future<File> _file(
    String clientId, {
    bool preview = false,
    bool original = false,
  }) async {
    final safe = clientId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final suffix = preview
        ? '.preview'
        : original
        ? '.original'
        : '';
    return File('${(await _dir()).path}/$safe$suffix');
  }

  @override
  Future<int> put(String clientId, Stream<List<int>> data) async {
    return _write(await _file(clientId), data);
  }

  @override
  Future<void> putOriginal(String clientId, Stream<List<int>> data) async {
    await _write(await _file(clientId, original: true), data);
  }

  @override
  Stream<List<int>> openReadOriginal(String clientId) async* {
    yield* (await _file(clientId, original: true)).openRead();
  }

  @override
  Future<bool> hasOriginal(String clientId) async {
    return (await _file(clientId, original: true)).exists();
  }

  Future<int> _write(File file, Stream<List<int>> data) async {
    // Written beside it and renamed, so a crash never leaves half a file
    // that looks whole.
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    var length = 0;
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        length += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await partial.rename(file.path);
    return length;
  }

  @override
  Future<void> putPreview(String clientId, Uint8List bytes) async {
    await (await _file(clientId, preview: true)).writeAsBytes(bytes);
  }

  @override
  Stream<List<int>> openRead(String clientId) async* {
    yield* (await _file(clientId)).openRead();
  }

  @override
  Future<int?> length(String clientId) async {
    final file = await _file(clientId);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<Uint8List?> readPreview(String clientId) async {
    final file = await _file(clientId, preview: true);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String clientId) async {
    for (final file in [
      await _file(clientId),
      await _file(clientId, preview: true),
      await _file(clientId, original: true),
    ]) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // Gone already, or busy; the next start cleans up.
      }
    }
  }

  @override
  Future<Set<String>> clientIds() async {
    final directory = await _dir();
    return {
      await for (final entity in directory.list())
        if (entity is File &&
            !entity.path.endsWith('.preview') &&
            !entity.path.endsWith('.original') &&
            !entity.path.endsWith('.part'))
          entity.uri.pathSegments.last,
    };
  }
}
