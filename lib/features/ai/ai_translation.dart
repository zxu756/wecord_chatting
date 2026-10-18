import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/auto_translate.dart';
import 'package:wecord/features/ai/translate_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

enum AiTranslationPhase { loading, done, failed }

/// The translation shown under one message.
@immutable
class AiMessageTranslation {
  const AiMessageTranslation({
    required this.phase,
    required this.language,
    this.text,
    this.error,
    this.auto = false,
    this.sourceHash,
  });

  final AiTranslationPhase phase;
  final AiLanguage language;
  final String? text;
  final Object? error;

  /// Made by "Auto-translate this chat": shown by the bubble footer entry
  /// (see [AutoTranslationFooter]) rather than under the message text.
  final bool auto;

  /// The hash of the message text this translates, so a translation of text
  /// that has since been edited is not shown.
  final int? sourceHash;
}

/// Translations of messages (the message menu's Translate, and what
/// "Auto-translate this chat" fills in), shown under the message until
/// hidden. Both go through the `ai` function's translate_batch, which keeps
/// a translation per message and language, so a translation someone already
/// asked for costs no model request; texts are also cached in memory for the
/// session, per message, text and language.
final aiTranslationsProvider =
    NotifierProvider<AiTranslations, Map<String, AiMessageTranslation>>(
      AiTranslations.new,
    );

class AiTranslations extends Notifier<Map<String, AiMessageTranslation>> {
  final _cache = <String, String>{};
  final _generations = <String, int>{};

  @override
  Map<String, AiMessageTranslation> build() => const {};

  String _cacheKey(String messageId, String text, AiLanguage language) {
    return '$messageId|${language.code}|${text.hashCode}';
  }

  /// Whether [messageId] shows a translation (or is getting one).
  bool isShown(String messageId) => state.containsKey(messageId);

  /// Translates [text] (the body of [messageId]) into [target] (the person's
  /// "Translate to" language by default) and shows it under the message.
  Future<void> translate(
    String messageId,
    String text, {
    String? conversationId,
    AiLanguage? target,
  }) async {
    final language =
        target ?? translateTargetOf(ref.read(aiTranslateSettingsProvider));
    final generation = (_generations[messageId] ?? 0) + 1;
    _generations[messageId] = generation;
    void show(AiMessageTranslation translation) {
      if (_generations[messageId] == generation) {
        state = {...state, messageId: translation};
      }
    }

    final key = _cacheKey(messageId, text, language);
    final cached = _cache[key];
    if (cached != null) {
      show(
        AiMessageTranslation(
          phase: AiTranslationPhase.done,
          language: language,
          text: cached,
        ),
      );
      return;
    }
    show(
      AiMessageTranslation(
        phase: AiTranslationPhase.loading,
        language: language,
      ),
    );
    try {
      final translated = await _fetch(
        messageId,
        text,
        language,
        conversationId,
      );
      _cache[key] = translated;
      show(
        AiMessageTranslation(
          phase: AiTranslationPhase.done,
          language: language,
          text: translated,
          sourceHash: text.hashCode,
        ),
      );
    } on Object catch (error) {
      if (error is AiNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      show(
        AiMessageTranslation(
          phase: AiTranslationPhase.failed,
          language: language,
          error: error,
          sourceHash: text.hashCode,
        ),
      );
    }
  }

  /// The translation of one message the person asked for: through the
  /// server's cache when the message is in a conversation, otherwise (a text
  /// that is not a message) straight from the model.
  Future<String> _fetch(
    String messageId,
    String text,
    AiLanguage language,
    String? conversationId,
  ) async {
    if (conversationId == null) {
      return ref
          .read(aiRepositoryProvider)
          .translate(text: text, target: language);
    }
    final result = await ref
        .read(translateRepositoryProvider)
        .translateBatch(
          conversationId: conversationId,
          messageIds: [messageId],
          target: language,
          manual: true,
        );
    final translated = result.translations[messageId]?.text.trim();
    if (translated != null && translated.isNotEmpty) {
      return translated;
    }
    throw result.limitReached
        ? const AiLimitReachedException()
        : result.skipped[messageId]?.retryable == false
        ? const AiRejectedException()
        : const AiFailedException();
  }

  /// Shows what auto-translate got for [messageId].
  void showAuto(
    String messageId, {
    required String text,
    required AiLanguage language,
    required int sourceHash,
  }) {
    if (state[messageId] case final shown? when !shown.auto) {
      // A translation the person asked for stays as it is.
      return;
    }
    state = {
      ...state,
      messageId: AiMessageTranslation(
        phase: AiTranslationPhase.done,
        language: language,
        text: text,
        auto: true,
        sourceHash: sourceHash,
      ),
    };
  }

  /// Shows the original again: removes the translation (the cache stays),
  /// and auto-translate leaves this message alone from now on.
  void hide(String messageId) {
    _generations[messageId] = (_generations[messageId] ?? 0) + 1;
    if (state.containsKey(messageId)) {
      state = {...state}..remove(messageId);
    }
    ref.read(autoTranslateProvider.notifier).dismiss(messageId);
  }
}

/// The translation under a message: the translated text with "Show
/// original", a spinner while it is on its way, or the error with a retry.
/// Nothing when the message isn't being translated by hand (what
/// auto-translate made is the bubble footer's: see [AutoTranslationFooter]).
class AiTranslationView extends ConsumerWidget {
  const AiTranslationView({
    required this.messageId,
    required this.text,
    required this.color,
    this.conversationId,
    super.key,
  });

