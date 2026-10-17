import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The `ai` Edge Function: catch-up summaries, rewriting drafts and
/// translating messages through the server's AI provider.
abstract interface class AiRepository {
  /// Whether AI is set up and today's use; throws
  /// [AiNotConfiguredException] when it is not.
  Future<AiStatus> status();

  /// A summary of the messages in [conversationId] after the reader's last
  /// read message ([afterMessageId], which may be null when the reader has
  /// read none; leave [useStoredMarker] true to use the server's marker
  /// instead). With [recent] the latest messages are summarized instead.
  /// Null when there is nothing to summarize.
  Future<AiSummary?> summarize({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
    AiLanguage language = AiLanguage.english,
  });

  /// [text] rewritten as [mode] asks, or translated into [target].
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
    AiLanguage? target,
    String? conversationId,
  });

  /// [text] translated into [target].
  Future<String> translate({
    required String text,
    required AiLanguage target,
    String? conversationId,
  });

  /// The text of voice message [messageId], transcribed by the server's
  /// speech-to-text provider (the web only; the apps transcribe on the
  /// device). The server finds the audio itself, as the caller. Throws
  /// [AiTranscribeNotConfiguredException] when the server has no provider.
  /// An empty string means no speech was found.
  Future<String> transcribe({required String messageId});

  /// Whether the circle allows AI features (on unless a manager turned
  /// them off).
  Future<bool> circleAiEnabled(String circleId);

  /// Turns AI features on or off for a circle; for members who manage it.
  Future<void> setCircleAiEnabled(String circleId, {required bool enabled});
}

class SupabaseAiRepository implements AiRepository {
  const SupabaseAiRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke('ai', body: body);
      data = response.data;
    } on FunctionException catch (error) {
      throw aiExceptionFor(error.status, error.details);
    } on Object catch (error) {
      if (error is AiException) {
        rethrow;
      }
      throw const AiFailedException();
    }
    if (data is! Map) {
      throw const AiFailedException();
    }
    return data.cast<String, dynamic>();
  }

  @override
  Future<AiStatus> status() async {
    final data = await _invoke({'action': 'status'});
    return AiStatus(
      dailyLimit: (data['daily_limit'] as num?)?.toInt() ?? 0,
      used: (data['used'] as num?)?.toInt() ?? 0,
      transcribeConfigured: data['transcribe_configured'] == true,
    );
  }

  @override
  Future<AiSummary?> summarize({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
    AiLanguage language = AiLanguage.english,
  }) async {
    final data = await _invoke({
      'action': 'summarize',
      'conversation_id': conversationId,
      if (!useStoredMarker && !recent) 'after_message_id': afterMessageId,
      'recent': recent,
      'language': language.code,
    });
    final summary = data['summary'];
    if (summary is! String || summary.trim().isEmpty) {
      return null;
    }
    return AiSummary(
      text: summary.trim(),
      messageCount: (data['message_count'] as num?)?.toInt() ?? 0,
      summarizedCount: (data['summarized_count'] as num?)?.toInt() ?? 0,
      firstMessageId: data['first_message_id'] as String?,
    );
  }

  Future<String> _text(Map<String, Object?> body) async {
    final data = await _invoke(body);
    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const AiFailedException();
    }
    return text.trim();
  }

  @override
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
    AiLanguage? target,
    String? conversationId,
  }) {
    return _text({
      'action': 'rewrite',
      'mode': mode.code,
      'text': text,
      if (mode == AiRewriteMode.translate) 'target': (target?.code ?? 'en'),
      'conversation_id': ?conversationId,
    });
  }

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
    String? conversationId,
  }) {
    return _text({
      'action': 'translate',
      'text': text,
      'target': target.code,
      'conversation_id': ?conversationId,
    });
  }

  @override
  Future<String> transcribe({required String messageId}) async {
    final data = await _invoke({
      'action': 'transcribe',
      'message_id': messageId,
    });
    final text = data['text'];
    if (text is! String) {
      throw const AiFailedException();
    }
    return text.trim();
  }

  @override
  Future<bool> circleAiEnabled(String circleId) async {
    final row = await _client
        .from('circles')
        .select('ai_enabled')
        .eq('id', circleId)
        .maybeSingle();
    return row?['ai_enabled'] as bool? ?? true;
  }

  @override
  Future<void> setCircleAiEnabled(
    String circleId, {
    required bool enabled,
  }) async {
    await _client.rpc(
      'set_circle_ai_enabled',
      params: {'target_circle_id': circleId, 'enabled': enabled},
    );
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoAiRepository implements AiRepository {
  const NoAiRepository();

  @override
  Future<AiStatus> status() => Future.error(const AiNotConfiguredException());

  @override
  Future<AiSummary?> summarize({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
    AiLanguage language = AiLanguage.english,
  }) => Future.error(const AiNotConfiguredException());

  @override
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
    AiLanguage? target,
    String? conversationId,
  }) => Future.error(const AiNotConfiguredException());

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
    String? conversationId,
  }) => Future.error(const AiNotConfiguredException());

  @override
  Future<String> transcribe({required String messageId}) =>
      Future.error(const AiNotConfiguredException());

  @override
  Future<bool> circleAiEnabled(String circleId) async => true;

  @override
  Future<void> setCircleAiEnabled(String circleId, {required bool enabled}) =>
      Future.error(const AiNotConfiguredException());
}

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  try {
    return SupabaseAiRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoAiRepository();
  } on Object {
    return const NoAiRepository();
  }
});

