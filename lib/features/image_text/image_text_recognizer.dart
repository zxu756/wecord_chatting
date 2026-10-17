import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/image_text/image_text_models.dart';

/// Reads the text in a picture. The iPhone and Mac apps do it on the device
/// with Apple Vision; no picture is ever sent to a server. Tests swap in a
/// fake.
abstract interface class ImageTextRecognizer {
  /// Whether this platform can read text from pictures at all. Where it
  /// can't, nothing is downloaded or sent anywhere.
  bool get isSupported;

  /// The text of the picture file at [path]. Throws [ImageTextException].
  Future<ImageText> recognize(String path);
}

/// Where there is no on-device recognizer (the web, Android, Windows and
/// Linux).
class UnsupportedImageTextRecognizer implements ImageTextRecognizer {
  const UnsupportedImageTextRecognizer();

  @override
  bool get isSupported => false;

  @override
  Future<ImageText> recognize(String path) =>
      Future.error(const ImageTextException(ImageTextFailure.unavailable));
}

/// Apple Vision through the Runner apps' `ImageTextPlugin` (channel
/// `wecord/image_text`): a `VNRecognizeTextRequest` at the accurate level,
/// for Simplified Chinese, Traditional Chinese and English.
///
/// `recognize {path, languages}` answers `{lines: [{text, confidence}],
/// languages: [...]}` (top to bottom) or fails with `unreadable`,
/// `unsupported` (an OS without Vision text recognition) or `failed`.
class NativeImageTextRecognizer implements ImageTextRecognizer {
  const NativeImageTextRecognizer([
    this._channel = const MethodChannel(imageTextChannelName),
  ]);

  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  Future<ImageText> recognize(String path) async {
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('recognize', {
        'path': path,
        'languages': imageTextLanguages,
      });
    } on MissingPluginException {
      throw const ImageTextException(ImageTextFailure.unavailable);
    } on PlatformException catch (error) {
      throw ImageTextException(switch (error.code) {
        'unreadable' => ImageTextFailure.unreadable,
        'unsupported' => ImageTextFailure.unavailable,
        _ => ImageTextFailure.failed,
      });
    }
    final text = imageTextFromChannel(result);
    if (text.isEmpty) {
      throw const ImageTextException(ImageTextFailure.noText);
    }
    return text;
  }
}

/// The name of the method channel of the native plugin.
const imageTextChannelName = 'wecord/image_text';

/// Maps what the native plugin answers to an [ImageText]: lines in order,
/// each trimmed, empty ones and ones the recognizer was not sure of at all
/// dropped.
ImageText imageTextFromChannel(Map<String, Object?>? result) {
  final raw = result?['lines'];
  if (raw is! List) {
    return const ImageText([]);
  }
  final lines = <String>[];
  for (final entry in raw) {
    final String? text;
    var confidence = 1.0;
    if (entry is Map) {
      final value = entry['text'];
      text = value is String ? value : null;
      final sure = entry['confidence'];
      if (sure is num) {
        confidence = sure.toDouble();
      }
    } else if (entry is String) {
      text = entry;
    } else {
      text = null;
    }
    final trimmed = text?.trim() ?? '';
    // Vision gives every line a confidence; a line it barely believes in
    // is more likely a texture than text.
    if (trimmed.isNotEmpty && confidence >= minLineConfidence) {
      lines.add(trimmed);
    }
  }
  return ImageText(lines);
}

/// Lines the recognizer is less sure of than this are left out.
const minLineConfidence = 0.2;

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// How text is read from pictures here: Apple Vision on iOS and macOS,
/// nothing on the web and elsewhere.
final imageTextRecognizerProvider = Provider<ImageTextRecognizer>((ref) {
  if (_isApple) {
    return const NativeImageTextRecognizer();
  }
  return const UnsupportedImageTextRecognizer();
});

/// Downloads a picture to a local file (kept in the viewer's download
/// cache) for the recognizer to read.
final imageTextFetcherProvider =
    Provider<Future<String> Function(PreviewFile file)>((ref) {
      return (file) {
        return ref
            .read(fileFetcherProvider)
            .download(
              file,
              url: () => ref.read(filePreviewServiceProvider).fileUrl(file),
            );
      };
    });
