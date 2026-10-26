import 'package:wecord/shared/l10n/l10n.dart';

/// A language the AI features write or translate into.
enum AiLanguage {
  english('en'),
  chinese('zh'),
  japanese('ja'),
  korean('ko'),
  spanish('es'),
  french('fr');

  const AiLanguage(this.code);

  /// The code the `ai` function takes.
  final String code;

  /// The language with [code], or null for none of the six.
  static AiLanguage? fromCode(Object? code) {
    for (final language in values) {
      if (language.code == code) {
        return language;
      }
    }
    return null;
  }

  String get label => switch (this) {
    AiLanguage.english => tr('English'),
    AiLanguage.chinese => tr('Chinese'),
    AiLanguage.japanese => tr('Japanese'),
    AiLanguage.korean => tr('Korean'),
    AiLanguage.spanish => tr('Spanish'),
    AiLanguage.french => tr('French'),
  };

  /// The language of the app's interface: summaries and translations of
  /// messages are written in it.
  static AiLanguage get appLanguage =>
      AppStrings.isChinese ? AiLanguage.chinese : AiLanguage.english;
}

/// What the composer's AI button can do with the draft.
enum AiRewriteMode {
  fix('fix'),
  shorter('shorter'),
  polite('polite'),
  formal('formal'),
  translate('translate');

  const AiRewriteMode(this.code);

  final String code;

  String get label => switch (this) {
    AiRewriteMode.fix => tr('Fix spelling & grammar'),
    AiRewriteMode.shorter => tr('Make it shorter'),
    AiRewriteMode.polite => tr('Make it more polite / friendly'),
    AiRewriteMode.formal => tr('Make it more formal'),
    AiRewriteMode.translate => tr('Translate to…'),
  };
}

/// Whether AI is set up on the server and how much of today's limit the
/// signed-in user has used.
class AiStatus {
  const AiStatus({
    required this.dailyLimit,
    required this.used,
    this.transcribeConfigured = false,
  });

  final int dailyLimit;
  final int used;

  /// Whether the server can also transcribe voice messages (the optional
  /// AI_TRANSCRIBE_* secrets are set). Only the web uses it: the iPhone and
  /// Mac apps transcribe on the device.
  final bool transcribeConfigured;

  int get remaining => (dailyLimit - used).clamp(0, dailyLimit);
}

/// A catch-up summary of a conversation.
class AiSummary {
  const AiSummary({
    required this.text,
    required this.messageCount,
    required this.summarizedCount,
    this.firstMessageId,
  });

  /// Bullet points, one per line.
  final String text;

  /// How many messages the summary covers (all of them, even when the
  /// oldest were left out for length).
  final int messageCount;
  final int summarizedCount;

  /// The first message of the range, to jump to.
  final String? firstMessageId;

  /// The bullet points without their markers or Markdown emphasis.
  List<String> get bullets => summaryBullets(text);
}

/// [text] as one entry per bullet point: list markers and `**` emphasis
/// removed, blank lines dropped.
List<String> summaryBullets(String text) {
  return [
    for (final line in text.split('\n'))
      if (_cleanBullet(line) case final bullet when bullet.isNotEmpty) bullet,
  ];
}

String _cleanBullet(String line) {
  return line
      .trim()
      .replaceFirst(RegExp(r'^([-*•·]|\d+[.)])\s+'), '')
      .replaceAll('**', '')
      .trim();
}

/// Why an AI request did not give an answer.
sealed class AiException implements Exception {
  const AiException();
}

/// AI isn't set up on the server (no provider secrets).
class AiNotConfiguredException extends AiException {
  const AiNotConfiguredException();
}

/// The user used up today's requests.
class AiLimitReachedException extends AiException {
  const AiLimitReachedException({this.limit, this.used});

  final int? limit;
  final int? used;
}

/// The server has AI but no speech-to-text provider (the optional
/// AI_TRANSCRIBE_* secrets).
class AiTranscribeNotConfiguredException extends AiException {
  const AiTranscribeNotConfiguredException();
}

/// The person turned AI features off in Settings → AI (the server was told).
class AiTurnedOffException extends AiException {
  const AiTurnedOffException();
}

/// The provider is out of capacity or quota for now; try again later.
class AiBusyException extends AiException {
  const AiBusyException();
}

/// The circle turned AI features off.
class AiDisabledInCircleException extends AiException {
  const AiDisabledInCircleException();
}

/// The person locked this chat (App lock and chat lock): AI never reads it.
class AiChatLockedException extends AiException {
  const AiChatLockedException();
}

/// The conversation or message can't be read, or is too long.
class AiRejectedException extends AiException {
  const AiRejectedException();
}

/// Anything else: the provider failed or the network did.
class AiFailedException extends AiException {
  const AiFailedException();
}

/// The exception for the `ai` function's error answer.
AiException aiExceptionFor(int? status, Object? details) {
  final code = details is Map ? details['error'] : null;
  switch (code) {
    case 'ai_not_configured':
      return const AiNotConfiguredException();
    case 'ai_limit_reached':
      return AiLimitReachedException(
        limit: details is Map ? (details['limit'] as num?)?.toInt() : null,
        used: details is Map ? (details['used'] as num?)?.toInt() : null,
      );
    case 'transcribe_not_configured':
      return const AiTranscribeNotConfiguredException();
    case 'ai_busy':
      return const AiBusyException();
    case 'ai_disabled_in_circle':
      return const AiDisabledInCircleException();
    case 'ai_disabled_for_user':
      return const AiTurnedOffException();
    case 'chat_locked':
      return const AiChatLockedException();
    case 'conversation_not_found' ||
        'note_not_found' ||
        'text_too_long' ||
        'message_not_found' ||
        'audio_too_long':
      return const AiRejectedException();
  }
  return const AiFailedException();
}

/// What to tell the user about [error], in their language.
String aiErrorMessage(Object error) {
  return switch (error) {
    AiNotConfiguredException() => tr(
      "AI features aren't set up on this server yet.",
    ),
    AiLimitReachedException(:final limit) when limit != null => tr(
      "You've reached today's AI limit of {limit} requests. It resets tomorrow.",
      {'limit': limit},
    ),
    AiLimitReachedException() => tr(
      "You've reached today's AI limit. It resets tomorrow.",
    ),
    AiTranscribeNotConfiguredException() => tr(
      "This server can't transcribe voice messages yet.",
    ),
    AiBusyException() => tr(
      'AI is busy right now. Try again in a little while.',
    ),
    AiDisabledInCircleException() => tr(
      'AI features are turned off in this circle.',
    ),
    AiTurnedOffException() => tr(
      'AI features are turned off. You can turn them on in Settings.',
    ),
    AiChatLockedException() => tr("AI doesn't read chats you've locked."),
    AiRejectedException() => tr("That can't be processed."),
    _ => tr('Something went wrong. Try again.'),
  };
}
