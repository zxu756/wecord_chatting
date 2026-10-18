import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

/// Somebody else in a note, from the presence channel.
@immutable
class NotePeer {
  const NotePeer({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.blockId,
    this.offset,
  });

  factory NotePeer.fromJson(Map<String, dynamic> json) {
    return NotePeer(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      blockId: json['block_id'] as String?,
      offset: (json['offset'] as num?)?.toInt(),
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;

  /// The block they are typing in, and where in it.
  final String? blockId;
  final int? offset;
}

/// Who else has a note open and where their cursor is, over a Realtime
/// presence channel. Closing it leaves the channel.
abstract interface class NotePresence {
  Stream<List<NotePeer>> get peers;

  /// Tells the others where this person is (null block: not typing).
  void update({String? blockId, int? offset});

  Future<void> close();
}

/// A change to a note the others made, from Realtime.
@immutable
class NoteMetaChange {
  const NoteMetaChange({
    required this.title,
    required this.icon,
    required this.managersOnly,
    required this.pinned,
    required this.deleted,
  });

  final String title;
  final String icon;
  final bool managersOnly;
  final bool pinned;
  final bool deleted;
}

abstract interface class NotesRepository implements NoteRemote {
  /// Counts and the pinned note of a conversation.
  Future<ConversationWorkspace> getWorkspace(String conversationId);

  Future<List<NoteSummary>> listNotes(String conversationId);

  Future<NoteMeta> createNote(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
  });

  Future<NoteSnapshot> getNote(String noteId);

  Future<NoteMeta> updateMeta(String noteId, Map<String, Object?> patch);

  /// Deletes the note and its pictures.
  Future<void> deleteNote(String noteId);

  Future<List<NoteVersionSummary>> listVersions(String noteId);

  Future<NoteVersion> getVersion(String versionId);

  Future<void> createVersion(String noteId, {String? label});

  Future<NoteMeta> restoreVersion(String versionId);

  /// Posts the note into [conversationId] as a card; returns the message id.
  Future<String> shareNote(String noteId, String conversationId);

  Future<List<NoteSearchHit>> searchNotes(String query);

  /// Stores a picture for the note and returns its storage path.
  Future<String> uploadImage(
    String noteId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });

  /// A temporary URL for a stored picture.
  Future<String> imageUrl(String path);

  /// Blocks of [noteId] as others change them.
  Stream<NoteBlock> blockChanges(String noteId);

  /// Title, icon, lock and pin changes of [noteId].
  Stream<NoteMetaChange> metaChanges(String noteId);

  /// Changes to the notes of a conversation (a new note, a rename, a pin).
  Stream<void> listChanges(String conversationId);

  NotePresence openPresence(
    String noteId, {
    required String userId,
    required String name,
    String? avatarUrl,
  });
}

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  try {
    return SupabaseNotesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedNotesRepository();
  }
});

String _extension(String fileName, String mimeType) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0 && dot < fileName.length - 1 && fileName.length - dot <= 6) {
    return fileName.substring(dot + 1).toLowerCase();
  }
  return switch (mimeType) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    _ => 'jpg',
  };
}

