import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

JSFunction? _constructor() {
  for (final name in ['SpeechRecognition', 'webkitSpeechRecognition']) {
    if (globalContext.has(name)) {
      final value = globalContext[name];
      if (value.isA<JSFunction>()) {
        return value as JSFunction;
      }
    }
  }
  return null;
}

/// The browser's recognizer, or null when it has none (Firefox).
VoiceRecognizer? createBrowserRecognizer() {
  return _constructor() == null ? null : BrowserVoiceRecognizer();
}

/// Dictation with the Web Speech API. The browser decides where the audio
/// goes: Chrome and Edge send it to their own speech service, which is why
/// the app says so before the first use. The API reports no loudness, so
/// the waveform is drawn from when speech starts and stops.
class BrowserVoiceRecognizer implements VoiceRecognizer {
  @override
  bool get isSupported => _constructor() != null;

  @override
  Future<VoiceInputCapabilities> capabilities(String locale) async {
    return VoiceInputCapabilities(
      supported: isSupported,
      engine: VoiceInputEngine.browser,
    );
  }

  @override
  Future<VoiceSession> start({
    required String locale,
    required bool allowServer,
  }) async {
    final constructor = _constructor();
    if (constructor == null) {
      throw const VoiceInputException(VoiceInputFailure.unsupportedLanguage);
    }
    final recognition = constructor.callAsConstructor<JSObject>();
    final session = _BrowserSession(recognition);
    recognition['lang'] = locale.toJS;
    recognition['continuous'] = true.toJS;
    recognition['interimResults'] = true.toJS;
    recognition['maxAlternatives'] = 1.toJS;
    session._wire();
    try {
      recognition.callMethod<JSAny?>('start'.toJS);
    } on Object {
      session._dispose();
      throw const VoiceInputException(VoiceInputFailure.failed);
    }
    return session;
  }
}

class _BrowserSession implements VoiceSession {
  _BrowserSession(this._recognition);

  final JSObject _recognition;
  final _controller = StreamController<VoiceInputEvent>.broadcast();
  final _random = math.Random();
  Timer? _levels;
  var _speaking = false;
  var _text = '';
  var _closed = false;
  var _stopping = false;
  var _level = 0.0;

  @override
  Stream<VoiceInputEvent> get events => _controller.stream;

  void _emit(VoiceInputEvent event) {
    if (!_closed) {
      _controller.add(event);
    }
  }

  void _wire() {
    _recognition['onresult'] = ((JSObject event) {
      final results = event['results'] as JSObject?;
      if (results == null) {
        return;
      }
      final length = (results['length'] as JSNumber?)?.toDartInt ?? 0;
      final buffer = StringBuffer();
      for (var i = 0; i < length; i++) {
        final result = results.callMethod<JSObject?>('item'.toJS, i.toJS);
        final best = result?.callMethod<JSObject?>('item'.toJS, 0.toJS);
        buffer.write((best?['transcript'] as JSString?)?.toDart ?? '');
      }
      _text = buffer.toString().trim();
      _speaking = true;
      _emit(VoicePartial(_text));
    }).toJS;
    _recognition['onspeechstart'] = ((JSAny? _) => _speaking = true).toJS;
    _recognition['onspeechend'] = ((JSAny? _) => _speaking = false).toJS;
    _recognition['onerror'] = ((JSObject event) {
      final code = (event['error'] as JSString?)?.toDart ?? '';
      final failure = switch (code) {
        'not-allowed' || 'service-not-allowed' => VoiceInputFailure.micDenied,
        'audio-capture' => VoiceInputFailure.micDenied,
        'language-not-supported' => VoiceInputFailure.unsupportedLanguage,
        'no-speech' || 'aborted' => null,
        _ => VoiceInputFailure.failed,
      };
      if (failure != null) {
        _emit(VoiceError(failure));
      }
    }).toJS;
    _recognition['onend'] = ((JSAny? _) {
      if (_text.isNotEmpty) {
        _emit(VoiceFinal(_text));
      }
      _emit(const VoiceEnded());
      _dispose();
    }).toJS;
    _levels = Timer.periodic(const Duration(milliseconds: 70), (_) {
      final target = _speaking ? 0.3 + 0.55 * _random.nextDouble() : 0.03;
      _level += (target - _level) * 0.5;
      _emit(VoiceLevel(_level));
      // Speech that stops producing words quiets down on its own.
      _speaking = _speaking && _random.nextInt(40) != 0;
    });
  }

  void _dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _levels?.cancel();
    for (final name in [
      'onresult',
      'onspeechstart',
      'onspeechend',
      'onerror',
      'onend',
    ]) {
      _recognition[name] = null;
    }
    unawaited(_controller.close());
  }

  @override
  Future<void> stop() async {
    if (_closed || _stopping) {
      return;
    }
    _stopping = true;
    try {
      _recognition.callMethod<JSAny?>('stop'.toJS);
    } on Object {
      _emit(const VoiceEnded());
      _dispose();
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) {
      return;
    }
    final recognition = _recognition;
    _dispose();
    try {
      recognition.callMethod<JSAny?>('abort'.toJS);
    } on Object {
      // Already stopped.
    }
  }
}
