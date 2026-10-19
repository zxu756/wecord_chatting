import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// What notes 2.0 adds to [NotesRepository]: comments, personal templates,
/// pages on the web, and the notifications about comments.
abstract interface class Notes2Repository {
  // ------------------------------------------------------------ comments --

  Future<List<NoteComment>> listComments(String noteId);

  /// Whether the person may comment on the note (they can write there; a
  /// note only managers can edit still takes comments).
  Future<bool> canComment(String noteId);

  /// Adds a comment, or a reply under [parentId]. [id] makes it safe to send
  /// again.
  Future<NoteComment> addComment(
    String noteId, {
    required String body,
    String? blockId,
    int? anchorStart,
    int? anchorEnd,
    String? anchorText,
    String? parentId,
    List<String> mentions = const [],
    String? id,
  });

  Future<NoteComment> editComment(String commentId, String body);

  Future<void> deleteComment(String commentId);

  Future<NoteComment> resolveComment(String commentId, {bool resolved = true});

  /// A tick whenever a comment of [noteId] is added, changed or deleted.
  Stream<void> commentChanges(String noteId);

  // ----------------------------------------------------------- templates --

  Future<List<NoteTemplateSummary>> listTemplates();

  Future<NoteTemplate> getTemplate(String templateId);

  Future<NoteTemplateSummary> saveTemplate(String noteId, String name);

  Future<void> deleteTemplate(String templateId);

  /// Starts a note in [conversationId] from [blocks] (a template).
  Future<NoteMeta> createNoteFromBlocks(
    String conversationId, {
    required String title,
    required String icon,
    required List<NoteTemplateBlock> blocks,
    String? id,
  });

  // ---------------------------------------------------------- publishing --

  Future<NotePublication> getPublication(String noteId);

  Future<NotePublication> publish(String noteId, {bool allowIndexing = false});

  Future<void> unpublish(String noteId);

  // ------------------------------------------------------- notifications --

  Future<List<NoteCommentNotification>> listCommentNotifications({
    int limit = 50,
  });

  /// Marks these read (all of them when [ids] is null).
  Future<void> markCommentNotificationsRead([List<String>? ids]);
}

final notes2RepositoryProvider = Provider<Notes2Repository>((ref) {
  try {
    return SupabaseNotes2Repository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedNotes2Repository();
  }
});

class SupabaseNotes2Repository implements Notes2Repository {
  const SupabaseNotes2Repository(this._client);

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
  Future<List<NoteComment>> listComments(String noteId) async {
    final data = await _client.rpc<Object?>(
      'list_note_comments',
      params: {'p_note_id': noteId},
    );
    return [for (final row in _rows(data)) NoteComment.fromJson(row)];
  }

  @override
  Future<bool> canComment(String noteId) async {
    final data = await _client.rpc<Object?>(
      'can_current_user_comment_note',
      params: {'target_note_id': noteId},
    );
    return data == true;
  }

  @override
  Future<NoteComment> addComment(
    String noteId, {
    required String body,
    String? blockId,
    int? anchorStart,
    int? anchorEnd,
    String? anchorText,
    String? parentId,
    List<String> mentions = const [],
    String? id,
  }) async {
    final data = await _client.rpc<Object?>(
      'add_note_comment',
      params: {
        'p_note_id': noteId,
        'p_body': body,
        'p_block_id': blockId,
        'p_anchor_start': anchorStart,
        'p_anchor_end': anchorEnd,
        'p_anchor_text': anchorText,
        'p_parent_id': parentId,
        'p_mentions': mentions,
        'p_id': id,
      },
    );
    return NoteComment.fromJson(_object(data));
  }

  @override
  Future<NoteComment> editComment(String commentId, String body) async {
    final data = await _client.rpc<Object?>(
      'edit_note_comment',
      params: {'p_comment_id': commentId, 'p_body': body},
    );
    return NoteComment.fromJson(_object(data));
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.rpc<Object?>(
      'delete_note_comment',
      params: {'p_comment_id': commentId},
    );
  }

  @override
  Future<NoteComment> resolveComment(
    String commentId, {
    bool resolved = true,
  }) async {
    final data = await _client.rpc<Object?>(
      'resolve_note_comment',
      params: {'p_comment_id': commentId, 'p_resolved': resolved},
    );
    return NoteComment.fromJson(_object(data));
  }

