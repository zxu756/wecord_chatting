import 'package:flutter/foundation.dart';
import 'package:wecord/features/ai/ai_models.dart';

/// One translated message, as the `ai` function's translate_batch gives it.
@immutable
class TranslatedMessage {
  const TranslatedMessage({required this.text, this.sourceLanguage});

  final String text;

  /// The language of the original, when the model said (null for "other").
  final AiLanguage? sourceLanguage;
}

/// Why a message came back without a translation (translate_batch's
/// `skipped`). Anything the app doesn't know counts as [unavailable].
enum TranslateSkip {
  /// Recalled, expired, waiting for review, or not readable by the person.
  unavailable,
  notText,
  nothingToTranslate,
  sameLanguage,
  skipLanguage,
  tooLong,

  /// Left for the next request (the batch was full, or the daily limit was
  /// reached with other answers in hand).
  later,
  failed;

  static TranslateSkip fromJson(Object? value) {
    return switch (value) {
      'not_text' => notText,
      'nothing_to_translate' => nothingToTranslate,
      'same_language' => sameLanguage,
      'skip_language' => skipLanguage,
      'too_long' => tooLong,
      'later' => later,
      'failed' => failed,
      _ => unavailable,
    };
  }

  /// Asking again could give a translation.
  bool get retryable => this == later || this == failed;
}

@immutable
class TranslateBatchResult {
  const TranslateBatchResult({
    this.translations = const {},
    this.skipped = const {},
    this.limitReached = false,
  });

  final Map<String, TranslatedMessage> translations;
  final Map<String, TranslateSkip> skipped;

  /// The daily limit stopped the messages that weren't cached.
  final bool limitReached;
}

/// What "Translate to" and "Don't translate" hold (Settings → AI).
@immutable
class AiTranslateSettings {
  const AiTranslateSettings({this.target, this.noTranslate = const {}});

  /// Null follows the language of the app.
  final AiLanguage? target;
  final Set<AiLanguage> noTranslate;

  AiTranslateSettings copyWith({
    Object? target = _unset,
    Set<AiLanguage>? noTranslate,
  }) {
    return AiTranslateSettings(
      target: identical(target, _unset) ? this.target : target as AiLanguage?,
      noTranslate: noTranslate ?? this.noTranslate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiTranslateSettings &&
      other.target == target &&
      setEquals(other.noTranslate, noTranslate);

  @override
  int get hashCode => Object.hash(target, Object.hashAllUnordered(noTranslate));
}

const _unset = Object();

/// One chat's "Auto-translate this chat" choice.
@immutable
class ConversationTranslatePref {
  const ConversationTranslatePref({this.auto = false, this.target});

  final bool auto;

  /// A language for this chat alone; null follows the person's default.
  final AiLanguage? target;

  @override
  bool operator ==(Object other) =>
      other is ConversationTranslatePref &&
      other.auto == auto &&
      other.target == target;

  @override
  int get hashCode => Object.hash(auto, target);
}

/// Translating messages through the `ai` function's cache, and the choices
/// that go with it. [AiRepository] implementations that can translate
/// messages implement this too (see translateRepositoryProvider).
abstract interface class TranslateRepository {
  /// Translations of [messageIds] (at most 20, all in [conversationId]) into
  /// [target]. The server answers from its cache first and only counts a
  /// request against the daily limit for what it has to translate. With
  /// [manual] the person asked for these messages: nothing is skipped for
  /// being in the target language or a language they don't translate.
  Future<TranslateBatchResult> translateBatch({
    required String conversationId,
    required List<String> messageIds,
    required AiLanguage target,
    bool manual = false,
  });

  /// "Translate to" and "Don't translate"; null when none are stored.
  Future<AiTranslateSettings?> loadSettings();

  Future<void> saveSettings(AiTranslateSettings settings);

  /// Copies the device's "AI features" switch to the server, which honours
  /// it for translations.
  Future<void> syncAiEnabled({required bool enabled});

  Future<ConversationTranslatePref> loadConversationPref(String conversationId);

  Future<void> saveConversationPref(
    String conversationId,
    ConversationTranslatePref pref,
  );
}
