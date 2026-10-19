import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_models.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';

enum VideoCaptionStatus {
  /// None yet; made when the person turns captions on.
  idle,

  /// Being made: the video is downloaded, then listened to.
  working,
  ready,
  failed,
}

class VideoCaptionsState {
  const VideoCaptionsState({
    this.status = VideoCaptionStatus.idle,
    this.captions,
    this.failure,
    this.progress,
  });

  final VideoCaptionStatus status;
  final VideoCaptions? captions;
  final VideoCaptionFailure? failure;

  /// How much of the video has been downloaded (0 to 1) while it is.
  final double? progress;

  bool get isWorking => status == VideoCaptionStatus.working;
}

/// The captions of one video in the viewer: found among those kept on this
/// device or made on it from the video's sound, and kept for next time.
final videoCaptionsProvider = NotifierProvider.autoDispose
    .family<VideoCaptionsController, VideoCaptionsState, PreviewFile>(
      VideoCaptionsController.new,
    );

class VideoCaptionsController extends Notifier<VideoCaptionsState> {
  VideoCaptionsController(this.file);

  final PreviewFile file;
  final _cancel = FetchCancel();
  var _disposed = false;

  @override
  VideoCaptionsState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _cancel.cancel();
    });
    unawaited(_useKept());
    return const VideoCaptionsState();
  }

  /// Captions already made for this video are there at once.
  Future<void> _useKept() async {
    try {
      final kept = await ref.read(videoCaptionCacheProvider).read(file.key);
      if (kept != null &&
          !_disposed &&
          state.status == VideoCaptionStatus.idle) {
        state = VideoCaptionsState(
          status: VideoCaptionStatus.ready,
          captions: kept,
        );
      }
    } on Object {
      // Nothing kept, or it could not be read: they are made when asked.
    }
  }

  /// Makes the captions (a no-op while being made or once there).
  Future<void> make() async {
    if (state.isWorking || state.status == VideoCaptionStatus.ready) {
      return;
    }
    final maker = ref.read(videoCaptionMakerProvider);
    if (!maker.available) {
      return;
    }
    state = const VideoCaptionsState(status: VideoCaptionStatus.working);
    try {
      final captions = await maker.make(
        file,
        url: () async =>
            await ref.read(filePreviewServiceProvider).fileUrl(file),
        onProgress: (received, total) {
          if (_disposed || total == null || total <= 0) {
            return;
          }
          state = VideoCaptionsState(
            status: VideoCaptionStatus.working,
            progress: (received / total).clamp(0.0, 1.0),
          );
        },
        cancel: _cancel,
      );
      if (_disposed) {
        return;
      }
      state = VideoCaptionsState(
        status: VideoCaptionStatus.ready,
        captions: captions,
      );
      try {
        await ref.read(videoCaptionCacheProvider).write(file.key, captions);
      } on Object {
        // They are shown; they are made again next time.
      }
    } on FetchCancelledException {
      // The viewer closed.
    } on VideoCaptionException catch (error) {
      if (!_disposed) {
        state = VideoCaptionsState(
          status: VideoCaptionStatus.failed,
          failure: error.kind,
        );
      }
    } on Object {
      if (!_disposed) {
        state = const VideoCaptionsState(
          status: VideoCaptionStatus.failed,
          failure: VideoCaptionFailure.failed,
        );
      }
    }
  }

  /// Tries again after a failure.
  Future<void> retry() {
    if (state.status == VideoCaptionStatus.failed) {
      state = const VideoCaptionsState();
    }
    return make();
  }
}
