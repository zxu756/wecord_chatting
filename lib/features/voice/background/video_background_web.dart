import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:dart_webrtc/dart_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;
import 'package:wecord/features/voice/background/video_background.dart';

/// LiveKit's track processors (Apache-2.0), pinned. They blur with MediaPipe's
/// selfie segmentation, running in the browser: the camera picture never
/// leaves the device unblurred. The library, MediaPipe's code and wasm
/// (`@mediapipe/tasks-vision` 0.10.14, jsDelivr) and the model are fetched
/// the first time blur is used. `web/index.html` maps the library's imports
/// (an import map), and `web/blur/livekit_client_shim.js` stands in for the
/// `livekit-client` logger it asks for.
const _processorsUrl =
    'https://cdn.jsdelivr.net/npm/@livekit/track-processors@0.8.2/dist/index.mjs';

const _blurRadius = 12;

Future<JSObject>? _loading;

/// Loads the library once; a failed load can be tried again later.
Future<JSObject> _loadLibrary() {
  return _loading ??= () async {
    try {
      return await importModule(_processorsUrl.toJS).toDart;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
}

/// The effects of the browser.
VideoBackgroundEffects platformVideoBackgroundEffects() =>
    const WebVideoEffects();

class WebVideoEffects implements VideoBackgroundEffects {
  const WebVideoEffects();

  /// Whether the browser has what the blur needs: OffscreenCanvas,
  /// VideoFrame, createImageBitmap and WebGL 2. (The library gives the same
  /// answer, but asking it means loading it.) Without the network the blur
  /// fails when it is first used instead, and the camera stays off.
  @override
  Future<VideoBackgroundSupport> detect() async {
    try {
      final global = globalContext;
      final hasApis =
          global.has('OffscreenCanvas') &&
          global.has('VideoFrame') &&
          global.has('createImageBitmap');
      if (!hasApis) {
        return VideoBackgroundSupport.none;
      }
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      return canvas.getContext('webgl2') == null
          ? VideoBackgroundSupport.none
          : VideoBackgroundSupport.inApp;
    } catch (_) {
      return VideoBackgroundSupport.none;
    }
  }

  @override
  BlurProcessor? createBlurProcessor() => WebBlurProcessor();

  @override
  Future<bool> systemBlurEnabled() async => false;

  @override
  Future<void> showSystemEffects() async {}
}

/// Blurs the background of a camera in the browser with LiveKit's
/// `BackgroundProcessor`.
class WebBlurProcessor implements BlurProcessor {
  JSObject? _processor;
  web.HTMLVideoElement? _element;
  rtc.MediaStreamTrack? _processed;
  var _enabled = true;

  @override
  String get name => 'wecord-background-blur';

  @override
  rtc.MediaStreamTrack? get processedTrack => _processed;

  @override
  Future<void> init(lk.VideoProcessorOptions options) async {
    final JSObject library;
    try {
      library = await _loadLibrary().timeout(const Duration(seconds: 20));
    } catch (error) {
      debugPrint('Background blur: could not load the library: $error');
      try {
        await options.track.stop();
      } catch (_) {
        // Already stopped.
      }
      throw const BackgroundBlurUnavailable();
    }
    try {
      final source = options.track;
      if (source is! rtc.MediaStreamTrackWeb) {
        throw StateError('not a browser track');
      }
      final jsTrack = source.jsTrack;
      // The processor reads the camera through a video element.
      final element = web.HTMLVideoElement()
        ..muted = true
        ..autoplay = true
        ..playsInline = true
        ..srcObject = web.MediaStream([jsTrack].toJS);
      await element.play().toDart;
      _element = element;

      final settings = JSObject()
        ..['mode'] = 'background-blur'.toJS
        ..['blurRadius'] = _blurRadius.toJS;
      final processor =
          (library['BackgroundProcessor']! as JSFunction).callAsFunction(
                null,
                settings,
              )!
              as JSObject;
      final init = JSObject()
        ..['kind'] = 'video'.toJS
        ..['track'] = jsTrack
        ..['element'] = element;
      await (processor.callMethod('init'.toJS, init)! as JSPromise).toDart;
      _processor = processor;
      final processedTrack = processor['processedTrack'];
      if (processedTrack == null) {
        throw StateError('no processed track');
      }
      _processed = rtc.MediaStreamTrackWeb(
        processedTrack as web.MediaStreamTrack,
      );
      if (!_enabled) {
        await setBlurEnabled(false);
      }
    } catch (error) {
      debugPrint('Background blur: could not start: $error');
      await destroy();
      // The camera was opened for us; without the blur it must not run.
      try {
        await options.track.stop();
      } catch (_) {
        // Already stopped.
      }
      throw const BackgroundBlurUnavailable();
    }
  }

  @override
  Future<void> restart(lk.VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> setBlurEnabled(bool enabled) async {
    _enabled = enabled;
    final processor = _processor;
    if (processor == null) {
      return;
    }
    final mode = JSObject()
      ..['mode'] = (enabled ? 'background-blur' : 'disabled').toJS;
    if (enabled) {
      mode['blurRadius'] = _blurRadius.toJS;
    }
    await (processor.callMethod('switchTo'.toJS, mode)! as JSPromise).toDart;
  }

  @override
  Future<void> destroy() async {
    final processor = _processor;
    _processor = null;
    _processed = null;
    try {
      if (processor != null) {
        await (processor.callMethod('destroy'.toJS)! as JSPromise).toDart;
      }
    } catch (_) {
      // Already gone.
    }
    _element?.srcObject = null;
    _element?.remove();
    _element = null;
  }

  @override
  Future<void> onPublish(lk.Room room) async {}

  @override
  Future<void> onUnpublish() async {}
}
