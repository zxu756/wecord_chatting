import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/media_send/blurhash.dart';
import 'package:wecord/features/chats/media_send/jpeg_metadata.dart';

/// The longest side a sent photo keeps; bigger ones are scaled down.
const maxPhotoEdge = 2560;

/// JPEG quality of photos that are re-encoded.
const photoJpegQuality = 85;

/// Quality when a HEIC photo has to become a JPEG but the sender asked for
/// the original.
const originalJpegQuality = 95;

/// What to do with a photo before it is uploaded.
enum PhotoAction {
  /// Send the file as it is (GIFs, WebP, SVG, PNGs within the limit...).
  keep,

  /// A JPEG that needs no new encoding: drop its metadata (GPS position,
  /// camera, time...) but keep the pixels and the orientation exactly.
  stripMetadata,

  /// Decode, scale down to [maxPhotoEdge] and encode again (JPEG at
  /// quality 85, PNG stays PNG). EXIF is gone and the orientation is
  /// applied to the pixels.
  reencode,
}

/// The decision for one photo; see [planPhotoCompression].
@immutable
class PhotoPlan {
  const PhotoPlan({
    required this.action,
    required this.width,
    required this.height,
    required this.mimeType,
    this.quality = photoJpegQuality,
  });

  final PhotoAction action;

  /// The size after the plan.
  final int width;
  final int height;

  /// The type after the plan (a HEIC photo becomes image/jpeg).
  final String mimeType;
  final int quality;

  @override
  bool operator ==(Object other) =>
      other is PhotoPlan &&
      other.action == action &&
      other.width == width &&
      other.height == height &&
      other.mimeType == mimeType &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(action, width, height, mimeType, quality);

  @override
  String toString() =>
      'PhotoPlan($action, ${width}x$height, $mimeType, q$quality)';
}

bool _isJpegType(String mime) =>
    mime == 'image/jpeg' || mime == 'image/jpg' || mime == 'image/pjpeg';

bool _isHeicType(String mime) =>
    mime == 'image/heic' ||
    mime == 'image/heif' ||
    mime == 'image/heic-sequence' ||
    mime == 'image/heif-sequence';

/// Decides what happens to a photo of [width] x [height] (as shown, after
/// its orientation) and type [mimeType].
///
/// * JPEG: longer than [maxPhotoEdge]: scaled and encoded again; otherwise
///   only its metadata is dropped, so a small photo is never re-compressed.
/// * PNG: scaled down when longer than [maxPhotoEdge], otherwise untouched.
/// * HEIC and BMP: become JPEG (browsers cannot show them), scaled unless
///   [original].
/// * GIF, WebP, AVIF, SVG and anything else: untouched (they may be
///   animated or have transparency).
///
/// With [original] (the "Original quality" switch) nothing is scaled or
/// re-compressed; a JPEG still loses its metadata.
PhotoPlan planPhotoCompression({
  required String mimeType,
  required int width,
  required int height,
  required bool original,
}) {
  final mime = mimeType.toLowerCase();
  final longEdge = math.max(width, height);
  final scaled = _scaledSize(width, height);
  final needsScale = !original && longEdge > maxPhotoEdge;

  if (_isJpegType(mime)) {
    if (needsScale) {
      return PhotoPlan(
        action: PhotoAction.reencode,
        width: scaled.$1,
        height: scaled.$2,
        mimeType: 'image/jpeg',
      );
    }
    return PhotoPlan(
      action: PhotoAction.stripMetadata,
      width: width,
      height: height,
      mimeType: 'image/jpeg',
    );
  }
  if (mime == 'image/png') {
    if (needsScale) {
      return PhotoPlan(
        action: PhotoAction.reencode,
        width: scaled.$1,
        height: scaled.$2,
        mimeType: 'image/png',
      );
    }
    return PhotoPlan(
      action: PhotoAction.keep,
      width: width,
      height: height,
      mimeType: mime,
    );
  }
  if (_isHeicType(mime) || mime == 'image/bmp') {
    return PhotoPlan(
      action: PhotoAction.reencode,
      width: needsScale ? scaled.$1 : width,
      height: needsScale ? scaled.$2 : height,
      mimeType: 'image/jpeg',
      quality: original ? originalJpegQuality : photoJpegQuality,
    );
  }
  return PhotoPlan(
    action: PhotoAction.keep,
    width: width,
    height: height,
    mimeType: mime,
  );
}

(int, int) _scaledSize(int width, int height) {
  final longEdge = math.max(width, height);
  if (longEdge <= maxPhotoEdge) {
    return (width, height);
  }
  final factor = maxPhotoEdge / longEdge;
  return (
    math.max(1, (width * factor).round()),
    math.max(1, (height * factor).round()),
  );
}

/// A photo ready to upload.
class PreparedPhoto {
  const PreparedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.width,
    required this.height,
    required this.plan,
    this.blurhash,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final int width;
  final int height;
  final PhotoPlan plan;
  final String? blurhash;
}

