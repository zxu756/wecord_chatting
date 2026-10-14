import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/voice/livekit_voice_call.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';

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
    );
  }
}

/// Connects to voice channels and keeps the server's voice state in step:
/// joins it, heartbeats every [voiceHeartbeatInterval] with the current
/// mute / deafen / video / screen flags, and leaves it on disconnect.
class VoiceSessionController extends StateNotifier<VoiceSession?> {
  VoiceSessionController({
    required VoiceRepository repository,
    required VoiceCallConnector connector,
    void Function(VoiceSession session)? onMembersChanged,
  }) : _repository = repository,
       _connector = connector,
       _onMembersChanged = onMembersChanged,
       super(null);

  final VoiceRepository _repository;
  final VoiceCallConnector _connector;
  final void Function(VoiceSession session)? _onMembersChanged;

  VoiceCall? _call;
  Timer? _heartbeat;
  AppLifecycleListener? _lifecycle;

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
      call = await _connector.connect(
        url: details.url,
        token: details.token,
        microphoneEnabled: true,
      );
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
      final details = await _repository.fetchCallConnectionDetails(callId);
      if (attempt != _attempt) {
        unawaited(_leaveCallQuietly(callId));
        return;
      }
      call = await _connector.connect(
        url: details.url,
        token: details.token,
        microphoneEnabled: true,
      );
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

  Future<void> _leaveCallQuietly(String callId) async {
    try {
      await _repository.leaveDirectCall(callId);
    } catch (_) {
      // The server drops it after a minute without heartbeats.
    }
  }

  void _connected(VoiceCall call) {
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
    state = state?.copyWith(
      status: VoiceSessionStatus.connected,
      selfMute: !(local?.microphoneEnabled ?? false),
      participants: call.participants,
      quality: call.quality,
    );
    _heartbeat = Timer.periodic(voiceHeartbeatInterval, (_) => _beat());
    _lifecycle = AppLifecycleListener(onDetach: () => unawaited(leave()));
    if (state?.selfMute == true) {
      unawaited(_pushFlags());
    }
    final session = state;
    if (session != null) {
      _membersChanged(session);
    }
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
    final call = _call;
    _call = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    if (session == null) {
      return;
    }
    state = null;
    call?.removeListener(_syncFromCall);
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
      await call.setRemoteAudioEnabled(true);
      await call.setMicrophoneEnabled(true);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfMute: false, selfDeaf: false);
    } else {
      await call.setMicrophoneEnabled(session.selfMute);
      if (!mounted) {
        return;
      }
      state = state?.copyWith(selfMute: !session.selfMute);
    }
    await _pushFlags();
  }

  Future<void> toggleDeafen() async {
    final session = state;
    final call = _call;
    if (session == null || call == null) {
      return;
    }
    if (session.selfDeaf) {
      await call.setRemoteAudioEnabled(true);
      await call.setMicrophoneEnabled(!_mutedBeforeDeafen);
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
      if (alive || attempt != _attempt) {
        return;
      }
      // The server dropped us (a missed heartbeat or lost access): join
      // again, or give up when that is refused (or the call ended).
      final channelId = session.channelId;
      final callId = session.callId;
      if (channelId != null) {
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
      const SnackBar(
        content: Text("You don't have permission to join this voice channel."),
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not connect to voice. Try again.')),
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
      const SnackBar(content: Text("You can't call in this conversation.")),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not start the call. Try again.')),
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
      title: const Text("Voice service isn't configured yet"),
      content: const Text(
        'Voice and video calls need a LiveKit server, which this WeCord '
        'server does not have yet. Ask whoever runs it to add the LiveKit '
        'URL, API key and secret; voice channels work as soon as they do.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
