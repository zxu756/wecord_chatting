import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/space_upload.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final groupSpaceRepositoryProvider = Provider<GroupSpaceRepository>((ref) {
  try {
    return SupabaseGroupSpaceRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(chatMediaUploaderProvider),
    );
  } on ProviderException {
    return const UninitializedGroupSpaceRepository();
  }
});

/// The group space of a chat (roadmap B6): albums for pictures and videos,
/// folders for files. Everything goes through the database functions of
/// migrations 202610280200 to 202610280230; a failure arrives as a
/// [PostgrestException] whose English message `errorText` words.
abstract interface class GroupSpaceRepository {
  Future<GroupSpaceInfo> info(String conversationId);

  // Albums.
  Future<List<SpaceAlbum>> listAlbums(String conversationId);
  Future<SpaceAlbum> createAlbum(String conversationId, String name);
  Future<void> renameAlbum(String albumId, String name);
  Future<void> setAlbumCover(String albumId, String? itemId);

  /// Deletes the album; the files nothing else uses leave Storage.
  Future<void> deleteAlbum(String albumId);
  Future<List<SpaceMedia>> listAlbumItems(String albumId);

  /// Adds the pictures and videos of [messageIds] (all the pictures of a sent
  /// album); view-once, expiring, deleted and forwarded ones are skipped.
  Future<AddResult> addMessagesToAlbum(String albumId, List<String> messageIds);
  Future<SpaceMedia> uploadToAlbum(
    String conversationId,
    String albumId,
    SpaceUpload upload,
  );
  Future<void> removeAlbumItem(String itemId);
  Future<void> setItemAlt(String itemId, String? alt);

  // The pictures of an event of the chat.
  Future<List<SpaceMedia>> listEventPhotos(
    String conversationId,
    String eventId,
  );
  Future<void> deleteEventPhoto(SpaceMedia photo);

  // Folders.
  Future<SpaceFolders> listFolders(String conversationId);
  Future<SpaceFolder> createFolder(String conversationId, String name);
  Future<void> renameFolder(String folderId, String name);
  Future<void> deleteFolder(String folderId);

  /// The files of a folder, or the top level when [folderId] is null.
  Future<List<SpaceFile>> listFiles(String conversationId, String? folderId);
  Future<AddResult> addMessagesToFolder(
    String conversationId,
    String? folderId,
    List<String> messageIds,
  );
  Future<SpaceFile> uploadToFolder(
    String conversationId,
    String? folderId,
    SpaceUpload upload,
  );
  Future<void> moveFile(String fileId, String? folderId);
  Future<void> renameFile(String fileId, String name);
  Future<void> removeFile(String fileId);
}

class SupabaseGroupSpaceRepository implements GroupSpaceRepository {
  const SupabaseGroupSpaceRepository(this._client, this._uploader);

  final SupabaseClient _client;
  final ChatMediaUploader _uploader;

  static final _random = math.Random.secure();

