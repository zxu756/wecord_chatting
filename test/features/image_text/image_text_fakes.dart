import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/image_text/image_text_models.dart';
import 'package:wecord/features/image_text/image_text_recognizer.dart';

import '../ai/ai_fakes.dart';

/// An [ImageTextRecognizer] for tests: what it finds is set up front and the
/// pictures it was asked to read are recorded.
class FakeImageTextRecognizer implements ImageTextRecognizer {
  FakeImageTextRecognizer({this.supported = true});

  final bool supported;

  @override
  bool get isSupported => supported;

  /// What [recognize] gives back.
  var lines = const ['Opening hours', 'Mon–Fri 9:00–18:00', '周末休息'];

  /// Thrown by [recognize] when set (once, when [errorOnce]).
  Object? error;
  var errorOnce = true;

  /// Holds [recognize] until completed (for the loading state).
  Completer<void>? gate;

  final paths = <String>[];

  @override
  Future<ImageText> recognize(String path) async {
    paths.add(path);
    await gate?.future;
    if (error case final failure?) {
      if (errorOnce) {
        error = null;
      }
      throw failure;
    }
    final text = ImageText(lines);
    if (text.isEmpty) {
      throw const ImageTextException(ImageTextFailure.noText);
    }
    return text;
  }
}

PreviewFile testPicture({String messageId = 'message-1'}) => PreviewFile(
  bucket: 'chat-images',
  path: 'conversation-1/$messageId.jpg',
  name: 'sign.jpg',
  mimeType: 'image/jpeg',
  size: 2048,
  messageId: messageId,
  conversationId: 'conversation-1',
);

/// The overrides that make the text-from-picture sheet work in a test.
class ImageTextWorld {
  ImageTextWorld({bool supported = true, this.aiOn = false})
    : recognizer = FakeImageTextRecognizer(supported: supported);

  final FakeImageTextRecognizer recognizer;
  final cache = InMemoryImageTextCache();
  final ai = FakeAiRepository();
  final fetched = <String>[];

  /// Whether AI is set up (Translate is offered).
  final bool aiOn;

  List<Override> get overrides => [
    imageTextRecognizerProvider.overrideWithValue(recognizer),
    imageTextCacheProvider.overrideWithValue(cache),
    imageTextFetcherProvider.overrideWithValue((file) async {
      fetched.add(file.key);
      return '/cache/${file.name}';
    }),
    aiRepositoryProvider.overrideWithValue(ai),
    aiAvailableProvider.overrideWith((ref, circleId) => aiOn),
  ];
}
