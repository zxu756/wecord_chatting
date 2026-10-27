import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:wecord/features/whiteboard/whiteboard_models.dart';

/// A picture ready to go on a board: small enough for the bucket (5 MB, in
/// JPEG, PNG, GIF or WebP) and no bigger than 1600 pixels on its long side.
class WhiteboardPicture {
  const WhiteboardPicture({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int width;
  final int height;

  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());
}

const _allowedTypes = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};

Future<ui.Image> _decode(Uint8List bytes, {int? targetLongSide}) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final first = await probe.getNextFrame();
  final natural = first.image;
  final width = natural.width;
  final height = natural.height;
  probe.dispose();
  if (targetLongSide == null || math.max(width, height) <= targetLongSide) {
    return natural;
  }
  natural.dispose();
  final landscape = width >= height;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: landscape ? targetLongSide : null,
    targetHeight: landscape ? null : targetLongSide,
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

String _baseName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return base.isEmpty ? 'picture' : base;
}

/// Reads [bytes], scales the picture down when needed and returns what to
/// upload; null when it cannot be read as a picture.
Future<WhiteboardPicture?> prepareWhiteboardPicture(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  try {
    var image = await _decode(bytes);
    final longSide = math.max(image.width, image.height);
    if (_allowedTypes.contains(mimeType) &&
        bytes.length <= WhiteboardLimits.maxPictureBytes &&
        longSide <= WhiteboardLimits.maxPictureSide) {
      final result = WhiteboardPicture(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        width: image.width,
        height: image.height,
      );
      image.dispose();
      return result;
    }
    image.dispose();
    // Re-encoded as PNG at smaller and smaller sizes until it fits.
    for (final side in const [1600, 1200, 800, 500]) {
      image = await _decode(bytes, targetLongSide: side);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (data != null && data.lengthInBytes <= WhiteboardLimits.maxPictureBytes) {
        return WhiteboardPicture(
          bytes: data.buffer.asUint8List(),
          fileName: '${_baseName(fileName)}.png',
          mimeType: 'image/png',
          width: width,
          height: height,
        );
      }
    }
    return null;
  } on Object {
    return null;
  }
}
