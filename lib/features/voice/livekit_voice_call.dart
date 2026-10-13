import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wecord/features/voice/voice_call.dart';

/// Connects to LiveKit rooms.
class LiveKitVoiceCallConnector implements VoiceCallConnector {
  const LiveKitVoiceCallConnector();

  @override
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
  }) async {
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
    );
    final call = LiveKitVoiceCall._(room);
    try {
      await room.connect(url, token);
    } catch (_) {
      await call._close();
      rethrow;
    }
    if (microphoneEnabled) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {
        // No microphone or no permission: stay connected, muted.
      }
    }
    return call;
  }
}

/// Asks which screen to share. Browsers show their own picker, so there
/// the source is left to them; macOS lists screens and windows here.
/// Returns null when cancelled.
Future<VoiceScreenSource?> pickLiveKitScreenSource(BuildContext context) async {
  if (kIsWeb) {
    return const VoiceScreenSource();
  }
  final source = await showDialog<rtc.DesktopCapturerSource>(
    context: context,
    builder: (context) => lk.ScreenSelectDialog(),
  );
  return source == null ? null : VoiceScreenSource(sourceId: source.id);
}

class LiveKitVoiceCall extends ChangeNotifier implements VoiceCall {
  LiveKitVoiceCall._(this._room) {
    _listener = _room.createListener();
    _listener.listen(_onEvent);
    _room.addListener(_changed);
  }

  final lk.Room _room;
  late final lk.EventsListener<lk.RoomEvent> _listener;
  final _disconnected = Completer<void>();
  var _closing = false;
  var _closed = false;
  var _remoteAudioEnabled = true;

  void _onEvent(lk.RoomEvent event) {
    switch (event) {
      case lk.RoomDisconnectedEvent():
        if (!_closing && !_disconnected.isCompleted) {
          _disconnected.complete();
        }
      case lk.TrackSubscribedEvent(:final track)
          when track is lk.RemoteAudioTrack && !_remoteAudioEnabled:
        // Stay deafened for people who join later.
        unawaited(track.disable());
      default:
        break;
    }
    _changed();
  }

  void _changed() {
    if (!_closed) {
      notifyListeners();
    }
  }

  @override
  Future<void> get disconnected => _disconnected.future;

  @override
  List<VoiceCallParticipant> get participants {
    final local = _room.localParticipant;
    return [
      if (local != null) _participant(local, isLocal: true),
      for (final remote in _room.remoteParticipants.values)
        _participant(remote, isLocal: false),
    ];
  }

  VoiceCallParticipant _participant(
    lk.Participant participant, {
    required bool isLocal,
  }) {
    lk.VideoTrack? video({required bool screen}) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (publication.isScreenShare == screen &&
            !publication.muted &&
            track is lk.VideoTrack) {
          return track;
        }
      }
      return null;
    }

    final camera = video(screen: false);
    final screen = video(screen: true);
    return VoiceCallParticipant(
      userId: participant.identity,
      name: participant.name.isEmpty ? participant.identity : participant.name,
      isLocal: isLocal,
      isSpeaking: participant.isSpeaking,
      microphoneEnabled: participant.isMicrophoneEnabled(),
      cameraEnabled: camera != null,
      screenShareEnabled: screen != null,
      cameraView: camera == null
          ? null
          : (context) =>
                lk.VideoTrackRenderer(camera, fit: lk.VideoViewFit.cover),
      screenView: screen == null
          ? null
          : (context) => lk.VideoTrackRenderer(screen),
    );
  }

  @override
  VoiceConnectionQuality get quality {
    return switch (_room.localParticipant?.connectionQuality) {
      lk.ConnectionQuality.excellent => VoiceConnectionQuality.excellent,
      lk.ConnectionQuality.good => VoiceConnectionQuality.good,
      lk.ConnectionQuality.poor => VoiceConnectionQuality.poor,
      lk.ConnectionQuality.lost => VoiceConnectionQuality.lost,
      _ => VoiceConnectionQuality.unknown,
    };
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    await _room.localParticipant?.setCameraEnabled(enabled);
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled, {String? sourceId}) async {
    await _room.localParticipant?.setScreenShareEnabled(
      enabled,
      screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
        sourceId: sourceId,
        maxFrameRate: 15,
      ),
    );
  }

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    _remoteAudioEnabled = enabled;
    for (final remote in _room.remoteParticipants.values) {
      for (final publication in remote.audioTrackPublications) {
        final track = publication.track;
        if (track == null) {
          continue;
        }
        if (enabled) {
          await track.enable();
        } else {
          await track.disable();
        }
      }
    }
    _changed();
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    await _close();
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closing = true;
    try {
      await _room.disconnect();
    } finally {
      _closed = true;
      _room.removeListener(_changed);
      await _listener.dispose();
      await _room.dispose();
      super.dispose();
    }
  }
}
