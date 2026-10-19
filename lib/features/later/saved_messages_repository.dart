import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/message.dart';

/// The private bucket the pictures of notes go to (migration
/// 202610250420). Each person writes only in their own folder.
const savedNotesBucket = 'saved-notes';

/// Most pictures on one note, entries kept, folders, and tags on one entry:
/// the server's limits (migrations 202610250400 to 202610250410).
const maxSavedNotePictures = 4;
const maxSavedItems = 1000;
const maxSavedFolders = 50;
const maxSavedTags = 10;
const maxSavedTagLength = 24;

/// What a saved entry is.
enum SavedKind {
  message,
  moment,
  circlePost,
  link,
  note,
  text;

  factory SavedKind.fromJson(Object? value) {
    return switch (value) {
      'moment' => moment,
      'circle_post' => circlePost,
      'link' => link,
      'note' => note,
      'text' => text,
      _ => message,
    };
  }

  String get wire => switch (this) {
    circlePost => 'circle_post',
    _ => name,
  };

  /// Written by the person themself: it never goes "no longer visible".
  bool get isOwn => this == link || this == note || this == text;
}

/// A picture of a note: its file in [savedNotesBucket] and its size.
class SavedImage {
  const SavedImage({required this.path, this.width, this.height});

  factory SavedImage.fromJson(Map<String, dynamic> json) {
    return SavedImage(
      path: json['path'] as String,
      width: (json['w'] as num?)?.toInt(),
      height: (json['h'] as num?)?.toInt(),
    );
  }

  final String path;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {'path': path, 'w': ?width, 'h': ?height};
}

/// A folder of the person's favorites.
class SavedFolder {
  const SavedFolder({required this.id, required this.name});

  factory SavedFolder.fromJson(Map<String, dynamic> json) {
    return SavedFolder(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
    );
  }

  final String id;
  final String name;
}

/// A picture chosen for a new note, already scaled to a JPEG.
class SavedNotePicture {
  const SavedNotePicture({required this.bytes, this.width, this.height});

  final Uint8List bytes;
  final int? width;
  final int? height;
}

/// A saved entry: a message, Moment or circle post (only a reference, read
/// live), a link, or the person's own note or text. [available] is false
/// when what it points to was deleted or can no longer be seen: the entry
/// then reads "no longer visible" and can only be filed or removed.
///
/// (The class keeps the name it had when only messages were kept.)
class SavedMessage {
  const SavedMessage({
    required this.id,
    required this.savedAt,
    this.conversationId,
    this.kind = SavedKind.message,
    this.messageId,
    this.circleId,
    this.doneAt,
    this.senderId,
    this.senderName = '',
    this.senderAvatarUrl,
    this.body = '',
    this.type = MessageType.text,
    this.messageCreatedAt,
    this.available = true,
    this.folderId,
    this.tags = const [],
    this.note,
    this.title,
    this.url,
    this.images = const [],
    this.extra = const {},
  });

  factory SavedMessage.fromJson(Map<String, dynamic> json) {
    final kind = SavedKind.fromJson(json['kind']);
    final available = json['available'] as bool? ?? false;
    final webhookName = json['webhook_name'] as String?;
    final live = json['content_body'] ?? json['body'];
    final tags = json['tags'];
    final images = json['images'];
    final extra = json['extra'];
    return SavedMessage(
      id: json['saved_id'] as String,
      kind: kind,
      messageId: (json['target_id'] ?? json['message_id']) as String?,
      conversationId: json['conversation_id'] as String?,
      circleId: json['circle_id'] as String?,
      savedAt: DateTime.parse(json['saved_at'] as String),
      doneAt: json['done_at'] == null
          ? null
          : DateTime.parse(json['done_at'] as String),
      senderId: json['sender_id'] as String?,
      senderName: webhookName ?? json['sender_display_name'] as String? ?? '',
      senderAvatarUrl: webhookName == null
          ? json['sender_avatar_url'] as String?
          : null,
      body: available
          ? (kind.isOwn ? json['body'] : live) as String? ?? ''
          : '',
      type: available && (json['content_type'] ?? json['type']) is String
          ? MessageType.fromJson(
              (json['content_type'] ?? json['type']) as String,
            )
          : MessageType.text,
      messageCreatedAt:
          (json['content_created_at'] ?? json['message_created_at']) == null
          ? null
          : DateTime.parse(
              (json['content_created_at'] ?? json['message_created_at'])
                  as String,
            ),
      available: available,
      folderId: json['folder_id'] as String?,
      tags: tags is List ? [for (final tag in tags) '$tag'] : const [],
      note: json['note'] as String?,
      title: json['title'] as String?,
      url: json['url'] as String?,
      images: images is List
          ? [
              for (final image in images)
                if (image is Map<String, dynamic>) SavedImage.fromJson(image),
            ]
          : const [],
      extra: extra is Map<String, dynamic> ? extra : const {},
    );
  }

  final String id;
  final SavedKind kind;

