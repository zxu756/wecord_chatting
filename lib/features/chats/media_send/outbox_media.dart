import 'package:flutter/foundation.dart';
import 'package:wecord/shared/models/message.dart';

/// What an attachment in the outbox is.
enum OutboxMediaKind {
  image,
  video,
  file;

  static OutboxMediaKind fromName(String? name) {
    return values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => OutboxMediaKind.file,
    );
  }
}

/// The attachment of an [OutboxEntry]: everything except its bytes, which
/// wait in the [PendingMediaStore] under the entry's client id.
@immutable
class OutboxMedia {
  const OutboxMedia({
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
    this.blurhash,
    this.groupId,
    this.groupIndex = 0,
    this.hasPreview = false,
  });

  factory OutboxMedia.fromJson(Map<String, dynamic> json) {
    return OutboxMedia(
      kind: OutboxMediaKind.fromName(json['kind'] as String?),
      fileName: json['file_name'] as String? ?? 'file',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      blurhash: json['blurhash'] as String?,
      groupId: json['group_id'] as String?,
      groupIndex: (json['group_index'] as num?)?.toInt() ?? 0,
      hasPreview: json['has_preview'] == true,
    );
  }

  final OutboxMediaKind kind;
  final String fileName;
  final String mimeType;

  /// Bytes to upload (after compression).
  final int size;
  final int? width;
  final int? height;
  final String? blurhash;

  /// Shared by the attachments of one album; null for a single one.
  final String? groupId;

  /// The place in its album, from 0.
  final int groupIndex;

  /// A small picture was kept in the store for the bubble.
  final bool hasPreview;

  /// The storage bucket: pictures and everything else live apart.
  String get bucket =>
      kind == OutboxMediaKind.image ? 'chat-images' : 'chat-files';

  MessageType get messageType =>
      kind == OutboxMediaKind.image ? MessageType.image : MessageType.file;

  bool get isVisual => kind != OutboxMediaKind.file;

  /// Only the first message of an album notifies.
  bool get notifies => groupId == null || groupIndex == 0;

  /// The attachment JSON the stored message carries.
  Map<String, dynamic> attachmentJson(String path) {
    return switch (kind) {
      OutboxMediaKind.image => ImageAttachment(
        bucket: bucket,
        path: path,
        mimeType: mimeType,
        size: size,
        width: width,
        height: height,
        blurhash: blurhash,
      ).toJson(),
      _ => FileAttachment(
        bucket: bucket,
        path: path,
        name: fileName,
        mimeType: mimeType,
        size: size,
        width: width,
        height: height,
        blurhash: blurhash,
      ).toJson(),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
      'width': width,
      'height': height,
      'blurhash': blurhash,
      'group_id': groupId,
      'group_index': groupIndex,
      'has_preview': hasPreview,
    };
  }
}

/// Where [clientId]'s attachment is stored: the same path every try, so an
/// upload whose answer was lost is found again (the server says it exists)
/// rather than stored twice.
String mediaStoragePath({
  required String conversationId,
  required String clientId,
  required String fileName,
}) {
  String clean(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-]+|[-]+$'), '');

  final name = fileName.trim().split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  var stem = clean(dot > 0 ? name.substring(0, dot) : name);
  var extension = dot > 0 ? clean(name.substring(dot + 1)) : '';
  if (extension.length > 10) {
    extension = extension.substring(0, 10);
  }
  if (stem.isEmpty) {
    stem = 'file';
  }
  if (stem.length > 60) {
    stem = stem.substring(0, 60);
  }
  final safe = extension.isEmpty ? stem : '$stem.$extension';
  return '$conversationId/$clientId-$safe';
}
