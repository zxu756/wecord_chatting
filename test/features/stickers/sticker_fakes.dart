import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:image/image.dart' as img;
import 'package:wecord/features/stickers/sticker_cutout.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';

/// A [UserSticker] with sensible defaults.
UserSticker userSticker(
  String id, {
  bool animated = false,
  int sortKey = 0,
  int width = 256,
  int height = 256,
}) {
  final extension = animated ? 'gif' : 'png';
  return UserSticker(
    id: id,
    ownerId: 'user-1',
    path: 'user-1/$id.$extension',
    width: width,
    height: height,
    animated: animated,
    sortKey: sortKey,
    createdAt: DateTime.utc(2026, 10, 22),
  );
}

/// A round "face" on a transparent background, as a PNG: the kind of thing a
/// sticker is. [hue] picks the colour.
Uint8List sampleStickerPng({
  int size = 160,
  int hue = 210,
  bool transparentCorners = true,
}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final center = size / 2;
  final radius = size * 0.45;
  final face = HSVColor.fromAHSV(1, hue.toDouble(), 0.55, 0.95).toColor();
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - center;
      final dy = y - center;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= radius) {
        var r = (face.r * 255).round();
        var g = (face.g * 255).round();
        var b = (face.b * 255).round();
        // Eyes and a smile.
        final eyeY = center - radius * 0.2;
        for (final eyeX in [center - radius * 0.35, center + radius * 0.35]) {
          final ex = x - eyeX;
          final ey = y - eyeY;
          if (ex * ex + ey * ey < radius * radius * 0.02) {
            r = 40;
            g = 40;
            b = 60;
          }
        }
        final smileDistance = math.sqrt(
          dx * dx + (dy - radius * 0.05) * (dy - radius * 0.05),
        );
        if ((smileDistance - radius * 0.55).abs() < radius * 0.06 &&
            dy > radius * 0.1) {
          r = 40;
          g = 40;
          b = 60;
        }
        image.setPixelRgba(x, y, r, g, b, 255);
      } else {
        image.setPixelRgba(x, y, 255, 255, 255, transparentCorners ? 0 : 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// A wide opaque picture with a flat background (a photo, say).
Uint8List samplePhotoPng({int width = 1200, int height = 800}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(90, 140, 200));
  img.fillCircle(
    image,
    x: width ~/ 2,
    y: height ~/ 2,
    radius: height ~/ 4,
    color: img.ColorRgb8(250, 200, 80),
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// A GIF of [frames] 1x1 frames: the smallest moving picture.
Uint8List tinyGif({int frames = 2, int extraBytes = 0}) {
  final bytes = <int>[
    ...'GIF89a'.codeUnits,
    1, 0, 1, 0, 0x80, 0, 0, // 1x1, a two-colour table
    0, 0, 0, 255, 255, 255,
  ];
  for (var i = 0; i < frames; i++) {
    bytes.addAll([0x21, 0xF9, 4, 0, 10, 0, 0, 0]); // graphic control
    bytes.addAll([0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0]); // image descriptor
    bytes.addAll([2, 2, 0x44, 1, 0]); // 1 pixel of LZW data
  }
  if (extraBytes > 0) {
    // A comment extension padding the file out.
    var left = extraBytes;
    bytes.addAll([0x21, 0xFE]);
    while (left > 0) {
      final chunk = math.min(255, left);
      bytes.add(chunk);
      bytes.addAll(List.filled(chunk, 0x20));
      left -= chunk;
    }
    bytes.add(0);
  }
  bytes.add(0x3B);
  return Uint8List.fromList(bytes);
}

/// A [UserStickersRepository] that keeps everything in memory.
class FakeUserStickersRepository implements UserStickersRepository {
  FakeUserStickersRepository([List<UserSticker>? stickers])
    : stickers = stickers ?? [];

  List<UserSticker> stickers;
  final added = <PreparedSticker>[];
  final deleted = <String>[];
  final reorders = <List<String>>[];
  final sent = <({String conversationId, String stickerId})>[];
  final downloads = <StickerFile>[];

  /// What [download] answers by file path; a sample picture otherwise.
  final files = <String, Uint8List>{};

  /// Thrown by the next [add] / [send] when set.
  Object? addError;
  Object? sendError;
  Object? downloadError;

  @override
  Future<List<UserSticker>> list() async => [...stickers];

  @override
  Future<UserSticker> add(PreparedSticker sticker) async {
    final error = addError;
    if (error != null) {
      throw error;
    }
    added.add(sticker);
    final created = userSticker(
      'added-${added.length}',
      animated: sticker.animated,
      sortKey: -added.length,
      width: sticker.width,
      height: sticker.height,
    );
    stickers = [created, ...stickers];
    return created;
  }

  @override
  Future<void> delete(UserSticker sticker) async {
    deleted.add(sticker.id);
    stickers = [
      for (final other in stickers)
        if (other.id != sticker.id) other,
    ];
  }

  @override
  Future<void> reorder(List<String> ids) async {
    reorders.add(ids);
    final byId = {for (final sticker in stickers) sticker.id: sticker};
    stickers = [for (final id in ids) ?byId[id]];
  }

  @override
  Future<String> createUrl(StickerFile file) async =>
      'https://example.test/${file.bucket}/${file.path}';

  @override
  Future<Uint8List> download(StickerFile file) async {
    downloads.add(file);
    final error = downloadError;
    if (error != null) {
      throw error;
    }
    return files[file.path] ?? sampleStickerPng();
  }

  @override
  Future<void> send({
    required String conversationId,
    required UserSticker sticker,
  }) async {
    final error = sendError;
    if (error != null) {
      throw error;
    }
    sent.add((conversationId: conversationId, stickerId: sticker.id));
  }
}

/// A [StickerCutout] that cuts a fixed picture out, or fails.
class FakeStickerCutout implements StickerCutout {
  FakeStickerCutout({this.available = true, Uint8List? result})
    : result = result ?? sampleStickerPng(hue: 20);

  bool available;
  Uint8List result;
  StickerCutoutFailure? failure;
  final cutOuts = <int>[];
  Completer<void>? gate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Uint8List> cutOut(Uint8List image) async {
    cutOuts.add(image.length);
    await gate?.future;
    final failure = this.failure;
    if (failure != null) {
      throw StickerCutoutException(failure);
    }
    return result;
  }
}

/// Providers for a test of stickers: the library [repository], the pictures
/// of its files (every file shows [image], the sample sticker by default)
/// and the [cutout].
List<Override> stickerOverrides(
  FakeUserStickersRepository repository, {
  FakeStickerCutout? cutout,
  Uint8List? image,
  bool imagesLoad = true,
}) {
  final picture = image ?? sampleStickerPng();
  return [
    userStickersRepositoryProvider.overrideWithValue(repository),
    stickerFileImageProvider.overrideWith(
      (ref, file) async => imagesLoad ? MemoryImage(picture) : null,
    ),
    stickerCutoutProvider.overrideWithValue(cutout ?? FakeStickerCutout()),
  ];
}
