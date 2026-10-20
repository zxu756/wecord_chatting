import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';

/// The longest side of a Moment's picture and of its thumbnail.
const momentPhotoEdge = 1920;
const momentThumbEdge = 480;
const momentCoverEdge = 1600;

/// The longest side of a picture put on a comment.
const momentCommentEdge = 960;

/// Scales a picked picture down and compresses it (the chat's photo code:
/// HEIC, PNG and WebP become JPEG, metadata such as the position is gone,
/// the orientation is applied) and makes its thumbnail. Null when the
/// picture cannot be read.
Future<MomentPhotoDraft?> prepareMomentPhoto({
  required String id,
  required Uint8List bytes,
  required String fileName,
}) async {
  final full = await prepareJpegPhoto(
    bytes: bytes,
    fileName: fileName,
    maxEdge: momentPhotoEdge,
    quality: 82,
  );
  if (full == null) {
    return null;
  }
  final thumb = await prepareJpegPhoto(
    bytes: full.bytes,
    fileName: fileName,
    maxEdge: momentThumbEdge,
    quality: 72,
  );
  if (thumb == null) {
    return null;
  }
  return MomentPhotoDraft(
    id: id,
    full: full.bytes,
    thumb: thumb.bytes,
    width: full.width,
    height: full.height,
  );
}

/// Why a video cannot be a Moment's.
enum MomentVideoProblem {
  /// Over a minute.
  tooLong,

  /// Over 50 MB.
  tooBig,

  /// Not an MP4, MOV or WebM.
  unsupported,

  /// The device could not read its length or a frame.
  unreadable,
}

class MomentVideoException implements Exception {
  const MomentVideoException(this.problem);

  final MomentVideoProblem problem;

  @override
  String toString() => 'MomentVideoException($problem)';
}

/// The length of a video file, or null when it cannot be read.
typedef MomentVideoDurationReader = Future<Duration?> Function(XFile file);

/// The length of a video, read with the same player the viewer uses (a
/// blob link on the web, a file elsewhere).
final momentVideoDurationReaderProvider = Provider<MomentVideoDurationReader>((
  ref,
) {
  final factory = ref.watch(videoControllerFactoryProvider);
  return (file) async {
    try {
      final controller = factory(localPath: file.path);
      try {
        await controller.initialize().timeout(const Duration(seconds: 20));
        return controller.value.duration;
      } finally {
        unawaited(controller.dispose());
      }
    } on Object {
      return null;
    }
  };
});

/// Checks a chosen video against the limits (50 MB, a minute, MP4, MOV or
/// WebM) before anything is read in full, with the chat's own file code:
/// type and size from [buildDraft], the poster frame from [videoPoster].
/// Throws [MomentVideoException].
Future<MomentVideoDraft> prepareMomentVideo(
  XFile file, {
  required VideoPosterReader videoPoster,
  required MomentVideoDurationReader videoDuration,
}) async {
  final name = file.name.toLowerCase();
  final extension = name.contains('.') ? name.split('.').last : '';
  if (!const {'mp4', 'm4v', 'mov', 'webm'}.contains(extension)) {
    throw const MomentVideoException(MomentVideoProblem.unsupported);
  }
  final draft = await buildDraft(file, videoPoster: videoPoster);
  if (draft.size > maxMomentVideoBytes) {
    throw const MomentVideoException(MomentVideoProblem.tooBig);
  }
  final duration = await videoDuration(file);
  if (duration == null || duration <= Duration.zero) {
    throw const MomentVideoException(MomentVideoProblem.unreadable);
  }
  if (duration > maxMomentVideoDuration) {
    throw const MomentVideoException(MomentVideoProblem.tooLong);
  }
  final frame = draft.thumbnail;
  if (frame == null) {
    throw const MomentVideoException(MomentVideoProblem.unreadable);
  }
  final poster = await prepareMomentPhoto(
    id: draft.id,
    bytes: frame,
    fileName: 'poster.jpg',
  );
  if (poster == null) {
    throw const MomentVideoException(MomentVideoProblem.unreadable);
  }
  return MomentVideoDraft(
    file: file,
    mimeType: switch (extension) {
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => 'video/mp4',
    },
    size: draft.size,
    duration: duration,
    poster: poster.full,
    posterThumb: poster.thumb,
    width: poster.width,
    height: poster.height,
  );
}

/// Chooses pictures for a Moment and for the cover.
abstract interface class MomentPhotoPicker {
  /// Up to [limit] pictures from the library, prepared; empty when cancelled.
  /// Ones that cannot be read are left out.
  Future<List<MomentPhotoDraft>> pickPhotos({required int limit});

  /// One picture as a JPEG for the cover; null when cancelled.
  Future<Uint8List?> pickCover();

  /// One video from the library, checked and with its poster frame; null
  /// when cancelled. Throws [MomentVideoException].
  Future<MomentVideoDraft?> pickVideo();

  /// One picture from the library for a comment, scaled down; null when
  /// cancelled or when it cannot be read.
  Future<MomentCommentPicture?> pickCommentPhoto();
}

class SystemMomentPhotoPicker implements MomentPhotoPicker {
  SystemMomentPhotoPicker(
    this._picker, {
    required this.videoPoster,
    required this.videoDuration,
  });

  final ImagePicker _picker;
  final VideoPosterReader videoPoster;
  final MomentVideoDurationReader videoDuration;
  var _counter = 0;

  @override
  Future<List<MomentPhotoDraft>> pickPhotos({required int limit}) async {
    final files = await _picker.pickMultiImage(limit: limit < 2 ? null : limit);
    final drafts = <MomentPhotoDraft>[];
    for (final file in files.take(limit)) {
      final draft = await prepareMomentPhoto(
        id: 'pick-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
        bytes: await file.readAsBytes(),
        fileName: file.name,
      );
      if (draft != null) {
        drafts.add(draft);
      }
    }
    return drafts;
  }

  @override
  Future<MomentVideoDraft?> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) {
      return null;
    }
    return prepareMomentVideo(
      file,
      videoPoster: videoPoster,
      videoDuration: videoDuration,
    );
  }

  @override
  Future<MomentCommentPicture?> pickCommentPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return null;
    }
    final prepared = await prepareJpegPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      maxEdge: momentCommentEdge,
      quality: 80,
    );
    if (prepared == null) {
      return null;
    }
    return MomentCommentPicture(
      bytes: prepared.bytes,
      extension: 'jpg',
      width: prepared.width,
      height: prepared.height,
    );
  }

  @override
  Future<Uint8List?> pickCover() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return null;
    }
    final prepared = await prepareJpegPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      maxEdge: momentCoverEdge,
      quality: 80,
    );
    return prepared?.bytes;
  }
}

final momentPhotoPickerProvider = Provider<MomentPhotoPicker>((ref) {
  return SystemMomentPhotoPicker(
    ImagePicker(),
    videoPoster: ref.watch(videoPosterReaderProvider),
    videoDuration: ref.watch(momentVideoDurationReaderProvider),
  );
});

/// How many more pictures a Moment with [count] can take.
int momentPhotoRoom(int count) => maxMomentPhotos - count;
