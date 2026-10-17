import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

enum VoicePhase {
  idle,

  /// Waiting for the person to agree to a speech service hearing them.
  consent,
  starting,
  listening,

  /// "Done" was pressed; waiting for the recognizer's last words.
  stopping,

  /// Something went wrong (the panel says what); the text so far stays.
  error,
}

/// How many bars of loudness the waveform keeps.
const voiceWaveBars = 36;

@immutable
class VoiceInputState {
  const VoiceInputState({
    this.phase = VoicePhase.idle,
    this.owner,
    this.language = VoiceInputLanguage.english,
    this.partial = '',
    this.levels = const [],
    this.engine = VoiceInputEngine.onDevice,
    this.failure,
  });

  final VoicePhase phase;

  /// What the words go to (a conversation's composer).
  final String? owner;
  final VoiceInputLanguage language;

  /// Everything heard in the session so far.
  final String partial;

  /// The latest loudness readings, 0...1, oldest first.
  final List<double> levels;
  final VoiceInputEngine engine;
  final VoiceInputFailure? failure;

  bool get isActive => phase != VoicePhase.idle;
  bool get isListening =>
      phase == VoicePhase.listening || phase == VoicePhase.starting;

  VoiceInputState copyWith({
    VoicePhase? phase,
    Object? owner = _keep,
    VoiceInputLanguage? language,
    String? partial,
    List<double>? levels,
    VoiceInputEngine? engine,
    Object? failure = _keep,
  }) {
    return VoiceInputState(
      phase: phase ?? this.phase,
      owner: identical(owner, _keep) ? this.owner : owner as String?,
      language: language ?? this.language,
      partial: partial ?? this.partial,
      levels: levels ?? this.levels,
      engine: engine ?? this.engine,
      failure: identical(failure, _keep)
          ? this.failure
          : failure as VoiceInputFailure?,
    );
  }
}

const Object _keep = Object();

/// Speak to type. Listens through the platform's [VoiceRecognizer] and writes
/// what it hears into a text field live, between the text that was before the
/// caret and after it. Done keeps the words (to edit and send as text),
/// Cancel puts the field back as it was. One dictation runs at a time.
///
/// The field is the person's too: typing into it while listening ends the
/// dictation and keeps what was typed.
final voiceInputProvider =
    NotifierProvider<VoiceInputController, VoiceInputState>(
      VoiceInputController.new,
    );

class VoiceInputController extends Notifier<VoiceInputState> {
  TextEditingController? _field;
  FocusNode? _focus;
  TextEditingValue? _original;
  var _before = '';
  var _after = '';
  var _lastWritten = '';
  var _sessionText = '';
  var _heardAnything = false;
  var _silentRestarts = 0;
  var _generation = 0;
  VoiceSession? _session;
  StreamSubscription<VoiceInputEvent>? _events;
  Timer? _idle;
  Timer? _finishTimeout;
  var _serverAllowed = false;

  /// How long nothing new is heard before listening stops by itself.
  static const idleTimeout = Duration(seconds: 25);

  /// How long Done waits for the recognizer's last words.
  static const finishTimeout = Duration(milliseconds: 1500);

  @override
  VoiceInputState build() {
    ref.onDispose(() {
      _generation++;
      _idle?.cancel();
      _finishTimeout?.cancel();
      unawaited(_events?.cancel());
      unawaited(_session?.cancel());
      _field?.removeListener(_onFieldChanged);
    });
    return VoiceInputState(language: VoiceInputLanguage.ofApp);
  }

  VoiceRecognizer get _recognizer => ref.read(voiceRecognizerProvider);

  // ------------------------------------------------------------- start --

  /// Starts listening for words to put into [field]. Does nothing while
  /// another dictation runs for the same [owner]; a dictation of another
  /// owner is cancelled first.
  Future<void> start({
    required String owner,
    required TextEditingController field,
    FocusNode? focus,
  }) async {
    if (state.isActive) {
      if (state.owner == owner) {
        return;
      }
      await cancel();
    }
    final generation = ++_generation;
    _attach(field, focus);
    state = VoiceInputState(
      phase: VoicePhase.starting,
      owner: owner,
      language: state.language,
    );
    await _prepare(generation);
  }

  void _attach(TextEditingController field, FocusNode? focus) {
    _field?.removeListener(_onFieldChanged);
    _field = field;
    _focus = focus;
    _original = field.value;
    final text = field.text;
    final selection = field.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _before = text.substring(0, start);
    _after = text.substring(end);
    _lastWritten = text;
    _sessionText = '';
    _heardAnything = false;
    _silentRestarts = 0;
    field.addListener(_onFieldChanged);
  }

