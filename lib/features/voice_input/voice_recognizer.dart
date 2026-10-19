import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/web_speech.dart' as web_speech;

/// One run of listening. [events] ends with a [VoiceEnded] (or when
/// [cancel] is called).
abstract interface class VoiceSession {
  Stream<VoiceInputEvent> get events;

  /// Stops listening and lets the recognizer finish what it heard: a
  /// [VoiceFinal] (when there was speech) and a [VoiceEnded] follow.
  Future<void> stop();

  /// Throws the session away: no more events.
  Future<void> cancel();
}

/// Live speech recognition for dictation ("speak to type"). The iPhone and
/// Mac apps use the system's recognizer, on the device when the language
/// allows; the web uses the browser's Web Speech API. Tests swap in a fake.
abstract interface class VoiceRecognizer {
  /// Whether this platform can dictate at all. Where it can't, the voice
  /// input mode is hidden.
  bool get isSupported;

  /// What can be done for [locale]. Never asks for any permission.
  Future<VoiceInputCapabilities> capabilities(String locale);

  /// Starts listening in [locale] (asking for the permissions the first
  /// time). A language that only a server can recognize needs
  /// [allowServer]; without it this throws a [VoiceInputException] with
  /// `needsServer`.
  ///
  /// [inCall] is for captions in a voice call: the call already owns the
  /// microphone and the audio session, so the recognizer listens alongside
  /// it and leaves the audio session as it is.
  Future<VoiceSession> start({
    required String locale,
    required bool allowServer,
    bool inCall = false,
  });
}

/// Where dictation isn't possible (Android, Windows, Linux, browsers without
/// the Web Speech API, and tests that don't set one up).
class UnsupportedVoiceRecognizer implements VoiceRecognizer {
  const UnsupportedVoiceRecognizer();

  @override
  bool get isSupported => false;

  @override
  Future<VoiceInputCapabilities> capabilities(String locale) async =>
      const VoiceInputCapabilities(supported: false);

  @override
  Future<VoiceSession> start({
    required String locale,
    required bool allowServer,
    bool inCall = false,
  }) => Future.error(
    const VoiceInputException(VoiceInputFailure.unsupportedLanguage),
  );
}

/// The system's recognizer through the Runner apps' `VoiceInputPlugin`
/// (channels `wecord/voice_input` and `wecord/voice_input/events`):
/// `SFSpeechRecognizer` fed by `AVAudioEngine`.
class NativeVoiceRecognizer implements VoiceRecognizer {
  NativeVoiceRecognizer({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('wecord/voice_input'),
      _events = events ?? const EventChannel('wecord/voice_input/events');

  final MethodChannel _channel;
  final EventChannel _events;

  _NativeSession? _active;
  StreamSubscription<Object?>? _subscription;

  @override
  bool get isSupported => true;

  @override
  Future<VoiceInputCapabilities> capabilities(String locale) async {
    final Map<String, Object?>? info;
    try {
      info = await _channel.invokeMapMethod<String, Object?>('capabilities', {
        'locale': locale,
      });
    } on MissingPluginException {
      return const VoiceInputCapabilities(supported: false);
    }
    if (info == null || info['supported'] != true) {
      return const VoiceInputCapabilities(supported: false);
    }
    return VoiceInputCapabilities(
      supported: true,
      available: info['available'] == true,
      engine: info['onDevice'] == true
          ? VoiceInputEngine.onDevice
          : VoiceInputEngine.appleServer,
    );
  }

  /// One subscription for the life of the app: the native side sends the
  /// events of whichever session is running.
  void _listen() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (Object? event) => _active?._handle(event),
      onError: (Object _) {},
    );
  }

  @override
  Future<VoiceSession> start({
    required String locale,
    required bool allowServer,
    bool inCall = false,
  }) async {
    _listen();
    final session = _NativeSession(_channel, () {
      if (_active != null) {
        _active = null;
      }
    });
    _active = session;
    try {
      await _channel.invokeMethod<void>('start', {
        'locale': locale,
        'allowServer': allowServer,
        if (inCall) 'inCall': true,
      });
    } on PlatformException catch (error) {
      _active = null;
      throw VoiceInputException(switch (error.code) {
        'not_authorized' => VoiceInputFailure.speechDenied,
        'mic_denied' => VoiceInputFailure.micDenied,
        'unsupported_locale' => VoiceInputFailure.unsupportedLanguage,
        'unavailable' => VoiceInputFailure.unavailable,
        _ => VoiceInputFailure.failed,
      }, needsServer: error.code == 'needs_server');
    } on MissingPluginException {
      _active = null;
      throw const VoiceInputException(VoiceInputFailure.unsupportedLanguage);
    }
    return session;
  }
}

class _NativeSession implements VoiceSession {
  _NativeSession(this._channel, this._onDone);

  final MethodChannel _channel;
  final void Function() _onDone;
  final _controller = StreamController<VoiceInputEvent>.broadcast();
  var _closed = false;

  @override
  Stream<VoiceInputEvent> get events => _controller.stream;

  void _handle(Object? event) {
    if (_closed || event is! Map) {
      return;
    }
    switch (event['type']) {
      case 'partial':
        _controller.add(VoicePartial('${event['text'] ?? ''}'));
      case 'final':
        _controller.add(VoiceFinal('${event['text'] ?? ''}'));
      case 'level':
        _controller.add(VoiceLevel((event['value'] as num?)?.toDouble() ?? 0));
      case 'error':
        _controller.add(const VoiceError(VoiceInputFailure.failed));
      case 'end':
        _controller.add(const VoiceEnded());
        _close();
    }
  }

  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _onDone();
    unawaited(_controller.close());
  }

  @override
  Future<void> stop() async {
    if (_closed) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      _controller.add(const VoiceEnded());
      _close();
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) {
      return;
    }
    _close();
    try {
      await _channel.invokeMethod<void>('cancel');
    } on Object {
      // Already gone.
    }
  }
}

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// How dictation works on this platform: the system's recognizer on iOS and
/// macOS, the browser's on the web, nothing elsewhere.
final voiceRecognizerProvider = Provider<VoiceRecognizer>((ref) {
  if (kIsWeb) {
    return web_speech.createBrowserRecognizer() ??
        const UnsupportedVoiceRecognizer();
  }
  if (_isApple) {
    return NativeVoiceRecognizer();
  }
  return const UnsupportedVoiceRecognizer();
});
