import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// What the AI made of a link ("Ask AI to check this link").
enum LinkVerdict {
  safe,
  suspicious,
  dangerous,
  unknown;

  static LinkVerdict fromName(Object? name) => values.firstWhere(
    (verdict) => verdict.name == name,
    orElse: () => unknown,
  );
}

@immutable
class LinkCheckResult {
  const LinkCheckResult({required this.verdict, this.reason});

  final LinkVerdict verdict;

  /// One sentence in the language that was asked for.
  final String? reason;
}

/// The `link_check` action of the `ai` function: the address (without its
/// query), the page's title and the app's rule signals go to the model, never
/// the message the link came in.
abstract interface class LinkCheckRepository {
  Future<LinkCheckResult> check({
    required String url,
    required bool chinese,
    String? conversationId,
  });
}

class SupabaseLinkCheckRepository implements LinkCheckRepository {
  const SupabaseLinkCheckRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<LinkCheckResult> check({
    required String url,
    required bool chinese,
    String? conversationId,
  }) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'link_check',
          'url': url,
          'language': chinese ? 'zh' : 'en',
          'conversation_id': ?conversationId,
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
    final reason = data['reason'];
    return LinkCheckResult(
      verdict: LinkVerdict.fromName(data['verdict']),
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
    );
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoLinkCheckRepository implements LinkCheckRepository {
  const NoLinkCheckRepository();

  @override
  Future<LinkCheckResult> check({
    required String url,
    required bool chinese,
    String? conversationId,
  }) => Future.error(const AiNotConfiguredException());
}

final linkCheckRepositoryProvider = Provider<LinkCheckRepository>((ref) {
  try {
    return SupabaseLinkCheckRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoLinkCheckRepository();
  } on Object {
    return const NoLinkCheckRepository();
  }
});
