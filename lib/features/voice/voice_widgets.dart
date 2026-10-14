import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/voice.dart';

/// Colour of "connected" and of the speaking ring.
const voiceConnectedColor = Color(0xFF23A55A);

/// The user ids speaking right now in the current user's call to
/// [channelId]; empty when not connected there.
Set<String> voiceSpeakingUserIds(VoiceSession? session, String channelId) {
  if (session == null || session.channelId != channelId) {
    return const {};
  }
  return {
    for (final participant in session.participants)
      if (participant.isSpeaking) participant.userId,
  };
}

/// The members connected to a voice channel, listed under it in the
/// channel sidebar: avatar (ringed while speaking), name, and their mute,
/// deafen, camera and screen share icons.
class VoiceChannelMembers extends ConsumerWidget {
  const VoiceChannelMembers({
    required this.channelId,
    required this.members,
    super.key,
  });

  final String channelId;
  final List<VoiceMemberState> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speaking = voiceSpeakingUserIds(
      ref.watch(voiceSessionProvider),
      channelId,
    );
    return Column(
      key: ValueKey('voice-channel-members-$channelId'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in members)
          _VoiceMemberRow(
            member: member,
            speaking: speaking.contains(member.userId),
          ),
      ],
    );
  }
}

class _VoiceMemberRow extends StatelessWidget {
  const _VoiceMemberRow({required this.member, required this.speaking});

