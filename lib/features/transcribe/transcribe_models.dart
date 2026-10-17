import 'package:flutter/foundation.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// Where a voice message is turned into text.
enum TranscribeEngine {
  /// The system's speech recognizer, running on this device (iPhone, Mac).
  onDevice,

  /// Apple's speech servers, for a language the device can't recognize on
  /// its own. Only after the person agreed to it.
  appleServer,

  /// The WeCord server's speech-to-text provider (the web).
  aiServer,
}

/// Why a voice message can't be transcribed here at all.
enum TranscribeUnavailable {
  /// This platform has no speech recognizer to use (the web without a
  /// server provider, Android, Windows, Linux).
  platform,

  /// The device has no recognizer for the language.
  language,

  /// The person turned AI features off in Settings → AI, which the web's
  /// server transcription belongs to.
  aiOff,
}

/// What a transcriber can do for one voice message.
@immutable
class TranscribePlan {
  const TranscribePlan.engine(
    TranscribeEngine this.engine, {
    this.canAutoStart = false,
  }) : unavailable = null;

  const TranscribePlan.unavailable(TranscribeUnavailable this.unavailable)
    : engine = null,
      canAutoStart = false;

  final TranscribeEngine? engine;
  final TranscribeUnavailable? unavailable;

  /// Whether transcribing on its own is fine: on the device, with speech
  /// recognition already allowed (or not yet asked about).
  final bool canAutoStart;
}

/// One voice message to transcribe.
@immutable
class TranscribeRequest {
  const TranscribeRequest({
    required this.messageId,
    required this.attachment,
    required this.locales,
    this.conversationId,
  });

  /// For a voice message in the app's language (Chinese or English).
  factory TranscribeRequest.forMessage({
    required String messageId,
    required VoiceAttachment attachment,
    String? conversationId,
  }) {
    return TranscribeRequest(
      messageId: messageId,
      conversationId: conversationId,
      attachment: attachment,
      locales: speechLocales(),
    );
  }

  final String messageId;
  final String? conversationId;
  final VoiceAttachment attachment;

  /// Speech recognition locales to try in order; the device's own language
  /// comes after them.
  final List<String> locales;
}

/// The speech recognition locale of the app's language: zh-CN for Chinese,
/// en-US otherwise.
List<String> speechLocales() => [AppStrings.isChinese ? 'zh-CN' : 'en-US'];

/// A transcript, and how it was made.
@immutable
class VoiceTranscript {
  const VoiceTranscript(this.text, this.engine);

  final String text;
  final TranscribeEngine engine;
}

enum TranscribeFailureKind {
  /// Speech recognition is turned off for the app in the system settings.
  notAuthorized,

  /// The recording has no speech in it.
  noSpeech,

  /// The audio is in a format the system can't open.
  unreadable,

  /// The recognizer can't run right now.
  unavailable,

  /// The language can't be recognized on the device; Apple's servers could.
  needsServer,

  failed,
}

class TranscribeException implements Exception {
  const TranscribeException(this.kind);

  final TranscribeFailureKind kind;

  @override
  String toString() => 'TranscribeException($kind)';
}

/// What to tell the person about [error], in their language.
String transcribeErrorMessage(Object error) {
  if (error is TranscribeException) {
    return switch (error.kind) {
      TranscribeFailureKind.notAuthorized => tr(
        'Speech recognition is turned off for WeCord. Turn it on in Settings, under Privacy, then try again.',
      ),
      TranscribeFailureKind.noSpeech => tr(
        "Couldn't find any speech in this voice message.",
      ),
      TranscribeFailureKind.unreadable => tr(
        "This voice message can't be transcribed.",
      ),
      TranscribeFailureKind.unavailable => tr(
        "Speech recognition isn't available right now. Try again later.",
      ),
      TranscribeFailureKind.needsServer ||
      TranscribeFailureKind.failed => tr('Something went wrong. Try again.'),
    };
  }
  return aiErrorMessage(error);
}

/// Whether trying again could help after [error].
bool transcribeCanRetry(Object error) {
  if (error is TranscribeException) {
    return switch (error.kind) {
      TranscribeFailureKind.noSpeech ||
      TranscribeFailureKind.unreadable => false,
      _ => true,
    };
  }
  return error is! AiNotConfiguredException &&
      error is! AiTranscribeNotConfiguredException &&
      error is! AiLimitReachedException &&
      error is! AiDisabledInCircleException &&
      error is! AiRejectedException;
}

/// The note shown instead of a transcript when [reason] rules it out.
String transcribeUnavailableMessage(TranscribeUnavailable reason) {
  return switch (reason) {
    TranscribeUnavailable.platform => tr(
      'Transcription is available in the iPhone and Mac apps.',
    ),
    TranscribeUnavailable.language => tr(
      "This device can't transcribe voice messages in this language yet.",
    ),
    TranscribeUnavailable.aiOff => tr(
      'Turn on AI features in Settings → AI to transcribe voice messages here.',
    ),
  };
}

/// How a finished transcript was made, for its caption.
String transcribeEngineCaption(TranscribeEngine engine) {
  return switch (engine) {
    TranscribeEngine.onDevice => tr('Transcribed on this device'),
    TranscribeEngine.appleServer => tr("Transcribed by Apple's speech service"),
    TranscribeEngine.aiServer => tr('Transcribed by AI on the server'),
  };
}
