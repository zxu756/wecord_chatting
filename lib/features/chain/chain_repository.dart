import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_sync.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Group chains (接龙) on the server: the `*_chain*` functions of migration
/// 202610180060.
abstract interface class ChainRepository {
  /// Posts a chain card into [conversationId]; the id of the card message.
  Future<String> create(String conversationId, ChainDraft draft);

  Future<ChainSnapshot> get(String chainId);

  /// Adds the caller's line.
  Future<ChainWriteResult> join(String chainId, String note);

  /// Changes the note of the caller's line.
  Future<ChainWriteResult> updateNote(String chainId, String note);

  /// Removes the caller's line.
  Future<void> leave(String chainId);

  /// Removes a line (the creator and moderators may remove anybody's).
  Future<void> removeEntry(String entryId);

  Future<void> setClosed(String chainId, {required bool closed});

  /// Fires whenever a line or the chain itself changes (Realtime).
  Stream<void> changes(String chainId);
}

class SupabaseChainRepository implements ChainRepository {
  SupabaseChainRepository(this._client) {
    _reads = ChainReadBatcher<ChainSnapshot>(_readMany);
    _hub = ChainChangeHub(_openChannel);
  }

  final SupabaseClient _client;

  /// Chains asked for in the same moment (every card on screen) are read
  /// with one request.
  late final ChainReadBatcher<ChainSnapshot> _reads;

  /// One Realtime channel per conversation for all its chain cards.
  late final ChainChangeHub _hub;

  /// Set once a server turns out not to have `get_chains` yet (older
  /// deployment): chains are then read one by one.
  var _batchMissing = false;

  void dispose() => _hub.dispose();

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw ChainException.fromPostgrest(error);
    }
  }

  Map<String, dynamic> _object(Object? data) {
    return Map<String, dynamic>.from(data! as Map);
  }

  @override
  Future<String> create(String conversationId, ChainDraft draft) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'create_chain',
        params: {
          'target_conversation_id': conversationId,
          'chain_title': draft.title.trim(),
          'chain_description': draft.description.trim().isEmpty
              ? null
              : draft.description.trim(),
          'chain_example': draft.example.trim().isEmpty
              ? null
              : draft.example.trim(),
          'chain_deadline': draft.deadline?.toUtc().toIso8601String(),
          'chain_max_entries': draft.maxEntries,
        },
      );
      final messageId = _object(data)['message_id'] as String;
      try {
        await _client.functions.invoke('push', body: {'message_id': messageId});
      } on Object {
        // Push is a courtesy; the card is already in the chat.
      }
      return messageId;
    });
  }

  @override
  Future<ChainSnapshot> get(String chainId) {
    return _guard(() async {
      try {
        return await _reads.read(chainId);
      } on ChainNotAvailable {
        throw const ChainException(ChainFailureKind.gone);
      }
    });
  }

  Future<Map<String, ChainSnapshot>> _readMany(List<String> chainIds) async {
    if (!_batchMissing) {
      try {
        final data = await _client.rpc<Object?>(
          'get_chains',
          params: {'target_chain_ids': chainIds},
        );
        final snapshots = <String, ChainSnapshot>{
          for (final item in data! as List)
            if (item is Map)
              (item['id'] as String): ChainSnapshot.fromJson(
                Map<String, dynamic>.from(item),
              ),
        };
        snapshots.forEach(
          (id, snapshot) => _hub.learn(id, snapshot.conversationId),
        );
        return snapshots;
      } on PostgrestException catch (error) {
        // PGRST202: the function is not on this server yet.
        if (error.code != 'PGRST202' && error.code != '42883') {
          rethrow;
        }
        _batchMissing = true;
      }
    }
    final snapshots = <String, ChainSnapshot>{};
    for (final id in chainIds) {
      try {
        final data = await _client.rpc<Object?>(
          'get_chain',
          params: {'target_chain_id': id},
        );
        final snapshot = ChainSnapshot.fromJson(_object(data));
        _hub.learn(id, snapshot.conversationId);
        snapshots[id] = snapshot;
      } on PostgrestException catch (error) {
        if (ChainException.fromPostgrest(error).kind != ChainFailureKind.gone) {
          rethrow;
        }
      }
    }
    return snapshots;
  }

  ChainWriteResult _result(Object? data) {
    return ChainWriteResult(noteHeld: data is Map && data['note_held'] == true);
  }

  @override
  Future<ChainWriteResult> join(String chainId, String note) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'join_chain',
        params: {'target_chain_id': chainId, 'entry_note': note.trim()},
      );
      return _result(data);
    });
  }

  @override
  Future<ChainWriteResult> updateNote(String chainId, String note) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'update_chain_entry',
        params: {'target_chain_id': chainId, 'entry_note': note.trim()},
      );
      return _result(data);
    });
  }

  @override
  Future<void> leave(String chainId) {
    return _guard(
      () => _client.rpc<Object?>(
        'leave_chain',
        params: {'target_chain_id': chainId},
      ),
    );
  }

  @override
  Future<void> removeEntry(String entryId) {
    return _guard(
      () => _client.rpc<Object?>(
        'remove_chain_entry',
        params: {'target_entry_id': entryId},
      ),
    );
  }

  @override
  Future<void> setClosed(String chainId, {required bool closed}) {
    return _guard(
      () => _client.rpc<Object?>(
        'set_chain_closed',
        params: {'target_chain_id': chainId, 'closed': closed},
      ),
    );
  }

  @override
  Stream<void> changes(String chainId) => _hub.changes(chainId);

  /// The conversation's channel (`chains:<conversation id>`), with the
  /// changes of its chains.
  FutureOr<void> Function() _openChannel(
    String conversationId,
    void Function(String? chainId) onChange,
  ) {
    final channel = _client
        .channel(ChainChangeHub.topicFor(conversationId))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chains',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            onChange(record['id'] as String?);
          },
        )
        .subscribe();
    return () => _client.removeChannel(channel);
  }
}