  /// The message, Moment or post this points to (`target_id`).
  final String? messageId;
  final String? conversationId;
  final String? circleId;
  final DateTime savedAt;
  final DateTime? doneAt;
  final String? senderId;
  final String senderName;
  final String? senderAvatarUrl;

  /// What is shown as the text: the message, Moment or post as it reads now,
  /// or the person's own link text, note or words.
  final String body;
  final MessageType type;
  final DateTime? messageCreatedAt;
  final bool available;
  final String? folderId;
  final List<String> tags;

  /// The person's remark.
  final String? note;
  final String? title;
  final String? url;
  final List<SavedImage> images;

  /// Extras by kind: a Moment's `moment_kind`, `photo_count`, `thumb`; a
  /// post's `circle_name`, `attachment_kind`.
  final Map<String, dynamic> extra;

  bool get isDone => doneAt != null;

  String get targetKey => '${kind.wire}:$messageId';
}

abstract interface class SavedMessagesRepository {
  /// Everything the user saved, newest first (active and done).
  Future<List<SavedMessage>> list();

  Future<void> save(String messageId);

  /// Keeps a Moment or a circle post ([kind] is one of those).
  Future<void> saveItem(SavedKind kind, String targetId);

  /// Keeps a web link; the same address is kept once. Returns the entry.
  Future<String> saveLink({
    required String url,
    String? title,
    String? folderId,
    List<String> tags = const [],
  });

  /// Keeps the person's own note: a title and/or words and/or pictures.
  /// Returns the entry. The pictures are uploaded first, and taken back if
  /// the note is not saved.
  Future<String> createNote({
    String? title,
    String? body,
    List<SavedNotePicture> pictures = const [],
    String? folderId,
    List<String> tags = const [],
  });

  /// Takes a saved entry out of the list, with the files of its pictures.
  Future<void> remove(String id, {List<SavedImage> images = const []});

  /// Marks it done, or active again.
  Future<void> setDone(String id, {required bool done});

  /// Changes an entry. [patch] holds only what changes (`folder_id`, `tags`,
  /// `note`, `title`, `body`, `images`). Pictures taken off a note are
  /// removed from Storage.
  Future<void> update(String id, Map<String, Object?> patch);

  /// The ids of the entries that match every word of [query].
  Future<Set<String>> search(String query);

  Future<List<SavedFolder>> folders();

  Future<String> createFolder(String name);

  Future<void> renameFolder(String id, String name);

  /// Deletes a folder; its entries stay, without one.
  Future<void> deleteFolder(String id);

  /// Renames a tag everywhere (a blank [to] removes it). Returns how many
  /// entries changed.
  Future<int> renameTag(String from, String to);

  /// A link to a picture of a note.
  Future<String> signedUrl(String path);
}

final savedMessagesRepositoryProvider = Provider<SavedMessagesRepository>((
  ref,
) {
  try {
    return SupabaseSavedMessagesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedSavedMessagesRepository();
  }
});

/// The user's saved entries.
final savedMessagesProvider = FutureProvider.autoDispose<List<SavedMessage>>((
  ref,
) {
  return ref.watch(savedMessagesRepositoryProvider).list();
});

/// The user's folders.
final savedFoldersProvider = FutureProvider.autoDispose<List<SavedFolder>>((
  ref,
) {
  return ref.watch(savedMessagesRepositoryProvider).folders();
});

/// The ids of the messages the user saved (done or not), for the message
/// menu's "Saved" state. Empty until loaded.
final savedMessageIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  return {
    for (final saved
        in ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[])
      if (saved.kind == SavedKind.message) ?saved.messageId,
  };
});

/// What the user saved, by `kind:target` (a Moment or a post), for the
/// "Saved" state of their menus. Empty until loaded.
final savedTargetKeysProvider = Provider.autoDispose<Set<String>>((ref) {
  return {
    for (final saved
        in ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[])
      if (saved.messageId != null) saved.targetKey,
  };
});

/// Saved entries still to do.
final activeSavedCountProvider = Provider.autoDispose<int>((ref) {
  return (ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[])
      .where((saved) => !saved.isDone)
      .length;
});

class SupabaseSavedMessagesRepository implements SavedMessagesRepository {
  SupabaseSavedMessagesRepository(this._client, {String Function()? newId})
    : _newId = newId ?? _randomUuid;

  final SupabaseClient _client;
  final String Function() _newId;

