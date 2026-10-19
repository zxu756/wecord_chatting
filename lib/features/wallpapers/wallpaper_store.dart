import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_photo_store_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/wallpapers/wallpaper_photo_store_web.dart'
    as platform;

/// The wallpaper choices kept on this device, per signed-in person, so a
/// chat paints with its wallpaper the moment it opens (before the server
/// has answered). The server is the truth; this is its copy.
abstract interface class WallpaperSettingsStore {
  Future<WallpaperSettings?> read(String userId);

  Future<void> write(String userId, WallpaperSettings settings);
}

class SharedPreferencesWallpaperSettingsStore
    implements WallpaperSettingsStore {
  const SharedPreferencesWallpaperSettingsStore();

  static String _key(String userId) => 'wecord.wallpapers.$userId';

  @override
  Future<WallpaperSettings?> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId));
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map
          ? WallpaperSettings.fromJson(Map<String, dynamic>.from(json))
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String userId, WallpaperSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(userId), jsonEncode(settings.toJson()));
  }
}

class InMemoryWallpaperSettingsStore implements WallpaperSettingsStore {
  InMemoryWallpaperSettingsStore([Map<String, WallpaperSettings>? initial])
    : values = {...?initial};

  final Map<String, WallpaperSettings> values;

  @override
  Future<WallpaperSettings?> read(String userId) async => values[userId];

  @override
  Future<void> write(String userId, WallpaperSettings settings) async {
    values[userId] = settings;
  }
}

/// The photos of photo wallpapers kept on this device (files on iOS and
/// macOS, IndexedDB on the web), by their path in the bucket.
abstract interface class WallpaperPhotoStore {
  Future<Uint8List?> read(String path);

  Future<void> write(String path, Uint8List bytes);

  Future<void> remove(String path);

  /// Forgets every photo (the person signed out).
  Future<void> clear();

  /// How many bytes the photos take on this device.
  Future<int> totalBytes();
}

class InMemoryWallpaperPhotoStore implements WallpaperPhotoStore {
  InMemoryWallpaperPhotoStore([Map<String, Uint8List>? initial])
    : photos = {...?initial};

  final Map<String, Uint8List> photos;

  @override
  Future<Uint8List?> read(String path) async => photos[path];

  @override
  Future<void> write(String path, Uint8List bytes) async {
    photos[path] = bytes;
  }

  @override
  Future<void> remove(String path) async {
    photos.remove(path);
  }

  @override
  Future<void> clear() async => photos.clear();

  @override
  Future<int> totalBytes() async =>
      photos.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}

final wallpaperSettingsStoreProvider = Provider<WallpaperSettingsStore>(
  (ref) => const SharedPreferencesWallpaperSettingsStore(),
);

final wallpaperPhotoStoreProvider = Provider<WallpaperPhotoStore>(
  (ref) => platform.createWallpaperPhotoStore(),
);
