import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    this.moderation,
    super.key,
  });

  final String channelId;
  final List<VoiceMemberState> members;

  /// What the current user may do to them from their menu.
  final VoiceModeration? moderation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speaking = voiceSpeakingUserIds(
      ref.watch(voiceSessionProvider),
      channelId,
    );
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id;
    return Column(
      key: ValueKey('voice-channel-members-$channelId'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in members)
          VoiceParticipantMenuRegion(
            person: VoiceMenuPerson(
              userId: member.userId,
              name: member.name,
              isLocal: member.userId == currentUserId,
              channelId: member.channelId,
              serverMute: member.serverMute,
              serverDeaf: member.serverDeaf,
            ),
            moderation: moderation,
            child: _VoiceMemberRow(
              member: member,
              speaking: speaking.contains(member.userId),
            ),
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
    final c = context.tokens.colors;
    final roleColor = member.roleColor;
    final touch = usesTouchInput(context);
    return Padding(
      key: ValueKey('voice-member-${member.userId}'),
      padding: const EdgeInsets.only(left: 30, top: 1, bottom: 1, right: 6),
      child: SizedBox(
        height: touch ? 34 : 28,
        child: Row(
          children: [
            VoiceSpeakingRing(
              speaking: speaking,
              child: VoiceAvatar(
                name: member.name,
                avatarUrl: member.avatarUrl,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: roleColor == null
                      ? (speaking ? c.ink : c.muted)
                      : Color(0xFF000000 | roleColor),
                  fontWeight: speaking ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (member.screen)
              _StateIcon(
                Icons.screen_share_outlined,
                tr('Sharing screen'),
                c.subtle,
              ),
            if (member.video)
              _StateIcon(Icons.videocam_outlined, tr('Camera on'), c.subtle),
            if (member.serverDeaf)
              _StateIcon(Icons.headset_off, tr('Server deafened'), c.danger)
            else if (member.selfDeaf)
              _StateIcon(Icons.headset_off_outlined, tr('Deafened'), c.subtle)
            else if (member.serverMute)
              _StateIcon(Icons.mic_off, tr('Server muted'), c.danger)
            else if (member.selfMute)
              _StateIcon(Icons.mic_off_outlined, tr('Muted'), c.subtle),
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

/// A green ring around [child] (a round avatar) while [speaking].
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
    final c = context.tokens.colors;
    return AnimatedContainer(
      key: speaking ? const ValueKey('voice-speaking-ring') : null,
      duration: WeCordMotion.durationOf(context, WeCordMotion.quick),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? c.success : c.success.withValues(alpha: 0),
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

/// The microphone button's tooltip: what pressing it does, or that a
/// moderator muted the current user.
String voiceMuteTooltip(VoiceSession session) {
  if (session.serverDeaf) {
    return tr('Server deafened');
  }
  if (session.serverMute) {
    return tr('Server muted');
  }
  return session.selfMute ? tr('Unmute') : tr('Mute');
}

/// The headset button's tooltip.
String voiceDeafenTooltip(VoiceSession session) {
  if (session.serverDeaf) {
    return tr('Server deafened');
  }
  return session.selfDeaf ? tr('Undeafen') : tr('Deafen');
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
/// disconnect while the current user is in a voice channel: a compact
/// glass pill shown above the user panel (and at the bottom of the channel
/// sidebar), so it stays while browsing. Tapping the channel calls
/// [onOpen].
class VoiceConnectedPanel extends ConsumerWidget {
  const VoiceConnectedPanel({this.onOpen, super.key});

  /// Opens the voice channel's view.
  final ValueChanged<VoiceSession>? onOpen;

  static const height = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    if (session == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final controller = ref.read(voiceSessionProvider.notifier);
    final connected = session.isConnected;
    final statusColor = connected ? c.successText : c.muted;
    final muted = session.selfMute || session.serverMute;
    final deafened = session.selfDeaf || session.serverDeaf;
    final touch = usesTouchInput(context);

    Widget panel(bool narrow) {
      final buttonSize = touch ? 38.0 : (narrow ? 30.0 : 34.0);
      final tileSize = narrow ? 18.0 : 38.0;
      Widget button({
        required String tooltip,
        required IconData icon,
        required Color fill,
        required Color foreground,
        required VoidCallback? onPressed,
      }) {
        return VoiceRoundButton(
          tooltip: tooltip,
          icon: icon,
          fill: fill,
          foreground: foreground,
          size: buttonSize,
          onPressed: onPressed,
        );
      }

      return WeCordGlass(
        key: const ValueKey('voice-connected-panel'),
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.only(left: 9, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: WeCordPressable(
                    onPressed: onOpen == null ? null : () => onOpen!(session),
                    pressedScale: 0.98,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                    builder: (context, states) => Row(
                      children: [
                        Tooltip(
                          message: connected
                              ? voiceQualityLabel(session.quality)
                              : tr('Connecting'),
                          child: Container(
                            width: tileSize,
                            height: tileSize,
                            decoration: ShapeDecoration(
                              color: narrow
                                  ? c.raised.withValues(alpha: 0)
                                  : connected
                                  ? c.successSoft
                                  : c.raised,
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: Icon(
                              voiceQualityIcon(session.quality),
                              key: const ValueKey('voice-quality-icon'),
                              size: 18,
                              color: statusColor,
                            ),
                          ),
                        ),
                        SizedBox(width: narrow ? 4 : 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                connected
                                    ? tr('Voice connected')
                                    : tr('Connecting…'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: narrow ? 12 : 13,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                              Text(
                                session.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                button(
                  tooltip: voiceMuteTooltip(session),
                  icon: muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  fill: muted ? c.dangerSoft : c.raised,
                  foreground: muted ? c.dangerText : c.ink,
                  onPressed: connected && !session.serverMute
                      ? () => runVoiceAction(context, controller.toggleMute)
                      : null,
                ),
                button(
                  tooltip: voiceDeafenTooltip(session),
                  icon: deafened
                      ? Icons.headset_off_rounded
                      : Icons.headset_outlined,
                  fill: deafened ? c.dangerSoft : c.raised,
                  foreground: deafened ? c.dangerText : c.ink,
                  onPressed: connected && !session.serverDeaf
                      ? () => runVoiceAction(context, controller.toggleDeafen)
                      : null,
                ),
                button(
                  tooltip: tr('Disconnect'),
                  icon: Icons.call_end_rounded,
                  fill: c.danger,
                  foreground: c.onDanger,
                  onPressed: controller.leave,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => panel(constraints.maxWidth < 300),
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
    final c = context.tokens.colors;
    final controller = ref.read(voiceSessionProvider.notifier);
    final muted = session.selfMute || session.serverMute;
    return Padding(
      key: const ValueKey('voice-rail-indicator'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VoiceRoundButton(
            tooltip: tr('Voice connected: {channel}', {
              'channel': session.channelName,
            }),
            icon: Icons.volume_up_rounded,
            fill: c.successSoft,
            foreground: c.successText,
            size: 40,
            onPressed: onOpen == null ? null : () => onOpen!(session),
          ),
          VoiceRoundButton(
            tooltip: voiceMuteTooltip(session),
            icon: muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            fill: muted ? c.dangerSoft : c.railItem,
            foreground: muted ? c.dangerText : c.ink,
            size: 36,
            onPressed: session.isConnected && !session.serverMute
                ? () => runVoiceAction(context, controller.toggleMute)
                : null,
          ),
          VoiceRoundButton(
            tooltip: tr('Disconnect'),
            icon: Icons.call_end_rounded,
            fill: c.danger,
            foreground: c.onDanger,
            size: 36,
            onPressed: controller.leave,
          ),
        ],
      ),
    );
  }
}

/// "2/5" after a voice channel with a user limit: who is in it, of how many
/// it takes.
class VoiceUserLimitBadge extends StatelessWidget {
  const VoiceUserLimitBadge({
    required this.count,
    required this.limit,
    super.key,
  });

  final int count;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final full = count >= limit;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: full
            ? tr('Full: {count} of {limit}', {'count': count, 'limit': limit})
            : tr('{count} of {limit}', {'count': count, 'limit': limit}),
        child: Container(
          key: const ValueKey('voice-user-limit-badge'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: full ? c.dangerSoft : c.raised,
            borderRadius: BorderRadius.circular(WeCordRadii.xs),
          ),
          child: Text(
            '${count.toString().padLeft(2, '0')}/'
            '${limit.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: full ? c.dangerText : c.subtle,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
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
