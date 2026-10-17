import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Reads the QR code in a picture ("Choose from photos"): PNG, JPEG, WebP
/// and the other formats the `image` package decodes. Null when there is no
/// QR code in it (or it cannot be read).
///
/// This is pure Dart (ZXing's port), so one path serves iOS, macOS and the
/// web: mobile_scanner decodes still pictures natively, but not in the
/// browser.
Future<String?> decodeQrFromImageBytes(Uint8List bytes) {
  return compute(_decode, bytes);
}

/// The longest side the picture is shrunk to when it is bigger: ZXing finds
/// codes faster, and as well, in a picture of this size.
const _maxSide = 1400;

String? _decode(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }
  // Phones record the rotation in EXIF; the code reads the same either way,
  // but a baked orientation makes the picture the size people see.
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > _maxSide) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? _maxSide : null,
      height: image.height > image.width ? _maxSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  final rgba = image.convert(numChannels: 4);
  final pixels = rgba
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(rgba.width, rgba.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final bitmap in [
    BinaryBitmap(HybridBinarizer(source)),
    BinaryBitmap(GlobalHistogramBinarizer(source)),
    BinaryBitmap(HybridBinarizer(source.invert())),
  ]) {
    try {
      return QRCodeReader().decode(bitmap, hints: hints).text;
    } on ReaderException {
      continue;
    } on Object {
      continue;
    }
  }
  return null;
}
