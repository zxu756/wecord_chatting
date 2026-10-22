// The browser's recorder for round video messages: getUserMedia for the
// camera and microphone, MediaRecorder for the recording.
//
// It asks MediaRecorder for MP4 first (Chrome 126 and later, Safari), because
// the iPhone app cannot play WebM; Firefox and older Chrome record WebM,
// which is sent as WebM and plays on every platform but the iPhone.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' as rtc;
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc_view;
import 'package:web/web.dart' as web;
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';

/// The recorder types to try, best first.
const _mimeCandidates = [
  'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
  'video/mp4;codecs=avc1,mp4a.40.2',
  'video/mp4',
  'video/webm;codecs=vp9,opus',
  'video/webm;codecs=vp8,opus',
  'video/webm',
];

/// The first of [_mimeCandidates] this browser can record, or null.
String? _recorderMimeType() {
  for (final type in _mimeCandidates) {
    if (web.MediaRecorder.isTypeSupported(type)) {
      return type;
    }
  }
  return null;
}

/// The browser's recorder.
VideoNoteCamera? createWebVideoNoteCamera() => WebVideoNoteCamera();

/// Whether this browser has a camera API and a recorder (a page that is not
/// served over HTTPS has no camera API).
bool browserCanRecordVideoNotes() {
  if (!globalContext.has('MediaRecorder')) {
    return false;
  }
  final devices = (web.window.navigator as JSObject).getProperty(
    'mediaDevices'.toJS,
  );
  return devices.isDefinedAndNotNull && _recorderMimeType() != null;
}

class WebVideoNoteCamera implements VideoNoteCamera {
  final _renderer = rtc_view.RTCVideoRenderer();
  rtc_view.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  final _chunks = <web.Blob>[];
  Completer<void>? _stopped;
  String _facing = 'user';
  var _cameraCount = 1;
  final _clock = Stopwatch();
  var _rendererReady = false;
  var _aspect = 4 / 3;

  @override
  Future<void> open() async {
    await _renderer.initialize();
    _rendererReady = true;
    await _openStream();
    try {
      final devices = await rtc_view.navigator.mediaDevices.enumerateDevices();
      _cameraCount = devices.where((d) => d.kind == 'videoinput').length;
    } on Object {
      _cameraCount = 1;
    }
  }

  Future<void> _openStream() async {
    await _closeStream();
    final constraints = <String, dynamic>{
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': {
        'facingMode': _facing,
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 24},
      },
    };
    final rtc_view.MediaStream stream;
    try {
      stream = await rtc_view.navigator.mediaDevices.getUserMedia(constraints);
    } on Object catch (error) {
      final text = '$error';
      if (text.contains('NotAllowed') || text.contains('Permission')) {
        throw VideoNoteCameraException(VideoNoteCameraProblem.denied, error);
      }
      if (text.contains('NotFound') || text.contains('Overconstrained')) {
        throw VideoNoteCameraException(VideoNoteCameraProblem.missing, error);
      }
      throw VideoNoteCameraException(VideoNoteCameraProblem.failed, error);
    }
    _stream = stream;
    _renderer.srcObject = stream;
    final settings = stream.getVideoTracks().firstOrNull?.getSettings();
    final width = (settings?['width'] as num?)?.toDouble();
    final height = (settings?['height'] as num?)?.toDouble();
    if (width != null && height != null && width > 0 && height > 0) {
      _aspect = width / height;
    }
  }

  Future<void> _closeStream() async {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
    }
  }

  @override
  double get previewAspect => _aspect;

  @override
  Widget buildPreview() {
    if (!_rendererReady) {
      return const SizedBox.shrink();
    }
    return rtc_view.RTCVideoView(
      _renderer,
      mirror: _facing == 'user',
      objectFit: rtc_view.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  @override
  bool get canSwitch => _cameraCount > 1;

  @override
  Future<void> switchCamera() async {
    if (_recorder != null) {
      return;
    }
    _facing = _facing == 'user' ? 'environment' : 'user';
    await _openStream();
  }

  @override
  Future<void> startRecording() async {
    final stream = _stream;
    if (stream is! rtc.MediaStreamWeb) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.failed);
    }
    final type = _recorderMimeType();
    if (type == null) {
      throw const VideoNoteCameraException(VideoNoteCameraProblem.unsupported);
    }
    _chunks.clear();
    final recorder = web.MediaRecorder(
      stream.jsStream,
      web.MediaRecorderOptions(
        mimeType: type,
        // Keeps a minute to about 6 MB.
        videoBitsPerSecond: 700000,
        audioBitsPerSecond: 64000,
      ),
    );
    recorder.addEventListener(
      'dataavailable',
      ((web.BlobEvent event) {
        if (event.data.size > 0) {
          _chunks.add(event.data);
        }
      }).toJS,
    );
    final stopped = _stopped = Completer<void>();
    recorder.addEventListener(
      'stop',
      ((web.Event _) {
        if (!stopped.isCompleted) {
          stopped.complete();
        }
      }).toJS,
    );
    recorder.start(1000);
    _recorder = recorder;
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<VideoNoteClip?> stopRecording() async {
    final recorder = _recorder;
    final stopped = _stopped;
    if (recorder == null || stopped == null) {
      return null;
    }
    _clock.stop();
    if (recorder.state != 'inactive') {
      recorder.stop();
    }
    await stopped.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    _recorder = null;
    _stopped = null;
    if (_chunks.isEmpty) {
      return null;
    }
    final mime = recorder.mimeType.split(';').first;
    final type = mime.isEmpty ? 'video/webm' : mime;
    final blob = web.Blob(
      _chunks.map((chunk) => chunk as JSAny).toList().toJS,
      web.BlobPropertyBag(type: type),
    );
    _chunks.clear();
    final buffer = await blob.arrayBuffer().toDart;
    final bytes = Uint8List.view(buffer.toDart);
    final isMp4 = type == 'video/mp4';
    return VideoNoteClip(
      file: XFile.fromData(
        bytes,
        mimeType: type,
        name: isMp4 ? 'video-message.mp4' : 'video-message.webm',
        length: bytes.length,
      ),
      durationMs: _clock.elapsedMilliseconds,
      mimeType: type,
      size: bytes.length,
    );
  }

  @override
  Future<void> cancelRecording() async {
    final recorder = _recorder;
    _recorder = null;
    _chunks.clear();
    _clock.stop();
    if (recorder != null && recorder.state != 'inactive') {
      recorder.stop();
    }
  }

  @override
  Future<void> dispose() async {
    await cancelRecording();
    await _closeStream();
    _renderer.srcObject = null;
    await _renderer.dispose();
  }
}
