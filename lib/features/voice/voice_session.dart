import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/features/voice/livekit_voice_call.dart';
import 'package:wecord/features/voice/soundboard_player.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/voice.dart';

final voiceCallConnectorProvider = Provider<VoiceCallConnector>((ref) {
  return const LiveKitVoiceCallConnector();
});

final voiceScreenSourcePickerProvider = Provider<VoiceScreenSourcePicker>((
  ref,
) {
  return pickLiveKitScreenSource;
});

/// Whether this device can share its screen in voice channels.
final voiceScreenShareSupportedProvider = Provider<bool>((ref) {
  return voiceScreenShareSupported(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );
});

/// The voice channel or direct / group call the current user is connected
/// to, if any. It lives for the whole app, so moving between channels,
/// circles and chats keeps the call; signing out ends it.
final voiceSessionProvider =
    StateNotifierProvider<VoiceSessionController, VoiceSession?>((ref) {
      final controller = VoiceSessionController(
        repository: ref.watch(voiceRepositoryProvider),
        connector: ref.watch(voiceCallConnectorProvider),
        settings: ref.read(voiceSettingsProvider),
        onCallJoined: ref.watch(pushRepositoryProvider).notifyCall,
        onMembersChanged: (session) {
          if (session.circleId case final circleId?) {
            ref.invalidate(voiceStatesProvider(circleId));
          } else {
            ref.invalidate(activeDirectCallsProvider);
          }
        },
      );
      ref.listen(authStateProvider.select((state) => state.valueOrNull?.id), (
        previous,
        next,
      ) {
        if (previous != next) {
          unawaited(controller.leave());
        }
      });
      ref.listen(voiceSettingsProvider, (previous, next) {
        unawaited(controller.updateSettings(next));
      });
      // Plays the soundboard sounds others play in the channel.
      final soundboard = SoundboardPlayback(
        repository: ref.watch(soundboardRepositoryProvider),
        player: ref.watch(soundboardPlayerProvider),
        volume: () => ref.read(voiceSettingsProvider).soundboardVolume,
      );
      final stopFollowing = controller.addListener(soundboard.follow);
      ref.onDispose(() {
        try {
          stopFollowing();
        } catch (_) {
          // The controller went first.
        }
        soundboard.dispose();
      });
      // The push to talk key works anywhere in the app while connected.
      bool onKey(KeyEvent event) {
        final settings = ref.read(voiceSettingsProvider);
        final key = settings.pushToTalkKey;
        if (!settings.pushToTalk || key == null || event.logicalKey != key) {
          return false;
        }
        if (event is KeyDownEvent) {
          unawaited(controller.setTransmitting(true));
        } else if (event is KeyUpEvent) {
          unawaited(controller.setTransmitting(false));
        }
        // Let the key type too, as it does elsewhere.
        return false;
      }

      try {
        HardwareKeyboard.instance.addHandler(onKey);
        ref.onDispose(() => HardwareKeyboard.instance.removeHandler(onKey));
      } catch (_) {
        // No keyboard binding (plain unit tests).
      }
      return controller;
    });

/// Where [session] is shown: its voice channel's page, or the chat the call
/// is in.
String voiceSessionPath(VoiceSession session) {
  final circleId = session.circleId;
  if (circleId == null) {
    return '${ChatsScreen.path}/${session.conversationId}';
  }
  return CircleChannelThreadScreen.pathFor(circleId, session.conversationId);
}

/// How often a connected client tells the server it is still there.
const voiceHeartbeatInterval = Duration(seconds: 20);

enum VoiceSessionStatus { connecting, connected }

@immutable
class VoiceSession {
  const VoiceSession({
    required this.conversationId,
    required this.channelName,
    this.circleId,
    this.channelId,
    this.callId,
    this.status = VoiceSessionStatus.connecting,
    this.selfMute = false,
    this.selfDeaf = false,
    this.video = false,
    this.screen = false,
    this.participants = const [],
    this.quality = VoiceConnectionQuality.unknown,
    this.pushToTalk = false,
    this.transmitting = false,
    this.serverMute = false,
    this.serverDeaf = false,
    this.stage = false,
    this.stageSpeaker = false,
    this.stageInvited = false,
    this.handRaised = false,
  });

