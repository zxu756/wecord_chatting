import 'package:wecord/features/ai/ai_models.dart';

/// A rough guess at the language of a text, from its script alone (the same
/// rule as the `ai` function's translate_batch, so the app does not ask for
/// what the server would skip).
enum RoughLanguage {
  chinese,
  japanese,
  korean,

  /// English, Spanish, French and the like: the script can't tell them apart.
  latin,

  /// Another script.
  other,

  /// No letters at all: emoji, links, @mentions, numbers, punctuation.
  none,
}

final _link = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);
final _mention = RegExp(r'(?:^|\s)@[\p{L}\p{N}_.\-]+', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _hangul = RegExp(r'\p{Script=Hangul}', unicode: true);
final _kana = RegExp(
  r'[\p{Script=Hiragana}\p{Script=Katakana}]',
  unicode: true,
);
final _han = RegExp(r'\p{Script=Han}', unicode: true);
final _latin = RegExp(r'\p{Script=Latin}', unicode: true);

/// The language [text] looks like, ignoring links, @mentions, emoji, digits
/// and punctuation.
RoughLanguage roughLanguage(String text) {
  final stripped = text.replaceAll(_link, ' ').replaceAll(_mention, ' ');
  var total = 0;
  var hangul = 0;
  var kana = 0;
  var han = 0;
  var latin = 0;
  for (final rune in stripped.runes) {
    final char = String.fromCharCode(rune);
    if (!_letter.hasMatch(char)) {
      continue;
    }
    total++;
    if (_hangul.hasMatch(char)) {
      hangul++;
    } else if (_kana.hasMatch(char)) {
      kana++;
    } else if (_han.hasMatch(char)) {
      han++;
    } else if (_latin.hasMatch(char)) {
      latin++;
    }
  }
  if (total == 0) {
    return RoughLanguage.none;
  }
  if (hangul / total >= 0.3) {
    return RoughLanguage.korean;
  }
  if (kana > 0 && (kana + han) / total >= 0.5) {
    return RoughLanguage.japanese;
  }
  if (han / total >= 0.5) {
    return RoughLanguage.chinese;
  }
  if (latin / total >= 0.6) {
    return RoughLanguage.latin;
  }
  return RoughLanguage.other;
}

/// The language [guess] is, when the script says so.
AiLanguage? languageOf(RoughLanguage guess) {
  return switch (guess) {
    RoughLanguage.chinese => AiLanguage.chinese,
    RoughLanguage.japanese => AiLanguage.japanese,
    RoughLanguage.korean => AiLanguage.korean,
    _ => null,
  };
}

/// The longest message auto-translate sends (longer ones keep the message
/// menu's Translate).
const autoTranslateMaxChars = 1500;

/// Whether auto-translate should ask for a translation of [text] into
/// [target]: it has letters, is not already in [target] by its script, is
/// not in a language in [skipLanguages] by its script, and is not too long.
bool worthTranslating(
  String text,
  AiLanguage target, {
  Set<AiLanguage> skipLanguages = const {},
}) {
  if (text.trim().isEmpty || text.length > autoTranslateMaxChars) {
    return false;
  }
  final guess = roughLanguage(text);
  if (guess == RoughLanguage.none) {
    return false;
  }
  final language = languageOf(guess);
  return language == null ||
      (language != target && !skipLanguages.contains(language));
}
