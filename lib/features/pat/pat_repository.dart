import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Why a pat or an undo did not happen.
enum PatFailure {
  /// The same person was patted less than 10 seconds ago.
  tooFast,

  /// Too many pats this hour.
  tooMany,

  /// Not allowed here: a blocked person, someone who left, a circle channel.
  notAllowed,

  /// More than 2 minutes have passed.
  undoExpired,

  /// Anything else (no connection, ...).
  other,
}

class PatException implements Exception {
  const PatException(this.failure);

  final PatFailure failure;

  @override
  String toString() => 'PatException($failure)';
}

/// The server side of pat-pat (migration 202610180032).
abstract interface class PatRepository {
  /// Pats [userId] in [conversationId]; the line arrives as a message.
  /// Throws [PatException].
  Future<String> pat({required String conversationId, required String userId});

  /// Takes the pat line [messageId] back. Throws [PatException].
  Future<void> undo(String messageId);

  /// The current user's suffix ('' when none).
  Future<String> suffix();

  /// Saves the suffix (the server trims it) and returns what it saved.
  Future<String> setSuffix(String value);
}

final patRepositoryProvider = Provider<PatRepository>((ref) {
  try {
    return SupabasePatRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedPatRepository();
  }
});

class SupabasePatRepository implements PatRepository {
  const SupabasePatRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> pat({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final data = await _client.rpc(
        'pat_user',
        params: {
          'target_conversation_id': conversationId,
          'target_user_id': userId,
        },
      );
      return (data as Map)['message_id'] as String;
    } on PostgrestException catch (error) {
      throw PatException(patFailureFrom(error));
    }
  }

  @override
  Future<void> undo(String messageId) async {
    try {
      await _client.rpc('undo_pat', params: {'target_message_id': messageId});
    } on PostgrestException catch (error) {
      throw PatException(patFailureFrom(error));
    }
  }

  @override
  Future<String> suffix() async {
    return await _client.rpc('get_my_pat_suffix') as String? ?? '';
  }

  @override
  Future<String> setSuffix(String value) async {
    return await _client.rpc('set_my_pat_suffix', params: {'new_suffix': value})
            as String? ??
        '';
  }
}

class _UninitializedPatRepository implements PatRepository {
  const _UninitializedPatRepository();

  Never _fail() => throw StateError('Supabase is not initialized.');

  @override
  Future<String> pat({
    required String conversationId,
    required String userId,
  }) async => _fail();

  @override
  Future<void> undo(String messageId) async => _fail();

  @override
  Future<String> suffix() async => '';

  @override
  Future<String> setSuffix(String value) async => _fail();
}

/// The current user's pat suffix. Read again after it was changed.
final patSuffixProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(patRepositoryProvider).suffix();
});

/// What a PostgREST error from pat_user / undo_pat means.
PatFailure patFailureFrom(PostgrestException error) {
  final message = error.message;
  return switch (error.code) {
    '53400' when message.contains('pat_too_fast') => PatFailure.tooFast,
    '53400' => PatFailure.tooMany,
    '42501' => PatFailure.notAllowed,
    '22023' when message.contains('pat_undo_expired') => PatFailure.undoExpired,
    '22023' => PatFailure.notAllowed,
    _ => PatFailure.other,
  };
}
