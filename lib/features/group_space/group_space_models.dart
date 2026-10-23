import 'package:flutter/foundation.dart' show immutable;
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/models/message.dart' show cleanImageAlt;

DateTime? _time(Object? value) {
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

/// What the group space of a chat allows the current person (the server's
/// `get_group_space`).
@immutable
class GroupSpaceInfo {
  const GroupSpaceInfo({
    this.supported = false,
    this.enabled = true,
    this.canAdd = false,
    this.canTidy = false,
    this.isAdmin = false,
    this.albumCount = 0,
    this.folderCount = 0,
  });

  factory GroupSpaceInfo.fromJson(Map<String, dynamic> json) {
    return GroupSpaceInfo(
      supported: json['supported'] == true,
      enabled: json['enabled'] != false,
      canAdd: json['can_add'] == true,
      canTidy: json['can_tidy'] == true,
      isAdmin: json['is_admin'] == true,
      albumCount: _int(json['album_count']),
      folderCount: _int(json['folder_count']),
    );
  }

  /// A group chat (direct chats and channels have no space).
  final bool supported;

  /// Off while disappearing messages are on: nothing can be added then.
  final bool enabled;

  /// May add pictures and files, make albums and folders.
  final bool canAdd;

  /// May rename and remove what is theirs (admins: anything).
  final bool canTidy;
  final bool isAdmin;
  final int albumCount;
  final int folderCount;
}

/// A file in Storage: a bucket and a path.
@immutable
class StoredPath {
  const StoredPath(this.bucket, this.path);

  final String bucket;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is StoredPath && other.bucket == bucket && other.path == path;

  @override
  int get hashCode => Object.hash(bucket, path);
}

enum SpaceAlbumKind { album, event }

/// An album of the group space: one somebody made, or the pictures of one of
/// the chat's events.
@immutable
class SpaceAlbum {
  const SpaceAlbum({
    required this.kind,
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.cover,
    this.creatorName,
    this.canManage = false,
    this.updatedAt,
    this.startsAt,
  });

  factory SpaceAlbum.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'];
    return SpaceAlbum(
      kind: json['kind'] == 'event'
          ? SpaceAlbumKind.event
          : SpaceAlbumKind.album,
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      itemCount: _int(json['item_count']),
      cover: cover is Map
          ? StoredPath(cover['bucket'] as String, cover['path'] as String)
          : null,
      creatorName: json['creator_name'] as String?,
      canManage: json['can_manage'] == true,
      updatedAt: _time(json['updated_at']),
      startsAt: _time(json['starts_at']),
    );
  }

  final SpaceAlbumKind kind;
  final String id;
  final String name;
  final int itemCount;
  final StoredPath? cover;
  final String? creatorName;

  /// The current person may rename and delete it.
  final bool canManage;
  final DateTime? updatedAt;

  /// An event's start.
  final DateTime? startsAt;

  bool get isEvent => kind == SpaceAlbumKind.event;
}

/// A picture or a video in an album.
@immutable
class SpaceMedia {
  const SpaceMedia({
    required this.id,
    required this.bucket,
    required this.path,
    required this.kind,
    required this.name,
    this.mimeType = '',
    this.size = 0,
    this.width,
    this.height,
    this.alt,
    this.blurhash,
    this.adderName,
    this.createdAt,
    this.fromChat = false,
    this.messageId,
    this.mine = false,
    this.canDelete = false,
  });

