import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/language_detect.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/features/ai/on_device/on_device_chat_reader.dart';
import 'package:wecord/features/ai/on_device/on_device_gate.dart';
import 'package:wecord/features/ai/on_device/on_device_text.dart';
import 'package:wecord/features/ai/translate_repository.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The AI repository of the iPhone and Mac apps (roadmap F8): summaries,
/// rewriting and translation run on the device's own model when the person
/// prefers that and the model can answer, and go to the server's `ai`
/// function (its daily limit, its rules) when it can't.
///
/// On the device nothing is sent anywhere, and nothing counts against the
/// daily limit. The rules of the server still hold: [gate] asks the person's
/// AI switch, the circle's or group's switch, advanced chat privacy (G6) and
/// the chat lock (G2) before any text is read, so the device can't be used to
/// get round them. The model's answer never falls back to the server after a
/// failure: text meant to stay on the device stays on it.
///
/// Everything else (status, circle switch, transcription, translation
/// settings) is the server's.
class OnDeviceFirstAiRepository implements AiRepository, TranslateRepository {
  OnDeviceFirstAiRepository({
    required this._server,
    required this._serverTranslate,
    required this.backend,
    required this.gate,
    required this.reader,
    required this.prefersOnDevice,
  });

  final AiRepository _server;
  final TranslateRepository _serverTranslate;
  final OnDeviceAiBackend backend;
  final OnDeviceAiGate gate;
  final OnDeviceChatReader reader;
  final bool Function() prefersOnDevice;

  /// Runs [local] on the device if the person prefers that and the model can
  /// answer, otherwise [remote]. The gate runs first on the device path; on
  /// the server path the server enforces the same rules itself.
  Future<T> _route<T>({
    required String? conversationId,
    required Future<T> Function() local,
    required Future<T> Function() remote,
  }) async {
    if (!backend.isSupportedPlatform || !prefersOnDevice()) {
      return remote();
    }
    final status = await backend.availability();
    if (!status.available) {
      return remote();
    }
    await gate.check(conversationId: conversationId);
    try {
      return await local();
    } on OnDeviceAiUnavailableException {
      // The model went away between the check and the request; nothing was
      // processed, so the server can take it.
      return remote();
    } on OnDeviceAiFailedException catch (error) {
      throw AiOnDeviceFailedException(error.kind);
    }
  }

  @override
  Future<AiSummary?> summarize({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
    AiLanguage language = AiLanguage.english,
  }) {
    return _route(
      conversationId: conversationId,
      remote: () => _server.summarize(
        conversationId: conversationId,
        afterMessageId: afterMessageId,
        useStoredMarker: useStoredMarker,
        recent: recent,
        language: language,
      ),
      local: () async {
        final log = await reader.loadLog(
          conversationId: conversationId,
          afterMessageId: afterMessageId,
          useStoredMarker: useStoredMarker,
          recent: recent,
        );
        if (log == null) {
          throw const AiRejectedException();
        }
        if (log.lines.isEmpty) {
          return null;
        }
        final text = await _summarizeLines(log.lines, language, recent: recent);
        return AiSummary(
          text: text,
          messageCount: log.total,
          summarizedCount: log.lines.length,
          firstMessageId: log.firstMessageId,
        );
      },
    );
  }

  /// A summary of [lines], in several requests when they don't fit the
  /// model's window: each part is summarized, then the summaries are merged.
  Future<String> _summarizeLines(
    List<String> lines,
    AiLanguage language, {
    required bool recent,
  }) async {
    var groups = groupLines(lines);
    if (groups.length == 1) {
      return backend.summarize(
        lines: groups.single,
        language: language,
        recent: recent,
      );
    }
    var partials = <String>[];
    for (final group in groups) {
      partials.add(
        await backend.summarize(
          lines: group,
          language: language,
          recent: recent,
        ),
      );
    }
    // Merge until the summaries fit one request.
    while (true) {
      final bullets = [
        for (final part in partials) ...summaryBullets(part).map((b) => '- $b'),
      ];
      groups = groupLines(bullets);
      if (groups.length == 1) {
        return backend.summarize(
          lines: groups.single,
          language: language,
          recent: recent,
          merge: true,
        );
      }
      final next = <String>[];
      for (final group in groups) {
        next.add(
          await backend.summarize(
            lines: group,
            language: language,
            recent: recent,
            merge: true,
          ),
        );
      }
      partials = next;
    }
  }

