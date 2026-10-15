import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Plays [track] at [volume] (1 as sent, up to 2).
Future<void> setRemoteAudioVolume(lk.RemoteAudioTrack track, double volume) {
  return rtc.Helper.setVolume(volume.clamp(0.0, 2.0), track.mediaStreamTrack);
}

/// Releases what [setRemoteAudioVolume] set up; nothing on native.
void disposeRemoteAudioVolumes() {}