  /// Checks the language and whether the person must agree first, then
  /// listens.
  Future<void> _prepare(int generation) async {
    final VoiceInputCapabilities capabilities;
    try {
      capabilities = await _recognizer.capabilities(state.language.locale);
    } on Object {
      return _fail(generation, VoiceInputFailure.failed);
    }
    if (generation != _generation) {
      return;
    }
    if (!capabilities.supported) {
      return _fail(generation, VoiceInputFailure.unsupportedLanguage);
    }
    if (!capabilities.available) {
      return _fail(generation, VoiceInputFailure.unavailable);
    }
    state = state.copyWith(engine: capabilities.engine);
    final needsConsent = switch (capabilities.engine) {
      VoiceInputEngine.onDevice => false,
      VoiceInputEngine.appleServer => !_serverAllowed,
      VoiceInputEngine.browser =>
        !_serverAllowed &&
            !await ref.read(voiceInputStoreProvider).loadBrowserConsent(),
    };
    if (generation != _generation) {
      return;
    }
    if (needsConsent) {
      state = state.copyWith(phase: VoicePhase.consent);
      return;
    }
    await _listen(generation);
  }

  /// The person agreed to the speech service hearing them.
  Future<void> grantConsent() async {
    if (state.phase != VoicePhase.consent) {
      return;
    }
    _serverAllowed = true;
    if (state.engine == VoiceInputEngine.browser) {
      try {
        await ref.read(voiceInputStoreProvider).saveBrowserConsent();
      } on Object {
        // Asked again next time.
      }
    }
    final generation = _generation;
    state = state.copyWith(phase: VoicePhase.starting);
    await _listen(generation);
  }

  Future<void> _listen(int generation) async {
    final VoiceSession session;
    try {
      session = await _recognizer.start(
        locale: state.language.locale,
        allowServer: _serverAllowed,
      );
    } on VoiceInputException catch (error) {
      if (generation != _generation) {
        return;
      }
      if (error.needsServer) {
        state = state.copyWith(
          phase: VoicePhase.consent,
          engine: VoiceInputEngine.appleServer,
        );
        return;
      }
      return _fail(generation, error.failure);
    } on Object {
      return _fail(generation, VoiceInputFailure.failed);
    }
    if (generation != _generation) {
      unawaited(session.cancel());
      return;
    }
    _session = session;
    _sessionText = '';
    _events = session.events.listen((event) => _onEvent(generation, event));
    state = state.copyWith(phase: VoicePhase.listening, partial: '');
    _armIdle(generation);
  }

  // ------------------------------------------------------------ events --

  void _onEvent(int generation, VoiceInputEvent event) {
    if (generation != _generation || !state.isActive) {
      return;
    }
    switch (event) {
      case VoicePartial(:final text):
        _heard(generation, text);
      case VoiceFinal(:final text):
        _heard(generation, text);
      case VoiceLevel(:final value):
        final levels = [...state.levels, value.clamp(0.0, 1.0)];
        if (levels.length > voiceWaveBars) {
          levels.removeRange(0, levels.length - voiceWaveBars);
        }
        state = state.copyWith(levels: levels);
      case VoiceError(:final failure):
        _fail(generation, failure);
      case VoiceEnded():
        unawaited(_ended(generation));
    }
  }

  void _heard(int generation, String text) {
    final trimmed = text.trim();
    if (trimmed != _sessionText) {
      _armIdle(generation);
    }
    _sessionText = trimmed;
    if (trimmed.isNotEmpty) {
      _heardAnything = true;
      _silentRestarts = 0;
    }
    _write(trimmed);
    state = state.copyWith(partial: trimmed);
  }

  /// The recognizer ended this stretch. After Done that is the end; while
  /// still listening (the recognizer's time limit, a silence, a new
  /// microphone) the words so far are kept and listening goes on.
  Future<void> _ended(int generation) async {
    _finishTimeout?.cancel();
    unawaited(_events?.cancel());
    _events = null;
    _session = null;
    if (generation != _generation) {
      return;
    }
    if (state.phase == VoicePhase.stopping) {
      return _finish(generation);
    }
    if (state.phase != VoicePhase.listening) {
      return;
    }
    if (_sessionText.isEmpty) {
      _silentRestarts++;
    }
    if (_silentRestarts >= 2) {
      // Nothing is coming in: stop instead of listening on forever.
      if (_heardAnything) {
        return _finish(generation);
      }
      return _fail(generation, VoiceInputFailure.noSpeech);
    }
    _before = _joined(_before, _sessionText);
    _sessionText = '';
    state = state.copyWith(phase: VoicePhase.starting, partial: '');
    await _listen(generation);
  }

  // ------------------------------------------------------------- writing --

  /// [before] + [text] with a space between where the languages need one.
  String _joined(String before, String text) {
    if (text.isEmpty) {
      return before;
    }
    final head = _needsSpace(before, text) ? '$before ' : before;
    return '$head$text';
  }

  static bool _wordChar(String character) {
    return RegExp(r'[A-Za-z0-9]').hasMatch(character);
  }