  /// The circle and voice channel, for a voice channel; null in a call.
  final String? circleId;
  final String? channelId;

  /// The direct or group call, once joined; null in a voice channel.
  final String? callId;

  /// The channel's conversation, or the chat the call is in, which names
  /// its route.
  final String conversationId;

  /// The channel's name, or the chat's title for a call.
  final String channelName;
  final VoiceSessionStatus status;
  final bool selfMute;
  final bool selfDeaf;
  final bool video;
  final bool screen;

  /// Who the media connection sees, the current user first. Empty while
  /// connecting.
  final List<VoiceCallParticipant> participants;
  final VoiceConnectionQuality quality;

  /// Push to talk is on: the microphone sends only while [transmitting].
  final bool pushToTalk;

  /// The push to talk key or button is held.
  final bool transmitting;

  /// A moderator muted or deafened the current user in this channel.
  final bool serverMute;
  final bool serverDeaf;

  /// The channel is a stage, where only speakers talk.
  final bool stage;

  /// On a stage: the current user is one of the speakers.
  final bool stageSpeaker;

  /// On a stage: a moderator invited the current user to speak.
  final bool stageInvited;

  /// On a stage: the current user raised their hand to speak.
  final bool handRaised;

  /// In a stage's audience, where the microphone stays off.
  bool get stageListener => stage && !stageSpeaker;

  /// Whether the microphone should be sending now.
  bool get microphoneWanted =>
      !selfMute &&
      !selfDeaf &&
      !serverMute &&
      !serverDeaf &&
      !stageListener &&
      (!pushToTalk || transmitting);

  /// Whether the others should be heard now.
  bool get hearingWanted => !selfDeaf && !serverDeaf;

  bool get isConnected => status == VoiceSessionStatus.connected;

  /// A call in a direct or group chat rather than a circle voice channel.
  bool get isDirectCall => channelId == null;

  VoiceSession copyWith({
    String? callId,
    VoiceSessionStatus? status,
    bool? selfMute,
    bool? selfDeaf,
    bool? video,
    bool? screen,
    List<VoiceCallParticipant>? participants,
    VoiceConnectionQuality? quality,
    bool? pushToTalk,
    bool? transmitting,
    bool? serverMute,
    bool? serverDeaf,
    bool? stage,
    bool? stageSpeaker,
    bool? stageInvited,
    bool? handRaised,
  }) {
    return VoiceSession(
      circleId: circleId,
      channelId: channelId,
      callId: callId ?? this.callId,
      conversationId: conversationId,
      channelName: channelName,
      status: status ?? this.status,
      selfMute: selfMute ?? this.selfMute,
      selfDeaf: selfDeaf ?? this.selfDeaf,
      video: video ?? this.video,
      screen: screen ?? this.screen,
      participants: participants ?? this.participants,
      quality: quality ?? this.quality,
      pushToTalk: pushToTalk ?? this.pushToTalk,
      transmitting: transmitting ?? this.transmitting,
      serverMute: serverMute ?? this.serverMute,
      serverDeaf: serverDeaf ?? this.serverDeaf,
      stage: stage ?? this.stage,
      stageSpeaker: stageSpeaker ?? this.stageSpeaker,
      stageInvited: stageInvited ?? this.stageInvited,
      handRaised: handRaised ?? this.handRaised,
    );
  }
}

/// Connects to voice channels and keeps the server's voice state in step:
/// joins it, heartbeats every [voiceHeartbeatInterval] with the current
/// mute / deafen / video / screen flags, and leaves it on disconnect.
class VoiceSessionController extends StateNotifier<VoiceSession?> {
  VoiceSessionController({
    required this._repository,
    required this._connector,
    this._onMembersChanged,
    this._onCallJoined,
    this._settings = const VoiceSettings(),
  }) : super(null);

  final VoiceRepository _repository;
  final VoiceCallConnector _connector;
  final void Function(VoiceSession session)? _onMembersChanged;

  /// Input mode, microphone processing and volumes, kept in step by
  /// [updateSettings].
  VoiceSettings _settings;

