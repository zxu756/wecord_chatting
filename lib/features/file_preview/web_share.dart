import 'dart:typed_data';

/// The browser's share sheet (the Web Share API, `navigator.share`), where
/// there is one: mobile Safari and Chrome, Safari and Edge on desktops.
abstract interface class WebShare {
  /// Whether this browser can share at all.
  bool get isAvailable;

  /// Shares the file itself ([bytes], when given and the browser can share
  /// files), else a link to it ([url]). Returns normally when the person
  /// cancels the share sheet.
  Future<void> share({
    required String name,
    required String mimeType,
    required Uri url,
    Uint8List? bytes,
  });
}

/// Outside the browser: never available.
class UnavailableWebShare implements WebShare {
  const UnavailableWebShare();

  @override
  bool get isAvailable => false;

  @override
  Future<void> share({
    required String name,
    required String mimeType,
    required Uri url,
    Uint8List? bytes,
  }) {
    throw UnsupportedError('No Web Share API here');
  }
}
