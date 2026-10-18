import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/media_send/jpeg_metadata.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';

img.Image _picture(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 255 / width).round()
      ..g = (pixel.y * 255 / height).round()
      ..b = 120;
  }
  return image;
}

Uint8List _jpeg(int width, int height, {bool gps = false}) {
  final image = _picture(width, height);
  if (gps) {
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(51, 1);
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(7, 1);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(_picture(width, height)));

Uint8List _gif(int width, int height) {
  final first = _picture(width, height)..frameDuration = 100;
  final second = _picture(width, height)
    ..frameDuration = 100
    ..clear(img.ColorRgb8(255, 0, 0));
  first.addFrame(second);
  return Uint8List.fromList(img.encodeGif(first));
}

(int, int) _sizeOf(Uint8List bytes) {
  final decoded = img.decodeImage(bytes)!;
  return (decoded.width, decoded.height);
}

void main() {
  group('prepareProfileImage', () {
    test('a big photo becomes an avatar of at most 512 px, much smaller, '
        'without its GPS position', () async {
      final source = _jpeg(3000, 2000, gps: true);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'Me.JPEG',
        mimeType: 'image/jpeg',
        maxEdge: avatarMaxEdge,
      );
      expect(image.mimeType, 'image/jpeg');
      final (width, height) = _sizeOf(image.bytes);
      expect(width, 512);
      expect(height, closeTo(341, 1));
      expect(image.bytes.length, lessThan(source.length ~/ 5));
      expect(readJpegMetadata(image.bytes)!.hasGps, isFalse);
    });

    test('a banner keeps up to 1600 px', () async {
      final source = _jpeg(4000, 1500);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'sky.jpg',
        mimeType: 'image/jpeg',
        maxEdge: bannerMaxEdge,
      );
      final (width, height) = _sizeOf(image.bytes);
      expect(width, 1600);
      expect(height, closeTo(600, 1));
      expect(image.bytes.length, lessThan(source.length));
    });

    test(
      'a photo that is small enough is only cleaned, pixel for pixel',
      () async {
        final source = _jpeg(400, 300, gps: true);
        expect(readJpegMetadata(source)!.hasGps, isTrue);
        final image = await prepareProfileImage(
          bytes: source,
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
          maxEdge: avatarMaxEdge,
        );
        expect(_sizeOf(image.bytes), (400, 300));
        expect(readJpegMetadata(image.bytes)!.hasGps, isFalse);
        expect(image.fileName, 'a.jpg');
      },
    );

    test('a big PNG becomes a JPEG avatar named for it', () async {
      final source = _png(2000, 2000);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'Logo.PNG',
        mimeType: 'image/png',
        maxEdge: avatarMaxEdge,
      );
      expect(image.mimeType, 'image/jpeg');
      expect(image.fileName, 'Logo.jpg');
      expect(_sizeOf(image.bytes), (512, 512));
      expect(image.bytes.length, lessThan(100 * 1024));
    });

    test(
      'a small PNG is left as it is (it may have see-through parts)',
      () async {
        final source = _png(64, 64);
        final image = await prepareProfileImage(
          bytes: source,
          fileName: 'dot.png',
          mimeType: 'image/png',
          maxEdge: avatarMaxEdge,
        );
        expect(identical(image.bytes, source), isTrue);
        expect(image.mimeType, 'image/png');
        expect(image.fileName, 'dot.png');
      },
    );

    test('an animated GIF keeps its animation, even a big one', () async {
      final source = _gif(900, 900);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'dance.gif',
        mimeType: 'image/gif',
        maxEdge: avatarMaxEdge,
      );
      expect(identical(image.bytes, source), isTrue);
      expect(image.mimeType, 'image/gif');
      expect(img.decodeGif(image.bytes)!.numFrames, 2);
    });

    test('a GIF is recognised by its bytes when the type is wrong', () async {
      final source = _gif(900, 900);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'dance',
        mimeType: 'application/octet-stream',
        maxEdge: avatarMaxEdge,
      );
      expect(identical(image.bytes, source), isTrue);
    });

    test('something that is not a picture goes up untouched', () async {
      final source = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final image = await prepareProfileImage(
        bytes: source,
        fileName: 'x.png',
        mimeType: 'image/png',
        maxEdge: avatarMaxEdge,
      );
      expect(identical(image.bytes, source), isTrue);
      expect(image.mimeType, 'image/png');
    });
  });

  group('what the repositories upload', () {
    test('a profile avatar is stored scaled down', () async {
      final dataSource = _SettingsUploads();
      final repository = SupabaseSettingsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        storagePathSeed: () => 'seed-1',
      );
      final source = _png(1800, 1200);
      final path = await repository.uploadAvatar(
        fileName: 'Me.PNG',
        mimeType: 'image/png',
        bytes: source,
      );
      expect(path, 'user-1/seed-1-me.jpg');
      expect(dataSource.mimeType, 'image/jpeg');
      expect(_sizeOf(dataSource.bytes!), (512, 341));
    });

    test(
      'a banner is stored up to 1600 px and a circle avatar at 512',
      () async {
        final dataSource = _ExtrasUploads();
        final extras = ProfileExtrasRepository(
          dataSource,
          currentUserId: () => 'user-1',
          storagePathSeed: () => '42',
        );
        final banner = await extras.uploadBanner(
          fileName: 'sky.png',
          mimeType: 'image/png',
          bytes: _png(3200, 1000),
        );
        expect(banner, 'profile-banners/user-1/42-sky.jpg');
        expect(_sizeOf(dataSource.uploads.last.bytes), (1600, 500));

        final circle = await extras.uploadCircleAvatar(
          circleId: 'c1',
          fileName: 'me.png',
          mimeType: 'image/png',
          bytes: _png(1000, 1000),
        );
        expect(circle, 'user-1/42-circle-c1-me.jpg');
        expect(_sizeOf(dataSource.uploads.last.bytes), (512, 512));
      },
    );

    test('an animated avatar goes up as the GIF it is', () async {
      final dataSource = _SettingsUploads();
      final repository = SupabaseSettingsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        storagePathSeed: () => 'seed-1',
      );
      final source = _gif(700, 700);
      final path = await repository.uploadAvatar(
        fileName: 'dance.gif',
        mimeType: 'image/gif',
        bytes: source,
      );
      expect(path, 'user-1/seed-1-dance.gif');
      expect(dataSource.mimeType, 'image/gif');
      expect(identical(dataSource.bytes, source), isTrue);
    });
  });
}

class _SettingsUploads implements SettingsDataSource {
  Uint8List? bytes;
  String? mimeType;

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    this.bytes = bytes;
    this.mimeType = mimeType;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Upload {
  _Upload(this.bucket, this.path, this.bytes, this.mimeType);

  final String bucket;
  final String path;
  final Uint8List bytes;
  final String mimeType;
}

class _ExtrasUploads implements ProfileExtrasDataSource {
  final uploads = <_Upload>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async =>
      null;

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add(_Upload(bucket, path, bytes, mimeType));
  }
}
