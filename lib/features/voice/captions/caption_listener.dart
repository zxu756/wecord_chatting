import 'dart:async';

import 'package:wecord/features/voice/captions/caption_segmenter.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

/// Listens to this device's own microphone for a call's captions (E1) and
/// hands out caption lines as they are heard. It reuses the platform's
/// speech recognizer from voice input (the system recognizer on iPhone and
/// Mac, the browser's on the web); the audio never leaves the device unless
/// the platform's recognizer sends it to its own service, which the person
/// agreed to first.
///
/// A recognition session ends by itself now and then (a silence, a time
/// limit, a new microphone), so the listener starts the next one while it is
/// wanted. Nothing is recorded: the words go to [onSegment] and are gone.
class CaptionListener {
  CaptionListener({
    required this._recognizer,
    required this.onSegment,
    required this.onFailure,
    DateTime Function()? now,
    this.tickEvery = const Duration(milliseconds: 400),
    this.restartAfter = const Duration(milliseconds: 250),
    this.stopTimeout = const Duration(milliseconds: 1500),
  }) : _now = now ?? DateTime.now;

  final VoiceRecognizer _recognizer;
  final DateTime Function() _now;

  /// A caption line: still being spoken ([CaptionSegment.isFinal] false) or
  /// settled.
  final void Function(CaptionSegment segment) onSegment;

  /// Listening can not go on: [needsServer] when the language can only be
  /// recognized by a service and the caller did not allow that.
  final void Function(VoiceInputFailure failure, {bool needsServer}) onFailure;

  final Duration tickEvery;
  final Duration restartAfter;
  final Duration stopTimeout;

  final _segmenter = CaptionSegmenter();
  VoiceSession? _session;
  StreamSubscription<VoiceInputEvent>? _events;
  Timer? _ticker;
  Timer? _restart;
  Timer? _stopTimer;
  var _generation = 0;
  var _wanted = false;
  var _stopping = false;
  var _silentRestarts = 0;
  late String _locale;
  late bool _allowServer;

  bool get isListening => _wanted;

  /// Starts listening in [locale] (and keeps going) until [stop].
  Future<void> start({
    required String locale,
    required bool allowServer,
  }) async {
    if (_wanted) {
      return;
    }
    _wanted = true;
    _locale = locale;
    _allowServer = allowServer;
    _silentRestarts = 0;
    final generation = ++_generation;
    _ticker?.cancel();
    _ticker = Timer.periodic(tickEvery, (_) => _tick(generation));
    await _open(generation);
  }

  void _tick(int generation) {
    if (generation != _generation) {
      return;
    }
    for (final segment in _segmenter.tick(_now())) {
      onSegment(segment);
    }
  }

  Future<void> _open(int generation) async {
    final VoiceSession session;
    try {
      session = await _recognizer.start(
        locale: _locale,
        allowServer: _allowServer,
        inCall: true,
      );
    } on VoiceInputException catch (error) {
      if (generation == _generation) {
        _giveUp(error.failure, needsServer: error.needsServer);
      }
      return;
    } on Object {
      if (generation == _generation) {
        _giveUp(VoiceInputFailure.failed);
      }
      return;
    }
    if (generation != _generation) {
      unawaited(session.cancel());
      return;
    }
    _session = session;
    _events = session.events.listen((event) => _onEvent(generation, event));
  }

  void _onEvent(int generation, VoiceInputEvent event) {
    if (generation != _generation) {
      return;
    }
    switch (event) {
      case VoicePartial(:final text):
      case VoiceFinal(:final text):
        if (text.trim().isNotEmpty) {
          _silentRestarts = 0;
        }
        for (final segment in _segmenter.hear(text, _now())) {
          onSegment(segment);
        }
      case VoiceLevel():
        break;
      case VoiceError(:final failure):
        _giveUp(failure);
      case VoiceEnded():
        _ended(generation);
    }
  }

  void _ended(int generation) {
    unawaited(_events?.cancel());
    _events = null;
    _session = null;
    for (final segment in _segmenter.finish()) {
      onSegment(segment);
    }
    if (_stopping) {
      _finishStop();
      return;
    }
    if (!_wanted) {
      return;
    }
    // Silent stretches end sessions quickly: wait a little longer each time
    // so a recognizer that keeps ending does not spin.
    _silentRestarts++;
    final wait = restartAfter * (1 + _silentRestarts.clamp(0, 2));
    _restart?.cancel();
    _restart = Timer(wait, () {
      if (generation == _generation && _wanted) {
        unawaited(_open(generation));
      }
    });
  }

  void _giveUp(VoiceInputFailure failure, {bool needsServer = false}) {
    _teardown();
    onFailure(failure, needsServer: needsServer);
  }

  /// Stops listening. What was being said is settled first, so the last
  /// words are not lost.
  Future<void> stop() async {
    if (!_wanted) {
      return;
    }
    final session = _session;
    if (session == null) {
      for (final segment in _segmenter.finish()) {
        onSegment(segment);
      }
      _teardown();
      return;
    }
    _stopping = true;
    _restart?.cancel();
    final done = Completer<void>();
    _stopDone = done;
    _stopTimer = Timer(stopTimeout, _finishStop);
    try {
      await session.stop();
    } on Object {
      _finishStop();
    }
    await done.future;
  }

  Completer<void>? _stopDone;

  void _finishStop() {
    _stopTimer?.cancel();
    for (final segment in _segmenter.finish()) {
      onSegment(segment);
    }
    final done = _stopDone;
    _stopDone = null;
    _teardown();
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  void _teardown() {
    _generation++;
    _wanted = false;
    _stopping = false;
    _ticker?.cancel();
    _ticker = null;
    _restart?.cancel();
    _restart = null;
    _stopTimer?.cancel();
    _stopTimer = null;
    unawaited(_events?.cancel());
    _events = null;
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(session.cancel());
    }
    _segmenter.reset();
  }

  /// Stops at once without settling anything.
  void dispose() {
    final done = _stopDone;
    _stopDone = null;
    _teardown();
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }
}
