import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/media_send/blurhash.dart';
import 'package:wecord/features/chats/media_send/jpeg_metadata.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';

Uint8List _jpeg(
  int width,
  int height, {
  int orientation = 1,
  bool gps = false,
}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 255 / width).round()
      ..g = (pixel.y * 255 / height).round()
      ..b = 120;
  }
  image.exif.imageIfd.orientation = orientation;
  if (gps) {
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(51, 1);
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(7, 1);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

void main() {
  group('planPhotoCompression', () {
    PhotoPlan plan(
      String mime,
      int width,
      int height, {
      bool original = false,
    }) {
      return planPhotoCompression(
        mimeType: mime,
        width: width,
        height: height,
        original: original,
      );
    }

    test('a JPEG within 2560 px is only cleaned, never re-compressed', () {
      expect(
        plan('image/jpeg', 2560, 1440),
        const PhotoPlan(
          action: PhotoAction.stripMetadata,
          width: 2560,
          height: 1440,
          mimeType: 'image/jpeg',
        ),
      );
      expect(plan('image/jpeg', 800, 600).action, PhotoAction.stripMetadata);
    });

    test('a JPEG over 2560 px on its long edge is scaled and re-encoded', () {
      expect(
        plan('image/jpeg', 4032, 3024),
        const PhotoPlan(
          action: PhotoAction.reencode,
          width: 2560,
          height: 1920,
          mimeType: 'image/jpeg',
          quality: 85,
        ),
      );
      // Portrait: the height is the long edge.
      expect(plan('image/jpeg', 3024, 4032).width, 1920);
      expect(plan('image/jpeg', 3024, 4032).height, 2560);
    });

    test('Original quality keeps size and pixels but still cleans a JPEG', () {
      final original = plan('image/jpeg', 6000, 4000, original: true);
      expect(original.action, PhotoAction.stripMetadata);
      expect(original.width, 6000);
      expect(original.height, 4000);
    });

    test('PNGs are scaled only when too big and stay PNGs', () {
      expect(plan('image/png', 1200, 800).action, PhotoAction.keep);
      final big = plan('image/png', 5000, 2500);
      expect(big.action, PhotoAction.reencode);
      expect(big.mimeType, 'image/png');
      expect(big.width, 2560);
      expect(big.height, 1280);
      expect(
        plan('image/png', 5000, 2500, original: true).action,
        PhotoAction.keep,
      );
    });

    test('HEIC becomes a JPEG, at higher quality when original', () {
      final normal = plan('image/heic', 4000, 3000);
      expect(normal.action, PhotoAction.reencode);
      expect(normal.mimeType, 'image/jpeg');
      expect(normal.quality, 85);
      expect(normal.width, 2560);
      final original = plan('image/heif', 4000, 3000, original: true);
      expect(original.quality, 95);
      expect(original.width, 4000);
    });

    test('GIFs, WebP and unknown types are left alone', () {
      for (final mime in ['image/gif', 'image/webp', 'image/avif', 'image/x']) {
        expect(plan(mime, 8000, 8000).action, PhotoAction.keep, reason: mime);
      }
    });
  });

  group('JPEG metadata', () {
    test('reads the orientation and GPS of an EXIF block', () {
      final jpeg = _jpeg(40, 20, orientation: 6, gps: true);
      final meta = readJpegMetadata(jpeg)!;
      expect(meta.orientation, 6);
      expect(meta.hasGps, isTrue);
      expect(meta.swapsAxes, isTrue);
    });

    test('stripping drops the GPS position and keeps the orientation', () {
      final jpeg = _jpeg(40, 20, orientation: 6, gps: true);
      final stripped = stripJpegMetadata(jpeg)!;
      final meta = readJpegMetadata(stripped)!;
      expect(meta.hasGps, isFalse);
      expect(meta.orientation, 6);
      expect(stripped.length, lessThan(jpeg.length));
      // Still a JPEG that decodes.
      expect(img.decodeJpg(stripped), isNotNull);
    });

    test('an upright photo ends up with no EXIF block at all', () {
      final stripped = stripJpegMetadata(_jpeg(40, 20, gps: true))!;
      final meta = readJpegMetadata(stripped)!;
      expect(meta.orientation, 1);
      expect(meta.hasGps, isFalse);
      // No APP1 marker (0xFFE1) before the scan.
      var hasApp1 = false;
      for (var i = 0; i + 1 < stripped.length; i++) {
        if (stripped[i] == 0xFF && stripped[i + 1] == 0xE1) {
          hasApp1 = true;
        }
      }
      expect(hasApp1, isFalse);
    });

    test('the pixels are not touched', () {
      final jpeg = _jpeg(64, 48, orientation: 3, gps: true);
      final stripped = stripJpegMetadata(jpeg)!;
      final before = img.decodeJpg(jpeg)!;
      final after = img.decodeJpg(stripped)!;
      expect(after.width, before.width);
      expect(after.height, before.height);
      expect(after.getPixel(10, 10).r, before.getPixel(10, 10).r);
    });

    test('anything that is not a JPEG is refused', () {
      expect(readJpegMetadata(Uint8List.fromList([1, 2, 3, 4, 5, 6])), isNull);
      expect(stripJpegMetadata(Uint8List.fromList([1, 2, 3, 4, 5, 6])), isNull);
    });
  });

  group('preparePhoto', () {
    testWidgets('a big photo is scaled to 2560 px and loses its GPS', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final source = _jpeg(3200, 1600, gps: true);
        final prepared = await preparePhoto(
          bytes: source,
          fileName: 'beach.JPG',
          mimeType: 'image/jpeg',
          original: false,
        );
        expect(prepared.plan.action, PhotoAction.reencode);
        expect(prepared.width, 2560);
        expect(prepared.height, 1280);
        expect(prepared.mimeType, 'image/jpeg');
        expect(prepared.fileName, 'beach.JPG');
        expect(readJpegMetadata(prepared.bytes)!.hasGps, isFalse);
        final decoded = img.decodeJpg(prepared.bytes)!;
        expect(decoded.width, 2560);
        expect(decoded.height, 1280);
        expect(BlurHash.isValid(prepared.blurhash), isTrue);
      });
    });

    testWidgets('a small sideways photo keeps its orientation, loses GPS', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final source = _jpeg(800, 400, orientation: 6, gps: true);
        final prepared = await preparePhoto(
          bytes: source,
          fileName: 'p.jpg',
          mimeType: 'image/jpeg',
          original: false,
        );
        expect(prepared.plan.action, PhotoAction.stripMetadata);
        // Shown upright: 400 wide, 800 tall.
        expect(prepared.width, 400);
        expect(prepared.height, 800);
        final meta = readJpegMetadata(prepared.bytes)!;
        expect(meta.orientation, 6);
        expect(meta.hasGps, isFalse);
      });
    });

    testWidgets('Original quality sends the full size', (tester) async {
      await tester.runAsync(() async {
        final source = _jpeg(3000, 1000, gps: true);
        final prepared = await preparePhoto(
          bytes: source,
          fileName: 'wide.jpg',
          mimeType: 'image/jpeg',
          original: true,
        );
        expect(prepared.width, 3000);
        expect(prepared.height, 1000);
        expect(readJpegMetadata(prepared.bytes)!.hasGps, isFalse);
      });
    });

    testWidgets('a rotated big photo is scaled upright', (tester) async {
      await tester.runAsync(() async {
        final source = _jpeg(3200, 1600, orientation: 6);
        final prepared = await preparePhoto(
          bytes: source,
          fileName: 'p.jpg',
          mimeType: 'image/jpeg',
          original: false,
        );
        // Orientation 6 turns it to 1600 x 3200, then it is scaled.
        expect(prepared.width, 1280);
        expect(prepared.height, 2560);
        expect(img.decodeJpg(prepared.bytes)!.height, 2560);
      });
    });

    testWidgets('something that is not a picture is passed on untouched', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final junk = Uint8List.fromList(List.filled(64, 7));
        final prepared = await preparePhoto(
          bytes: junk,
          fileName: 'x.jpg',
          mimeType: 'image/jpeg',
          original: false,
        );
        expect(prepared.bytes, junk);
        expect(prepared.blurhash, isNull);
      });
    });
  });

  group('BlurHash', () {
    test('round trips a colour', () {
      final pixels = Uint8List(16 * 16 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 220;
        pixels[i + 1] = 40;
        pixels[i + 2] = 40;
        pixels[i + 3] = 255;
      }
      final hash = BlurHash.encode(pixels, width: 16, height: 16);
      expect(hash.length, 4 + 2 * 4 * 3);
      expect(BlurHash.isValid(hash), isTrue);
      final average = BlurHash.averageColor(hash)!;
      expect((average.r * 255).round(), closeTo(220, 2));
      expect((average.g * 255).round(), closeTo(40, 2));
      // The format samples its waves at the pixel corners, so a flat
      // colour comes back a little off at this tiny size.
      final decoded = BlurHash.decode(hash, width: 4, height: 4);
      expect(decoded[4], closeTo(220, 20));
      expect(decoded[5], closeTo(40, 20));
      expect(decoded[7], 255);
    });

    test('keeps a left to right gradient', () {
      const w = 32;
      const h = 16;
      final pixels = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = 4 * (x + y * w);
          pixels[i] = x < w / 2 ? 240 : 10;
          pixels[i + 1] = 20;
          pixels[i + 2] = x < w / 2 ? 20 : 240;
          pixels[i + 3] = 255;
        }
      }
      final hash = BlurHash.encode(pixels, width: w, height: h);
      final decoded = BlurHash.decode(hash, width: 8, height: 4);
      // Left is red, right is blue.
      expect(decoded[0], greaterThan(decoded[2]));
      final last = 4 * 7;
      expect(decoded[last + 2], greaterThan(decoded[last]));
    });

    test('decodes a hash from the BlurHash site and rejects bad ones', () {
      const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      expect(BlurHash.isValid(hash), isTrue);
      expect(BlurHash.decode(hash, width: 6, height: 4).length, 6 * 4 * 4);
      expect(BlurHash.isValid('short'), isFalse);
      expect(BlurHash.isValid('LEHV6nWB2yk8pyo0adR*.7kCMdnjX'), isFalse);
      expect(BlurHash.isValid(null), isFalse);
      expect(BlurHash.componentsFor(100, 50), (4, 3));
      expect(BlurHash.componentsFor(50, 100), (3, 4));
    });
  });
}