  Future<Map<String, dynamic>> _object(
    String function,
    Map<String, dynamic> params,
  ) async {
    final row = await _client.rpc<dynamic>(function, params: params);
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> _rows(
    String function,
    Map<String, dynamic> params,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(function, params: params);
    return [for (final row in rows) Map<String, dynamic>.from(row as Map)];
  }

  /// Takes the files an RPC says nothing names any more out of Storage. Best
  /// effort: the entry is already gone, and a file left behind harms nobody.
  Future<void> _removeFiles(List<Map<String, dynamic>> rows) async {
    final byBucket = <String, List<String>>{};
    for (final row in rows) {
      final bucket = row['bucket_id'] as String?;
      final path = row['object_path'] as String?;
      if (bucket != null && path != null) {
        byBucket.putIfAbsent(bucket, () => []).add(path);
      }
    }
    for (final entry in byBucket.entries) {
      try {
        await _client.storage.from(entry.key).remove(entry.value);
      } on Object {
        // Left for later.
      }
    }
  }

  @override
  Future<GroupSpaceInfo> info(String conversationId) async {
    return GroupSpaceInfo.fromJson(
      await _object('get_group_space', {'p_conversation_id': conversationId}),
    );
  }

  @override
  Future<List<SpaceAlbum>> listAlbums(String conversationId) async {
    final rows = await _rows('list_group_albums', {
      'p_conversation_id': conversationId,
    });
    return [for (final row in rows) SpaceAlbum.fromJson(row)];
  }

  @override
  Future<SpaceAlbum> createAlbum(String conversationId, String name) async {
    return SpaceAlbum.fromJson(
      await _object('create_group_album', {
        'p_conversation_id': conversationId,
        'p_name': name,
      }),
    );
  }

  @override
  Future<void> renameAlbum(String albumId, String name) async {
    await _client.rpc<dynamic>(
      'rename_group_album',
      params: {'p_album_id': albumId, 'p_name': name},
    );
  }

  @override
  Future<void> setAlbumCover(String albumId, String? itemId) async {
    await _client.rpc<dynamic>(
      'set_group_album_cover',
      params: {'p_album_id': albumId, 'p_item_id': itemId},
    );
  }

  @override
  Future<void> deleteAlbum(String albumId) async {
    await _removeFiles(
      await _rows('delete_group_album', {'p_album_id': albumId}),
    );
  }

  @override
  Future<List<SpaceMedia>> listAlbumItems(String albumId) async {
    final rows = await _rows('list_album_items', {'p_album_id': albumId});
    return [for (final row in rows) SpaceMedia.fromJson(row)];
  }

  @override
  Future<AddResult> addMessagesToAlbum(
    String albumId,
    List<String> messageIds,
  ) async {
    return AddResult.fromJson(
      await _object('add_album_items_from_messages', {
        'p_album_id': albumId,
        'p_message_ids': messageIds,
      }),
    );
  }

  /// Where an upload goes: the chat's own folder, under `space/`, so the
  /// rules that say who may read and write there apply as they are.
  String _newPath(String conversationId, SpaceUpload upload) {
    final seed =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    return '$conversationId/space/$seed${upload.extension}';
  }

  Future<String> _store(
    String conversationId,
    String bucket,
    SpaceUpload upload,
  ) async {
    final path = _newPath(conversationId, upload);
    await _uploader.upload(
      bucket: bucket,
      path: path,
      mimeType: upload.mimeType,
      length: upload.length,
      data: upload.data(),
    );
    return path;
  }

  @override
  Future<SpaceMedia> uploadToAlbum(
    String conversationId,
    String albumId,
    SpaceUpload upload,
  ) async {
    final bucket = upload.isImage ? 'chat-images' : 'chat-files';
    final path = await _store(conversationId, bucket, upload);
    return SpaceMedia.fromJson(
      await _object('add_album_upload', {
        'p_album_id': albumId,
        'p_bucket': bucket,
        'p_path': path,
        'p_name': upload.name,
        'p_mime_type': upload.mimeType,
        'p_size': upload.length,
        'p_width': upload.width,
        'p_height': upload.height,
        'p_alt': upload.alt,
        'p_blurhash': upload.blurhash,
      }),
    );
  }

  @override
  Future<void> removeAlbumItem(String itemId) async {
    await _removeFiles(await _rows('remove_album_item', {'p_item_id': itemId}));
  }

  @override
  Future<void> setItemAlt(String itemId, String? alt) async {
    await _client.rpc<dynamic>(
      'set_album_item_alt',
      params: {'p_item_id': itemId, 'p_alt': alt},
    );
  }

  @override
  Future<List<SpaceMedia>> listEventPhotos(
    String conversationId,
    String eventId,
  ) async {
    final rows = await _rows('list_group_event_album', {
      'p_conversation_id': conversationId,
      'p_event_id': eventId,
    });
    return [for (final row in rows) SpaceMedia.fromJson(row)];
  }

  @override
  Future<void> deleteEventPhoto(SpaceMedia photo) async {
    await _client.rpc<dynamic>(
      'delete_event_photo',
      params: {'p_photo_id': photo.id},
    );
    try {
      await _client.storage.from(photo.bucket).remove([photo.path]);
    } on Object {
      // The picture is off the event; the file may stay.
    }
  }

  @override
  Future<SpaceFolders> listFolders(String conversationId) async {
    return SpaceFolders.fromJson(
      await _object('list_group_folders', {
        'p_conversation_id': conversationId,
      }),
    );
  }

  @override
  Future<SpaceFolder> createFolder(String conversationId, String name) async {
    return SpaceFolder.fromJson(
      await _object('create_group_folder', {
        'p_conversation_id': conversationId,
        'p_name': name,
      }),
    );
  }

  @override
  Future<void> renameFolder(String folderId, String name) async {
    await _client.rpc<dynamic>(
      'rename_group_folder',
      params: {'p_folder_id': folderId, 'p_name': name},
    );
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    await _removeFiles(
      await _rows('delete_group_folder', {'p_folder_id': folderId}),
    );
  }

  @override
  Future<List<SpaceFile>> listFiles(
    String conversationId,
    String? folderId,
  ) async {
    final rows = await _rows('list_folder_files', {
      'p_conversation_id': conversationId,
      'p_folder_id': folderId,
    });
    return [for (final row in rows) SpaceFile.fromJson(row)];
  }

  @override
  Future<AddResult> addMessagesToFolder(
    String conversationId,
    String? folderId,
    List<String> messageIds,
  ) async {
    return AddResult.fromJson(
      await _object('add_folder_files_from_messages', {
        'p_conversation_id': conversationId,
        'p_folder_id': folderId,
        'p_message_ids': messageIds,
      }),
    );
  }

  @override
  Future<SpaceFile> uploadToFolder(
    String conversationId,
    String? folderId,
    SpaceUpload upload,
  ) async {
    final path = await _store(conversationId, 'chat-files', upload);
    return SpaceFile.fromJson(
      await _object('add_folder_upload', {
        'p_conversation_id': conversationId,
        'p_folder_id': folderId,
        'p_bucket': 'chat-files',
        'p_path': path,
        'p_name': upload.name,
        'p_mime_type': upload.mimeType,
        'p_size': upload.length,
      }),
    );
  }

  @override
  Future<void> moveFile(String fileId, String? folderId) async {
    await _client.rpc<dynamic>(
      'move_folder_file',
      params: {'p_file_id': fileId, 'p_folder_id': folderId},
    );
  }

  @override
  Future<void> renameFile(String fileId, String name) async {
    await _client.rpc<dynamic>(
      'rename_folder_file',
      params: {'p_file_id': fileId, 'p_name': name},
    );
  }

  @override
  Future<void> removeFile(String fileId) async {
    await _removeFiles(
      await _rows('remove_folder_file', {'p_file_id': fileId}),
    );
  }
}

/// Where Supabase is not set up (tests that do not look at the space).
class UninitializedGroupSpaceRepository implements GroupSpaceRepository {
  const UninitializedGroupSpaceRepository();

