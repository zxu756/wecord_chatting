import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show immutable;
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatFileTooLargeException, maxChatFileBytes;
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/file_preview/preview_file.dart';

/// Something to put in the group space, ready to upload.
@immutable
class SpaceUpload {
  const SpaceUpload({
    required this.name,
    required this.mimeType,
    required this.length,
    required this.data,
    required this.kind,
    this.width,
    this.height,
    this.blurhash,
    this.alt,
  });

  final String name;
  final String mimeType;
  final int length;

  /// The bytes, read when the upload starts (called once per attempt).
  final Stream<List<int>> Function() data;
  final DraftKind kind;
  final int? width;
  final int? height;
  final String? blurhash;
  final String? alt;

  /// A picture the picture bucket takes (scaled and cleaned like a chat's).
  bool get isImage => kind == DraftKind.image;
  bool get isVideo => kind == DraftKind.video;

  /// The dot and extension the stored file gets, from its name.
  String get extension {
    final ext = fileExtensionOf(name);
    if (ext.isEmpty ||
        ext.length > 10 ||
        !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
      return '';
    }
    return '.$ext';
  }

  SpaceUpload withAlt(String? value) => SpaceUpload(
    name: name,
    mimeType: mimeType,
    length: length,
    data: data,
    kind: kind,
    width: width,
    height: height,
    blurhash: blurhash,
    alt: value,
  );
}

/// A file or picture that is not something an album takes.
class NotAlbumMediaException implements Exception {
  const NotAlbumMediaException(this.name);

  final String name;

  @override
  String toString() => 'NotAlbumMediaException($name)';
}

/// Looks at [file] and gets it ready for the group space.
///
/// A picture is scaled and cleaned of its metadata the way a picture sent in a
/// chat is (so it lands in the picture bucket, which takes only pictures); a
/// video and any other file go up as they are (with [asIs], pictures too: the
/// files of a folder are kept as they were). With [mediaOnly] (albums) a
/// document is refused with [NotAlbumMediaException]; a file over the 50 MB
/// limit is refused with [ChatFileTooLargeException] before it is read.
Future<SpaceUpload> prepareSpaceUpload(
  XFile file, {
  bool mediaOnly = false,
  bool asIs = false,
  String? alt,
}) async {
  final draft = await buildDraft(file);
  if (draft.size > maxChatFileBytes) {
    throw const ChatFileTooLargeException();
  }
  if (mediaOnly && draft.kind == DraftKind.file) {
    throw NotAlbumMediaException(draft.name);
  }
  if (draft.kind == DraftKind.image && !asIs) {
    final prepared = await preparePhoto(
      bytes: await file.readAsBytes(),
      fileName: draft.name,
      mimeType: draft.mimeType,
      original: false,
    );
    final Uint8List bytes = prepared.bytes;
    return SpaceUpload(
      name: prepared.fileName,
      mimeType: prepared.mimeType,
      length: bytes.length,
      data: () => Stream.value(bytes),
      kind: DraftKind.image,
      width: prepared.width > 0 ? prepared.width : draft.width,
      height: prepared.height > 0 ? prepared.height : draft.height,
      blurhash: prepared.blurhash,
      alt: alt,
    );
  }
  return SpaceUpload(
    name: draft.name,
    mimeType: draft.mimeType,
    length: draft.size,
    data: file.openRead,
    kind: draft.kind,
    width: draft.width,
    height: draft.height,
  );
}