  /// Called with each call joined, so a newly started one rings by push
  /// (the server ignores calls someone else started).
  final Future<void> Function(String callId)? _onCallJoined;

  VoiceCall? _call;
  Timer? _heartbeat;
  Timer? _retryMicrophone;
  AppLifecycleListener? _lifecycle;

  /// Changes to the current user's own voice state, while in a channel.
  StreamSubscription<void>? _ownStateChanges;

  /// Bumped by every join and leave, so a slow join that was overtaken
  /// gives up.
  var _attempt = 0;

  /// Whether the user was muted before deafening, restored on undeafen.
  var _mutedBeforeDeafen = false;

  /// Set once the provider is gone, after which nothing is notified.
  var _disposed = false;

  void _membersChanged(VoiceSession session) {
    if (!_disposed) {
      _onMembersChanged?.call(session);
    }
  }

  /// Connects to [channelId], leaving any other voice channel first. Throws
  /// [VoiceNotConfiguredException] when voice is not set up,
  /// [VoiceAccessDeniedException] without permission, or the connection
  /// error; the session is then gone.
  Future<void> join({
    required String circleId,
    required String channelId,
    required String conversationId,
    required String channelName,
  }) async {
    if (state?.channelId == channelId) {
      return;
    }
    await leave();
    final attempt = ++_attempt;
    state = VoiceSession(
      circleId: circleId,
      channelId: channelId,
      conversationId: conversationId,
      channelName: channelName,
    );
    VoiceCall? call;
    try {
      final details = await _repository.fetchConnectionDetails(channelId);
      if (attempt != _attempt) {
        return;
      }
      state = state?.copyWith(
        serverMute: details.serverMute,
        serverDeaf: details.serverDeaf,
        stage: details.stage,
        stageSpeaker: details.stageSpeaker,
      );
      call = await _connect(details);
      if (attempt != _attempt) {
        await call.disconnect();
        return;
      }
      await _repository.joinVoiceState(channelId);
      if (attempt != _attempt) {
        await call.disconnect();
        return;
      }
    } catch (_) {
      if (attempt == _attempt) {
        state = null;
      }
      try {
        await call?.disconnect();
      } catch (_) {}
      rethrow;
    }
    _connected(call);
  }

  /// Joins the call in [conversationId] (a direct or group chat), starting
  /// it when there is none and leaving any other call or voice channel.
  /// [video] turns the camera on once connected. Throws like [join].
  Future<void> startCall({
    required String conversationId,
    required String name,
    bool video = false,
  }) async {
    final current = state;
    if (current != null &&
        current.isDirectCall &&
        current.conversationId == conversationId) {
      if (video && !current.video && current.isConnected) {
        await toggleCamera();
      }
      return;
    }
    await leave();
    final attempt = ++_attempt;
    state = VoiceSession(conversationId: conversationId, channelName: name);
    VoiceCall? call;
    String? callId;
    try {
      callId = await _repository.startDirectCall(conversationId);
      if (attempt != _attempt) {
        unawaited(_leaveCallQuietly(callId));
        return;
      }
      state = state?.copyWith(callId: callId);
      unawaited(_onCallJoined?.call(callId));
      final details = await _repository.fetchCallConnectionDetails(callId);
      if (attempt != _attempt) {
        unawaited(_leaveCallQuietly(callId));
        return;
      }
      call = await _connect(details);
      if (attempt != _attempt) {
        await call.disconnect();
        unawaited(_leaveCallQuietly(callId));
        return;
      }
    } catch (_) {
      if (attempt == _attempt) {
        state = null;
      }
      try {
        await call?.disconnect();
      } catch (_) {}
      if (callId != null) {
        unawaited(_leaveCallQuietly(callId));
      }
      rethrow;
    }
    _connected(call);
    if (video) {
      try {
        await toggleCamera();
      } catch (_) {
        // The call works without the camera; the button tries again.
      }
    }
  }

