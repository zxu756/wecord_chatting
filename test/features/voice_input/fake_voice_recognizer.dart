import 'dart:async';

import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

/// A recognizer the test drives by hand: it reports what the test [say]s.
class FakeVoiceRecognizer implements VoiceRecognizer {
  FakeVoiceRecognizer({
    this.supported = true,
    this.engine = VoiceInputEngine.onDevice,
    this.available = true,
  });

  bool supported;
  VoiceInputEngine engine;
  bool available;

  /// Makes the next [start] fail.
  VoiceInputException? startError;

  /// Languages with no recognizer.
  final unsupportedLocales = <String>{};

  final starts = <({String locale, bool allowServer})>[];
  final sessions = <FakeVoiceSession>[];

  FakeVoiceSession get session => sessions.last;

  @override
  bool get isSupported => supported;

  @override
  Future<VoiceInputCapabilities> capabilities(String locale) async {
    return VoiceInputCapabilities(
      supported: supported && !unsupportedLocales.contains(locale),
      available: available,
      engine: engine,
    );
  }

  @override
  Future<VoiceSession> start({
    required String locale,
    required bool allowServer,
  }) async {
    if (startError case final error?) {
      startError = null;
      throw error;
    }
    starts.add((locale: locale, allowServer: allowServer));
    final session = FakeVoiceSession();
    sessions.add(session);
    return session;
  }
}

class FakeVoiceSession implements VoiceSession {
  final _controller = StreamController<VoiceInputEvent>.broadcast(sync: true);
  var stopped = false;
  var cancelled = false;

  /// What [stop] reports as the last words (default: the last partial).
  String? lastWords;
  String _text = '';

  /// Whether stopping ends the session by itself (a real recognizer does).
  bool endsOnStop = true;

  @override
  Stream<VoiceInputEvent> get events => _controller.stream;

  /// The recognizer heard [text] (everything of this session so far).
  void say(String text) {
    _text = text;
    _controller.add(VoicePartial(text));
  }

  void level(double value) => _controller.add(VoiceLevel(value));

  void fail(VoiceInputFailure failure) => _controller.add(VoiceError(failure));

  /// The recognizer ends the session by itself (a time limit, silence).
  void end([String? finalText]) {
    final text = finalText ?? _text;
    if (text.isNotEmpty) {
      _controller.add(VoiceFinal(text));
    }
    _controller.add(const VoiceEnded());
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (endsOnStop) {
      end(lastWords);
    }
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}
