import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// What the `ai` function's `extract_actions` found in some messages.
class ExtractedActions {
  const ExtractedActions({required this.items, required this.messageCount});

  final List<ExtractedAction> items;

  /// How many of the chosen messages were readable and went to the model.
  final int messageCount;
}

/// The to-dos and events in messages a person chose (F4). Throws an
/// [AiException] when the server cannot answer.
abstract interface class ExtractActionsRepository {
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  });
}

class SupabaseExtractActionsRepository implements ExtractActionsRepository {
  const SupabaseExtractActionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  }) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'extract_actions',
          'conversation_id': conversationId,
          'message_ids': messageIds,
          // Dates are read in the person's own zone. The apps know their
          // offset from UTC; the server prefers a zone name when it has one.
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
    if (data is! Map || data['items'] is! List) {
      throw const AiFailedException();
    }
    return ExtractedActions(
      items: [
        for (final item in data['items'] as List)
          ?ExtractedAction.maybeFromJson(item),
      ],
      messageCount: (data['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoExtractActionsRepository implements ExtractActionsRepository {
  const NoExtractActionsRepository();

  @override
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  }) => Future.error(const AiNotConfiguredException());
}

final extractActionsRepositoryProvider = Provider<ExtractActionsRepository>((
  ref,
) {
  try {
    return SupabaseExtractActionsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoExtractActionsRepository();
  } on Object {
    return const NoExtractActionsRepository();
  }
});
