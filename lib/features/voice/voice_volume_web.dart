import 'dart:async';
import 'dart:js_interop';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

/// LiveKit plays each remote audio track in an `<audio>` element with this
/// id prefix and the track's cid.
const _audioElementPrefix = 'livekit_audio_';

/// The gain nodes boosting tracks above 100%, by audio element id.
final _boosts = <String, _Boost>{};

class _Boost {
  _Boost(this.context, this.stream, this.gain);

  final web.AudioContext context;
  final web.MediaStream stream;
  final web.GainNode gain;

  void close() {
    try {
      unawaited(context.close().toDart);
    } catch (_) {
      // Already closed.
    }
  }
}

/// Plays [track] at [volume] (1 as sent, up to 2). Audio elements stop at
/// 100%, so louder plays through a gain node with the element muted.
Future<void> setRemoteAudioVolume(
  lk.RemoteAudioTrack track,
  double volume,
) async {
  final id = '$_audioElementPrefix${track.getCid()}';
  // The element appears once the track starts, just after it subscribes.
  for (var attempt = 0; attempt < 10; attempt++) {
    final element = web.document.getElementById(id);
    if (element != null && element.isA<web.HTMLAudioElement>()) {
      _apply(id, element as web.HTMLAudioElement, volume);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void _apply(String id, web.HTMLAudioElement audio, double volume) {
  final clamped = volume.clamp(0.0, 2.0);
  if (clamped <= 1) {
    _boosts.remove(id)?.close();
    audio.muted = false;
    audio.volume = clamped;
    return;
  }
  final source = audio.srcObject;
  if (source == null || !source.isA<web.MediaStream>()) {
    audio.volume = 1;
    return;
  }
  final stream = source as web.MediaStream;
  var boost = _boosts[id];
  if (boost == null || !identical(boost.stream, stream)) {
    boost?.close();
    final context = web.AudioContext();
    final gain = context.createGain();
    context.createMediaStreamSource(stream).connect(gain);
    gain.connect(context.destination);
    boost = _boosts[id] = _Boost(context, stream, gain);
  }
  boost.gain.gain.value = clamped;
  // The element keeps the stream flowing; the gain node plays it.
  audio.volume = 1;
  audio.muted = true;
}

/// Releases the gain nodes of a call that ended.
void disposeRemoteAudioVolumes() {
  for (final boost in _boosts.values) {
    boost.close();
  }
  _boosts.clear();
}