/// Today's AI status, or null once the server said AI isn't set up. An
/// error (offline, say) leaves AI hidden until the next refresh.
final aiStatusProvider = FutureProvider<AiStatus?>((ref) async {
  try {
    return await ref.watch(aiRepositoryProvider).status();
  } on AiNotConfiguredException {
    return null;
  }
});

/// Where the per-user AI switch is kept; tests swap in memory.
abstract interface class AiEnabledStore {
  Future<bool?> load();

  Future<void> save(bool enabled);
}

const _aiEnabledKey = 'wecord.ai.enabled';

class SharedPreferencesAiEnabledStore implements AiEnabledStore {
  const SharedPreferencesAiEnabledStore();

  @override
  Future<bool?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_aiEnabledKey);
  }

  @override
  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_aiEnabledKey, enabled);
  }
}

class InMemoryAiEnabledStore implements AiEnabledStore {
  InMemoryAiEnabledStore([this._enabled]);

  bool? _enabled;

  @override
  Future<bool?> load() async => _enabled;

  @override
  Future<void> save(bool enabled) async => _enabled = enabled;
}

final aiEnabledStoreProvider = Provider<AiEnabledStore>(
  (ref) => const SharedPreferencesAiEnabledStore(),
);

/// The user's own switch for AI features (Settings → AI), on by default
/// and kept on this device. AI is only offered when the server has it set
/// up too; see [aiAvailableProvider].
final aiEnabledProvider = NotifierProvider<AiEnabledController, bool>(
  AiEnabledController.new,
);

class AiEnabledController extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(aiEnabledStoreProvider).load().then((enabled) {
      // A choice made while loading wins over the saved one.
      if (enabled != null && !_changed) {
        state = enabled;
      }
    }, onError: (Object _) {});
    return true;
  }

  Future<void> set(bool enabled) async {
    _changed = true;
    state = enabled;
    try {
      await ref.read(aiEnabledStoreProvider).save(enabled);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Whether a circle allows AI features: on unless a manager turned them
/// off. Assumed on until known.
final circleAiEnabledProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, circleId) {
    return ref.watch(aiRepositoryProvider).circleAiEnabled(circleId);
  },
);

/// Whether AI entry points show for a conversation of [circleId] (null
/// outside circles): the server has AI set up, the user has it on, and the
/// circle allows it.
final aiAvailableProvider = Provider.family<bool, String?>((ref, circleId) {
  if (!ref.watch(aiEnabledProvider) ||
      ref.watch(aiStatusProvider).value == null) {
    return false;
  }
  return circleId == null ||
      (ref.watch(circleAiEnabledProvider(circleId)).value ?? true);
});
