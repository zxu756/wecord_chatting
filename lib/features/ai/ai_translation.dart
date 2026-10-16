import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
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
  });

  final AiTranslationPhase phase;
  final AiLanguage language;
  final String? text;
  final Object? error;
}

/// Translations of messages into the app's language, shown inline under the
/// message until hidden. Translated texts are cached in memory for the
/// session, per message, text and language, so showing one again costs no
/// request. Nothing is stored on the server.
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

  /// Translates [text] (the body of [messageId]) into [target] (the app's
  /// language by default) and shows it under the message.
  Future<void> translate(
    String messageId,
    String text, {
    String? conversationId,
    AiLanguage? target,
  }) async {
    final language = target ?? AiLanguage.appLanguage;
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
      final translated = await ref
          .read(aiRepositoryProvider)
          .translate(
            text: text,
            target: language,
            conversationId: conversationId,
          );
      _cache[key] = translated;
      show(
        AiMessageTranslation(
          phase: AiTranslationPhase.done,
          language: language,
          text: translated,
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
        ),
      );
    }
  }

  /// Shows the original again: removes the translation (the cache stays).
  void hide(String messageId) {
    _generations[messageId] = (_generations[messageId] ?? 0) + 1;
    if (state.containsKey(messageId)) {
      state = {...state}..remove(messageId);
    }
  }
}

/// The translation under a message: the translated text with "Show
/// original", a spinner while it is on its way, or the error with a retry.
/// Nothing when the message isn't being translated.
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
    if (translation == null) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(aiTranslationsProvider.notifier);
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
                  () => notifier.hide(messageId),
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
                    () => unawaited(
                      notifier.translate(
                        messageId,
                        text,
                        conversationId: conversationId,
                      ),
                    ),
                    key: const ValueKey('ai-translation-retry'),
                  ),
                link(tr('Dismiss'), () => notifier.hide(messageId)),
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