class _UninitializedChainRepository implements ChainRepository {
  const _UninitializedChainRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized before using chains.');

  @override
  Future<String> create(String conversationId, ChainDraft draft) => _fail();

  @override
  Future<ChainSnapshot> get(String chainId) => _fail();

  @override
  Future<ChainWriteResult> join(String chainId, String note) => _fail();

  @override
  Future<ChainWriteResult> updateNote(String chainId, String note) => _fail();

  @override
  Future<void> leave(String chainId) => _fail();

  @override
  Future<void> removeEntry(String entryId) => _fail();

  @override
  Future<void> setClosed(String chainId, {required bool closed}) => _fail();

  @override
  Stream<void> changes(String chainId) => const Stream.empty();
}

final chainRepositoryProvider = Provider<ChainRepository>((ref) {
  try {
    final repository = SupabaseChainRepository(
      ref.watch(supabaseClientProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  } on ProviderException {
    return const _UninitializedChainRepository();
  }
});

/// A chain with its lines. Reads again (at most every 300 ms) when anyone
/// changes it, and when its deadline passes, so a card is always live.
final chainProvider = FutureProvider.autoDispose.family<ChainSnapshot, String>((
  ref,
  chainId,
) async {
  final repository = ref.watch(chainRepositoryProvider);
  Timer? pending;
  final subscription = repository.changes(chainId).listen((_) {
    pending ??= Timer(const Duration(milliseconds: 300), () {
      pending = null;
      ref.invalidateSelf();
    });
  }, onError: (Object _) {});
  ref.onDispose(() {
    pending?.cancel();
    unawaited(subscription.cancel());
  });
  final snapshot = await repository.get(chainId);
  final deadline = snapshot.deadline;
  if (deadline != null) {
    final wait = deadline.difference(DateTime.now());
    if (wait > Duration.zero && wait < const Duration(days: 7)) {
      final timer = Timer(
        wait + const Duration(seconds: 1),
        ref.invalidateSelf,
      );
      ref.onDispose(timer.cancel);
    }
  }
  return snapshot;
});
