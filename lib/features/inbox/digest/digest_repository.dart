// The daily digest's calls (migration 202610230510) and the providers the
// inbox and the settings page read.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

abstract interface class DigestRepository {
  /// The finished digests of the last week, newest first. Chats the person
  /// has left or may no longer read are already out of them.
  Future<List<AiDigest>> list();

  Future<void> markRead(List<String> ids);

  Future<DigestSettings> settings();

  /// Saves what is given; the rest stays. [minute] goes with [hour].
  Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? language,
  });

  /// Follows or unfollows a chat. Throws [DigestLimitReached] at 10 chats.
  /// Returns how many chats are followed afterwards.
  Future<int> setSubscription(
    String conversationId, {
    required bool subscribed,
    String? language,
  });
}

class SupabaseDigestRepository implements DigestRepository {
  const SupabaseDigestRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AiDigest>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_ai_digests');
    return [
      for (final row in rows)
        AiDigest.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> markRead(List<String> ids) async {
    await _client.rpc<void>('mark_ai_digests_read', params: {'p_ids': ids});
  }

  @override
  Future<DigestSettings> settings() async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'get_ai_digest_settings',
    );
    return DigestSettings.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? language,
  }) async {
    await _client.rpc<void>(
      'set_ai_digest_settings',
      params: {
        'p_enabled': enabled,
        'p_deliver_at': hour == null
            ? null
            : '${hour.toString().padLeft(2, '0')}:'
                  '${(minute ?? 0).toString().padLeft(2, '0')}',
        'p_language': language,
      },
    );
  }

  @override
  Future<int> setSubscription(
    String conversationId, {
    required bool subscribed,
    String? language,
  }) async {
    try {
      final count = await _client.rpc<int>(
        'set_ai_digest_subscription',
        params: {
          'p_conversation_id': conversationId,
          'p_subscribed': subscribed,
          'p_language': language,
        },
      );
      return count;
    } on PostgrestException catch (error) {
      if (error.code == '54000' || (error.message.contains('digest_limit'))) {
        throw const DigestLimitReached();
      }
      rethrow;
    }
  }
}

class _UninitializedDigestRepository implements DigestRepository {
  const _UninitializedDigestRepository();

  @override
  Future<List<AiDigest>> list() async => const [];

  @override
  Future<void> markRead(List<String> ids) async {}

  @override
  Future<DigestSettings> settings() async => const DigestSettings();

  @override
  Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? language,
  }) async {}

  @override
  Future<int> setSubscription(
    String conversationId, {
    required bool subscribed,
    String? language,
  }) async => subscribed ? 1 : 0;
}

final digestRepositoryProvider = Provider<DigestRepository>((ref) {
  try {
    return SupabaseDigestRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedDigestRepository();
  }
});

/// The digests waiting in Notifications, newest first. Empty when they cannot
/// be loaded: the inbox still shows the rest.
final aiDigestsProvider = FutureProvider.autoDispose<List<AiDigest>>((
  ref,
) async {
  try {
    return await ref.watch(digestRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});

/// How many digests have not been read, for the Notifications badge.
final aiDigestsUnreadProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(aiDigestsProvider)
          .value
          ?.where((digest) => digest.isUnread)
          .length ??
      0;
});

/// The person's digest settings and the chats they follow.
final digestSettingsProvider = FutureProvider.autoDispose<DigestSettings>((
  ref,
) {
  return ref.watch(digestRepositoryProvider).settings();
});
