import 'dart:convert';
import 'dart:typed_data';

import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/indexed_db_store.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// Photos in IndexedDB (as base64 text, which is what its store holds).
WallpaperPhotoStore createWallpaperPhotoStore() {
  return KeyValueWallpaperPhotoStore(
    () => IndexedDbKeyValueStore.open('wecord-wallpapers'),
  );
}

class KeyValueWallpaperPhotoStore implements WallpaperPhotoStore {
  KeyValueWallpaperPhotoStore(this._open);

  final Future<KeyValueStore> Function() _open;
  Future<KeyValueStore?>? _store;

  Future<KeyValueStore?> _resolve() {
    return _store ??= () async {
      try {
        return await _open();
      } on Object {
        return null;
      }
    }();
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final value = await (await _resolve())?.read(path);
      return value == null ? null : base64Decode(value);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      await (await _resolve())?.write(path, base64Encode(bytes));
    } on Object {
      // Not kept; it is fetched again next time.
    }
  }

  @override
  Future<void> remove(String path) async {
    try {
      await (await _resolve())?.delete(path);
    } on Object {
      // Already gone.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await _resolve())?.clear();
    } on Object {
      // Nothing to wipe.
    }
  }
}