/// The size of the picture in [bytes] as it is shown (EXIF orientation
/// applied); null when it cannot be decoded.
Future<(int, int)?> readPhotoSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // The engines (and browsers) apply the EXIF orientation, so this is
    // the size the photo is shown at.
    return (descriptor.width, descriptor.height);
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Makes [bytes] ready to send: scales, re-encodes or cleans it as
/// [planPhotoCompression] says, and works out its size and BlurHash.
/// Falls back to the untouched file (metadata aside) when it cannot be
/// decoded.
Future<PreparedPhoto> preparePhoto({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required bool original,
}) async {
  final size = await readPhotoSize(bytes);
  if (size == null) {
    return PreparedPhoto(
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      width: 0,
      height: 0,
      plan: PhotoPlan(
        action: PhotoAction.keep,
        width: 0,
        height: 0,
        mimeType: mimeType,
      ),
    );
  }
  var plan = planPhotoCompression(
    mimeType: mimeType,
    width: size.$1,
    height: size.$2,
    original: original,
  );

  var outBytes = bytes;
  var outName = fileName;
  if (plan.action == PhotoAction.stripMetadata) {
    final cleaned = stripJpegMetadata(bytes);
    if (cleaned != null) {
      outBytes = cleaned;
    } else {
      // Not a well-formed JPEG: decoding and encoding drops the metadata.
      plan = PhotoPlan(
        action: PhotoAction.reencode,
        width: plan.width,
        height: plan.height,
        mimeType: 'image/jpeg',
        quality: original ? originalJpegQuality : photoJpegQuality,
      );
    }
  }
  if (plan.action == PhotoAction.reencode) {
    final encoded = await _decodeAndEncode(bytes, plan);
    if (encoded != null) {
      outBytes = encoded.bytes;
      plan = PhotoPlan(
        action: PhotoAction.reencode,
        width: encoded.width,
        height: encoded.height,
        mimeType: plan.mimeType,
        quality: plan.quality,
      );
      outName = _renamed(fileName, plan.mimeType);
    } else {
      plan = PhotoPlan(
        action: PhotoAction.keep,
        width: size.$1,
        height: size.$2,
        mimeType: mimeType,
      );
    }
  }
  final hash = await photoBlurHash(outBytes);
  return PreparedPhoto(
    bytes: outBytes,
    mimeType: plan.mimeType,
    fileName: outName,
    width: plan.width,
    height: plan.height,
    plan: plan,
    blurhash: hash,
  );
}

/// "IMG_1.HEIC" with the extension of [mimeType] ("IMG_1.jpg").
String _renamed(String fileName, String mimeType) {
  final extension = switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    _ => null,
  };
  if (extension == null) {
    return fileName;
  }
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final current = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  if (current == extension || (extension == 'jpg' && current == 'jpeg')) {
    return fileName;
  }
  return '${stem.isEmpty ? 'photo' : stem}.$extension';
}

class _Encoded {
  const _Encoded(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

Future<_Encoded?> _decodeAndEncode(Uint8List bytes, PhotoPlan plan) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    // Only the long side is given, so the decoder keeps the proportions
    // (and applies the EXIF orientation, which the plan's size already
    // reflects).
    final landscape = plan.width >= plan.height;
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: landscape ? plan.width : null,
      targetHeight: landscape ? null : plan.height,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final width = image.width;
    final height = image.height;
    if (plan.mimeType == 'image/png') {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return null;
      }
      return _Encoded(data.buffer.asUint8List(), width, height);
    }
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      return null;
    }
    final jpeg = await compute(
      _encodeJpeg,
      _JpegJob(rgba.buffer.asUint8List(), width, height, plan.quality),
    );
    return _Encoded(jpeg, width, height);
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

class _JpegJob {
  const _JpegJob(this.rgba, this.width, this.height, this.quality);

  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}

/// Runs in an isolate (inline on the web). The pixels carry no metadata, so
/// none is written.
Uint8List _encodeJpeg(_JpegJob job) {
  // JPEG has no transparency: lay see-through pixels on white.
  final rgba = job.rgba;
  for (var i = 3; i < rgba.length; i += 4) {
    final alpha = rgba[i];
    if (alpha != 255) {
      final back = 255 * (255 - alpha);
      rgba[i - 3] = (rgba[i - 3] * alpha + back) ~/ 255;
      rgba[i - 2] = (rgba[i - 2] * alpha + back) ~/ 255;
      rgba[i - 1] = (rgba[i - 1] * alpha + back) ~/ 255;
      rgba[i] = 255;
    }
  }
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: job.quality));
}

/// A BlurHash for the picture in [bytes], from a 32 pixel version of it;
/// null when it cannot be decoded.
Future<String?> photoBlurHash(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final size = await readPhotoSize(bytes);
    if (size == null || size.$1 <= 0 || size.$2 <= 0) {
      return null;
    }
    final landscape = size.$1 >= size.$2;
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: landscape ? 32 : null,
      targetHeight: landscape ? null : 32,
    );
    image = (await codec.getNextFrame()).image;
    return await blurHashOfImage(image);
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// The BlurHash of a (small) decoded image.
Future<String?> blurHashOfImage(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null || image.width <= 0 || image.height <= 0) {
    return null;
  }
  final (x, y) = BlurHash.componentsFor(image.width, image.height);
  return BlurHash.encode(
    data.buffer.asUint8List(),
    width: image.width,
    height: image.height,
    componentsX: x,
    componentsY: y,
  );
}

/// A small JPEG of the picture in [bytes] (at most [maxEdge] pixels on its
/// long side), for the tray and for the bubble while it uploads; null when
/// it cannot be decoded.
Future<Uint8List?> makeThumbnail(Uint8List bytes, {int maxEdge = 480}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final size = await readPhotoSize(bytes);
    if (size == null) {
      return null;
    }
    final landscape = size.$1 >= size.$2;
    final longEdge = landscape ? size.$1 : size.$2;
    final scaled = longEdge > maxEdge;
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: scaled && landscape ? maxEdge : null,
      targetHeight: scaled && !landscape ? maxEdge : null,
    );
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      return null;
    }
    return await compute(
      _encodeJpeg,
      _JpegJob(rgba.buffer.asUint8List(), image.width, image.height, 72),
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
