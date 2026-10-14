import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/models/voice.dart';

/// A voice channel: while the current user is connected to it, everyone in
/// the call (video when they publish it, the shared screen larger) and the
/// call controls; otherwise who is there and a Join button.
class VoiceChannelView extends ConsumerWidget {
  const VoiceChannelView({
    required this.circleId,
    required this.channelId,
    required this.conversationId,
    required this.channelName,
    this.canConnect = true,
    this.actions = const [],
    this.onBack,
    super.key,
  });

  final String circleId;
  final String channelId;
  final String conversationId;
  final String channelName;

  /// Whether the current user has connect_voice here.
  final bool canConnect;
  final List<ChatThreadAction> actions;

  /// Shows a back button calling this, when set.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final here = session != null && session.channelId == channelId;
    final members = voiceMembersIn(watchVoiceStates(ref, circleId), channelId);

    final Widget body;
    if (here && session.isConnected) {
      body = VoiceCallGrid(
        session: session,
        people: {
          for (final member in members)
            member.userId: (
              name: member.name,
              avatarUrl: member.avatarUrl,
              selfDeaf: member.selfDeaf,
            ),
        },
      );
    } else if (here) {
      body = const Center(
        key: ValueKey('voice-connecting'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Connecting…'),
          ],
        ),
      );
    } else {
      body = _NotConnected(
        members: members,
        canConnect: canConnect,
        onJoin: () => joinVoiceChannel(
          context,
          ref,
          circleId: circleId,
          channelId: channelId,
          conversationId: conversationId,
          channelName: channelName,
        ),
      );
    }

    return Scaffold(
      key: ValueKey('voice-channel-view-$channelId'),
      appBar: AppBar(
        automaticallyImplyLeading: onBack == null,
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
        title: Row(
          children: [
            const Icon(Icons.volume_up_outlined, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [for (final action in actions) action.toIconButton()],
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (here && session.isConnected)
            SizedBox(
              width: double.infinity,
              child: VoiceCallControls(session: session),
            ),
        ],
      ),
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({
    required this.members,
    required this.canConnect,
    required this.onJoin,
  });

  final List<VoiceMemberState> members;
  final bool canConnect;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('voice-not-connected'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              members.isEmpty
                  ? 'No one is here yet.'
                  : members.length == 1
                  ? '1 person is here'
                  : '${members.length} people are here',
              style: theme.textTheme.titleMedium,
            ),
            if (members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final member in members)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FallbackAvatar(
                          title: member.name,
                          avatarUrl: member.avatarUrl,
                          radius: 20,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (canConnect)
              FilledButton.icon(
                key: const ValueKey('voice-join-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: voiceConnectedColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: onJoin,
                icon: const Icon(Icons.call),
                label: const Text('Join voice'),
              )
            else
              Text(
                "You don't have permission to join this voice channel.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}

/// What the server knows about someone in a call: the name and avatar to
/// show, and whether they deafened themselves.
typedef VoiceCallPerson = ({String name, String? avatarUrl, bool selfDeaf});

/// Everyone in the call: shared screens first and wide, then a tile per
/// person (their camera, or their avatar), outlined while they speak.
class VoiceCallGrid extends StatelessWidget {
  const VoiceCallGrid({required this.session, required this.people, super.key});

  final VoiceSession session;

  /// The server's view of each participant, by user id.
  final Map<String, VoiceCallPerson> people;

  @override
  Widget build(BuildContext context) {
    final participants = session.participants;
    final screens = [
      for (final participant in participants)
        if (participant.screenView != null) participant,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const padding = 12.0;
        final width = constraints.maxWidth - padding * 2;
        final columns = width < 420
            ? 2
            : width < 760
            ? 3
            : 4;
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        return SingleChildScrollView(
          key: const ValueKey('voice-call-grid'),
          padding: const EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final participant in screens) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _Tile(
                    key: ValueKey('voice-screen-tile-${participant.userId}'),
                    label:
                        '${people[participant.userId]?.name ?? participant.name}'
                        "'s screen",
                    speaking: false,
                    child: ColoredBox(
                      color: Colors.black,
                      child: participant.screenView!(context),
                    ),
                  ),
                ),
                const SizedBox(height: spacing),
              ],
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final participant in participants)
                    SizedBox(
                      width: tileWidth,
                      height: tileWidth * 10 / 16,
                      child: _ParticipantTile(
                        participant: participant,
                        name:
                            people[participant.userId]?.name ??
                            participant.name,
                        avatarUrl: people[participant.userId]?.avatarUrl,
                        deafened:
                            (participant.isLocal && session.selfDeaf) ||
                            (people[participant.userId]?.selfDeaf ?? false),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.name,
    required this.avatarUrl,
    required this.deafened,
  });

  final VoiceCallParticipant participant;
  final String name;
  final String? avatarUrl;
  final bool deafened;

  @override
  Widget build(BuildContext context) {
    final camera = participant.cameraView;
    return _Tile(
      key: ValueKey('voice-tile-${participant.userId}'),
      label: participant.isLocal ? '$name (you)' : name,
      speaking: participant.isSpeaking,
      trailing: deafened
          ? Icons.headset_off
          : participant.microphoneEnabled
          ? null
          : Icons.mic_off,
      child: camera != null
          ? camera(context)
          // Above the name label at the bottom.
          : Align(
              alignment: const Alignment(0, -0.3),
              child: LayoutBuilder(
                builder: (context, constraints) => FallbackAvatar(
                  title: name,
                  avatarUrl: avatarUrl,
                  radius: (constraints.biggest.shortestSide * 0.22).clamp(
                    14.0,
                    44.0,
                  ),
                ),
              ),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.speaking,
    required this.child,
    this.trailing,
    super.key,
  });

  final String label;
  final bool speaking;
  final Widget child;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: speaking ? voiceConnectedColor : Colors.transparent,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (speaking)
            const SizedBox.shrink(key: ValueKey('voice-tile-speaking')),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (trailing != null) ...[
                          Icon(trailing, size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Microphone, deafen, camera, screen share (where the platform can) and
/// disconnect.
class VoiceCallControls extends ConsumerStatefulWidget {
  const VoiceCallControls({required this.session, super.key});

  final VoiceSession session;

  @override
  ConsumerState<VoiceCallControls> createState() => _VoiceCallControlsState();
}

class _VoiceCallControlsState extends ConsumerState<VoiceCallControls> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleScreenShare() async {
    final controller = ref.read(voiceSessionProvider.notifier);
    if (widget.session.screen) {
      await controller.setScreenShare(null);
      return;
    }
    final source = await ref.read(voiceScreenSourcePickerProvider)(context);
    if (source != null) {
      await controller.setScreenShare(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final controller = ref.read(voiceSessionProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final canShareScreen = ref.watch(voiceScreenShareSupportedProvider);

    Widget toggle({
      required String tooltip,
      required IconData icon,
      required bool on,
      required VoidCallback? onPressed,
      Key? key,
    }) {
      return IconButton.filledTonal(
        key: key,
        tooltip: tooltip,
        isSelected: on,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: on ? colorScheme.inverseSurface : null,
          foregroundColor: on ? colorScheme.onInverseSurface : null,
        ),
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon),
      );
    }

    return Material(
      key: const ValueKey('voice-call-controls'),
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              toggle(
                key: const ValueKey('voice-control-mic'),
                tooltip: session.selfMute ? 'Unmute' : 'Mute',
                icon: session.selfMute ? Icons.mic_off : Icons.mic_none,
                on: session.selfMute,
                onPressed: () => _run(
                  controller.toggleMute,
                  'Could not change the microphone.',
                ),
              ),
              toggle(
                key: const ValueKey('voice-control-deafen'),
                tooltip: session.selfDeaf ? 'Undeafen' : 'Deafen',
                icon: session.selfDeaf
                    ? Icons.headset_off
                    : Icons.headset_outlined,
                on: session.selfDeaf,
                onPressed: () =>
                    _run(controller.toggleDeafen, 'Could not deafen.'),
              ),
              toggle(
                key: const ValueKey('voice-control-camera'),
                tooltip: session.video ? 'Turn off camera' : 'Turn on camera',
                icon: session.video
                    ? Icons.videocam_outlined
                    : Icons.videocam_off_outlined,
                on: session.video,
                onPressed: () => _run(
                  controller.toggleCamera,
                  'Could not use the camera. Check the camera permission.',
                ),
              ),
              if (canShareScreen)
                toggle(
                  key: const ValueKey('voice-control-screen'),
                  tooltip: session.screen ? 'Stop sharing' : 'Share screen',
                  icon: session.screen
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
                  on: session.screen,
                  onPressed: () =>
                      _run(_toggleScreenShare, 'Could not share the screen.'),
                ),
              IconButton.filled(
                key: const ValueKey('voice-control-leave'),
                tooltip: 'Disconnect',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: controller.leave,
                icon: const Icon(Icons.call_end),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