  @override
  Future<List<SavedMessage>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_saved_items');
    return [
      for (final row in rows)
        SavedMessage.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> save(String messageId) async {
    await _client.rpc<dynamic>(
      'save_message',
      params: {'p_message_id': messageId},
    );
  }

  @override
  Future<void> saveItem(SavedKind kind, String targetId) async {
    await _client.rpc<dynamic>(
      'save_item',
      params: {'p_kind': kind.wire, 'p_target_id': targetId},
    );
  }

  @override
  Future<String> saveLink({
    required String url,
    String? title,
    String? folderId,
    List<String> tags = const [],
  }) async {
    final id = await _client.rpc<dynamic>(
      'save_link',
      params: {
        'p_url': url,
        'p_title': title,
        'p_folder_id': folderId,
        'p_tags': tags,
      },
    );
    return '$id';
  }

  @override
  Future<String> createNote({
    String? title,
    String? body,
    List<SavedNotePicture> pictures = const [],
    String? folderId,
    List<String> tags = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    final id = _newId();
    final images = <SavedImage>[];
    final uploaded = <String>[];
    try {
      if (pictures.isNotEmpty && userId == null) {
        throw StateError('Sign in first.');
      }
      for (final (index, picture) in pictures.indexed) {
        final path = '$userId/$id-$index.jpg';
        await _client.storage
            .from(savedNotesBucket)
            .uploadBinary(
              path,
              picture.bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        uploaded.add(path);
        images.add(
          SavedImage(path: path, width: picture.width, height: picture.height),
        );
      }
      await _client.rpc<dynamic>(
        'create_saved_note',
        params: {
          'p_id': id,
          'p_title': title,
          'p_body': body,
          'p_images': [for (final image in images) image.toJson()],
          'p_folder_id': folderId,
          'p_tags': tags,
        },
      );
    } catch (_) {
      if (uploaded.isNotEmpty) {
        try {
          await _client.storage.from(savedNotesBucket).remove(uploaded);
        } catch (_) {}
      }
      rethrow;
    }
    return id;
  }

  @override
  Future<void> remove(String id, {List<SavedImage> images = const []}) async {
    await _client.from('saved_items').delete().eq('id', id);
    await _removeFiles([for (final image in images) image.path]);
  }

  Future<void> _removeFiles(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    try {
      await _client.storage.from(savedNotesBucket).remove(paths);
    } catch (_) {
      // The entry is gone; a file that stays is only wasted space.
    }
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    await _client.rpc<dynamic>(
      'set_saved_message_done',
      params: {'p_id': id, 'p_done': done},
    );
  }

  @override
  Future<void> update(String id, Map<String, Object?> patch) async {
    final removed = await _client.rpc<dynamic>(
      'update_saved_item',
      params: {'p_id': id, 'p_patch': patch},
    );
    if (removed is List) {
      await _removeFiles([for (final path in removed) '$path']);
    }
  }

  @override
  Future<Set<String>> search(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_saved_items',
      params: {'p_query': query},
    );
    return {
      for (final row in rows)
        if (row is Map<String, dynamic>) row['saved_id'] as String,
    };
  }

  @override
  Future<List<SavedFolder>> folders() async {
    final rows = await _client
        .from('saved_folders')
        .select('id, name')
        .order('created_at');
    return [for (final row in rows) SavedFolder.fromJson(row)];
  }

  @override
  Future<String> createFolder(String name) async {
    final id = await _client.rpc<dynamic>(
      'create_saved_folder',
      params: {'p_name': name},
    );
    return '$id';
  }

  @override
  Future<void> renameFolder(String id, String name) async {
    await _client.rpc<dynamic>(
      'rename_saved_folder',
      params: {'p_id': id, 'p_name': name},
    );
  }

  @override
  Future<void> deleteFolder(String id) async {
    await _client.from('saved_folders').delete().eq('id', id);
  }

  @override
  Future<int> renameTag(String from, String to) async {
    final changed = await _client.rpc<dynamic>(
      'rename_saved_tag',
      params: {'p_old': from, 'p_new': to},
    );
    return changed is num ? changed.toInt() : 0;
  }

  @override
  Future<String> signedUrl(String path) {
    return _client.storage.from(savedNotesBucket).createSignedUrl(path, 3600);
  }
}

class UninitializedSavedMessagesRepository implements SavedMessagesRepository {
  const UninitializedSavedMessagesRepository();

  static StateError _unavailable() =>
      StateError('Supabase must be initialized to save.');

  @override
  Future<List<SavedMessage>> list() async => const [];

  @override
  Future<void> save(String messageId) => throw _unavailable();

  @override
  Future<void> saveItem(SavedKind kind, String targetId) =>
      throw _unavailable();

  @override
  Future<String> saveLink({
    required String url,
    String? title,
    String? folderId,
    List<String> tags = const [],
  }) => throw _unavailable();

  @override
  Future<String> createNote({
    String? title,
    String? body,
    List<SavedNotePicture> pictures = const [],
    String? folderId,
    List<String> tags = const [],
  }) => throw _unavailable();

  @override
  Future<void> remove(String id, {List<SavedImage> images = const []}) async {}

  @override
  Future<void> setDone(String id, {required bool done}) async {}

  @override
  Future<void> update(String id, Map<String, Object?> patch) async {}

  @override
  Future<Set<String>> search(String query) async => const {};

  @override
  Future<List<SavedFolder>> folders() async => const [];

  @override
  Future<String> createFolder(String name) => throw _unavailable();

  @override
  Future<void> renameFolder(String id, String name) async {}

  @override
  Future<void> deleteFolder(String id) async {}

  @override
  Future<int> renameTag(String from, String to) async => 0;

  @override
  Future<String> signedUrl(String path) => throw _unavailable();
}

/// A random version 4 UUID.
String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
