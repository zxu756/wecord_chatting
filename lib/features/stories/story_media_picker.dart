import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/stories/stories_models.dart';

/// A picture picked for a daily, before it is edited and scaled.
class PickedStoryPhoto {
  const PickedStoryPhoto({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Checks a chosen video against the limits of a daily (15 seconds, 20 MB,
/// MP4, MOV or WebM) before anything is read in full, with the chat's own
/// file code: type and size from [buildDraft], the poster frame from
/// [videoPoster]. Throws [MomentVideoException].
Future<MomentVideoDraft> prepareStoryVideo(
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
  if (draft.size > maxStoryVideoBytes) {
    throw const MomentVideoException(MomentVideoProblem.tooBig);
  }
  final duration = await videoDuration(file);
  if (duration == null || duration <= Duration.zero) {
    throw const MomentVideoException(MomentVideoProblem.unreadable);
  }
  if (duration > maxStoryVideoDuration) {
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

/// Chooses the photo or video of a daily, from the library or the camera.
abstract interface class StoryMediaPicker {
  /// Whether the device has a camera to offer (phones; not desktops or the
  /// browser's file picker).
  bool get hasCamera;

  /// One picture; null when cancelled.
  Future<PickedStoryPhoto?> pickPhoto({required bool camera});

  /// One video, checked and with its poster frame; null when cancelled.
  /// Throws [MomentVideoException].
  Future<MomentVideoDraft?> pickVideo({required bool camera});
}

class SystemStoryMediaPicker implements StoryMediaPicker {
  SystemStoryMediaPicker(
    this._picker, {
    required this.videoPoster,
    required this.videoDuration,
    this.hasCamera = false,
  });

  final ImagePicker _picker;
  final VideoPosterReader videoPoster;
  final MomentVideoDurationReader videoDuration;

  @override
  final bool hasCamera;

  @override
  Future<PickedStoryPhoto?> pickPhoto({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (file == null) {
      return null;
    }
    return PickedStoryPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  @override
  Future<MomentVideoDraft?> pickVideo({required bool camera}) async {
    final file = await _picker.pickVideo(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(seconds: 15),
    );
    if (file == null) {
      return null;
    }
    return prepareStoryVideo(
      file,
      videoPoster: videoPoster,
      videoDuration: videoDuration,
    );
  }
}

final storyMediaPickerProvider = Provider<StoryMediaPicker>((ref) {
  return SystemStoryMediaPicker(
    ImagePicker(),
    videoPoster: ref.watch(videoPosterReaderProvider),
    videoDuration: ref.watch(momentVideoDurationReaderProvider),
    hasCamera: _deviceHasCamera(),
  );
});

bool _deviceHasCamera() {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
