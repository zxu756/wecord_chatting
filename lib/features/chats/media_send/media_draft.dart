import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/file_picker_service.dart';
import 'package:wecord/features/chats/media_send/album_layout.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';

/// What a chosen file turns into when sent.
enum DraftKind {
  /// A picture the app can decode: scaled and cleaned before upload.
  image,

  /// A video: sent as it is, with a poster frame.
  video,

  /// Anything else: sent as it is.
  file,
}

/// Reads a still frame of a video, or null where that is not possible.
typedef VideoPosterReader = Future<Uint8List?> Function(XFile file);

/// A file waiting in the tray above the composer.
@immutable
class DraftAttachment {
  const DraftAttachment({
    required this.id,
    required this.file,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.kind,
    this.thumbnail,
    this.width,
    this.height,
    this.source,
    this.edits,
  });

  /// Tells drafts apart in the tray (a file may be added twice).
  final String id;
  final XFile file;
  final String name;
  final String mimeType;

  /// The size of the file as chosen (before any compression).
  final int size;
  final DraftKind kind;

  /// A small JPEG or PNG of the picture, or of a video's poster frame.
  final Uint8List? thumbnail;

  /// The picture's size as shown (a video: of its poster frame).
  final int? width;
  final int? height;

  /// The picture as it was chosen, kept while [file] holds its edited copy
  /// (see the photo editor); null for a picture that was not edited.
  final XFile? source;

  /// What was done in the photo editor, to open it again where it was left.
  final EditorDocument? edits;

  bool get isEdited => source != null;

  /// A still picture the photo editor can open (not an animated GIF).
  bool get canEdit =>
      kind == DraftKind.image &&
      thumbnail != null &&
      !overLimit &&
      mimeType != 'image/gif';

  DraftAttachment copyWith({
    String? id,
    XFile? file,
    String? name,
    String? mimeType,
    int? size,
    Uint8List? thumbnail,
    int? width,
    int? height,
    XFile? source,
    EditorDocument? edits,
  }) {
    return DraftAttachment(
      id: id ?? this.id,
      file: file ?? this.file,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      kind: kind,
      thumbnail: thumbnail ?? this.thumbnail,
      width: width ?? this.width,
      height: height ?? this.height,
      source: source ?? this.source,
      edits: edits ?? this.edits,
    );
  }

  /// Bigger than a chat takes. Pictures may still shrink below it when
  /// they are sent, but one this big is not even read.
  bool get overLimit => size > maxChatFileBytes;

  /// Videos are the one thing worth warning about before the limit: the
  /// upload takes a while.
  bool get isLarge => size > 20 * 1024 * 1024;
}

var _draftCounter = 0;

/// Looks at [file]: what it is, how big, and a small picture of it.
///
/// Pictures are read once to measure and shrink them; a file over the
/// 50 MB limit is never read at all. Where a video's poster frame cannot be
/// made, [videoPoster] returns null and the video shows as a plain tile.
Future<DraftAttachment> buildDraft(
  XFile file, {
  VideoPosterReader? videoPoster,
}) async {
  final name = file.name.isNotEmpty ? file.name : 'file';
  final size = await file.length();
  final header = await _header(file);
  final mime = chatFileMimeType(
    name: name,
    reported: file.mimeType,
    headerBytes: header,
  );
  final id = 'draft-${_draftCounter++}';
  var kind = switch (previewKindFor(name: name, mimeType: mime)) {
    PreviewKind.image => DraftKind.image,
    PreviewKind.video => DraftKind.video,
    _ => DraftKind.file,
  };

  Uint8List? thumbnail;
  int? width;
  int? height;
  if (size <= maxChatFileBytes) {
    if (kind == DraftKind.image) {
      final bytes = await file.readAsBytes();
      final shape = await readPhotoSize(bytes);
      if (shape == null) {
        // Something the device cannot decode (a HEIC in a browser...): it
        // is still sent, as a file.
        kind = DraftKind.file;
      } else {
        width = shape.$1;
        height = shape.$2;
        thumbnail = await makeThumbnail(bytes);
      }
    } else if (kind == DraftKind.video && videoPoster != null) {
      try {
        thumbnail = await videoPoster(file);
      } on Object {
        thumbnail = null;
      }
      if (thumbnail != null) {
        final shape = await readPhotoSize(thumbnail);
        width = shape?.$1;
        height = shape?.$2;
      }
    }
  }
  return DraftAttachment(
    id: id,
    file: file,
    name: name,
    mimeType: mime,
    size: size,
    kind: kind,
    thumbnail: thumbnail,
    width: width,
    height: height,
  );
}

Future<List<int>?> _header(XFile file) async {
  try {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, 64)) {
      builder.add(chunk);
      if (builder.length >= 32) {
        break;
      }
    }
    final bytes = builder.takeBytes();
    return bytes.length > 32 ? bytes.sublist(0, 32) : bytes;
  } on Object {
    return null;
  }
}

/// The result of adding files to the tray.
@immutable
class DraftBatch {
  const DraftBatch({required this.drafts, required this.leftOut});

  final List<DraftAttachment> drafts;

  /// How many files did not fit the 10 an album holds.
  final int leftOut;
}

/// Builds drafts for [files], at most [room] of them.
Future<DraftBatch> buildDrafts(
  List<XFile> files, {
  required int room,
  VideoPosterReader? videoPoster,
}) async {
  final take = files.take(room < 0 ? 0 : room).toList();
  final drafts = <DraftAttachment>[];
  for (final file in take) {
    drafts.add(await buildDraft(file, videoPoster: videoPoster));
  }
  return DraftBatch(drafts: drafts, leftOut: files.length - take.length);
}

/// How many attachments the tray holds at most.
const maxTrayItems = maxAlbumItems;
