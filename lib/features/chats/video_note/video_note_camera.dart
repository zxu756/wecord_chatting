// The camera behind round video messages (A13).
//
// One interface, three recorders (the roadmap's `camera` plugin does not reach
// every platform):
//  * iPhone: the `camera` plugin (video_note_camera_plugins.dart);
//  * Mac: `camera_macos`, same file;
//  * browsers: the page's own getUserMedia and MediaRecorder
//    (video_note_camera_web.dart), which prefers MP4 so that the iPhone app
//    can play what a browser recorded; browsers that can only record WebM
//    send WebM, which plays everywhere but on iPhones.
// Anything else (no camera, a refused permission, an old browser) is a
// [VideoNoteCameraException] the recording page explains.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/video_note/video_note_camera_plugins.dart';
import 'package:wecord/features/chats/video_note/video_note_camera_web_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/chats/video_note/video_note_camera_web.dart'
    as web_camera;
import 'package:wecord/features/chats/video_note/video_note_models.dart';

/// A camera and microphone that can record one round video message.
abstract interface class VideoNoteCamera {
  /// Opens the front camera and the microphone. Throws
  /// [VideoNoteCameraException].
  Future<void> open();

  /// The live picture, as it is (width over height in [previewAspect]); the
  /// recording page crops it to a circle.
  Widget buildPreview();

  /// Width over height of [buildPreview] (1 until the camera is open).
  double get previewAspect;

  /// There is more than one camera to switch between.
  bool get canSwitch;

  Future<void> switchCamera();

  Future<void> startRecording();

  /// Stops and returns what was recorded, or null when nothing was.
  Future<VideoNoteClip?> stopRecording();

  /// Stops and throws the recording away.
  Future<void> cancelRecording();

  Future<void> dispose();
}

/// Makes the recorder for this device; tests swap in a fake.
typedef VideoNoteCameraFactory = VideoNoteCamera Function();

final videoNoteCameraFactoryProvider = Provider<VideoNoteCameraFactory>((ref) {
  return () {
    if (kIsWeb) {
      return web_camera.createWebVideoNoteCamera() ??
          const UnsupportedVideoNoteCamera();
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => PluginVideoNoteCamera(),
      TargetPlatform.macOS => MacosVideoNoteCamera(),
      _ => const UnsupportedVideoNoteCamera(),
    };
  };
});

/// Whether this device or browser can record a round video message at all.
/// A false answer hides the "+" menu entry; a true one can still end in a
/// refused permission, which the recording page explains.
final videoNoteSupportedProvider = Provider<bool>((ref) {
  if (kIsWeb) {
    return web_camera.browserCanRecordVideoNotes();
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
});

/// Stands in where recording is not possible.
class UnsupportedVideoNoteCamera implements VideoNoteCamera {
  const UnsupportedVideoNoteCamera();

  @override
  Future<void> open() {
    throw const VideoNoteCameraException(VideoNoteCameraProblem.unsupported);
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  double get previewAspect => 1;

  @override
  bool get canSwitch => false;

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<VideoNoteClip?> stopRecording() async => null;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}
}
