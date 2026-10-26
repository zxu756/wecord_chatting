// The recorders that use a camera plugin: `camera` on the iPhone and
// `camera_macos` on the Mac. See video_note_camera.dart.
import 'dart:async';

import 'package:camera/camera.dart' as cam;
import 'package:camera_macos/camera_macos.dart' as mac;
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';

/// The iPhone's recorder (the `camera` plugin): the front camera at medium
/// quality (about 480 p, a minute is a few megabytes), portrait.
class PluginVideoNoteCamera implements VideoNoteCamera {
  cam.CameraController? _controller;
  List<cam.CameraDescription> _cameras = const [];
  var _index = 0;
  final _clock = Stopwatch();

  @override
  Future<void> open() async {
    try {
      _cameras = await cam.availableCameras();
    } on cam.CameraException catch (error) {
      throw _problemOf(error);
    }
    if (_cameras.isEmpty) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.missing);
    }
    // Starts on the front camera, the one a person talks into.
    final front = _cameras.indexWhere(
      (camera) => camera.lensDirection == cam.CameraLensDirection.front,
    );
    _index = front < 0 ? 0 : front;
    await _start();
  }

  Future<void> _start() async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    final controller = cam.CameraController(
      _cameras[_index],
      cam.ResolutionPreset.medium,
      enableAudio: true,
    );
    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.prepareForVideoRecording();
    } on cam.CameraException catch (error) {
      await controller.dispose();
      throw _problemOf(error);
    }
    _controller = controller;
  }

  VideoNoteCameraException _problemOf(cam.CameraException error) {
    final code = error.code;
    if (code.contains('AccessDenied') || code.contains('Restricted')) {
      return VideoNoteCameraException(VideoNoteCameraProblem.denied, error);
    }
    if (code.contains('NoCamera') || code.contains('CameraNotFound')) {
      return VideoNoteCameraException(VideoNoteCameraProblem.missing, error);
    }
    return VideoNoteCameraException(VideoNoteCameraProblem.failed, error);
  }

  @override
  double get previewAspect {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return 1;
    }
    final landscape = controller.value.aspectRatio;
    // The picture is locked to portrait: narrower than tall.
    return landscape > 1 ? 1 / landscape : landscape;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return cam.CameraPreview(controller);
  }

  @override
  bool get canSwitch => _cameras.length > 1;

  @override
  Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }
    _index = (_index + 1) % _cameras.length;
    await _start();
  }

  @override
  Future<void> startRecording() async {
    final controller = _controller;
    if (controller == null) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.failed);
    }
    try {
      await controller.startVideoRecording();
    } on cam.CameraException catch (error) {
      throw _problemOf(error);
    }
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<VideoNoteClip?> stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      return null;
    }
    _clock.stop();
    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } on cam.CameraException catch (error) {
      throw _problemOf(error);
    }
    final size = controller.value.previewSize;
    return VideoNoteClip(
      file: file,
      durationMs: _clock.elapsedMilliseconds,
      // The plugin writes H.264 and AAC in a QuickTime/MP4 container, which
      // every player here opens as MP4.
      mimeType: 'video/mp4',
      size: await file.length(),
      width: size?.height.round(),
      height: size?.width.round(),
    );
  }

  @override
  Future<void> cancelRecording() async {
    final controller = _controller;
    if (controller != null && controller.value.isRecordingVideo) {
      try {
        await controller.stopVideoRecording();
      } on Object {
        // The recording is being thrown away.
      }
    }
    _clock.stop();
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// The Mac's recorder (`camera_macos`). The plugin's own view opens the
/// camera once it is on screen, so [open] waits for the page to show
/// [buildPreview].
class MacosVideoNoteCamera implements VideoNoteCamera {
  mac.CameraMacOSController? _controller;
  final _opened = Completer<void>();
  final _key = GlobalKey();
  final _clock = Stopwatch();
  Completer<mac.CameraMacOSFile?>? _autoStopped;
  var _recording = false;

  @override
  Future<void> open() {
    return _opened.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw const VideoNoteCameraException(VideoNoteCameraProblem.denied);
      },
    );
  }

  @override
  double get previewAspect => 4 / 3;

  @override
  Widget buildPreview() {
    return mac.CameraMacOSView(
      key: _key,
      fit: BoxFit.cover,
      cameraMode: mac.CameraMacOSMode.video,
      resolution: mac.PictureResolution.medium,
      audioQuality: mac.AudioQuality.medium,
      audioFormat: mac.AudioFormat.kAudioFormatMPEG4AAC,
      videoFormat: mac.VideoFormat.mp4,
      onCameraLoading: (error) {
        if (error != null && !_opened.isCompleted) {
          _opened.completeError(
            VideoNoteCameraException(VideoNoteCameraProblem.denied, error),
          );
        }
        return const SizedBox.shrink();
      },
      onCameraInizialized: (controller) {
        _controller = controller;
        if (!_opened.isCompleted) {
          _opened.complete();
        }
      },
    );
  }

  @override
  bool get canSwitch => false;

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> startRecording() async {
    final controller = _controller;
    if (controller == null) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.failed);
    }
    _autoStopped = Completer<mac.CameraMacOSFile?>();
    final started = await controller.recordVideo(
      maxVideoDuration: maxVideoNoteSeconds.toDouble(),
      enableAudio: true,
      onVideoRecordingFinished: (file, exception) {
        // The plugin stopped at the longest length by itself.
        if (!(_autoStopped?.isCompleted ?? true)) {
          _autoStopped!.complete(file);
        }
      },
    );
    if (started == false) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.failed);
    }
    _recording = true;
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<VideoNoteClip?> stopRecording() async {
    final controller = _controller;
    if (controller == null || !_recording) {
      return null;
    }
    _recording = false;
    _clock.stop();
    final mac.CameraMacOSFile? recorded;
    if (_autoStopped?.isCompleted ?? false) {
      recorded = await _autoStopped!.future;
    } else {
      recorded = await controller.stopRecording();
    }
    final path = recorded?.url;
    final bytes = recorded?.bytes;
    if (recorded == null || (path == null && bytes == null)) {
      return null;
    }
    final file = path != null
        ? XFile(path, mimeType: 'video/mp4')
        : XFile.fromData(bytes!, mimeType: 'video/mp4');
    return VideoNoteClip(
      file: file,
      durationMs: _clock.elapsedMilliseconds,
      mimeType: 'video/mp4',
      size: bytes?.length ?? await file.length(),
    );
  }

  @override
  Future<void> cancelRecording() async {
    if (_recording) {
      _recording = false;
      try {
        await _controller?.stopRecording();
      } on Object {
        // The recording is being thrown away.
      }
    }
    _clock.stop();
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    try {
      await controller?.destroy();
    } on Object {
      // Already gone.
    }
  }
}
