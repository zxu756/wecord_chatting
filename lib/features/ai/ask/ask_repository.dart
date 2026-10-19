import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Asks the `ai` function's `ask` action a question about the person's chats
/// (F1). Throws an [AiException] when the server cannot answer.
abstract interface class AskRepository {
  Future<AskAnswer> ask({
    required String question,
    required MessageSearchScope scope,
    AiLanguage? language,
    DateTime? now,
  });
}

class SupabaseAskRepository implements AskRepository {
  const SupabaseAskRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AskAnswer> ask({
    required String question,
    required MessageSearchScope scope,
    AiLanguage? language,
    DateTime? now,
  }) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'ask',
          'question': question,
          'scope': scope.toJson(),
          'language': (language ?? AiLanguage.appLanguage).code,
          // Dates in the answer are read in the person's own zone.
          'utc_offset_minutes':
              (now ?? DateTime.now()).timeZoneOffset.inMinutes,
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
    if (data is! Map) {
      throw const AiFailedException();
    }
    return AskAnswer.fromJson(data);
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoAskRepository implements AskRepository {
  const NoAskRepository();

  @override
  Future<AskAnswer> ask({
    required String question,
    required MessageSearchScope scope,
    AiLanguage? language,
    DateTime? now,
  }) => Future.error(const AiNotConfiguredException());
}

final askRepositoryProvider = Provider<AskRepository>((ref) {
  try {
    return SupabaseAskRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoAskRepository();
  } on Object {
    return const NoAskRepository();
  }
});