  final String messageId;

  /// The message's own text, to translate again on a retry.
  final String text;
  final String? conversationId;

  /// The message text color, which the translation follows.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translation = ref.watch(
      aiTranslationsProvider.select((all) => all[messageId]),
    );
    if (translation == null || translation.auto) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(aiTranslationsProvider.notifier);
    return TranslationCard(
      translation: translation,
      color: color,
      onHide: () => notifier.hide(messageId),
      onRetry: () => unawaited(
        notifier.translate(messageId, text, conversationId: conversationId),
      ),
    );
  }
}

/// The card of a translation: a rule on the left, the text, the language and
/// "Show original" (or a spinner, or the error with "Try again"). Used under
/// the message text (Translate) and in the bubble footer (auto-translate).
class TranslationCard extends StatelessWidget {
  const TranslationCard({
    required this.translation,
    required this.color,
    required this.onHide,
    required this.onRetry,
    super.key,
  });

  final AiMessageTranslation translation;
  final Color color;
  final VoidCallback onHide;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final caption = color.withValues(alpha: 0.75);

    Widget link(String label, VoidCallback onPressed, {Key? key}) {
      return WeCordPressable(
        key: key,
        onPressed: onPressed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        builder: (context, states) => Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      );
    }

    final Widget body;
    switch (translation.phase) {
      case AiTranslationPhase.loading:
        body = Semantics(
          liveRegion: true,
          label: tr('Translating…'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: caption,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tr('Translating…'),
                style: TextStyle(fontSize: 13, color: caption),
              ),
            ],
          ),
        );
      case AiTranslationPhase.done:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                translation.text ?? '',
                key: const ValueKey('ai-translation-text'),
                style: TextStyle(fontSize: 14.5, height: 1.45, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  tr('Translated to {language}', {
                    'language': translation.language.label,
                  }),
                  style: TextStyle(fontSize: 12.5, color: caption),
                ),
                link(
                  tr('Show original'),
                  onHide,
                  key: const ValueKey('ai-translation-hide'),
                ),
              ],
            ),
          ],
        );
      case AiTranslationPhase.failed:
        final error = translation.error ?? const AiFailedException();
        final canRetry =
            error is! AiNotConfiguredException &&
            error is! AiLimitReachedException &&
            error is! AiTurnedOffException &&
            error is! AiDisabledInCircleException;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                aiErrorMessage(error),
                key: const ValueKey('ai-translation-error'),
                style: TextStyle(fontSize: 13, height: 1.4, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              children: [
                if (canRetry)
                  link(
                    tr('Try again'),
                    onRetry,
                    key: const ValueKey('ai-translation-retry'),
                  ),
                link(tr('Dismiss'), onHide),
              ],
            ),
          ],
        );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        key: const ValueKey('ai-translation'),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: caption, width: 2)),
        ),
        child: body,
      ),
    );
  }
}
