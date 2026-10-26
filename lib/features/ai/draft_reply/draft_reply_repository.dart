import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The longest note about what the person wants to say, as the server limits
/// it.
const draftReplyMaxIntentLength = 300;

/// How many of the chat's latest messages the server reads for the replies.
const draftReplyContextMessages = 20;

/// "Help me reply" (the `ai` function's `draft_reply` action): replies to
/// the end of a chat, which the app only ever puts in the message box.
abstract interface class DraftReplyRepository {
  /// Two or three replies to the latest messages of [conversationId] as the
  /// person sees them, or to what they want to say ([intent], one line).
  /// Empty when there is nothing to reply to yet. Throws an [AiException] when
  /// there is no answer (AI off, the chat locked, the limit reached, ...).
  Future<List<String>> suggest({
    required String conversationId,
    String? intent,
    AiLanguage? language,
  });
}

class SupabaseDraftReplyRepository implements DraftReplyRepository {
  const SupabaseDraftReplyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<String>> suggest({
    required String conversationId,
    String? intent,
    AiLanguage? language,
  }) async {
    final note = intent?.trim() ?? '';
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'draft_reply',
          'conversation_id': conversationId,
          if (note.isNotEmpty) 'intent': note,
          'language': ?language?.code,
        },
      );
      data = response.data;
    } on FunctionException catch (error) {
      throw aiExceptionFor(error.status, error.details);
    } on Object catch (error) {
      if (error is AiException) {
        rethrow;
      }
      throw const AiFailedException();
    }
    if (data is! Map || data['replies'] is! List) {
      throw const AiFailedException();
    }
    return [
      for (final reply in data['replies'] as List)
        if (reply is String && reply.trim().isNotEmpty) reply.trim(),
    ];
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoDraftReplyRepository implements DraftReplyRepository {
  const NoDraftReplyRepository();

  @override
  Future<List<String>> suggest({
    required String conversationId,
    String? intent,
    AiLanguage? language,
  }) => Future.error(const AiNotConfiguredException());
}

final draftReplyRepositoryProvider = Provider<DraftReplyRepository>((ref) {
  try {
    return SupabaseDraftReplyRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoDraftReplyRepository();
  } on Object {
    return const NoDraftReplyRepository();
  }
});
