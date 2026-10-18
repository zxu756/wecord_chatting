import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:wecord/features/stickers/user_sticker.dart';

/// The picture formats a library sticker is kept in.
enum StickerFormat {
  png,
  gif,
  webp;

  String get extension => name;
  String get mimeType => 'image/$name';
}

/// What [prepareSticker] makes: bytes ready for the library.
class PreparedSticker {
  const PreparedSticker({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.animated,
  });

  final Uint8List bytes;
  final StickerFormat format;
  final int width;
  final int height;
  final bool animated;
}

/// The format of a picture by its first bytes: PNG, GIF or WebP; null for
/// anything else (JPEG, HEIC, ...).
StickerFormat? sniffStickerFormat(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return StickerFormat.png;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return StickerFormat.gif;
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 'RIFF') &&
      _ascii(bytes, 8, 'WEBP')) {
    return StickerFormat.webp;
  }
  return null;
}

bool _ascii(Uint8List bytes, int offset, String text) {
  if (offset + text.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < text.length; i++) {
    if (bytes[offset + i] != text.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

/// Whether [bytes] of [format] hold more than one frame. A GIF is walked
/// block by block (two image descriptors make it a movie); a WebP says so in
/// its header flags; an animated PNG (APNG) has an `acTL` chunk before its
/// first `IDAT`.
bool isAnimatedStickerBytes(Uint8List bytes, StickerFormat format) {
  return switch (format) {
    StickerFormat.gif => _gifFrameCount(bytes) > 1,
    StickerFormat.webp => _webpAnimated(bytes),
    StickerFormat.png => _apngAnimated(bytes),
  };
}

int _gifFrameCount(Uint8List bytes) {
  if (bytes.length < 13) {
    return 0;
  }
  var index = 10;
  final packed = bytes[index];
  index += 3;
  if (packed & 0x80 != 0) {
    index += 3 * (1 << ((packed & 0x07) + 1));
  }
  var frames = 0;
  while (index < bytes.length) {
    final block = bytes[index++];
    if (block == 0x3B) {
      break;
    }
    if (block == 0x21) {
      index++;
      index = _skipSubBlocks(bytes, index);
    } else if (block == 0x2C) {
      frames++;
      if (frames > 1) {
        return frames;
      }
      if (index + 9 > bytes.length) {
        break;
      }
      final flags = bytes[index + 8];
      index += 9;
      if (flags & 0x80 != 0) {
        index += 3 * (1 << ((flags & 0x07) + 1));
      }
      index++;
      index = _skipSubBlocks(bytes, index);
    } else {
      break;
    }
  }
  return frames;
}

int _skipSubBlocks(Uint8List bytes, int start) {
  var index = start;
  while (index < bytes.length) {
    final size = bytes[index++];
    if (size == 0) {
      break;
    }
    index += size;
  }
  return index;
}

bool _webpAnimated(Uint8List bytes) {
  if (bytes.length < 21 || !_ascii(bytes, 12, 'VP8X')) {
    return false;
  }
  return bytes[20] & 0x02 != 0;
}

bool _apngAnimated(Uint8List bytes) {
  var index = 8;
  while (index + 8 <= bytes.length) {
    final length =
        (bytes[index] << 24) |
        (bytes[index + 1] << 16) |
        (bytes[index + 2] << 8) |
        bytes[index + 3];
    if (_ascii(bytes, index + 4, 'acTL')) {
      return true;
    }
    if (_ascii(bytes, index + 4, 'IDAT')) {
      return false;
    }
    index += 12 + length;
  }
  return false;
}

/// Makes a library sticker of [bytes].
///
///  * A GIF or WebP that moves is kept as it is when it is at most 1 MB
///    ([UserStickerException.animatedTooLarge] otherwise, or its first frame
///    when [stillIfTooLarge]).
///  * Anything else (a PNG, JPEG, WebP photo, the first frame of an APNG) is
///    drawn at most [maxEdge] pixels on its long side and saved as a PNG,
///    which keeps transparency and is shrunk until it fits in 1 MB.
///
/// Throws [UserStickerException] for something that is not a picture.
Future<PreparedSticker> prepareSticker(
  Uint8List bytes, {
  int maxEdge = userStickerMaxEdge,
  bool stillIfTooLarge = false,
}) async {
  final format = sniffStickerFormat(bytes);
  if (format != null &&
      format != StickerFormat.png &&
      isAnimatedStickerBytes(bytes, format)) {
    if (bytes.length <= maxUserStickerBytes) {
      final size = await _imageSize(bytes);
      return PreparedSticker(
        bytes: bytes,
        format: format,
        width: size.width,
        height: size.height,
        animated: true,
      );
    }
    if (!stillIfTooLarge) {
      throw UserStickerException.animatedTooLarge();
    }
  }
  return _prepareStill(bytes, maxEdge: maxEdge);
}

Future<({int width, int height})> _imageSize(Uint8List bytes) async {
  final descriptor = await _descriptor(bytes);
  try {
    return (width: descriptor.width, height: descriptor.height);
  } finally {
    descriptor.dispose();
  }
}

Future<ui.ImageDescriptor> _descriptor(Uint8List bytes) async {
  final ui.ImmutableBuffer buffer;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  } catch (_) {
    throw UserStickerException.unreadable();
  }
  try {
    return await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    throw UserStickerException.unreadable();
  } finally {
    buffer.dispose();
  }
}

/// The long side [edge] gives a picture of [width] x [height], in pixels:
/// the picture itself when it is already smaller.
({int width, int height}) fitWithin(int width, int height, int edge) {
  final longest = width > height ? width : height;
  if (longest <= edge) {
    return (width: width, height: height);
  }
  final scale = edge / longest;
  return (
    width: (width * scale).round().clamp(1, edge),
    height: (height * scale).round().clamp(1, edge),
  );
}

Future<PreparedSticker> _prepareStill(
  Uint8List bytes, {
  required int maxEdge,
}) async {
  final descriptor = await _descriptor(bytes);
  try {
    var edge = maxEdge;
    // Drawn smaller until the PNG fits; a sticker is rarely over 300 KB.
    for (var attempt = 0; attempt < 6; attempt++) {
      final size = fitWithin(descriptor.width, descriptor.height, edge);
      final codec = await descriptor.instantiateCodec(
        targetWidth: size.width,
        targetHeight: size.height,
      );
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) {
            throw UserStickerException.unreadable();
          }
          final png = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          if (png.length <= maxUserStickerBytes || edge <= 96) {
            return PreparedSticker(
              bytes: png,
              format: StickerFormat.png,
              width: image.width,
              height: image.height,
              animated: false,
            );
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
      edge = (edge * 0.7).round();
    }
    throw UserStickerException.unreadable();
  } finally {
    descriptor.dispose();
  }
}
