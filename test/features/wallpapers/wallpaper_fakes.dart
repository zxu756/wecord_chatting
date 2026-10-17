import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_repository.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// The wallpaper server in memory: rows, the bucket and what was removed.
class FakeWallpaperRepository implements WallpaperRepository {
  FakeWallpaperRepository([WallpaperSettings? settings])
    : settings = settings ?? const WallpaperSettings();

  WallpaperSettings settings;

  /// The bucket: path to bytes.
  final bucket = <String, Uint8List>{};

  /// Photos removed from the bucket, in order.
  final removed = <String>[];
  final saves = <(String?, ChatWallpaper)>[];
  final clears = <String?>[];
  var uploads = 0;
  var loads = 0;
  var downloads = 0;

  /// Makes the next write fail.
  Object? failWrites;
  Object? failLoad;
  final _changes = StreamController<void>.broadcast();

  /// Pretends another device changed the rows.
  void changeElsewhere(WallpaperSettings next) {
    settings = next;
    _changes.add(null);
  }

  @override
  Future<WallpaperSettings> load() async {
    loads += 1;
    final error = failLoad;
    if (error != null) {
      throw error;
    }
    return settings;
  }

  void _maybeFail() {
    final error = failWrites;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> save(String? conversationId, ChatWallpaper wallpaper) async {
    _maybeFail();
    saves.add((conversationId, wallpaper));
    final previous = conversationId == null
        ? settings.defaultWallpaper
        : settings.chats[conversationId];
    settings = settings.withWallpaper(conversationId, wallpaper);
    final freed = previous?.photoPath;
    if (freed != null && freed != wallpaper.photoPath) {
      bucket.remove(freed);
      removed.add(freed);
    }
  }

  @override
  Future<void> clear(String? conversationId) async {
    _maybeFail();
    clears.add(conversationId);
    final previous = conversationId == null
        ? settings.defaultWallpaper
        : settings.chats[conversationId];
    settings = settings.withWallpaper(conversationId, null);
    final freed = previous?.photoPath;
    if (freed != null) {
      bucket.remove(freed);
      removed.add(freed);
    }
  }

  @override
  Future<String> uploadPhoto(Uint8List bytes) async {
    _maybeFail();
    uploads += 1;
    final path =
        'user-1/00000000-0000-4000-8000-${uploads.toString().padLeft(12, '0')}.jpg';
    bucket[path] = bytes;
    return path;
  }

  @override
  Future<void> discardPhoto(String path) async {
    bucket.remove(path);
    removed.add(path);
  }

  @override
  Future<Uint8List> downloadPhoto(String path) async {
    downloads += 1;
    final bytes = bucket[path];
    if (bytes == null) {
      throw StateError('no such photo');
    }
    return bytes;
  }

  @override
  Stream<void> changes() => _changes.stream;
}

/// The three stores a test needs to keep wallpapers off the real server and
/// disk.
class WallpaperTestStores {
  WallpaperTestStores({
    FakeWallpaperRepository? repository,
    InMemoryWallpaperSettingsStore? cache,
    InMemoryWallpaperPhotoStore? photos,
  }) : repository = repository ?? FakeWallpaperRepository(),
       cache = cache ?? InMemoryWallpaperSettingsStore(),
       photos = photos ?? InMemoryWallpaperPhotoStore();

  final FakeWallpaperRepository repository;
  final InMemoryWallpaperSettingsStore cache;
  final InMemoryWallpaperPhotoStore photos;

  List<Override> get overrides => [
    wallpaperRepositoryProvider.overrideWithValue(repository),
    wallpaperSettingsStoreProvider.overrideWithValue(cache),
    wallpaperPhotoStoreProvider.overrideWithValue(photos),
  ];
}

/// A small landscape picture as a JPEG: a sky, a sun and two hills. Enough
/// color and structure to see how a photo wallpaper reads.
Uint8List samplePhotoBytes({int width = 640, int height = 960}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final t = y / height;
    for (var x = 0; x < width; x++) {
      // Sky: warm at the horizon, blue above.
      var r = (70 + 170 * t).round();
      var g = (120 + 90 * t).round();
      var b = (200 - 20 * t).round();
      final dx = x - width * 0.68;
      final dy = y - height * 0.3;
      if (dx * dx + dy * dy < math.pow(width * 0.09, 2)) {
        r = 255;
        g = 236;
        b = 170;
      }
      final hill1 = height * (0.62 + 0.06 * math.sin(x / width * math.pi * 2));
      final hill2 =
          height * (0.72 + 0.05 * math.sin(x / width * math.pi * 3 + 1));
      if (y > hill2) {
        r = 38;
        g = 74;
        b = 62;
      } else if (y > hill1) {
        r = 74;
        g = 120;
        b = 96;
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Pumps frames and lets pictures decode in between (decoding runs outside
/// the test's fake clock).
Future<void> settleWithImages(WidgetTester tester) async {
  for (var round = 0; round < 5; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
