import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wecord/features/voice/ai_noise_filter.dart';
import 'package:wecord/features/voice/background/video_background.dart';
import 'package:wecord/features/voice/background/video_background_platform.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_volume.dart';

/// Connects to LiveKit rooms.
class LiveKitVoiceCallConnector implements VoiceCallConnector {
  /// [noiseBackend] makes the AI noise filter and [effects] (the platform's
  /// by default) blurs the camera's background; tests swap in fakes.
  const LiveKitVoiceCallConnector({
    this.noiseBackend = openKrispBackend,
    this.effects,
  });

  final AiNoiseBackendFactory noiseBackend;
  final VideoBackgroundEffects? effects;

  @override
  Future<bool> aiNoiseSupported() => krispSupportedHere();

  @override
  Future<VoiceCall> connect({
    required String url,
    required String token,
    required bool microphoneEnabled,
    VoiceAudioProcessing audio = const VoiceAudioProcessing(),
    Map<String, double> userVolumes = const {},
  }) async {
    // Null when the device, browser or LiveKit project can't run it: the
    // call then uses the standard noise suppression, as before.
    final filter = await AiNoiseFilter.open(
      noiseBackend,
      url: url,
      token: token,
    );
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: liveKitCaptureOptions(
          const lk.AudioCaptureOptions(),
          audio,
          filter: filter,
        ),
      ),
    );
    final backgroundEffects = effects ?? platformVideoBackgroundEffects();
    final backgroundSupport = await backgroundEffects.detect();
    final call = LiveKitVoiceCall._(
      room,
      filter,
      audio,
      backgroundEffects,
      backgroundSupport,
    ).._volumes = Map.of(userVolumes);
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

