import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/translate_repository.dart';

/// Settings → AI → "Translate to" and "Don't translate": kept on the server
/// (user_ai_settings) so every device of the person agrees, and read once
/// per session. Until it is read, the defaults apply.
final aiTranslateSettingsProvider =
    NotifierProvider<AiTranslateSettingsController, AiTranslateSettings>(
      AiTranslateSettingsController.new,
    );

class AiTranslateSettingsController extends Notifier<AiTranslateSettings> {
  var _changed = false;

  @override
  AiTranslateSettings build() {
    unawaited(_load());
    return const AiTranslateSettings();
  }

  Future<void> _load() async {
    try {
      final stored = await ref.read(translateRepositoryProvider).loadSettings();
      // A choice made while loading wins over the stored one.
      if (stored != null && !_changed && ref.mounted) {
        state = stored;
      }
    } on Object {
      // Offline: the defaults apply.
    }
  }

  Future<void> setTarget(AiLanguage? target) =>
      _set(state.copyWith(target: target));

  Future<void> setNoTranslate(AiLanguage language, {required bool on}) {
    final next = {...state.noTranslate};
    if (on) {
      next.add(language);
    } else {
      next.remove(language);
    }
    return _set(state.copyWith(noTranslate: next));
  }

  Future<void> _set(AiTranslateSettings next) async {
    _changed = true;
    state = next;
    try {
      await ref.read(translateRepositoryProvider).saveSettings(next);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// The language messages are translated into: the person's choice, or the
/// language of the app.
AiLanguage translateTargetOf(AiTranslateSettings settings) =>
    settings.target ?? AiLanguage.appLanguage;

/// "Auto-translate this chat", per chat (conversation_translation_prefs),
/// loaded when a chat asks for it.
final conversationTranslateProvider =
    NotifierProvider<
      ConversationTranslateController,
      Map<String, ConversationTranslatePref>
    >(ConversationTranslateController.new);

class ConversationTranslateController
    extends Notifier<Map<String, ConversationTranslatePref>> {
  final _loading = <String>{};

  @override
  Map<String, ConversationTranslatePref> build() => const {};

  /// Reads the choice for [conversationId] from the server once.
  void ensureLoaded(String conversationId) {
    if (state.containsKey(conversationId) || !_loading.add(conversationId)) {
      return;
    }
    unawaited(() async {
      try {
        final pref = await ref
            .read(translateRepositoryProvider)
            .loadConversationPref(conversationId);
        if (ref.mounted && !state.containsKey(conversationId)) {
          state = {...state, conversationId: pref};
        }
      } on Object {
        // Offline: off until it can be read.
      } finally {
        _loading.remove(conversationId);
      }
    }());
  }

  ConversationTranslatePref of(String conversationId) =>
      state[conversationId] ?? const ConversationTranslatePref();

  Future<void> setAuto(String conversationId, {required bool on}) => _set(
    conversationId,
    ConversationTranslatePref(auto: on, target: of(conversationId).target),
  );

  Future<void> _set(
    String conversationId,
    ConversationTranslatePref pref,
  ) async {
    state = {...state, conversationId: pref};
    try {
      await ref
          .read(translateRepositoryProvider)
          .saveConversationPref(conversationId, pref);
    } on Object {
      // Still applies for this session.
    }
  }
}
