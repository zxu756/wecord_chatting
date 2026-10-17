import 'package:flutter/foundation.dart';

/// The languages the recognizer is asked to read, in the order of Apple
/// Vision's names: Simplified and Traditional Chinese, and English.
const imageTextLanguages = ['zh-Hans', 'zh-Hant', 'en-US'];

/// The text found in a picture.
@immutable
class ImageText {
  const ImageText(this.lines);

  /// What was found, top to bottom, one entry per line of text in the
  /// picture.
  final List<String> lines;

  String get text => lines.join('\n');

  bool get isEmpty => lines.isEmpty;
}

/// Why text could not be read from a picture.
enum ImageTextFailure {
  /// This platform can't read text on the device (the web, Android...).
  unavailable,

  /// The picture holds no text.
  noText,

  /// The file is not a picture the system can open.
  unreadable,

  /// Anything else; trying again may help.
  failed,
}

class ImageTextException implements Exception {
  const ImageTextException(this.kind);

  final ImageTextFailure kind;

  @override
  String toString() => 'ImageTextException($kind)';
}
