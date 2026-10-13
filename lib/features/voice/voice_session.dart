import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
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

/// The voice channel the current user is connected to, if any. It lives
/// for the whole app, so moving between channels and circles keeps the
/// call; signing out ends it.
final voiceSessionProvider =
    StateNotifierProvider<VoiceSessionController, VoiceSession?>((ref) {
      final controller = VoiceSessionController(
        repository: ref.watch(voiceRepositoryProvider),
        connector: ref.watch(voiceCallConnectorProvider),
        onMembersChanged: (circleId) =>
            ref.invalidate(voiceStatesProvider(circleId)),
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

/// How often a connected client tells the server it is still there.
const voiceHeartbeatInterval = Duration(seconds: 20);

enum VoiceSessionStatus { connecting, connected }

@immutable
class VoiceSession {
  const VoiceSession({
    required this.circleId,
    required this.channelId,
    required this.conversationId,
    required this.channelName,
    this.status = VoiceSessionStatus.connecting,
    this.selfMute = false,
    this.selfDeaf = false,
    this.video = false,
    this.screen = false,
    this.participants = const [],
    this.quality = VoiceConnectionQuality.unknown,
  });

  final String circleId;
  final String channelId;

  /// The channel's conversation, which names its route.
  final String conversationId;
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

  VoiceSession copyWith({
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
    void Function(String circleId)? onMembersChanged,
  }) : _repository = repository,
       _connector = connector,
       _onMembersChanged = onMembersChanged,
       super(null);

  final VoiceRepository _repository;
  final VoiceCallConnector _connector;
  final void Function(String circleId)? _onMembersChanged;

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

  void _membersChanged(String circleId) {
    if (!_disposed) {
      _onMembersChanged?.call(circleId);
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
    _membersChanged(circleId);
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
    try {
      await _repository.leaveVoiceState();
    } catch (_) {
      // The server drops it after a minute without heartbeats.
    }
    _membersChanged(session.circleId);
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
      await _repository.updateVoiceState(
        selfMute: session.selfMute,
        selfDeaf: session.selfDeaf,
        video: session.video,
        screen: session.screen,
      );
    } catch (_) {
      // The next heartbeat tries again.
    }
  }

  Future<void> _beat() async {
    final session = state;
    if (session == null || !session.isConnected) {
      return;
    }
    final attempt = _attempt;
    try {
      final alive = await _repository.updateVoiceState(
        selfMute: session.selfMute,
        selfDeaf: session.selfDeaf,
        video: session.video,
        screen: session.screen,
      );
      if (alive || attempt != _attempt) {
        return;
      }
      // The server dropped us (a missed heartbeat or lost access): join
      // again, or give up when that is refused.
      await _repository.joinVoiceState(session.channelId);
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
