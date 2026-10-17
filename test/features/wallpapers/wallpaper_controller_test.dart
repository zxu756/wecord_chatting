import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';

import 'wallpaper_fakes.dart';

const _dawn = ChatWallpaper.preset('dawn');
const _dots = ChatWallpaper.preset('dots');

ProviderContainer _container(
  WallpaperTestStores stores, {
  String? userId = 'user-1',
}) {
  final container = ProviderContainer(
    overrides: [
      ...stores.overrides,
      wallpaperUserIdProvider.overrideWithValue(userId),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'paints from the copy on this device before the server answers',
    () async {
      final stores = WallpaperTestStores();
      stores.cache.values['user-1'] = const WallpaperSettings(
        defaultWallpaper: _dawn,
        chats: {'a': _dots},
      );
      stores.repository.failLoad = StateError('offline');
      final container = _container(stores);
      final subscription = container.listen(wallpapersProvider, (_, _) {});
      addTearDown(subscription.close);

      expect(container.read(wallpapersProvider).loaded, isFalse);
      await _flush();
      expect(container.read(wallpapersProvider).loaded, isTrue);
      expect(container.read(chatWallpaperProvider('a')), _dots);
      // Another chat follows the default.
      expect(container.read(chatWallpaperProvider('b')), _dawn);
    },
  );

  test('the server wins once it answers, and is kept for next time', () async {
    final stores = WallpaperTestStores(
      repository: FakeWallpaperRepository(
        const WallpaperSettings(defaultWallpaper: _dots),
      ),
    );
    stores.cache.values['user-1'] = const WallpaperSettings(
      defaultWallpaper: _dawn,
    );
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);

    await _flush();
    await _flush();
    expect(container.read(wallpapersProvider).settings.defaultWallpaper, _dots);
    expect(stores.cache.values['user-1']!.defaultWallpaper, _dots);
  });

  test('a change on another device shows up', () async {
    final stores = WallpaperTestStores();
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    await _flush();
    expect(container.read(chatWallpaperProvider('a')).isNone, isTrue);

    stores.repository.changeElsewhere(
      const WallpaperSettings(chats: {'a': _dots}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(container.read(chatWallpaperProvider('a')), _dots);
  });

  test('setting a wallpaper shows at once, saves and remembers', () async {
    final stores = WallpaperTestStores();
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    await _flush();
    final controller = container.read(wallpapersProvider.notifier);

    final saving = controller.set('a', _dots);
    expect(container.read(chatWallpaperProvider('a')), _dots);
    await saving;
    expect(stores.repository.saves, [('a', _dots)]);
    expect(stores.cache.values['user-1']!.chats['a'], _dots);

    await controller.set(null, _dawn);
    expect(container.read(chatWallpaperProvider('b')), _dawn);
    expect(container.read(chatWallpaperProvider('a')), _dots);
  });

  test('a refused change is put back and reported', () async {
    final stores = WallpaperTestStores();
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    await _flush();
    final controller = container.read(wallpapersProvider.notifier);
    await controller.set('a', _dots);

    stores.repository.failWrites = StateError('no connection');
    await expectLater(controller.set('a', _dawn), throwsStateError);
    expect(container.read(chatWallpaperProvider('a')), _dots);
    await expectLater(controller.reset('a'), throwsStateError);
    expect(container.read(chatWallpaperProvider('a')), _dots);
    expect(stores.cache.values['user-1']!.chats['a'], _dots);
  });

  test('use default clears the chat\'s own wallpaper', () async {
    final stores = WallpaperTestStores();
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    await _flush();
    final controller = container.read(wallpapersProvider.notifier);
    await controller.set(null, _dawn);
    await controller.set('a', _dots);

    await controller.reset('a');
    expect(container.read(chatWallpaperProvider('a')), _dawn);
    expect(stores.repository.clears, ['a']);
    expect(container.read(wallpapersProvider).settings.hasOwn('a'), isFalse);
  });

  test(
    'a photo goes up scaled down and compressed, and is kept here',
    () async {
      final stores = WallpaperTestStores();
      final container = _container(stores);
      final subscription = container.listen(wallpapersProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(wallpapersProvider.notifier);

      // A photo bigger than a wallpaper needs to be.
      final big = samplePhotoBytes(width: 3000, height: 4000);
      final prepared = await prepareWallpaperPhoto(big);
      expect(prepared.length, lessThan(big.length));
      final size = (await readPhotoSize(prepared))!;
      expect(size.$1 > size.$2 ? size.$1 : size.$2, wallpaperPhotoEdge);
      expect(size.$2 / size.$1, closeTo(4 / 3, 0.01));
      final path = await controller.uploadPhoto(prepared);
      expect(path, matches(RegExp(r'^user-1/[0-9a-f-]{36}\.jpg$')));
      expect(stores.repository.bucket[path], prepared);
      expect(stores.photos.photos[path], prepared);
      expect(stores.repository.uploads, 1);
    },
  );

  test('replacing a photo frees the old one on the device too', () async {
    final stores = WallpaperTestStores();
    final container = _container(stores);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    await _flush();
    final controller = container.read(wallpapersProvider.notifier);
    final first = await controller.uploadPhoto(Uint8List.fromList([1, 2, 3]));
    await controller.set('a', ChatWallpaper.photo(first));
    final second = await controller.uploadPhoto(Uint8List.fromList([4, 5, 6]));
    await controller.set('a', ChatWallpaper.photo(second, blur: true));

    expect(stores.repository.removed, [first]);
    expect(stores.photos.photos.containsKey(first), isFalse);
    expect(stores.photos.photos.containsKey(second), isTrue);

    await controller.reset('a');
    expect(stores.repository.removed, [first, second]);
    expect(stores.photos.photos, isEmpty);
  });

  test('a picture that is not a picture is refused', () async {
    await expectLater(
      prepareWallpaperPhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<WallpaperPhotoException>()),
    );
  });

  test('nobody signed in: no wallpapers, and the photos are wiped', () async {
    final stores = WallpaperTestStores();
    stores.photos.photos['x'] = Uint8List.fromList([1]);
    stores.cache.values['user-1'] = const WallpaperSettings(
      defaultWallpaper: _dawn,
    );
    final container = _container(stores, userId: null);
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    expect(container.read(wallpapersProvider).loaded, isTrue);
    expect(container.read(chatWallpaperProvider('a')).isNone, isTrue);
    expect(stores.photos.photos, isEmpty);
    expect(stores.repository.loads, 0);
  });

  test('each person has their own copy', () async {
    final stores = WallpaperTestStores();
    stores.cache.values['user-1'] = const WallpaperSettings(
      defaultWallpaper: _dawn,
    );
    stores.cache.values['user-2'] = const WallpaperSettings(
      defaultWallpaper: _dots,
    );
    stores.repository.failLoad = StateError('offline');
    final container = _container(stores, userId: 'user-2');
    final subscription = container.listen(wallpapersProvider, (_, _) {});
    addTearDown(subscription.close);
    await _flush();
    expect(container.read(chatWallpaperProvider('a')), _dots);
  });
}