  Future<VoiceCall> _connect(VoiceConnectionDetails details) {
    return _connector.connect(
      url: details.url,
      token: details.token,
      // Server-muted tokens can't publish the microphone, and a stage's
      // audience can't publish at all.
      microphoneEnabled:
          !details.serverMute &&
          !details.serverDeaf &&
          (!details.stage || details.stageSpeaker),
      audio: _settings.audioProcessing,
      userVolumes: _settings.userVolumes,
    );
  }

  Future<void> _leaveCallQuietly(String callId) async {
    try {
      await _repository.leaveDirectCall(callId);
    } catch (_) {
      // The server drops it after a minute without heartbeats.
    }
  }

  /// [carried] is the session before a move, whose mute and deafen stay.
  void _connected(VoiceCall call, {VoiceSession? carried}) {
    _call = call;
    call.addListener(_syncFromCall);
    unawaited(
      call.disconnected.then((_) {
        if (identical(_call, call)) {
          unawaited(leave());
        }
      }),
    );
    final local = _localParticipant(call);
    final current = state;
    final serverSilenced =
        current != null &&
        (current.serverMute || current.serverDeaf || current.stageListener);
    state = current?.copyWith(
      status: VoiceSessionStatus.connected,
      // Without a working microphone the user starts muted; server-muted,
      // the microphone was never opened.
      selfMute:
          carried?.selfMute ??
          (serverSilenced ? false : !(local?.microphoneEnabled ?? false)),
      selfDeaf: carried?.selfDeaf,
      participants: call.participants,
      quality: call.quality,
      pushToTalk: _settings.pushToTalk,
      transmitting: false,
    );
    if (carried != null ||
        serverSilenced ||
        (_settings.pushToTalk && state?.selfMute == false)) {
      // Push to talk sends only while the key is held.
      unawaited(_applyMicrophone());
    }
    if (state?.hearingWanted == false) {
      unawaited(_applyHearing());
    }
    _heartbeat = Timer.periodic(voiceHeartbeatInterval, (_) => _beat());
    _lifecycle = AppLifecycleListener(onDetach: () => unawaited(leave()));
    if (current?.channelId != null) {
      _ownStateChanges = _repository.ownVoiceStateChanges().listen(
        (_) => unawaited(_syncOwnState()),
      );
    }
    if (state?.selfMute == true || carried != null) {
      unawaited(_pushFlags());
    }
    final session = state;
    if (session != null) {
      _membersChanged(session);
    }
  }