  Future<T> _fail<T>() =>
      Future.error(StateError('The group space needs a signed-in session.'));

  @override
  Future<GroupSpaceInfo> info(String conversationId) async =>
      const GroupSpaceInfo();
  @override
  Future<List<SpaceAlbum>> listAlbums(String conversationId) => _fail();
  @override
  Future<SpaceAlbum> createAlbum(String conversationId, String name) => _fail();
  @override
  Future<void> renameAlbum(String albumId, String name) => _fail();
  @override
  Future<void> setAlbumCover(String albumId, String? itemId) => _fail();
  @override
  Future<void> deleteAlbum(String albumId) => _fail();
  @override
  Future<List<SpaceMedia>> listAlbumItems(String albumId) => _fail();
  @override
  Future<AddResult> addMessagesToAlbum(
    String albumId,
    List<String> messageIds,
  ) => _fail();
  @override
  Future<SpaceMedia> uploadToAlbum(
    String conversationId,
    String albumId,
    SpaceUpload upload,
  ) => _fail();
  @override
  Future<void> removeAlbumItem(String itemId) => _fail();
  @override
  Future<void> setItemAlt(String itemId, String? alt) => _fail();
  @override
  Future<List<SpaceMedia>> listEventPhotos(
    String conversationId,
    String eventId,
  ) => _fail();
  @override
  Future<void> deleteEventPhoto(SpaceMedia photo) => _fail();
  @override
  Future<SpaceFolders> listFolders(String conversationId) => _fail();
  @override
  Future<SpaceFolder> createFolder(String conversationId, String name) =>
      _fail();
  @override
  Future<void> renameFolder(String folderId, String name) => _fail();
  @override
  Future<void> deleteFolder(String folderId) => _fail();
  @override
  Future<List<SpaceFile>> listFiles(String conversationId, String? folderId) =>
      _fail();
  @override
  Future<AddResult> addMessagesToFolder(
    String conversationId,
    String? folderId,
    List<String> messageIds,
  ) => _fail();
  @override
  Future<SpaceFile> uploadToFolder(
    String conversationId,
    String? folderId,
    SpaceUpload upload,
  ) => _fail();
  @override
  Future<void> moveFile(String fileId, String? folderId) => _fail();
  @override
  Future<void> renameFile(String fileId, String name) => _fail();
  @override
  Future<void> removeFile(String fileId) => _fail();
}
