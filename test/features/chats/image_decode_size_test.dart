import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'mixed_thread_fixture.dart';

/// A picture in a chat is decoded at the size it is shown, not at the size
/// it was sent: a 2560 pixel photo decodes to ~20 MB, and the image cache
/// (100 MB) holds five of them.
void main() {
  Future<void> settleImages(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('chat pictures are decoded at their display size', (
    tester,
  ) async {
    // A large photo: 1800 x 2400 would decode to 17 MB.
    final world = MixedThreadWorld(
      count: 6,
      wallpaper: false,
      slots: const [3],
      imageSize: (1800, 2400),
    );
    final cache = PaintingBinding.instance.imageCache..clear();
    world.prepare(tester);
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();
    await settleImages(tester);

    final decoded = cache.currentSizeBytes;
    final images = cache.liveImageCount + cache.currentSize;
    debugPrint(
      'Image cache after opening a chat of large pictures: '
      '${(decoded / 1e6).toStringAsFixed(1)} MB in '
      '${cache.currentSize} images ($images live or cached)',
    );
    expect(cache.currentSize, greaterThan(0));
    // Each tile is about 256 x 340 logical pixels at 3x: a picture decoded
    // that size is ~3 MB, not 17.
    expect(decoded / cache.currentSize, lessThan(5e6));

    await world.close(tester);
    cache.clear();
  });

  testWidgets('an avatar is decoded at the size of the avatar', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cache = PaintingBinding.instance.imageCache..clear();
    // A camera photo as the avatar: 1800 x 2400, 17 MB decoded.
    final photo = MemoryImage(samplePng(width: 1800, height: 2400));
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (var i = 0; i < 3; i++)
              PersonAvatar(name: 'Ada', size: 40, image: photo),
            ThingAvatar(label: 'Club', size: 40, image: photo),
          ],
        ),
      ),
    );
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'Image cache with 4 avatars of a large photo: '
      '${(cache.currentSizeBytes / 1e6).toStringAsFixed(2)} MB',
    );
    expect(cache.currentSize, greaterThan(0));
    // 40 logical pixels at 3x, twice over for pictures that are not square:
    // 240 x 320 pixels, 0.3 MB, not 17.
    expect(cache.currentSizeBytes, lessThan(1e6));
    cache.clear();
  });
}
