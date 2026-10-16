import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final messageSearchRepositoryProvider = Provider<MessageSearchRepository>((
  ref,
) {
  try {
    final client = ref.watch(supabaseClientProvider);
    return SupabaseMessageSearchRepository(
      (name, params) => client.rpc<Object?>(name, params: params),
    );
  } on ProviderException {
    return const UninitializedMessageSearchRepository();
  }
});

/// Calls a Postgres function (Supabase `rpc`).
typedef SearchRpc =
    Future<Object?> Function(String name, Map<String, dynamic> params);

/// Message search, its filter suggestions and the context of a result
/// (`search_messages`, `search_filter_suggestions`,
/// `search_message_context`).
abstract interface class MessageSearchRepository {
  Future<SearchPage> search(MessageSearchRequest request);

  /// The visible messages just before and after [messageId].
  Future<SearchContext> context(String messageId, {int before, int after});

  /// People in the conversations of [scope], for `from:` and `mentions:`.
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope,
    int limit,
  });

  /// Conversations of [scope], for `in:`.
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope,
    int limit,
  });
}

class SupabaseMessageSearchRepository implements MessageSearchRepository {
  const SupabaseMessageSearchRepository(this._rpc);

  final SearchRpc _rpc;

  @override
  Future<SearchPage> search(MessageSearchRequest request) async {
    final result = await _rpc('search_messages', request.toParams());
    return SearchPage.fromJson(_map(result));
  }

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async {
    final result = await _rpc('search_message_context', {
      'target_message_id': messageId,
      'before_count': before,
      'after_count': after,
    });
    return SearchContext.fromJson(_map(result));
  }

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    final rows = await _suggest('user', prefix, scope, limit);
    return [for (final row in rows) SearchPerson.fromJson(row)];
  }

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    final rows = await _suggest('conversation', prefix, scope, limit);
    return [for (final row in rows) SearchPlace.fromJson(row)];
  }

  Future<List<Map<String, dynamic>>> _suggest(
    String kind,
    String prefix,
    MessageSearchScope scope,
    int limit,
  ) async {
    final result = await _rpc('search_filter_suggestions', {
      'kind': kind,
      'prefix': prefix,
      'scope': scope.toJson(),
      'max_results': limit,
    });
    return [
      for (final row in result as List<dynamic>? ?? const [])
        (row as Map).cast<String, dynamic>(),
    ];
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw const FormatException('Unexpected search response');
  }
}

class UninitializedMessageSearchRepository implements MessageSearchRepository {
  const UninitializedMessageSearchRepository();

  @override
  Future<SearchPage> search(MessageSearchRequest request) async =>
      const SearchPage(hits: [], total: 0);

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async => const SearchContext();

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async => const [];

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async => const [];
}
