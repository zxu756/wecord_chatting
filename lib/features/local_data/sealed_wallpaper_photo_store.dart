import 'dart:async';
import 'dart:typed_data';

import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// A [WallpaperPhotoStore] that keeps the photos encrypted (G8). A photo
/// kept before that is read as it is and written back encrypted; one that
/// cannot be opened (the key was replaced) reads as missing and is fetched
/// again.
class SealedWallpaperPhotoStore implements WallpaperPhotoStore {
  SealedWallpaperPhotoStore(this.inner, this.cipher);

  final WallpaperPhotoStore inner;
  final LocalCipher cipher;

  @override
  Future<Uint8List?> read(String path) async {
    final stored = await inner.read(path);
    if (stored == null) {
      return null;
    }
    if (isSealedBytes(stored)) {
      return cipher.openBytes(stored);
    }
    // From before the encryption.
    unawaited(write(path, stored).catchError((Object _) {}));
    return stored;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    await inner.write(path, await cipher.sealBytes(bytes));
  }

  @override
  Future<void> remove(String path) => inner.remove(path);

  @override
  Future<void> clear() => inner.clear();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}
