import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads text out loud with the device's own voice (`AVSpeechSynthesizer` on
/// iPhone and Mac, the browser's `speechSynthesis` on the web). Nothing is
/// sent anywhere. Tests swap in a fake.
abstract interface class SpeechReader {
  /// Whether this device can read aloud at all.
  bool get isSupported;

  /// True while something is being read.
  ValueListenable<bool> get speaking;

  /// Reads [text] in [language] (a BCP-47 tag such as `zh-CN` or `en-US`),
  /// stopping whatever was being read. Completes when the reading started;
  /// [speaking] says when it ends. Throws a [SpeechReaderException] when the
  /// device cannot.
  Future<void> speak(String text, {required String language});

  /// Stops reading.
  Future<void> stop();
}

class SpeechReaderException implements Exception {
  const SpeechReaderException([this.message]);

  final String? message;

  @override
  String toString() => 'SpeechReaderException(${message ?? ''})';
}

/// The language to read [text] in: Chinese when it holds Chinese characters
/// (or when there is no letter to tell by and the app is in Chinese), else
/// English.
String speechLanguageFor(String text, {required bool appIsChinese}) {
  final chinese = RegExp(r'[㐀-鿿]').hasMatch(text);
  final latin = RegExp(r'[A-Za-z]').hasMatch(text);
  if (chinese) {
    return 'zh-CN';
  }
  if (latin) {
    return 'en-US';
  }
  return appIsChinese ? 'zh-CN' : 'en-US';
}

/// The system's voice through the `flutter_tts` plugin.
class SystemSpeechReader implements SpeechReader {
  SystemSpeechReader([this._tts]);

  FlutterTts? _tts;
  final ValueNotifier<bool> _speaking = ValueNotifier(false);
  var _ready = false;

  @override
  bool get isSupported => true;

  @override
  ValueListenable<bool> get speaking => _speaking;

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (!_ready) {
      _ready = true;
      void done() => _speaking.value = false;
      tts.setStartHandler(() => _speaking.value = true);
      tts.setCompletionHandler(done);
      tts.setCancelHandler(done);
      tts.setPauseHandler(done);
      tts.setErrorHandler((_) => done());
      try {
        // A gentler pace than the default: 0.5 is the iPhone's normal pace,
        // the browser's scale is 1 for normal.
        await tts.setSpeechRate(kIsWeb ? 0.85 : 0.42);
        await tts.setVolume(1);
        await tts.awaitSpeakCompletion(false);
      } on Object {
        // The defaults will do.
      }
    }
    return tts;
  }

  @override
  Future<void> speak(String text, {required String language}) async {
    try {
      final tts = await _engine();
      await tts.stop();
      await tts.setLanguage(language);
      _speaking.value = true;
      final result = await tts.speak(text);
      if (result == 0) {
        _speaking.value = false;
        throw const SpeechReaderException('The device refused to speak');
      }
    } on SpeechReaderException {
      rethrow;
    } on Object catch (error) {
      _speaking.value = false;
      throw SpeechReaderException('$error');
    }
  }

  @override
  Future<void> stop() async {
    _speaking.value = false;
    try {
      await _tts?.stop();
    } on Object {
      // Nothing to stop.
    }
  }
}

/// The voice the app uses.
final speechReaderProvider = Provider<SpeechReader>((ref) {
  final reader = SystemSpeechReader();
  ref.onDispose(() => unawaited(reader.stop()));
  return reader;
});