  /// Hears the others or not, to match the session.
  Future<void> _applyHearing() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return;
    }
    try {
      await call.setRemoteAudioEnabled(session.hearingWanted);
    } catch (_) {
      // The next change tries again.
    }
  }

  /// Follows the server's view of the current user in a voice channel: a
  /// moderator's mute, deafen, move or disconnect.
  Future<void> _syncOwnState() async {
    final session = state;
    if (session == null || session.channelId == null || !session.isConnected) {
      return;
    }
    final attempt = _attempt;
    final OwnVoiceState own;
    try {
      own = await _repository.fetchOwnVoiceState();
    } catch (_) {
      return;
    }
    final current = state;
    if (attempt != _attempt || current == null || !mounted) {
      return;
    }
    final channelId = own.channelId;
    if (channelId == null) {
      if (own.disconnected) {
        await leave();
      }
      // Otherwise it went stale; the heartbeat joins again.
      return;
    }
    if (channelId != current.channelId) {
      await _moveTo(own, current);
      return;
    }
    if (current.stage &&
        (own.stageSpeaker != current.stageSpeaker ||
            own.stageInvited != current.stageInvited ||
            own.handRaised != current.handRaised)) {
      await _followStageRole(own, current);
      return;
    }
    if (own.serverMute == current.serverMute &&
        own.serverDeaf == current.serverDeaf) {
      return;
    }
    state = current.copyWith(
      serverMute: own.serverMute,
      serverDeaf: own.serverDeaf,
      transmitting: false,
    );
    await _applyHearing();
    if (!await _applyMicrophone()) {
      // Unmuted before the voice server allowed the microphone again.
      _retryMicrophone?.cancel();
      _retryMicrophone = Timer(
        const Duration(seconds: 3),
        () => unawaited(_applyMicrophone()),
      );
    }
  }

  /// Follows the current user's place on a stage: becoming a speaker
  /// starts muted, and going back to the audience turns the microphone,
  /// camera and screen off. Either way the voice server is asked to match,
  /// so publishing is allowed or stopped without reconnecting.
  Future<void> _followStageRole(OwnVoiceState own, VoiceSession current) async {
    final promoted = own.stageSpeaker && !current.stageSpeaker;
    final demoted = !own.stageSpeaker && current.stageSpeaker;
    state = current.copyWith(
      serverMute: own.serverMute,
      serverDeaf: own.serverDeaf,
      stageSpeaker: own.stageSpeaker,
      stageInvited: own.stageInvited,
      handRaised: own.handRaised,
      selfMute: promoted ? true : null,
      video: demoted ? false : null,
      screen: demoted ? false : null,
      transmitting: false,
    );
    final call = _call;
    if (!promoted && !demoted) {
      return;
    }
    final channelId = current.channelId;
    final userId = call == null ? null : _localParticipant(call)?.userId;
    if (channelId != null && userId != null) {
      try {
        await _repository.enforceVoiceState(
          channelId: channelId,
          userId: userId,
        );
      } catch (_) {
        // A moderator's client asks too.
      }
    }
    if (demoted && call != null) {
      try {
        if (current.video) {
          await call.setCameraEnabled(false);
        }
        if (current.screen) {
          await call.setScreenShareEnabled(false);
        }
      } catch (_) {
        // The voice server stops them anyway.
      }
    }
    await _applyMicrophone();
    await _pushFlags();
  }

  /// Reloads the current user's own voice state now, after a stage action,
  /// rather than waiting for its change event.
  Future<void> syncOwnState() => _syncOwnState();

  /// Reconnects to the channel a moderator moved the current user to,
  /// keeping their own mute and deafen.
  Future<void> _moveTo(OwnVoiceState own, VoiceSession previous) async {
    final channelId = own.channelId!;
    final attempt = ++_attempt;
    final oldCall = _stopConnection();
    try {
      await oldCall?.disconnect();
    } catch (_) {
      // Already gone.
    }
    state = VoiceSession(
      circleId: own.circleId ?? previous.circleId,
      channelId: channelId,
      conversationId: own.conversationId ?? previous.conversationId,
      channelName: own.channelName ?? previous.channelName,
      selfMute: previous.selfMute,
      selfDeaf: previous.selfDeaf,
      serverMute: own.serverMute,
      serverDeaf: own.serverDeaf,
    );
    _membersChanged(previous);
    VoiceCall? call;
    try {
      final details = await _repository.fetchConnectionDetails(channelId);
      if (attempt != _attempt) {
        return;
      }
      state = state?.copyWith(
        stage: details.stage,
        stageSpeaker: details.stageSpeaker,
      );
      call = await _connect(details);
      if (attempt != _attempt) {
        await call.disconnect();
        return;
      }
    } catch (_) {
      try {
        await call?.disconnect();
      } catch (_) {}
      if (attempt == _attempt) {
        await leave();
      }
      return;
    }
    _connected(call, carried: previous);
  }

  /// Stops the heartbeat and listeners and forgets the call, returning it
  /// for the caller to disconnect.
  VoiceCall? _stopConnection() {
    final call = _call;
    _call = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _retryMicrophone?.cancel();
    _retryMicrophone = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_ownStateChanges?.cancel());
    _ownStateChanges = null;
    call?.removeListener(_syncFromCall);
    return call;
  }

  VoiceCallParticipant? _localParticipant(VoiceCall call) {
    for (final participant in call.participants) {
      if (participant.isLocal) {
        return participant;
      }
    }
    return null;
  }

  void _syncFromCall() {
    final call = _call;
    final session = state;
    if (call == null || session == null) {
      return;
    }
    state = session.copyWith(
      participants: call.participants,
      quality: call.quality,
    );
  }

  /// Disconnects and clears the server state; does nothing when not
  /// connected.
  Future<void> leave() async {
    _attempt++;
    final session = state;
    final call = _stopConnection();
    if (session == null) {
      return;
    }
    state = null;
    try {
      await call?.disconnect();
    } catch (_) {
      // Already gone.
    }
    final callId = session.callId;
    if (session.isDirectCall) {
      if (callId != null) {
        await _leaveCallQuietly(callId);
      }
    } else {
      try {
        await _repository.leaveVoiceState();
      } catch (_) {
        // The server drops it after a minute without heartbeats.
      }
    }
    _membersChanged(session);
  }

  Future<void> toggleMute() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return;
    }
    if (session.selfDeaf) {
      // Unmuting while deafened undeafens too.
      final next = session.copyWith(selfMute: false, selfDeaf: false);
      await call.setRemoteAudioEnabled(next.hearingWanted);
      await call.setMicrophoneEnabled(next.microphoneWanted);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfMute: false, selfDeaf: false);
    } else {
      final next = session.copyWith(selfMute: !session.selfMute);
      await call.setMicrophoneEnabled(next.microphoneWanted);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfMute: !session.selfMute);
    }
    await _pushFlags();
  }

  /// Starts or stops sending while push to talk is on (the key or the
  /// hold to talk button). Does nothing otherwise.
  Future<void> setTransmitting(bool transmitting) async {
    final session = state;
    if (session == null ||
        !session.isConnected ||
        !session.pushToTalk ||
        session.transmitting == transmitting) {
      return;
    }
    state = session.copyWith(transmitting: transmitting);
    await _applyMicrophone();
  }

  /// Turns the microphone on or off to match the session; false when that
  /// failed.
  Future<bool> _applyMicrophone() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return true;
    }
    try {
      await call.setMicrophoneEnabled(session.microphoneWanted);
      return true;
    } catch (_) {
      // No microphone or no permission; the mute button says why.
      return false;
    }
  }

  /// Applies changed voice settings to the call in progress.
  Future<void> updateSettings(VoiceSettings settings) async {
    final previous = _settings;
    _settings = settings;
    final session = state;
    final call = _call;
    if (session == null || call == null || !session.isConnected) {
      return;
    }
    if (previous.pushToTalk != settings.pushToTalk) {
      state = session.copyWith(
        pushToTalk: settings.pushToTalk,
        transmitting: false,
      );
      await _applyMicrophone();
    }
    try {
      if (previous.audioProcessing != settings.audioProcessing) {
        await call.setAudioProcessing(settings.audioProcessing);
      }
      if (!mapEquals(previous.userVolumes, settings.userVolumes)) {
        await call.setUserVolumes(settings.userVolumes);
      }
    } catch (_) {
      // Applies from the next call.
    }
  }

  Future<void> toggleDeafen() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return;
    }
    if (session.selfDeaf) {
      final next = session.copyWith(
        selfDeaf: false,
        selfMute: _mutedBeforeDeafen,
      );
      await call.setRemoteAudioEnabled(next.hearingWanted);
      await call.setMicrophoneEnabled(next.microphoneWanted);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfDeaf: false, selfMute: _mutedBeforeDeafen);
    } else {
      _mutedBeforeDeafen = session.selfMute;
      await call.setRemoteAudioEnabled(false);
      await call.setMicrophoneEnabled(false);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfDeaf: true, selfMute: true);
    }
    await _pushFlags();
  }

  Future<void> toggleCamera() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return;
    }
    await call.setCameraEnabled(!session.video);
    if (!mounted) {
      return;
    }
    state = state?.copyWith(video: !session.video);
    await _pushFlags();
  }

  /// Starts sharing [source], or stops sharing when it is null.
  Future<void> setScreenShare(VoiceScreenSource? source) async {
    final call = _call;
    if (state == null || call == null) {
      return;
    }
    await call.setScreenShareEnabled(
      source != null,
      sourceId: source?.sourceId,
    );
    if (!mounted) {
      return;
    }
    state = state?.copyWith(screen: source != null);
    await _pushFlags();
  }

  Future<void> _pushFlags() async {
    final session = state;
    if (session == null || !session.isConnected) {
      return;
    }
    try {
      await _sendFlags(session);
    } catch (_) {
      // The next heartbeat tries again.
    }
  }

  /// Sends the flags and heartbeat; false when the server dropped us.
  Future<bool> _sendFlags(VoiceSession session) {
    final callId = session.callId;
    if (session.isDirectCall) {
      if (callId == null) {
        return Future.value(false);
      }
      return _repository.updateDirectCallState(
        callId: callId,
        selfMute: session.selfMute,
        selfDeaf: session.selfDeaf,
        video: session.video,
        screen: session.screen,
      );
    }
    return _repository.updateVoiceState(
      selfMute: session.selfMute,
      selfDeaf: session.selfDeaf,
      video: session.video,
      screen: session.screen,
    );
  }

  Future<void> _beat() async {
    final session = state;
    if (session == null || !session.isConnected) {
      return;
    }
    final attempt = _attempt;
    try {
      final alive = await _sendFlags(session);
      if (attempt != _attempt) {
        return;
      }
      if (alive) {
        // Catches a move or server mute whose change event was missed.
        if (session.channelId != null) {
          await _syncOwnState();
        }
        return;
      }
      // The server dropped us (a missed heartbeat, lost access, or a
      // moderator disconnected us): join again, or give up when that is
      // refused (or the call ended).
      final channelId = session.channelId;
      final callId = session.callId;
      if (channelId != null) {
        final own = await _repository.fetchOwnVoiceState();
        if (own.disconnected) {
          if (attempt == _attempt) {
            await leave();
          }
          return;
        }
        await _repository.joinVoiceState(channelId);
      } else if (callId == null || !await _repository.joinDirectCall(callId)) {
        if (attempt == _attempt) {
          await leave();
        }
        return;
      }
      await _pushFlags();
    } on VoiceAccessDeniedException {
      if (attempt == _attempt) {
        await leave();
      }
    } on VoiceChannelFullException {
      if (attempt == _attempt) {
        await leave();
      }
    } catch (_) {
      // A network hiccup: the next heartbeat tries again.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(leave());
    super.dispose();
  }
}

