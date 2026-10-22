import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';

/// A camera that shows a coloured box and records whatever the test says.
class FakeVideoNoteCamera implements VideoNoteCamera {
  FakeVideoNoteCamera({
    this.openError,
    this.recordedMs = 12000,
    this.recordedBytes = 2500000,
    this.switchable = true,
  });

  /// What [open] throws, when set.
  final VideoNoteCameraException? openError;

  /// What the next recording lasted and weighed.
  int recordedMs;
  int recordedBytes;
  final bool switchable;

  var opened = false;
  var recording = false;
  var cancelled = false;
  var disposed = false;
  var switches = 0;
  var starts = 0;

  /// Returns nothing from the next [stopRecording] when set.
  bool dropRecording = false;

  @override
  Future<void> open() async {
    final error = openError;
    if (error != null) {
      throw error;
    }
    opened = true;
  }

  @override
  Widget buildPreview() => const ColoredBox(
    key: ValueKey('fake-camera-picture'),
    color: Colors.teal,
  );

  @override
  double get previewAspect => 3 / 4;

  @override
  bool get canSwitch => switchable;

  @override
  Future<void> switchCamera() async {
    switches += 1;
  }

  @override
  Future<void> startRecording() async {
    starts += 1;
    recording = true;
  }

  @override
  Future<VideoNoteClip?> stopRecording() async {
    recording = false;
    if (dropRecording) {
      return null;
    }
    return VideoNoteClip(
      file: XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'video/mp4',
        name: 'video-message.mp4',
      ),
      durationMs: recordedMs,
      mimeType: 'video/mp4',
      size: recordedBytes,
      width: 480,
      height: 640,
    );
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
    cancelled = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A player that plays nothing; the test moves its clock.
class FakeNotePlayer extends VideoPlayerController {
  FakeNotePlayer({this.size = const Size(480, 640)})
    : super.networkUrl(Uri.parse('fake://video-note'));

  final Size size;
  double? lastVolume;
  bool? looping;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 12),
      size: size,
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

  @override
  Future<void> setLooping(bool looping) async {
    this.looping = looping;
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  // The real dispose would talk to a platform player that is not there.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}