class SupabaseNotesRepository implements NotesRepository {
  const SupabaseNotesRepository(this._client);

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
  Future<ConversationWorkspace> getWorkspace(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'get_conversation_workspace',
      params: {'p_conversation_id': conversationId},
    );
    return ConversationWorkspace.fromJson(_object(data));
  }

  @override
  Future<List<NoteSummary>> listNotes(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_notes',
      params: {'p_conversation_id': conversationId},
    );
    return [
      for (final row in _rows(data))
        NoteSummary.fromJson(row, conversationId: conversationId),
    ];
  }

  @override
  Future<NoteMeta> createNote(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
  }) async {
    final data = await _client.rpc<Object?>(
      'create_note',
      params: {
        'p_conversation_id': conversationId,
        'p_title': title,
        'p_icon': icon,
        'p_id': id,
      },
    );
    return NoteMeta.fromJson(_object(data));
  }

  @override
  Future<NoteSnapshot> getNote(String noteId) async {
    final data = await _client.rpc<Object?>(
      'get_note',
      params: {'p_note_id': noteId},
    );
    return NoteSnapshot.fromJson(_object(data));
  }

  @override
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  ) async {
    final data = await _client.rpc<Object?>(
      'note_apply_ops',
      params: {'p_note_id': noteId, 'p_ops': ops},
    );
    return [
      if (data is List)
        for (final row in data)
          if (row is Map) NoteOpResult.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<NoteMeta> updateMeta(String noteId, Map<String, Object?> patch) async {
    final data = await _client.rpc<Object?>(
      'update_note_meta',
      params: {'p_note_id': noteId, 'p_patch': patch},
    );
    return NoteMeta.fromJson(_object(data));
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final data = await _client.rpc<Object?>(
      'delete_note',
      params: {'p_note_id': noteId},
    );
    final paths = [
      for (final row in _rows(data))
        if (row['object_path'] is String) row['object_path'] as String,
    ];
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from('note-files').remove(paths);
      } on Object {
        // The note is gone; leftover pictures are only wasted space.
      }
    }
  }

  @override
  Future<List<NoteVersionSummary>> listVersions(String noteId) async {
    final data = await _client.rpc<Object?>(
      'list_note_versions',
      params: {'p_note_id': noteId},
    );
    return [for (final row in _rows(data)) NoteVersionSummary.fromJson(row)];
  }

  @override
  Future<NoteVersion> getVersion(String versionId) async {
    final data = await _client.rpc<Object?>(
      'get_note_version',
      params: {'p_version_id': versionId},
    );
    return NoteVersion.fromJson(_object(data));
  }

  @override
  Future<void> createVersion(String noteId, {String? label}) async {
    await _client.rpc<Object?>(
      'create_note_version',
      params: {'p_note_id': noteId, 'p_label': label},
    );
  }

  @override
  Future<NoteMeta> restoreVersion(String versionId) async {
    final data = await _client.rpc<Object?>(
      'restore_note_version',
      params: {'p_version_id': versionId},
    );
    return NoteMeta.fromJson(_object(data));
  }

  @override
  Future<String> shareNote(String noteId, String conversationId) async {
    final data = await _client.rpc<Object?>(
      'share_note',
      params: {'p_note_id': noteId, 'p_conversation_id': conversationId},
    );
    final messageId = '$data';
    try {
      await _client.functions.invoke('push', body: {'message_id': messageId});
    } on Object {
      // Push is a courtesy; the card is already in the chat.
    }
    return messageId;
  }

  @override
  Future<List<NoteSearchHit>> searchNotes(String query) async {
    final data = await _client.rpc<Object?>(
      'search_notes',
      params: {'p_query': query},
    );
    return [for (final row in _rows(data)) NoteSearchHit.fromJson(row)];
  }

  @override
  Future<String> uploadImage(
    String noteId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '$noteId/$id.${_extension(fileName, mimeType)}';
    await _client.storage
        .from('note-files')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  @override
  Future<String> imageUrl(String path) {
    return _client.storage.from('note-files').createSignedUrl(path, 3600);
  }

  @override
  Stream<NoteBlock> blockChanges(String noteId) {
    late RealtimeChannel channel;
    late StreamController<NoteBlock> controller;
    controller = StreamController<NoteBlock>(
      onListen: () {
        channel = _client
            .channel('note-blocks-$noteId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'note_blocks',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'note_id',
                value: noteId,
              ),
              callback: (payload) {
                final record = payload.newRecord;
                if (record.isEmpty) {
                  return;
                }
                try {
                  controller.add(NoteBlock.fromJson(record));
                } on Object {
                  // A row of a shape we do not know; the next fetch has it.
                }
              },
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
  Stream<NoteMetaChange> metaChanges(String noteId) {
    late RealtimeChannel channel;
    late StreamController<NoteMetaChange> controller;
    controller = StreamController<NoteMetaChange>(
      onListen: () {
        channel = _client
            .channel('note-meta-$noteId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'notes',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: noteId,
              ),
              callback: (payload) {
                final record = payload.newRecord;
                if (record.isEmpty) {
                  return;
                }
                controller.add(
                  NoteMetaChange(
                    title: record['title'] as String? ?? '',
                    icon: record['icon'] as String? ?? NoteMeta.defaultIcon,
                    managersOnly: record['managers_only'] == true,
                    pinned: record['pinned'] == true,
                    deleted: record['deleted_at'] != null,
                  ),
                );
              },
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
  Stream<void> listChanges(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('notes-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
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
  NotePresence openPresence(
    String noteId, {
    required String userId,
    required String name,
    String? avatarUrl,
  }) {
    return _SupabaseNotePresence(
      _client,
      noteId,
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
    );
  }
}

class _SupabaseNotePresence implements NotePresence {
  _SupabaseNotePresence(
    SupabaseClient client,
    String noteId, {
    required this.userId,
    required this.name,
    this.avatarUrl,
  }) : _client = client {
    _channel = client
        .channel(
          notePresenceTopic(noteId),
          opts: privateChannelConfig(presenceKey: userId),
        )
        .onPresenceSync((_) => _emit())
        .onPresenceJoin((_) => _emit())
        .onPresenceLeave((_) => _emit())
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _subscribed = true;
            unawaited(_track());
          }
        });
  }

  final SupabaseClient _client;
  final String userId;
  final String name;
  final String? avatarUrl;
  late final RealtimeChannel _channel;
  final _controller = StreamController<List<NotePeer>>.broadcast();
  var _subscribed = false;
  String? _blockId;
  int? _offset;
  Timer? _debounce;

  @override
  Stream<List<NotePeer>> get peers => _controller.stream;

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    final peers = <NotePeer>[];
    for (final state in _channel.presenceState()) {
      if (state.key == userId) {
        continue;
      }
      for (final presence in state.presences) {
        try {
          peers.add(NotePeer.fromJson(presence.payload));
        } on Object {
          // A malformed presence is ignored.
        }
        break;
      }
    }
    _controller.add(peers);
  }

  Future<void> _track() {
    return _channel.track({
      'user_id': userId,
      'name': name,
      'avatar_url': avatarUrl,
      'block_id': _blockId,
      'offset': _offset,
    });
  }

  @override
  void update({String? blockId, int? offset}) {
    _blockId = blockId;
    _offset = offset;
    if (!_subscribed) {
      return;
    }
    // Cursor moves are sent at most a few times a second.
    _debounce ??= Timer(const Duration(milliseconds: 150), () {
      _debounce = null;
      unawaited(_track());
    });
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _controller.close();
    try {
      await _channel.untrack();
    } on Object {
      // Leaving anyway.
    }
    await _client.removeChannel(_channel);
  }
}

/// Used where Supabase is not set up (tests); every call fails.
class UninitializedNotesRepository implements NotesRepository {
  const UninitializedNotesRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized first.');

  @override
  Future<ConversationWorkspace> getWorkspace(String conversationId) async =>
      _fail();

  @override
  Future<List<NoteSummary>> listNotes(String conversationId) async => _fail();

  @override
  Future<NoteMeta> createNote(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
  }) async => _fail();

  @override
  Future<NoteSnapshot> getNote(String noteId) async => _fail();

  @override
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  ) async => _fail();

  @override
  Future<NoteMeta> updateMeta(
    String noteId,
    Map<String, Object?> patch,
  ) async => _fail();

  @override
  Future<void> deleteNote(String noteId) async => _fail();

  @override
  Future<List<NoteVersionSummary>> listVersions(String noteId) async => _fail();

  @override
  Future<NoteVersion> getVersion(String versionId) async => _fail();

  @override
  Future<void> createVersion(String noteId, {String? label}) async => _fail();

  @override
  Future<NoteMeta> restoreVersion(String versionId) async => _fail();

  @override
  Future<String> shareNote(String noteId, String conversationId) async =>
      _fail();

  @override
  Future<List<NoteSearchHit>> searchNotes(String query) async => const [];

  @override
  Future<String> uploadImage(
    String noteId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => _fail();

  @override
  Future<String> imageUrl(String path) async => _fail();

  @override
  Stream<NoteBlock> blockChanges(String noteId) => const Stream.empty();

  @override
  Stream<NoteMetaChange> metaChanges(String noteId) => const Stream.empty();

  @override
  Stream<void> listChanges(String conversationId) => const Stream.empty();

  @override
  NotePresence openPresence(
    String noteId, {
    required String userId,
    required String name,
    String? avatarUrl,
  }) => const _NoPresence();
}

class _NoPresence implements NotePresence {
  const _NoPresence();

  @override
  Stream<List<NotePeer>> get peers => const Stream.empty();

  @override
  void update({String? blockId, int? offset}) {}

  @override
  Future<void> close() async {}
}
