import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_noise_filter/livekit_noise_filter.dart';

/// Why the AI noise filter can't be used here.
class AiNoiseUnavailable implements Exception {
  const AiNoiseUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'AiNoiseUnavailable: $reason';
}

/// What an AI noise filter is made of: the processor attached to the
/// microphone track, and the switch that lets audio through untouched.
class AiNoiseBackend {
  const AiNoiseBackend({required this.processor, required this.setBypass});

  final lk.TrackProcessor<lk.AudioProcessorOptions> processor;

  /// true lets the microphone through unfiltered.
  final Future<void> Function(bool bypass) setBypass;
}

/// Makes a backend for the room at [url] opened with [token], or throws
/// when it can't be used.
typedef AiNoiseBackendFactory =
    Future<AiNoiseBackend> Function(String url, String token);

/// LiveKit's Krisp filter, once this device and the LiveKit project allow
/// it. Throws [AiNoiseUnavailable] otherwise.
Future<AiNoiseBackend> openKrispBackend(String url, String token) async {
  if (!await krispSupportedHere()) {
    throw const AiNoiseUnavailable(
      'this device or browser cannot run the filter',
    );
  }
  if (!await _projectAllows(url, token)) {
    throw const AiNoiseUnavailable(
      'the LiveKit project does not have enhanced noise cancellation',
    );
  }
  final filter = LiveKitNoiseFilter();
  return AiNoiseBackend(processor: filter, setBypass: filter.setBypass);
}

/// Whether the platform (or browser) can run the Krisp filter. Never throws.
Future<bool> krispSupportedHere() async {
  try {
    // The web build answers with a Future<void> that holds the bool.
    final Future<Object?> probe = LiveKitNoiseFilter.isSupported();
    return await probe == true;
  } catch (error) {
    debugPrint('AI noise suppression: support check failed: $error');
    return false;
  }
}

/// Asks the LiveKit server whether the project may use the filter, the way
/// the filter itself does when it starts. Asking first means a project
/// without it never gets a filter attached at all, so the standard noise
/// suppression stays on.
Future<bool> _projectAllows(String url, String token) async {
  final base = Uri.parse(url.replaceFirst(RegExp('^ws'), 'http'));
  final settings = base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/settings',
    query: '',
  );
  final client = http.Client();
  try {
    final response = await client
        .get(settings, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      return false;
    }
    final body = jsonDecode(response.body);
    return body is Map && body['enhancedNoiseCancellation'] == true;
  } finally {
    client.close();
  }
}

/// A microphone processor that can never break the call. Whatever the
/// wrapped filter throws, or if it is not running when it should be, the
/// filter is marked failed, becomes a no-op and listeners are told, so the
/// call can go back to the standard noise suppression.
class AiNoiseFilter extends ChangeNotifier
    implements lk.TrackProcessor<lk.AudioProcessorOptions> {
  AiNoiseFilter._(this._backend, {required this.needsProcessedTrack});

  /// Opens the backend, or returns null (and says why in the log) when AI
  /// noise suppression can't be used. Never throws.
  static Future<AiNoiseFilter?> open(
    AiNoiseBackendFactory factory, {
    required String url,
    required String token,
    bool? needsProcessedTrack,
  }) async {
    try {
      return AiNoiseFilter._(
        await factory(url, token),
        // Browsers hand back a new track; native filters work in place.
        needsProcessedTrack: needsProcessedTrack ?? kIsWeb,
      );
    } catch (error) {
      debugPrint('AI noise suppression: not used: $error');
      return null;
    }
  }

  final AiNoiseBackend _backend;
  final bool needsProcessedTrack;
  var _failed = false;
  var _disposed = false;
  var _enabled = true;
  lk.Room? _room;

  /// The filter is usable: nothing has gone wrong with it.
  bool get working => !_failed;

  @override
  String get name => _backend.processor.name;

  /// Filters the microphone, or lets it through untouched.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _guard(() => _backend.setBypass(!enabled));
  }

  @override
  Future<void> init(lk.AudioProcessorOptions options) async {
    await _guard(() => _backend.processor.init(options));
    if (!_failed && needsProcessedTrack && processedTrack == null) {
      // The browser filter returns quietly when it can't start (a sample
      // rate it doesn't handle, a Safari without the needed API).
      _fail('the filter did not start');
    }
    final room = _room;
    if (!_failed && room != null) {
      // The microphone was restarted (unmuted after being stopped, or its
      // device changed): LiveKit sets the processor up again but only
      // tells it about the room when a track is first published, and the
      // browser filter stays off until then.
      await onPublish(room);
    }
  }

  @override
  Future<void> restart(lk.AudioProcessorOptions options) {
    return _guard(() => _backend.processor.restart(options));
  }

  @override
  Future<void> onPublish(lk.Room room) async {
    _room = room;
    await _guard(() => _backend.processor.onPublish(room));
    if (!_enabled) {
      // Publishing switches the filter on.
      await _guard(() => _backend.setBypass(true));
    }
  }

  @override
  Future<void> onUnpublish() {
    _room = null;
    return _guard(_backend.processor.onUnpublish);
  }

  @override
  Future<void> destroy() async {
    // Always cleans up, even after a failure.
    try {
      await _backend.processor.destroy();
    } catch (error) {
      debugPrint('AI noise suppression: cleanup failed: $error');
    }
  }

  @override
  rtc.MediaStreamTrack? get processedTrack =>
      _failed ? null : _backend.processor.processedTrack;

  Future<void> _guard(Future<void> Function() run) async {
    if (_failed) {
      return;
    }
    try {
      await run();
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object reason) {
    if (_failed) {
      return;
    }
    _failed = true;
    debugPrint(
      'AI noise suppression stopped, using standard noise suppression: '
      '$reason',
    );
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