  final VoiceMemberState member;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurfaceVariant;
    final roleColor = member.roleColor;
    return Padding(
      key: ValueKey('voice-member-${member.userId}'),
      padding: const EdgeInsets.only(left: 28, top: 2, bottom: 2, right: 4),
      child: SizedBox(
        height: usesTouchInput(context) ? 32 : 26,
        child: Row(
          children: [
            VoiceSpeakingRing(
              speaking: speaking,
              child: FallbackAvatar(
                title: member.name,
                avatarUrl: member.avatarUrl,
                radius: 10,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: roleColor == null
                      ? colorScheme.onSurfaceVariant
                      : Color(0xFF000000 | roleColor),
                  fontWeight: speaking ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (member.screen)
              _StateIcon(
                Icons.screen_share_outlined,
                tr('Sharing screen'),
                muted,
              ),
            if (member.video)
              _StateIcon(Icons.videocam_outlined, tr('Camera on'), muted),
            if (member.selfDeaf)
              _StateIcon(Icons.headset_off_outlined, tr('Deafened'), muted)
            else if (member.selfMute)
              _StateIcon(Icons.mic_off_outlined, tr('Muted'), muted),
          ],
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }
}

/// A green ring around [child] while [speaking].
class VoiceSpeakingRing extends StatelessWidget {
  const VoiceSpeakingRing({
    required this.speaking,
    required this.child,
    super.key,
  });

  final bool speaking;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: speaking ? const ValueKey('voice-speaking-ring') : null,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? voiceConnectedColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

/// Runs a call control, saying so when it fails.
Future<void> runVoiceAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not change the call. Try again.'))),
    );
  }
}

IconData voiceQualityIcon(VoiceConnectionQuality quality) {
  return switch (quality) {
    VoiceConnectionQuality.excellent => Icons.signal_cellular_alt,
    VoiceConnectionQuality.good => Icons.signal_cellular_alt_2_bar,
    VoiceConnectionQuality.poor => Icons.signal_cellular_alt_1_bar,
    VoiceConnectionQuality.lost =>
      Icons.signal_cellular_connected_no_internet_0_bar,
    VoiceConnectionQuality.unknown => Icons.signal_cellular_alt,
  };
}

String voiceQualityLabel(VoiceConnectionQuality quality) {
  return switch (quality) {
    VoiceConnectionQuality.excellent => tr('Excellent connection'),
    VoiceConnectionQuality.good => tr('Good connection'),
    VoiceConnectionQuality.poor => tr('Poor connection'),
    VoiceConnectionQuality.lost => tr('Connection lost'),
    VoiceConnectionQuality.unknown => tr('Connection quality unknown'),
  };
}

/// "Voice connected", the channel, connection quality and mute / deafen /
/// disconnect, while the current user is in a voice channel. Shown at the
/// bottom of the channel sidebar and above the phone navigation bar, so it
/// stays while browsing. Tapping the channel name calls [onOpen].
class VoiceConnectedPanel extends ConsumerWidget {
  const VoiceConnectedPanel({this.onOpen, super.key});

  /// Opens the voice channel's view.
  final ValueChanged<VoiceSession>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    if (session == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final controller = ref.read(voiceSessionProvider.notifier);
    final connected = session.isConnected;
    final statusColor = connected
        ? voiceConnectedColor
        : colorScheme.onSurfaceVariant;

    return Material(
      key: const ValueKey('voice-connected-panel'),
      color: colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onOpen == null ? null : () => onOpen!(session),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Tooltip(
                              message: connected
                                  ? voiceQualityLabel(session.quality)
                                  : tr('Connecting'),
                              child: Icon(
                                voiceQualityIcon(session.quality),
                                key: const ValueKey('voice-quality-icon'),
                                size: 16,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                connected
                                    ? tr('Voice connected')
                                    : tr('Connecting…'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          session.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _PanelButton(
                tooltip: session.selfMute ? tr('Unmute') : tr('Mute'),
                icon: session.selfMute ? Icons.mic_off : Icons.mic_none,
                active: session.selfMute,
                onPressed: connected
                    ? () => runVoiceAction(context, controller.toggleMute)
                    : null,
              ),
              _PanelButton(
                tooltip: session.selfDeaf ? tr('Undeafen') : tr('Deafen'),
                icon: session.selfDeaf
                    ? Icons.headset_off
                    : Icons.headset_outlined,
                active: session.selfDeaf,
                onPressed: connected
                    ? () => runVoiceAction(context, controller.toggleDeafen)
                    : null,
              ),
              _PanelButton(
                tooltip: tr('Disconnect'),
                icon: Icons.call_end,
                onPressed: controller.leave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Muted or deafened: drawn in the error colour.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: usesTouchInput(context) ? null : VisualDensity.compact,
      color: active ? Theme.of(context).colorScheme.error : null,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    );
  }
}

/// A small "in voice" button for the navigation rail, shown where the
/// channel sidebar (and its panel) is not.
class VoiceRailIndicator extends ConsumerWidget {
  const VoiceRailIndicator({this.onOpen, super.key});

  final ValueChanged<VoiceSession>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    if (session == null) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(voiceSessionProvider.notifier);
    return Padding(
      key: const ValueKey('voice-rail-indicator'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            tooltip: tr('Voice connected: {channel}', {
              'channel': session.channelName,
            }),
            style: IconButton.styleFrom(foregroundColor: voiceConnectedColor),
            onPressed: onOpen == null ? null : () => onOpen!(session),
            icon: const Icon(Icons.volume_up),
          ),
          IconButton(
            tooltip: session.selfMute ? tr('Unmute') : tr('Mute'),
            color: session.selfMute
                ? Theme.of(context).colorScheme.error
                : null,
            onPressed: session.isConnected
                ? () => runVoiceAction(context, controller.toggleMute)
                : null,
            icon: Icon(session.selfMute ? Icons.mic_off : Icons.mic_none),
          ),
          IconButton(
            tooltip: tr('Disconnect'),
            onPressed: controller.leave,
            icon: const Icon(Icons.call_end),
          ),
        ],
      ),
    );
  }
}

/// The members in [channelId] from [states].
List<VoiceMemberState> voiceMembersIn(
  List<VoiceMemberState> states,
  String channelId,
) {
  return [
    for (final state in states)
      if (state.channelId == channelId) state,
  ];
}

/// Watches who is in the circle's voice channels; empty while loading.
List<VoiceMemberState> watchVoiceStates(WidgetRef ref, String circleId) {
  return ref.watch(voiceStatesProvider(circleId)).valueOrNull ?? const [];
}
