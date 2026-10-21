import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The calls behind a circle's knowledge base. The words of a page are
/// written through the notes' own repository (a page is a note of the
/// circle); this one is about the tree, who may read and edit, and reading.
abstract interface class KnowledgeBaseRepository {
  /// The pages the caller may read, flat.
  Future<List<KbPage>> listPages(String circleId);

  /// Starts a page; [parentId] null makes a top-level one. Safe to send again
  /// with the same [id].
  Future<NoteMeta> createPage(
    String circleId, {
    String? parentId,
    String title = '',
    String? icon,
    String? id,
  });

  /// Puts a page below [parentId] (null: top level), before [beforeId] or
  /// last.
  Future<void> movePage(String pageId, {String? parentId, String? beforeId});

  /// Deletes a page and its pictures; the pages inside move up a level.
  Future<void> deletePage(String pageId);

  Future<KbPageAccess> getAccess(String pageId);

  Future<void> setAccess(
    String pageId, {
    required List<String> viewRoleIds,
    required List<String> editRoleIds,
  });

  /// Records that the caller opened the page (required reading).
  Future<void> markRead(String pageId);

  Future<List<KbSearchHit>> search(String circleId, String query);

  /// Tells when the pages of the circle change (a new page, a move, a
  /// rename, a delete).
  Stream<void> changes(String circleId);
}

final knowledgeBaseRepositoryProvider = Provider<KnowledgeBaseRepository>((
  ref,
) {
  try {
    return SupabaseKnowledgeBaseRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedKnowledgeBaseRepository();
  }
});

class SupabaseKnowledgeBaseRepository implements KnowledgeBaseRepository {
  const SupabaseKnowledgeBaseRepository(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _object(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw StateError('Unexpected response.');
  }

  List<Map<String, dynamic>> _rows(Object? data) {
    return [
      if (data is List)
        for (final row in data)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<List<KbPage>> listPages(String circleId) async {
    final data = await _client.rpc<Object?>(
      'kb_list_pages',
      params: {'p_circle_id': circleId},
    );
    return [for (final row in _rows(data)) KbPage.fromJson(row)];
  }

  @override
  Future<NoteMeta> createPage(
    String circleId, {
    String? parentId,
    String title = '',
    String? icon,
    String? id,
  }) async {
    final data = await _client.rpc<Object?>(
      'kb_create_page',
      params: {
        'p_circle_id': circleId,
        'p_parent_id': parentId,
        'p_title': title,
        'p_icon': icon,
        'p_id': id,
      },
    );
    return NoteMeta.fromJson(_object(data));
  }

  @override
  Future<void> movePage(
    String pageId, {
    String? parentId,
    String? beforeId,
  }) async {
    await _client.rpc<Object?>(
      'kb_move_page',
      params: {
        'p_page_id': pageId,
        'p_parent_id': parentId,
        'p_before_id': beforeId,
      },
    );
  }

  @override
  Future<void> deletePage(String pageId) async {
    final data = await _client.rpc<Object?>(
      'kb_delete_page',
      params: {'p_page_id': pageId},
    );
    final paths = [
      for (final row in _rows(data))
        if (row['object_path'] is String) row['object_path'] as String,
    ];
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from('note-files').remove(paths);
      } on Object {
        // The page is gone; leftover pictures are only wasted space.
      }
    }
  }

  @override
  Future<KbPageAccess> getAccess(String pageId) async {
    final data = await _client.rpc<Object?>(
      'kb_get_page_access',
      params: {'p_page_id': pageId},
    );
    return KbPageAccess.fromJson(_object(data));
  }

  @override
  Future<void> setAccess(
    String pageId, {
    required List<String> viewRoleIds,
    required List<String> editRoleIds,
  }) async {
    await _client.rpc<Object?>(
      'kb_set_page_access',
      params: {
        'p_page_id': pageId,
        'p_view_role_ids': viewRoleIds,
        'p_edit_role_ids': editRoleIds,
      },
    );
  }

  @override
  Future<void> markRead(String pageId) async {
    await _client.rpc<Object?>('kb_mark_read', params: {'p_page_id': pageId});
  }

  @override
  Future<List<KbSearchHit>> search(String circleId, String query) async {
    final data = await _client.rpc<Object?>(
      'kb_search',
      params: {'p_circle_id': circleId, 'p_query': query, 'p_limit': 30},
    );
    return [for (final row in _rows(data)) KbSearchHit.fromJson(row)];
  }

  @override
  Stream<void> changes(String circleId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('knowledge-$circleId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

/// Used where Supabase is not set up (tests); every call fails.
class UninitializedKnowledgeBaseRepository implements KnowledgeBaseRepository {
  const UninitializedKnowledgeBaseRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized first.');

  @override
  Future<List<KbPage>> listPages(String circleId) async => _fail();

  @override
  Future<NoteMeta> createPage(
    String circleId, {
    String? parentId,
    String title = '',
    String? icon,
    String? id,
  }) async => _fail();

  @override
  Future<void> movePage(
    String pageId, {
    String? parentId,
    String? beforeId,
  }) async => _fail();

  @override
  Future<void> deletePage(String pageId) async => _fail();

  @override
  Future<KbPageAccess> getAccess(String pageId) async => _fail();

  @override
  Future<void> setAccess(
    String pageId, {
    required List<String> viewRoleIds,
    required List<String> editRoleIds,
  }) async => _fail();

  @override
  Future<void> markRead(String pageId) async => _fail();

  @override
  Future<List<KbSearchHit>> search(String circleId, String query) async =>
      const [];

  @override
  Stream<void> changes(String circleId) => const Stream.empty();
}

/// The pages of a circle's knowledge base, refreshed when they change. Null
/// until the first answer.
final kbPagesProvider = FutureProvider.autoDispose.family<List<KbPage>, String>(
  (ref, circleId) async {
    final repository = ref.watch(knowledgeBaseRepositoryProvider);
    Timer? debounce;
    final subscription = repository.changes(circleId).listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), () {
        ref.invalidateSelf();
      });
    });
    ref.onDispose(() {
      debounce?.cancel();
      unawaited(subscription.cancel());
    });
    return repository.listPages(circleId);
  },
);

/// The same pages as a tree.
final kbTreeProvider = Provider.autoDispose.family<AsyncValue<KbTree>, String>((
  ref,
  circleId,
) {
  return ref.watch(kbPagesProvider(circleId)).whenData(KbTree.new);
});
