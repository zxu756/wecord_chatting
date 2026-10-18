import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/user_sticker.dart';

import 'sticker_fakes.dart';

Uint8List _webp({required bool animated}) {
  // RIFF....WEBPVP8X + 4 size bytes + flags: the animation bit is 0x02.
  final bytes = Uint8List(30);
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WEBP'.codeUnits);
  bytes.setAll(12, 'VP8X'.codeUnits);
  bytes[20] = animated ? 0x12 : 0x10;
  return bytes;
}

Uint8List _png({required bool animated}) {
  final bytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  void chunk(String type, int length) {
    bytes.addAll([0, 0, 0, length]);
    bytes.addAll(type.codeUnits);
    bytes.addAll(List.filled(length, 0));
    bytes.addAll([0, 0, 0, 0]);
  }

  chunk('IHDR', 13);
  if (animated) {
    chunk('acTL', 8);
  }
  chunk('IDAT', 4);
  return Uint8List.fromList(bytes);
}

void main() {
  group('formats', () {
    test('the format comes from the first bytes', () {
      expect(sniffStickerFormat(tinyGif()), StickerFormat.gif);
      expect(sniffStickerFormat(_webp(animated: false)), StickerFormat.webp);
      expect(sniffStickerFormat(_png(animated: false)), StickerFormat.png);
      expect(
        sniffStickerFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3])),
        isNull,
      );
      expect(sniffStickerFormat(Uint8List(0)), isNull);
    });

    test('a GIF is animated from its second frame', () {
      expect(
        isAnimatedStickerBytes(tinyGif(frames: 1), StickerFormat.gif),
        isFalse,
      );
      expect(
        isAnimatedStickerBytes(tinyGif(frames: 2), StickerFormat.gif),
        isTrue,
      );
      expect(
        isAnimatedStickerBytes(tinyGif(frames: 5), StickerFormat.gif),
        isTrue,
      );
      // Padding before the trailer does not make frames.
      expect(
        isAnimatedStickerBytes(
          tinyGif(frames: 1, extraBytes: 3000),
          StickerFormat.gif,
        ),
        isFalse,
      );
      expect(
        isAnimatedStickerBytes(
          Uint8List.fromList([0x47, 0x49, 0x46]),
          StickerFormat.gif,
        ),
        isFalse,
      );
    });

    test('a WebP says so in its header, a PNG with an animation chunk', () {
      expect(
        isAnimatedStickerBytes(_webp(animated: true), StickerFormat.webp),
        isTrue,
      );
      expect(
        isAnimatedStickerBytes(_webp(animated: false), StickerFormat.webp),
        isFalse,
      );
      expect(
        isAnimatedStickerBytes(_png(animated: true), StickerFormat.png),
        isTrue,
      );
      expect(
        isAnimatedStickerBytes(_png(animated: false), StickerFormat.png),
        isFalse,
      );
    });

    test('a picture is fitted to the long side', () {
      expect(fitWithin(1200, 800, 512), (width: 512, height: 341));
      expect(fitWithin(800, 1200, 512), (width: 341, height: 512));
      expect(fitWithin(300, 200, 512), (width: 300, height: 200));
      expect(fitWithin(4000, 1, 512), (width: 512, height: 1));
    });

    test('the library path says what it is', () {
      expect(userStickerExtension('a/b.gif'), 'gif');
      expect(userStickerExtension('a/b.WEBP'), 'webp');
      expect(userStickerExtension('a/b.png'), 'png');
      expect(userStickerExtension('a/b'), 'png');
      expect(userSticker('s1', animated: true).mimeType, 'image/gif');
      expect(userSticker('s2').mimeType, 'image/png');
    });
  });

  group('prepareSticker', () {
    testWidgets('a big still is drawn to 512 and kept as a PNG', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final prepared = await prepareSticker(samplePhotoPng());
        expect(prepared.format, StickerFormat.png);
        expect(prepared.animated, isFalse);
        expect(prepared.width, 512);
        expect(prepared.height, 341);
        expect(sniffStickerFormat(prepared.bytes), StickerFormat.png);
        expect(prepared.bytes.length, lessThanOrEqualTo(maxUserStickerBytes));
      });
    });

    testWidgets('a small sticker stays as it is, transparency included', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final prepared = await prepareSticker(sampleStickerPng(size: 160));
        expect(prepared.width, 160);
        expect(prepared.height, 160);
        expect(prepared.format, StickerFormat.png);
      });
    });

    testWidgets('a moving GIF within 1 MB is kept byte for byte', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final gif = tinyGif(frames: 3);
        final prepared = await prepareSticker(gif);
        expect(prepared.animated, isTrue);
        expect(prepared.format, StickerFormat.gif);
        expect(prepared.bytes, gif);
        expect(prepared.width, 1);
        expect(prepared.height, 1);
      });
    });

    testWidgets('a moving GIF over 1 MB is refused, or kept as a still', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final big = tinyGif(frames: 2, extraBytes: maxUserStickerBytes + 10);
        await expectLater(
          prepareSticker(big),
          throwsA(isA<UserStickerException>()),
        );
        final still = await prepareSticker(big, stillIfTooLarge: true);
        expect(still.animated, isFalse);
        expect(still.format, StickerFormat.png);
      });
    });

    testWidgets('something that is not a picture is refused', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          prepareSticker(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
          throwsA(isA<UserStickerException>()),
        );
      });
    });
  });
}
