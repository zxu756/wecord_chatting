import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_photo_store_io.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings kept on this device', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keep each person\'s choices apart', () async {
      const store = SharedPreferencesWallpaperSettingsStore();
      const ada = WallpaperSettings(
        defaultWallpaper: ChatWallpaper.preset('dawn'),
        chats: {'a': ChatWallpaper.photo('u/p.jpg', blur: true)},
      );
      expect(await store.read('ada'), isNull);
      await store.write('ada', ada);
      await store.write(
        'bob',
        const WallpaperSettings(defaultWallpaper: ChatWallpaper.preset('dots')),
      );
      expect(await store.read('ada'), ada);
      expect(
        (await store.read('bob'))!.defaultWallpaper,
        const ChatWallpaper.preset('dots'),
      );
    });

    test('a damaged copy is ignored', () async {
      SharedPreferences.setMockInitialValues({
        'wecord.wallpapers.ada': '{not json',
        'wecord.wallpapers.bob': '[1, 2]',
      });
      const store = SharedPreferencesWallpaperSettingsStore();
      expect(await store.read('ada'), isNull);
      expect(await store.read('bob'), isNull);
    });
  });

  group('photos kept on this device', () {
    late Directory directory;
    late FileWallpaperPhotoStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('wallpaper-photos');
      store = FileWallpaperPhotoStore(
        () async => Directory('${directory.path}/wallpapers'),
      );
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('are written, read, removed and wiped', () async {
      const path = 'user-1/00000000-0000-4000-8000-000000000001.jpg';
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(await store.read(path), isNull);
      await store.write(path, bytes);
      expect(await store.read(path), bytes);
      // Nothing half-written is left beside it.
      final names = Directory(
        '${directory.path}/wallpapers',
      ).listSync().map((entity) => entity.path.split('/').last).toList();
      expect(names.where((name) => name.endsWith('.part')), isEmpty);

      await store.write('other.jpg', bytes);
      await store.remove(path);
      expect(await store.read(path), isNull);
      expect(await store.read('other.jpg'), bytes);

      await store.clear();
      expect(await store.read('other.jpg'), isNull);
    });

    test('a path cannot climb out of the folder', () async {
      await store.write('../../escape.jpg', Uint8List.fromList([9]));
      expect(File('${directory.path}/escape.jpg').existsSync(), isFalse);
      expect(await store.read('../../escape.jpg'), isNotNull);
    });
  });

  test('the in-memory stores behave like the real ones', () async {
    final photos = InMemoryWallpaperPhotoStore();
    await photos.write('a', Uint8List.fromList([1]));
    expect(await photos.read('a'), [1]);
    await photos.clear();
    expect(await photos.read('a'), isNull);
  });
}