/// The microphone options for [audio].
///
/// With an AI noise [filter] that still works it is attached as the audio
/// processor and the "Noise suppression" setting switches it (see
/// [AiNoiseFilter.setEnabled]). WebRTC's own noise suppression is then
/// turned off on iOS and macOS, so the voice is not processed twice. In
/// browsers the filter switches it off itself once it is running, and
/// leaving it on until then means a browser where the filter doesn't start
/// still has noise suppression. Apple's voice isolation follows the
/// setting either way, as it is a choice the user makes for the system.
/// Without a filter, or once it has failed, the standard noise suppression
/// applies as it always did.
lk.AudioCaptureOptions liveKitCaptureOptions(
  lk.AudioCaptureOptions options,
  VoiceAudioProcessing audio, {
  AiNoiseFilter? filter,
  bool web = kIsWeb,
}) {
  final ai = filter != null && filter.working;
  return options.copyWith(
    processor: filter,
    noiseSuppression: audio.noiseSuppression && (web || !ai),
    voiceIsolation: audio.noiseSuppression,
    echoCancellation: audio.echoCancellation,
    autoGainControl: audio.autoGainControl,
    stopAudioCaptureOnMute: !audio.keepMicrophoneOpen,
  );
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
  LiveKitVoiceCall._(
    this._room,
    this._filter,
    this._audio,
    this._effects,
    this._support,
  ) {
    _listener = _room.createListener();
    _listener.listen(_onEvent);
    _room.addListener(_changed);
    _filter?.addListener(_filterChanged);
    unawaited(_filter?.setEnabled(_audio.noiseSuppression));
    if (_support == VideoBackgroundSupport.system) {
      unawaited(_readSystemBlur());
    }
  }

  final lk.Room _room;
  final AiNoiseFilter? _filter;
  final VideoBackgroundEffects _effects;
  final VideoBackgroundSupport _support;
  var _blur = false;
  BlurProcessor? _blurProcessor;
  var _systemBlur = false;
  Timer? _systemBlurPoll;
  var _audio = const VoiceAudioProcessing();
  var _filterFallbackDone = false;
  Timer? _filterFallback;
  late final lk.EventsListener<lk.RoomEvent> _listener;
  final _disconnected = Completer<void>();
  var _closing = false;
  var _closed = false;
  var _remoteAudioEnabled = true;
  var _audioOnly = false;
  var _volumes = <String, double>{};
  final _reactions = StreamController<VoiceReaction>.broadcast();
  final _reactionReceiver = ReactionReceiver();
  final _dataMessages = StreamController<VoiceDataMessage>.broadcast();

  void _onEvent(lk.RoomEvent event) {
    switch (event) {
      case lk.RoomDisconnectedEvent():
        if (!_closing && !_disconnected.isCompleted) {
          _disconnected.complete();
        }
      case lk.TrackSubscribedEvent(:final track, :final participant)
          when track is lk.RemoteAudioTrack:
        if (!_remoteAudioEnabled) {
          // Stay deafened for people who join later.
          unawaited(track.disable());
        }
        final volume = _volumes[participant.identity];
        if (volume != null) {
          unawaited(_applyVolume(track, volume));
        }
      case lk.TrackPublishedEvent(:final publication)
          when _audioOnly && publication.kind == lk.TrackType.VIDEO:
        // Someone turned a camera on while this one is audio only.
        unawaited(_unsubscribe(publication));
      case lk.TrackSubscribedEvent(:final publication)
          when _audioOnly && publication.kind == lk.TrackType.VIDEO:
        unawaited(_unsubscribe(publication));
      case lk.DataReceivedEvent(:final participant, :final data, :final topic):
        // The sender is who LiveKit says, whatever the message claims.
        final reaction = _reactionReceiver.receive(
          senderId: participant?.identity,
          topic: topic,
          data: data,
        );
        if (reaction != null && !_reactions.isClosed) {
          _reactions.add(reaction);
        } else if (topic != null &&
            topic != reactionTopic &&
            participant != null &&
            !_dataMessages.isClosed) {
          _dataMessages.add(
            VoiceDataMessage(
              senderId: participant.identity,
              topic: topic,
              data: data,
            ),
          );
        }
      case lk.LocalTrackPublishedEvent(:final publication)
          when publication.kind == lk.TrackType.AUDIO:
        if (_filter?.working == false) {
          unawaited(_fallBackToStandardNoise());
        }
      default:
        break;
    }
    _changed();
  }

  /// The AI filter broke. The microphone is restarted without it shortly,
  /// as it is often in the middle of starting when this happens.
  void _filterChanged() {
    _filterFallback?.cancel();
    _filterFallback = Timer(const Duration(milliseconds: 300), () {
      unawaited(_fallBackToStandardNoise());
    });
    _changed();
  }

  /// Puts WebRTC's own noise suppression back on the microphone. Waits for
  /// the microphone to exist if it doesn't yet.
  Future<void> _fallBackToStandardNoise() async {
    if (_closed || _filterFallbackDone || _room.localParticipant == null) {
      return;
    }
    if (_room.localParticipant!.audioTrackPublications.isEmpty) {
      return;
    }
    _filterFallbackDone = true;
    try {
      await _applyAudioProcessing(_audio, force: true);
    } catch (_) {
      // The microphone keeps the filter-free options on its next start.
    }
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
      captionsHost: participant.attributes[captionHostAttribute] == '1',
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
  VoiceNoiseMode get noiseMode =>
      _filter?.working == true ? VoiceNoiseMode.ai : VoiceNoiseMode.standard;

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
  Stream<VoiceReaction> get reactions => _reactions.stream;

  @override
  Future<void> sendReaction(String emoji) async {
    if (!callReactionEmojis.contains(emoji)) {
      return;
    }
    await _room.localParticipant?.publishData(
      encodeReaction(emoji),
      reliable: true,
      topic: reactionTopic,
    );
  }

  @override
  Stream<VoiceDataMessage> get dataMessages => _dataMessages.stream;

  @override
  Future<void> publishData(
    List<int> data, {
    required String topic,
    bool reliable = true,
  }) async {
    await _room.localParticipant?.publishData(
      data,
      reliable: reliable,
      topic: topic,
    );
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final local = _room.localParticipant;
    if (local == null) {
      return;
    }
    if (_support == VideoBackgroundSupport.system) {
      await local.setCameraEnabled(enabled);
      _watchSystemBlur(enabled);
      return;
    }
    if (_support != VideoBackgroundSupport.inApp) {
      await local.setCameraEnabled(enabled);
      return;
    }
    // With our own blur the camera is stopped and published afresh each
    // time: LiveKit puts the unprocessed picture back on a camera that was
    // only muted, which would send it unblurred.
    if (enabled) {
      await _startCamera(local);
    } else {
      await _stopCamera(local);
    }
  }

  lk.LocalTrackPublication? _cameraOf(lk.LocalParticipant local) =>
      local.getTrackPublicationBySource(lk.TrackSource.camera);

  Future<void> _stopCamera(lk.LocalParticipant local) async {
    _blurProcessor = null;
    final publication = _cameraOf(local);
    if (publication != null) {
      await local.removePublishedTrack(publication.sid);
    }
  }

  Future<void> _startCamera(lk.LocalParticipant local) async {
    final running = _cameraOf(local);
    if (running != null && !running.muted) {
      return;
    }
    await _stopCamera(local);
    final processor = _blur ? _effects.createBlurProcessor() : null;
    _blurProcessor = processor;
    try {
      await local.setCameraEnabled(
        true,
        cameraCaptureOptions: lk.CameraCaptureOptions(processor: processor),
      );
    } catch (_) {
      _blurProcessor = null;
      rethrow;
    }
  }

  @override
  VideoBackgroundSupport get backgroundSupport => _support;

  @override
  bool get backgroundBlur =>
      _support == VideoBackgroundSupport.system ? _systemBlur : _blur;

  @override
  Future<void> setBackgroundBlur(bool enabled) async {
    if (_support != VideoBackgroundSupport.inApp) {
      return;
    }
    _blur = enabled;
    final local = _room.localParticipant;
    final camera = local == null ? null : _cameraOf(local);
    if (local == null || camera == null || camera.muted) {
      _changed();
      return;
    }
    try {
      final processor = _blurProcessor;
      if (processor != null) {
        // Already on the camera: switch it without restarting.
        await processor.setBlurEnabled(enabled);
      } else if (enabled) {
        await _stopCamera(local);
        try {
          await _startCamera(local);
        } catch (_) {
          // The camera is off now, and must not come back unblurred.
          throw const BackgroundBlurUnavailable();
        }
      }
    } catch (_) {
      _blur = false;
      rethrow;
    } finally {
      _changed();
    }
  }

  @override
  Future<void> showSystemVideoEffects() async {
    await _effects.showSystemEffects();
    unawaited(_readSystemBlur());
  }

  /// Follows the system's blur while the camera is on, since the user
  /// switches it outside the app.
  void _watchSystemBlur(bool cameraOn) {
    _systemBlurPoll?.cancel();
    _systemBlurPoll = null;
    unawaited(_readSystemBlur());
    if (cameraOn) {
      _systemBlurPoll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_readSystemBlur()),
      );
    }
  }

  Future<void> _readSystemBlur() async {
    final enabled = await _effects.systemBlurEnabled();
    if (!_closed && enabled != _systemBlur) {
      _systemBlur = enabled;
      _changed();
    }
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
  Future<void> setAudioOnly(bool enabled) async {
    _audioOnly = enabled;
    for (final remote in _room.remoteParticipants.values) {
      for (final publication in remote.videoTrackPublications) {
        if (enabled) {
          await _unsubscribe(publication);
        } else {
          await _subscribe(publication);
        }
      }
    }
    _changed();
  }

  Future<void> _unsubscribe(lk.RemoteTrackPublication publication) async {
    try {
      await publication.unsubscribe();
    } catch (_) {
      // The track is gone, or the room is closing.
    }
  }

  Future<void> _subscribe(lk.RemoteTrackPublication publication) async {
    try {
      await publication.subscribe();
    } catch (_) {
      // See [_unsubscribe].
    }
  }

  @override
  Future<void> setAudioProcessing(VoiceAudioProcessing audio) {
    return _applyAudioProcessing(audio);
  }

  Future<void> _applyAudioProcessing(
    VoiceAudioProcessing audio, {
    bool force = false,
  }) async {
    _audio = audio;
    // Switching the AI filter needs no restart.
    await _filter?.setEnabled(audio.noiseSuppression);
    final local = _room.localParticipant;
    if (local == null) {
      return;
    }
    for (final publication in local.audioTrackPublications) {
      final track = publication.track;
      if (track == null) {
        continue;
      }
      final before = track.currentOptions;
      final after = liveKitCaptureOptions(before, audio, filter: _filter);
      track.currentOptions = after;
      final changed =
          before.noiseSuppression != after.noiseSuppression ||
          before.voiceIsolation != after.voiceIsolation ||
          before.echoCancellation != after.echoCancellation ||
          before.autoGainControl != after.autoGainControl;
      // A muted microphone picks the options up when it unmutes; restarting
      // it now could start sending.
      if ((changed || force) && !publication.muted) {
        await track.restartTrack();
      }
    }
    _changed();
  }

  @override
  Future<void> setUserVolumes(Map<String, double> volumes) async {
    _volumes = Map.of(volumes);
    for (final remote in _room.remoteParticipants.values) {
      for (final publication in remote.audioTrackPublications) {
        final track = publication.track;
        if (track != null) {
          await _applyVolume(track, _volumes[remote.identity] ?? 1);
        }
      }
    }
  }

  Future<void> _applyVolume(lk.RemoteAudioTrack track, double volume) async {
    try {
      await setRemoteAudioVolume(track, volume);
    } catch (_) {
      // Not supported here; the participant plays at the normal volume.
    }
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
    _filterFallback?.cancel();
    _systemBlurPoll?.cancel();
    try {
      await _room.disconnect();
    } finally {
      _closed = true;
      _filter?.removeListener(_filterChanged);
      disposeRemoteAudioVolumes();
      unawaited(_reactions.close());
      unawaited(_dataMessages.close());
      _room.removeListener(_changed);
      await _listener.dispose();
      await _room.dispose();
      _filter?.dispose();
      super.dispose();
    }
  }
}