/// Joins [channelId]; explains when voice is not set up or not allowed.
/// Returns whether the user ends up connected to it.
Future<bool> joinVoiceChannel(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String channelId,
  required String conversationId,
  required String channelName,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(voiceSessionProvider.notifier)
        .join(
          circleId: circleId,
          channelId: channelId,
          conversationId: conversationId,
          channelName: channelName,
        );
    return ref.read(voiceSessionProvider)?.channelId == channelId;
  } on VoiceNotConfiguredException {
    if (context.mounted) {
      await showVoiceNotConfiguredDialog(context);
    }
  } on VoiceAccessDeniedException {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tr("You don't have permission to join this voice channel."),
        ),
      ),
    );
  } on VoiceChannelFullException {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('This voice channel is full.'))),
    );
  } catch (error, stackTrace) {
    debugPrint('Voice join failed: $error\n$stackTrace');
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not connect to voice. Try again.'))),
    );
  }
  return false;
}

/// Calls in [conversationId] (joining the call already going on there);
/// explains when voice is not set up or calling is not allowed. Returns
/// whether the user ends up in the call.
Future<bool> startDirectCall(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required String name,
  bool video = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(voiceSessionProvider.notifier)
        .startCall(conversationId: conversationId, name: name, video: video);
    ref.invalidate(activeDirectCallsProvider);
    final session = ref.read(voiceSessionProvider);
    return session != null &&
        session.isDirectCall &&
        session.conversationId == conversationId;
  } on VoiceNotConfiguredException {
    if (context.mounted) {
      await showVoiceNotConfiguredDialog(context);
    }
  } on VoiceAccessDeniedException {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("You can't call in this conversation."))),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not start the call. Try again.'))),
    );
  }
  return false;
}

Future<void> showVoiceNotConfiguredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('voice-not-configured-dialog'),
      scrollable: true,
      icon: const Icon(Icons.headset_off_outlined),
      title: Text(tr("Voice service isn't configured yet")),
      content: Text(
        tr(
          'Voice and video calls need a LiveKit server, which this WeCord '
          'server does not have yet. Ask whoever runs it to add the LiveKit '
          'URL, API key and secret; voice channels work as soon as they do.',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('OK')),
        ),
      ],
    ),
  );
}
