import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// Photos as files in the app's support folder (not the temp folder, which
/// the system may empty).
WallpaperPhotoStore createWallpaperPhotoStore() {
  return FileWallpaperPhotoStore(() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/wallpapers');
  });
}

class FileWallpaperPhotoStore implements WallpaperPhotoStore {
  FileWallpaperPhotoStore(this._directory);

  final Future<Directory> Function() _directory;
  Directory? _resolved;

  Future<Directory> _dir() async {
    final existing = _resolved;
    if (existing != null) {
      return existing;
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    return _resolved = directory;
  }

  Future<File> _file(String path) async {
    final safe = path.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${(await _dir()).path}/$safe');
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final file = await _file(path);
      return await file.exists() ? await file.readAsBytes() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      final file = await _file(path);
      // Written aside and renamed, so a photo is never half there.
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on Object {
      // Not kept; it is fetched again next time.
    }
  }

  @override
  Future<void> remove(String path) async {
    try {
      final file = await _file(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Already gone.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final directory = await _dir();
      await for (final entity in directory.list()) {
        await entity.delete(recursive: true);
      }
    } on Object {
      // Nothing to wipe.
    }
  }
}
