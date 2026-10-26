import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Group tabs on the server: the `*_conversation_tab*` functions of migration
/// 202610280550.
abstract interface class GroupTabsRepository {
  /// The tabs of a chat; [includeUnavailable] also lists the ones whose
  /// target is gone (the manage sheet removes those).
  Future<GroupTabs> tabs(
    String conversationId, {
    bool includeUnavailable = false,
  });

  /// Adds a tab; its id.
  Future<String> add(
    String conversationId, {
    required String kind,
    String? target,
    String? title,
  });

  Future<void> rename(String tabId, String title);

  Future<void> remove(String tabId);

  /// Puts the tabs in the order of [tabIds].
  Future<void> reorder(String conversationId, List<String> tabIds);

  /// Forms and check-ins of the chat a tab can point at (notes and lists come
  /// from their own providers).
  Future<List<GroupTabCandidate>> candidates(
    String conversationId,
    String kind,
  );
}

class SupabaseGroupTabsRepository implements GroupTabsRepository {
  SupabaseGroupTabsRepository(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw GroupTabException.fromPostgrest(error);
    }
  }

  @override
  Future<GroupTabs> tabs(
    String conversationId, {
    bool includeUnavailable = false,
  }) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'get_conversation_tabs',
        params: {
          'target_conversation_id': conversationId,
          'include_unavailable': includeUnavailable,
        },
      );
      return GroupTabs.fromJson(Map<String, dynamic>.from(data! as Map));
    });
  }

  @override
  Future<String> add(
    String conversationId, {
    required String kind,
    String? target,
    String? title,
  }) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'add_conversation_tab',
        params: {
          'target_conversation_id': conversationId,
          'tab_kind': kind,
          'tab_target': target,
          'tab_title': title,
        },
      );
      return (data! as Map)['id'] as String;
    });
  }

  @override
  Future<void> rename(String tabId, String title) {
    return _guard(
      () => _client.rpc<Object?>(
        'update_conversation_tab',
        params: {'target_tab_id': tabId, 'tab_title': title},
      ),
    );
  }

  @override
  Future<void> remove(String tabId) {
    return _guard(
      () => _client.rpc<Object?>(
        'delete_conversation_tab',
        params: {'target_tab_id': tabId},
      ),
    );
  }

  @override
  Future<void> reorder(String conversationId, List<String> tabIds) {
    return _guard(
      () => _client.rpc<Object?>(
        'reorder_conversation_tabs',
        params: {'target_conversation_id': conversationId, 'tab_ids': tabIds},
      ),
    );
  }

  @override
  Future<List<GroupTabCandidate>> candidates(
    String conversationId,
    String kind,
  ) async {
    // Both tables are read through their row level security: a member sees
    // the forms and check-ins whose cards they can read.
    final table = switch (kind) {
      GroupTabKinds.form => 'forms',
      GroupTabKinds.checkIn => 'check_in_boards',
      _ => null,
    };
    if (table == null) {
      return const [];
    }
    final rows = await _client
        .from(table)
        .select('id, title, closed_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(30);
    return [
      for (final row in rows)
        GroupTabCandidate(
          target: row['id'] as String,
          title: row['title'] as String? ?? '',
          closed: row['closed_at'] != null,
        ),
    ];
  }
}

class _UninitializedGroupTabsRepository implements GroupTabsRepository {
  const _UninitializedGroupTabsRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized before using tabs.');

  // Reading finds no tabs (the chat page asks for them in every group).
  @override
  Future<GroupTabs> tabs(
    String conversationId, {
    bool includeUnavailable = false,
  }) async => const GroupTabs();

  @override
  Future<String> add(
    String conversationId, {
    required String kind,
    String? target,
    String? title,
  }) => _fail();

  @override
  Future<void> rename(String tabId, String title) => _fail();

  @override
  Future<void> remove(String tabId) => _fail();

  @override
  Future<void> reorder(String conversationId, List<String> tabIds) => _fail();

  @override
  Future<List<GroupTabCandidate>> candidates(
    String conversationId,
    String kind,
  ) => _fail();
}

final groupTabsRepositoryProvider = Provider<GroupTabsRepository>((ref) {
  try {
    return SupabaseGroupTabsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedGroupTabsRepository();
  }
});

/// The tabs of a chat. Read when the chat opens and again after a change
/// here; tabs rarely change, so there is no live feed.
final groupTabsProvider = FutureProvider.autoDispose.family<GroupTabs, String>((
  ref,
  conversationId,
) {
  return ref.watch(groupTabsRepositoryProvider).tabs(conversationId);
});

/// Every tab of a chat, the ones with a missing target too (manage sheet).
final groupTabsAllProvider = FutureProvider.autoDispose
    .family<GroupTabs, String>((ref, conversationId) {
      return ref
          .watch(groupTabsRepositoryProvider)
          .tabs(conversationId, includeUnavailable: true);
    });

/// Forms or check-ins a tab can point at: (conversation id, kind).
final groupTabCandidatesProvider = FutureProvider.autoDispose
    .family<List<GroupTabCandidate>, ({String conversationId, String kind})>((
      ref,
      key,
    ) {
      return ref
          .watch(groupTabsRepositoryProvider)
          .candidates(key.conversationId, key.kind);
    });

/// Reads a chat's tabs again (after adding, renaming, removing).
void refreshGroupTabs(WidgetRef ref, String conversationId) {
  ref
    ..invalidate(groupTabsProvider(conversationId))
    ..invalidate(groupTabsAllProvider(conversationId));
}
