import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Reads and writes the person's quick replies (table `quick_replies`, owner
/// only by row level security) and their away auto-reply (columns of
/// `user_notification_settings`, written through `set_away_reply`).
abstract interface class QuickRepliesRepository {
  /// The phrases in the order they were made.
  Future<List<QuickReply>> load();

  /// Keeps a new phrase; throws [QuickReplyException].
  Future<QuickReply> create({required String shortcut, required String body});

  /// Changes a phrase; throws [QuickReplyException].
  Future<void> update(
    String id, {
    required String shortcut,
    required String body,
  });

  Future<void> delete(String id);

  /// The away auto-reply as set now.
  Future<AwayReply> loadAway();

  /// Sets the away auto-reply; throws [StateError] with a reason the server
  /// gave when it refuses.
  Future<void> saveAway(AwayReply away);
}

class SupabaseQuickRepliesRepository implements QuickRepliesRepository {
  const SupabaseQuickRepliesRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to use quick replies.');
    }
    return id;
  }

  @override
  Future<List<QuickReply>> load() async {
    final rows = await _client.from('quick_replies').select().order(
      'created_at',
    );
    return [
      for (final row in rows)
        QuickReply.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<QuickReply> create({
    required String shortcut,
    required String body,
  }) async {
    final problem = checkQuickReply(shortcut, body);
    if (problem != null) {
      throw QuickReplyException(problem);
    }
    try {
      final row = await _client
          .from('quick_replies')
          .insert({
            'user_id': _userId,
            'shortcut': normalizeQuickReplyShortcut(shortcut),
            'body': body.trim(),
          })
          .select()
          .single();
      return QuickReply.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw _problemOf(error) ?? error;
    }
  }

  @override
  Future<void> update(
    String id, {
    required String shortcut,
    required String body,
  }) async {
    final problem = checkQuickReply(shortcut, body);
    if (problem != null) {
      throw QuickReplyException(problem);
    }
    try {
      await _client
          .from('quick_replies')
          .update({
            'shortcut': normalizeQuickReplyShortcut(shortcut),
            'body': body.trim(),
          })
          .eq('id', id);
    } on PostgrestException catch (error) {
      throw _problemOf(error) ?? error;
    }
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('quick_replies').delete().eq('id', id);
  }

  @override
  Future<AwayReply> loadAway() async {
    final row = await _client
        .from('user_notification_settings')
        .select('away_enabled, away_message, away_until, away_in_quiet_hours')
        .eq('user_id', _userId)
        .maybeSingle();
    return AwayReply.fromJson(row == null ? null : Map.of(row));
  }

  @override
  Future<void> saveAway(AwayReply away) async {
    await _client.rpc<dynamic>(
      'set_away_reply',
      params: {
        'enabled': away.enabled,
        'message': away.message,
        'until_at': away.until?.toUtc().toIso8601String(),
        'during_quiet_hours': away.duringQuietHours,
      },
    );
  }

  QuickReplyException? _problemOf(PostgrestException error) {
    if (error.code == '23505') {
      return const QuickReplyException(QuickReplyProblem.taken);
    }
    if (error.code == '54000') {
      return const QuickReplyException(QuickReplyProblem.limit);
    }
    if (error.code == '23514') {
      return QuickReplyException(
        error.message.contains('body')
            ? QuickReplyProblem.body
            : QuickReplyProblem.shortcut,
      );
    }
    return null;
  }
}

/// Stands in before Supabase is set up (tests): nothing stored.
class UninitializedQuickRepliesRepository implements QuickRepliesRepository {
  const UninitializedQuickRepliesRepository();

  @override
  Future<List<QuickReply>> load() async => const [];

  @override
  Future<QuickReply> create({required String shortcut, required String body}) {
    throw StateError('Supabase must be initialized to keep quick replies.');
  }

  @override
  Future<void> update(
    String id, {
    required String shortcut,
    required String body,
  }) {
    throw StateError('Supabase must be initialized to keep quick replies.');
  }

  @override
  Future<void> delete(String id) {
    throw StateError('Supabase must be initialized to keep quick replies.');
  }

  @override
  Future<AwayReply> loadAway() async => const AwayReply();

  @override
  Future<void> saveAway(AwayReply away) {
    throw StateError('Supabase must be initialized to set the away reply.');
  }
}

final quickRepliesRepositoryProvider = Provider<QuickRepliesRepository>((ref) {
  try {
    return SupabaseQuickRepliesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedQuickRepliesRepository();
  }
});

/// The person's phrases: fetched when something first needs them, again
/// after a change here.
final quickRepliesProvider = FutureProvider.autoDispose<List<QuickReply>>((
  ref,
) {
  return ref.watch(quickRepliesRepositoryProvider).load();
});

/// The person's away auto-reply as stored.
final awayReplyProvider = FutureProvider.autoDispose<AwayReply>((ref) {
  return ref.watch(quickRepliesRepositoryProvider).loadAway();
});