  static bool _needsSpace(String left, String right) {
    if (left.isEmpty || right.isEmpty) {
      return false;
    }
    final last = left.substring(left.length - 1);
    final first = right.substring(0, 1);
    if (RegExp(r'\s').hasMatch(last) || RegExp(r'\s').hasMatch(first)) {
      return false;
    }
    // Words of a spaced language; Chinese runs together.
    if (_wordChar(last) && _wordChar(first)) {
      return true;
    }
    return RegExp(r'[.,!?;:]').hasMatch(last) && _wordChar(first);
  }

  void _write(String text) {
    final field = _field;
    if (field == null) {
      return;
    }
    final head = _joined(_before, text);
    final tail = text.isNotEmpty && _needsSpace(head, _after)
        ? ' $_after'
        : _after;
    final value = '$head$tail';
    _lastWritten = value;
    field.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: head.length),
    );
  }

  void _onFieldChanged() {
    final field = _field;
    if (field == null || state.phase != VoicePhase.listening) {
      return;
    }
    if (field.text != _lastWritten) {
      // The person is typing: leave their text alone. Listening ends and
      // whatever they typed stays.
      _teardown();
      state = VoiceInputState(language: state.language);
    }
  }

  // ----------------------------------------------------------- stopping --

  /// Done: stops listening and keeps the words in the field.
  Future<void> done() async {
    final generation = _generation;
    switch (state.phase) {
      case VoicePhase.listening:
        state = state.copyWith(phase: VoicePhase.stopping);
        _idle?.cancel();
        _finishTimeout = Timer(finishTimeout, () => _finish(generation));
        try {
          await _session?.stop();
        } on Object {
          _finish(generation);
        }
      case VoicePhase.starting:
      case VoicePhase.consent:
      case VoicePhase.error:
        // Nothing was heard yet: closing is cancelling.
        await cancel();
      case VoicePhase.stopping:
      case VoicePhase.idle:
        break;
    }
  }

  void _finish(int generation) {
    if (generation != _generation || state.phase == VoicePhase.idle) {
      return;
    }
    final focus = _focus;
    _teardown();
    state = VoiceInputState(language: state.language);
    focus?.requestFocus();
  }

  /// Cancel: stops listening and puts the field back as it was.
  Future<void> cancel() async {
    if (state.phase == VoicePhase.idle) {
      return;
    }
    final field = _field;
    final original = _original;
    final focus = _focus;
    _teardown();
    if (field != null && original != null) {
      field.value = original;
    }
    state = VoiceInputState(language: state.language);
    focus?.requestFocus();
  }

  void _teardown() {
    _generation++;
    _idle?.cancel();
    _finishTimeout?.cancel();
    unawaited(_events?.cancel());
    unawaited(_session?.cancel());
    _events = null;
    _session = null;
    _field?.removeListener(_onFieldChanged);
    _field = null;
    _focus = null;
    _original = null;
  }

  void _fail(int generation, VoiceInputFailure failure) {
    if (generation != _generation) {
      return;
    }
    _idle?.cancel();
    _finishTimeout?.cancel();
    unawaited(_events?.cancel());
    unawaited(_session?.cancel());
    _events = null;
    _session = null;
    _field?.removeListener(_onFieldChanged);
    state = state.copyWith(phase: VoicePhase.error, failure: failure);
  }

  /// Closes an error message. What was heard before it stays in the field.
  void dismissError() {
    if (state.phase != VoicePhase.error) {
      return;
    }
    final focus = _focus;
    _teardown();
    state = VoiceInputState(language: state.language);
    focus?.requestFocus();
  }

  void _armIdle(int generation) {
    _idle?.cancel();
    _idle = Timer(idleTimeout, () {
      if (generation == _generation && state.phase == VoicePhase.listening) {
        unawaited(done());
      }
    });
  }

  // ----------------------------------------------------------- language --

  /// Switches between 中文 and English. While listening (or showing a
  /// problem or the consent question) what was heard so far stays and
  /// listening starts again in the new language.
  Future<void> setLanguage(VoiceInputLanguage language) async {
    if (language == state.language) {
      return;
    }
    if (state.phase == VoicePhase.idle || _field == null) {
      state = state.copyWith(language: language);
      return;
    }
    await _restart(language);
  }

  /// Tries again after a problem.
  Future<void> retry() async {
    if (state.phase == VoicePhase.error && _field != null) {
      await _restart(state.language);
    }
  }

  Future<void> _restart(VoiceInputLanguage language) async {
    final generation = ++_generation;
    _idle?.cancel();
    _finishTimeout?.cancel();
    unawaited(_events?.cancel());
    unawaited(_session?.cancel());
    _events = null;
    _session = null;
    _before = _joined(_before, _sessionText);
    _sessionText = '';
    _silentRestarts = 0;
    _field!
      ..removeListener(_onFieldChanged)
      ..addListener(_onFieldChanged);
    state = state.copyWith(
      language: language,
      phase: VoicePhase.starting,
      partial: '',
      failure: null,
    );
    await _prepare(generation);
  }
}