  @override
  Stream<void> commentChanges(String noteId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('note-comments-$noteId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'note_comments',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'note_id',
                value: noteId,
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

  @override
  Future<List<NoteTemplateSummary>> listTemplates() async {
    final data = await _client.rpc<Object?>('list_note_templates');
    return [for (final row in _rows(data)) NoteTemplateSummary.fromJson(row)];
  }

  @override
  Future<NoteTemplate> getTemplate(String templateId) async {
    final data = await _client.rpc<Object?>(
      'get_note_template',
      params: {'p_id': templateId},
    );
    return NoteTemplate.fromJson(_object(data));
  }

  @override
  Future<NoteTemplateSummary> saveTemplate(String noteId, String name) async {
    final data = await _client.rpc<Object?>(
      'save_note_template',
      params: {'p_note_id': noteId, 'p_name': name},
    );
    return NoteTemplateSummary.fromJson(_object(data));
  }

  @override
  Future<void> deleteTemplate(String templateId) async {
    await _client.rpc<Object?>(
      'delete_note_template',
      params: {'p_id': templateId},
    );
  }

  @override
  Future<NoteMeta> createNoteFromBlocks(
    String conversationId, {
    required String title,
    required String icon,
    required List<NoteTemplateBlock> blocks,
    String? id,
  }) async {
    final data = await _client.rpc<Object?>(
      'create_note_from_blocks',
      params: {
        'p_conversation_id': conversationId,
        'p_title': title,
        'p_icon': icon,
        'p_blocks': [for (final block in blocks) block.toJson()],
        'p_id': id,
      },
    );
    return NoteMeta.fromJson(_object(data));
  }

  @override
  Future<NotePublication> getPublication(String noteId) async {
    final data = await _client.rpc<Object?>(
      'get_note_publication',
      params: {'p_note_id': noteId},
    );
    return NotePublication.fromJson(_object(data));
  }

  @override
  Future<NotePublication> publish(
    String noteId, {
    bool allowIndexing = false,
  }) async {
    final data = await _client.rpc<Object?>(
      'publish_note',
      params: {'p_note_id': noteId, 'p_allow_indexing': allowIndexing},
    );
    return NotePublication.fromJson(_object(data));
  }

  @override
  Future<void> unpublish(String noteId) async {
    await _client.rpc<Object?>('unpublish_note', params: {'p_note_id': noteId});
  }

  @override
  Future<List<NoteCommentNotification>> listCommentNotifications({
    int limit = 50,
  }) async {
    final data = await _client.rpc<Object?>(
      'list_note_comment_notifications',
      params: {'p_limit': limit},
    );
    return [
      for (final row in _rows(data)) NoteCommentNotification.fromJson(row),
    ];
  }

  @override
  Future<void> markCommentNotificationsRead([List<String>? ids]) async {
    await _client.rpc<Object?>(
      'mark_note_comment_notifications_read',
      params: {'p_ids': ids},
    );
  }
}

/// Used where Supabase is not set up (tests); every call fails, except the
/// ones that only list.
class UninitializedNotes2Repository implements Notes2Repository {
  const UninitializedNotes2Repository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized first.');

  @override
  Future<List<NoteComment>> listComments(String noteId) async => const [];

  @override
  Future<bool> canComment(String noteId) async => false;

  @override
  Future<NoteComment> addComment(
    String noteId, {
    required String body,
    String? blockId,
    int? anchorStart,
    int? anchorEnd,
    String? anchorText,
    String? parentId,
    List<String> mentions = const [],
    String? id,
  }) async => _fail();

  @override
  Future<NoteComment> editComment(String commentId, String body) async =>
      _fail();

  @override
  Future<void> deleteComment(String commentId) async => _fail();

  @override
  Future<NoteComment> resolveComment(
    String commentId, {
    bool resolved = true,
  }) async => _fail();

  @override
  Stream<void> commentChanges(String noteId) => const Stream.empty();

  @override
  Future<List<NoteTemplateSummary>> listTemplates() async => const [];

  @override
  Future<NoteTemplate> getTemplate(String templateId) async => _fail();

  @override
  Future<NoteTemplateSummary> saveTemplate(String noteId, String name) async =>
      _fail();

  @override
  Future<void> deleteTemplate(String templateId) async => _fail();

  @override
  Future<NoteMeta> createNoteFromBlocks(
    String conversationId, {
    required String title,
    required String icon,
    required List<NoteTemplateBlock> blocks,
    String? id,
  }) async => _fail();

  @override
  Future<NotePublication> getPublication(String noteId) async =>
      const NotePublication();

  @override
  Future<NotePublication> publish(
    String noteId, {
    bool allowIndexing = false,
  }) async => _fail();

  @override
  Future<void> unpublish(String noteId) async => _fail();

  @override
  Future<List<NoteCommentNotification>> listCommentNotifications({
    int limit = 50,
  }) async => const [];

  @override
  Future<void> markCommentNotificationsRead([List<String>? ids]) async {}
}