  factory SpaceMedia.fromJson(Map<String, dynamic> json) {
    return SpaceMedia(
      id: json['id'] as String,
      bucket: json['bucket'] as String,
      path: json['path'] as String,
      kind: json['kind'] as String? ?? 'image',
      name: json['name'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      size: _int(json['size']),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      alt: cleanImageAlt(json['alt']),
      blurhash: json['blurhash'] as String?,
      adderName: json['adder_name'] as String?,
      createdAt: _time(json['created_at']),
      fromChat: json['from_chat'] == true,
      messageId: json['message_id'] as String?,
      mine: json['mine'] == true,
      canDelete: json['can_delete'] == true,
    );
  }

  final String id;
  final String bucket;
  final String path;

  /// `image` or `video`.
  final String kind;
  final String name;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;

  /// What the picture shows, for people who cannot see it.
  final String? alt;
  final String? blurhash;
  final String? adderName;
  final DateTime? createdAt;

  /// It came from a message of the chat (not uploaded to the space).
  final bool fromChat;

  /// The message it came from, while that message exists.
  final String? messageId;
  final bool mine;
  final bool canDelete;

  bool get isVideo => kind == 'video';

  StoredPath get stored => StoredPath(bucket, path);

  /// The viewer's description of the file; pictures of events carry no type,
  /// so one is taken from the name.
  PreviewFile toPreviewFile() {
    final extension = fileExtensionOf(name);
    final guessed = mimeType.isNotEmpty
        ? mimeType
        : (isVideo
              ? 'video/mp4'
              : 'image/${extension == 'jpg' || extension.isEmpty ? 'jpeg' : extension}');
    return PreviewFile(
      bucket: bucket,
      path: path,
      name: name.isEmpty ? path.split('/').last : name,
      mimeType: guessed,
      size: size,
      width: width,
      height: height,
      alt: alt,
      messageId: messageId,
      senderName: adderName,
      sentAt: createdAt,
    );
  }
}

/// A folder of the group's files.
@immutable
class SpaceFolder {
  const SpaceFolder({
    required this.id,
    required this.name,
    this.fileCount = 0,
    this.creatorName,
    this.canManage = false,
    this.createdAt,
  });

  factory SpaceFolder.fromJson(Map<String, dynamic> json) {
    return SpaceFolder(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      fileCount: _int(json['file_count']),
      creatorName: json['creator_name'] as String?,
      canManage: json['can_manage'] == true,
      createdAt: _time(json['created_at']),
    );
  }

  final String id;
  final String name;
  final int fileCount;
  final String? creatorName;
  final bool canManage;
  final DateTime? createdAt;
}

/// The folders of a group, and how many files sit outside any folder.
@immutable
class SpaceFolders {
  const SpaceFolders({this.folders = const [], this.rootCount = 0});

  factory SpaceFolders.fromJson(Map<String, dynamic> json) {
    return SpaceFolders(
      folders: [
        for (final row in (json['folders'] as List<dynamic>? ?? const []))
          SpaceFolder.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      rootCount: _int(json['root_count']),
    );
  }

  final List<SpaceFolder> folders;
  final int rootCount;
}

/// A file in a folder (or at the top of the group's files).
@immutable
class SpaceFile {
  const SpaceFile({
    required this.id,
    required this.bucket,
    required this.path,
    required this.kind,
    required this.name,
    this.folderId,
    this.mimeType = '',
    this.size = 0,
    this.alt,
    this.adderName,
    this.createdAt,
    this.fromChat = false,
    this.messageId,
    this.mine = false,
    this.canDelete = false,
  });

  factory SpaceFile.fromJson(Map<String, dynamic> json) {
    return SpaceFile(
      id: json['id'] as String,
      folderId: json['folder_id'] as String?,
      bucket: json['bucket'] as String,
      path: json['path'] as String,
      kind: json['kind'] as String? ?? 'file',
      name: json['name'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      size: _int(json['size']),
      alt: cleanImageAlt(json['alt']),
      adderName: json['adder_name'] as String?,
      createdAt: _time(json['created_at']),
      fromChat: json['from_chat'] == true,
      messageId: json['message_id'] as String?,
      mine: json['mine'] == true,
      canDelete: json['can_delete'] == true,
    );
  }

  final String id;
  final String? folderId;
  final String bucket;
  final String path;

  /// `image`, `video` or `file`.
  final String kind;
  final String name;
  final String mimeType;
  final int size;
  final String? alt;
  final String? adderName;
  final DateTime? createdAt;
  final bool fromChat;
  final String? messageId;
  final bool mine;
  final bool canDelete;

  StoredPath get stored => StoredPath(bucket, path);

  PreviewFile toPreviewFile() {
    return PreviewFile(
      bucket: bucket,
      path: path,
      name: name.isEmpty ? path.split('/').last : name,
      mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      size: size,
      alt: alt,
      messageId: messageId,
      senderName: adderName,
      sentAt: createdAt,
    );
  }
}

/// How many of the chosen messages went in and how many did not.
@immutable
class AddResult {
  const AddResult({this.added = 0, this.skipped = 0});

  factory AddResult.fromJson(Map<String, dynamic> json) =>
      AddResult(added: _int(json['added']), skipped: _int(json['skipped']));

  final int added;
  final int skipped;
}