  @override
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
    AiLanguage? target,
    String? conversationId,
  }) {
    return _route(
      conversationId: conversationId,
      remote: () => _server.rewrite(
        mode: mode,
        text: text,
        target: target,
        conversationId: conversationId,
      ),
      local: () => _pieces(
        text,
        (piece) => mode == AiRewriteMode.translate
            ? backend.translate(
                text: piece,
                target: target ?? AiLanguage.english,
              )
            : backend.rewrite(mode: mode, text: piece),
      ),
    );
  }

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
    String? conversationId,
  }) {
    return _route(
      conversationId: conversationId,
      remote: () => _server.translate(
        text: text,
        target: target,
        conversationId: conversationId,
      ),
      local: () => _pieces(
        text,
        (piece) => backend.translate(text: piece, target: target),
      ),
    );
  }

  /// [text] processed in pieces that fit the model's window, joined again.
  Future<String> _pieces(
    String text,
    Future<String> Function(String piece) process,
  ) async {
    final pieces = splitText(text);
    if (pieces.isEmpty) {
      throw const AiRejectedException();
    }
    final parts = <String>[];
    for (final piece in pieces) {
      parts.add(await process(piece.text));
    }
    return joinPieces(pieces, parts);
  }

  @override
  Future<TranslateBatchResult> translateBatch({
    required String conversationId,
    required List<String> messageIds,
    required AiLanguage target,
    bool manual = false,
  }) {
    return _route(
      conversationId: conversationId,
      remote: () => _serverTranslate.translateBatch(
        conversationId: conversationId,
        messageIds: messageIds,
        target: target,
        manual: manual,
      ),
      local: () => _translateBatchLocally(
        conversationId: conversationId,
        messageIds: messageIds,
        target: target,
        manual: manual,
      ),
    );
  }

  /// The server's translate_batch rules, with the device doing the work (and
  /// no cache, so no row of the server holds any text).
  Future<TranslateBatchResult> _translateBatchLocally({
    required String conversationId,
    required List<String> messageIds,
    required AiLanguage target,
    required bool manual,
  }) async {
    var skipLanguages = const <AiLanguage>{};
    if (!manual) {
      try {
        skipLanguages =
            (await _serverTranslate.loadSettings())?.noTranslate ??
            skipLanguages;
      } on Object {
        // The default rules.
      }
    }
    final loaded = {
      for (final message in await reader.loadMessages(
        conversationId: conversationId,
        ids: messageIds,
      ))
        message.id: message,
    };
    final translations = <String, TranslatedMessage>{};
    final skipped = <String, TranslateSkip>{};
    for (final id in messageIds) {
      final message = loaded[id];
      if (message == null || message.unavailable) {
        skipped[id] = TranslateSkip.unavailable;
      } else if (message.type != 'text') {
        skipped[id] = TranslateSkip.notText;
      } else if (message.body.trim().isEmpty) {
        skipped[id] = TranslateSkip.nothingToTranslate;
      } else if (message.body.length > autoTranslateMaxChars) {
        skipped[id] = TranslateSkip.tooLong;
      } else if (!manual) {
        final guess = roughLanguage(message.body);
        final language = languageOf(guess);
        if (guess == RoughLanguage.none) {
          skipped[id] = TranslateSkip.nothingToTranslate;
        } else if (language == target) {
          skipped[id] = TranslateSkip.sameLanguage;
        } else if (language != null && skipLanguages.contains(language)) {
          skipped[id] = TranslateSkip.skipLanguage;
        }
      }
      if (skipped.containsKey(id)) {
        continue;
      }
      final body = loaded[id]!.body;
      try {
        final text = await _pieces(
          body,
          (piece) => backend.translate(text: piece, target: target),
        );
        translations[id] = TranslatedMessage(text: text);
      } on OnDeviceAiFailedException {
        skipped[id] = TranslateSkip.failed;
      } on OnDeviceAiUnavailableException {
        if (translations.isEmpty) {
          // Nothing was translated yet: the server can take the whole batch.
          rethrow;
        }
        skipped[id] = TranslateSkip.later;
      }
    }
    return TranslateBatchResult(translations: translations, skipped: skipped);
  }

  // The rest is the server's.

  @override
  Future<AiStatus> status() => _server.status();

  @override
  Future<String> transcribe({required String messageId}) =>
      _server.transcribe(messageId: messageId);

  @override
  Future<bool> circleAiEnabled(String circleId) =>
      _server.circleAiEnabled(circleId);

  @override
  Future<void> setCircleAiEnabled(String circleId, {required bool enabled}) =>
      _server.setCircleAiEnabled(circleId, enabled: enabled);

  @override
  Future<AiTranslateSettings?> loadSettings() =>
      _serverTranslate.loadSettings();

  @override
  Future<void> saveSettings(AiTranslateSettings settings) =>
      _serverTranslate.saveSettings(settings);

  @override
  Future<void> syncAiEnabled({required bool enabled}) =>
      _serverTranslate.syncAiEnabled(enabled: enabled);

  @override
  Future<ConversationTranslatePref> loadConversationPref(
    String conversationId,
  ) => _serverTranslate.loadConversationPref(conversationId);

  @override
  Future<void> saveConversationPref(
    String conversationId,
    ConversationTranslatePref pref,
  ) => _serverTranslate.saveConversationPref(conversationId, pref);
}

/// [server] with the on-device model in front of it, where the platform has
/// one (iOS and macOS); [server] itself everywhere else.
AiRepository withOnDeviceAi(Ref ref, SupabaseAiRepository server) {
  final backend = ref.watch(onDeviceAiBackendProvider);
  if (!backend.isSupportedPlatform) {
    return server;
  }
  final client = ref.watch(supabaseClientProvider);
  return OnDeviceFirstAiRepository(
    server: server,
    serverTranslate: server,
    backend: backend,
    reader: SupabaseOnDeviceChatReader(client),
    // Read when asked, not when built: this repository is built before the
    // switches it asks about, and they change while the app runs.
    prefersOnDevice: () => ref.read(preferOnDeviceAiProvider),
    gate: AppOnDeviceAiGate(
      aiEnabled: () => ref.read(aiEnabledProvider),
      lockedChatIds: () => ref.read(lockedConversationIdsProvider),
      conversationAllowed: (id) => supabaseConversationAllowed(client, id),
      threadParent: (id) => supabaseThreadParent(client, id),
    ),
  );
}
