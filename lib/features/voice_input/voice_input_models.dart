import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The languages voice input can listen for. It starts with the app's
/// language and the person can switch in the panel.
enum VoiceInputLanguage {
  chinese('zh-CN', '中文'),
  english('en-US', 'English');

  const VoiceInputLanguage(this.locale, this.label);

  /// The BCP 47 tag the recognizers take.
  final String locale;

  /// Written in its own language, as a language switch does.
  final String label;

  /// The language the interface is in right now.
  static VoiceInputLanguage get ofApp =>
      AppStrings.isChinese ? chinese : english;
}

/// Who turns the speech into words, which decides what the person is told.
enum VoiceInputEngine {
  /// The speech never leaves the device.
  onDevice,

  /// Apple's speech servers (a language the device can't do by itself).
  appleServer,

  /// The browser's speech service (Chrome sends audio to Google, for one).
  browser,
}

/// What a recognizer can do for a language right now. Never asks for any
/// permission.
@immutable
class VoiceInputCapabilities {
  const VoiceInputCapabilities({
    required this.supported,
    this.available = true,
    this.engine = VoiceInputEngine.onDevice,
  });

  /// There is a recognizer for the language at all.
  final bool supported;

  /// It can be used right now (it may not be, for want of a network or
  /// while the system is busy).
  final bool available;

  /// Where the audio is processed.
  final VoiceInputEngine engine;

  bool get usable => supported && available;
}

enum VoiceInputFailure {
  /// Speech recognition is turned off for the app in the system settings.
  speechDenied,

  /// The microphone is turned off for the app (or the browser tab).
  micDenied,

  /// The language has no recognizer here.
  unsupportedLanguage,

  /// The recognizer can't be used right now.
  unavailable,

  /// Nothing was heard.
  noSpeech,

  /// The recognizer failed, or the network did (in the browser).
  failed;

  /// What to tell the person.
  String get message => switch (this) {
    speechDenied => tr(
      'Speech recognition is turned off for WeCord. Turn it on in Settings, under Privacy, then try again.',
    ),
    micDenied => tr(
      'The microphone is turned off for WeCord. Turn it on in Settings, then try again.',
    ),
    unsupportedLanguage => tr(
      "This device can't recognize speech in this language yet.",
    ),
    unavailable => tr(
      "Speech recognition isn't available right now. Try again later.",
    ),
    noSpeech => tr("Couldn't hear anything. Try again."),
    failed => tr("Voice input stopped working. Try again."),
  };
}

/// Something the recognizer reports while a session runs.
sealed class VoiceInputEvent {
  const VoiceInputEvent();
}

/// Everything recognized in this session so far (not just the new words),
/// still open to change as more is heard.
class VoicePartial extends VoiceInputEvent {
  const VoicePartial(this.text);

  final String text;
}

/// Everything recognized in this session, settled. The session ends right
/// after it (the recognizer is done with this stretch of speech).
class VoiceFinal extends VoiceInputEvent {
  const VoiceFinal(this.text);

  final String text;
}

/// How loud it is, 0...1, for the waveform.
class VoiceLevel extends VoiceInputEvent {
  const VoiceLevel(this.value);

  final double value;
}

class VoiceError extends VoiceInputEvent {
  const VoiceError(this.failure);

  final VoiceInputFailure failure;
}

/// The session is over (always the last event of one).
class VoiceEnded extends VoiceInputEvent {
  const VoiceEnded();
}

/// A session could not start.
class VoiceInputException implements Exception {
  const VoiceInputException(this.failure, {this.needsServer = false});

  final VoiceInputFailure failure;

  /// The language can only be recognized on a server and the caller did not
  /// allow that.
  final bool needsServer;

  @override
  String toString() => 'VoiceInputException($failure)';
}
