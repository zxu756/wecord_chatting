import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/voice/soundboard_sheet.dart';
import 'package:wecord/features/voice/stage_channel_view.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';

/// From this width the voice view shows its chat beside the call; below
/// it the chat opens full screen.
const voiceChatPanelBreakpoint = 760.0;

/// How wide the chat beside the call is.
const voiceChatPanelWidth = 360.0;

/// A voice channel: while the current user is connected to it, everyone in
/// the call (video when they publish it, the shared screen larger) and the
/// call controls; otherwise who is there and a Join button. The chat button
/// opens the channel's own text chat, beside the call on wide screens.
/// A stage shows its speakers above its audience instead ([StageView]).
class VoiceChannelView extends ConsumerStatefulWidget {
  const VoiceChannelView({
    required this.circleId,
    required this.channelId,
    required this.conversationId,
    required this.channelName,
    this.canConnect = true,
    this.actions = const [],
    this.onBack,
    this.moderation,
    this.chatBuilder,
    this.initialChatOpen = false,
    this.isStage = false,
    this.stageModerator = false,
    this.canManageSounds = false,
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

  /// What the current user may do to participants from their menu.
  final VoiceModeration? moderation;

  /// Builds the channel's text chat; no chat button without it.
  final WidgetBuilder? chatBuilder;

  /// Starts with the chat open beside the call (on wide screens).
  final bool initialChatOpen;

  /// The channel is a stage.
  final bool isStage;

  /// The current user moderates the stage (Mute Members and Move Members).
  final bool stageModerator;

  /// The current user adds and deletes the circle's soundboard sounds
  /// (Manage Emoji).
  final bool canManageSounds;

  @override
  ConsumerState<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends ConsumerState<VoiceChannelView> {
  late var _chatOpen = widget.initialChatOpen;

  void _toggleChat(bool wide) {
    final builder = widget.chatBuilder;
    if (builder == null) {
      return;
    }
    if (wide) {
      setState(() => _chatOpen = !_chatOpen);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => KeyedSubtree(
          key: ValueKey('voice-chat-page-${widget.channelId}'),
          child: builder(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(voiceSessionProvider);
    final channelId = widget.channelId;
    final here = session != null && session.channelId == channelId;
    final members = voiceMembersIn(
      watchVoiceStates(ref, widget.circleId),
      channelId,
    );
    final chatBuilder = widget.chatBuilder;
    final unread = chatBuilder == null
        ? 0
        : (ref.watch(conversationsProvider).valueOrNull ??
                      const <ConversationSummary>[])
                  .where(
                    (conversation) => conversation.id == widget.conversationId,
                  )
                  .map((conversation) => conversation.unreadCount)
                  .firstOrNull ??
              0;

    final Widget body;
    if (widget.isStage && here && session.isConnected) {
      body = StageView(
        session: session,
        circleId: widget.circleId,
        channelId: channelId,
        members: members,
        moderator: widget.stageModerator,
      );
    } else if (widget.isStage && !here) {
      body = StageLobby(
        circleId: widget.circleId,
        channelId: channelId,
        members: members,
        canConnect: widget.canConnect,
        onJoin: () => joinVoiceChannel(
          context,
          ref,
          circleId: widget.circleId,
          channelId: channelId,
          conversationId: widget.conversationId,
          channelName: widget.channelName,
        ),
      );
    } else if (here && session.isConnected) {
      body = VoiceCallGrid(
        session: session,
        moderation: widget.moderation,
        people: {
          for (final member in members)
            member.userId: (
              name: member.name,
              avatarUrl: member.avatarUrl,
              selfDeaf: member.selfDeaf,
              serverMute: member.serverMute,
              serverDeaf: member.serverDeaf,
            ),
        },
      );
    } else if (here) {
      body = Center(
        key: const ValueKey('voice-connecting'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr('Connecting…')),
          ],
        ),
      );
    } else {
      body = _NotConnected(
        members: members,
        canConnect: widget.canConnect,
        onJoin: () => joinVoiceChannel(
          context,
          ref,
          circleId: widget.circleId,
          channelId: channelId,
          conversationId: widget.conversationId,
          channelName: widget.channelName,
        ),
      );
    }

    final call = Column(
      children: [
        Expanded(child: body),
        if (here && session.isConnected)
          SizedBox(
            width: double.infinity,
            child: widget.isStage
                ? StageControls(
                    session: session,
                    circleId: widget.circleId,
                    channelId: channelId,
                    moderator: widget.stageModerator,
                    soundboard: (
                      circleId: widget.circleId,
                      canManage: widget.canManageSounds,
                    ),
                  )
                : VoiceCallControls(
                    session: session,
                    soundboard: (
                      circleId: widget.circleId,
                      canManage: widget.canManageSounds,
                    ),
                  ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= voiceChatPanelBreakpoint;
        final showPanel = wide && _chatOpen && chatBuilder != null;
        final chatButton = chatBuilder == null
            ? null
            : IconButton(
                key: const ValueKey('voice-chat-button'),
                tooltip: showPanel ? tr('Hide chat') : tr('Show chat'),
                isSelected: showPanel,
                onPressed: () => _toggleChat(wide),
                icon: Badge(
                  key: unread > 0
                      ? const ValueKey('voice-chat-unread-badge')
                      : null,
                  isLabelVisible: unread > 0 && !showPanel,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: Icon(
                    showPanel ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  ),
                ),
              );
        return Scaffold(
          key: ValueKey('voice-channel-view-$channelId'),
          appBar: AppBar(
            automaticallyImplyLeading: widget.onBack == null,
            leading: widget.onBack == null
                ? null
                : IconButton(
                    tooltip: tr('Back'),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  ),
            title: Row(
              children: [
                Icon(
                  widget.isStage ? Icons.podcasts : Icons.volume_up_outlined,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              ?chatButton,
              for (final action in widget.actions) action.toIconButton(),
            ],
          ),
          body: showPanel
              ? Row(
                  children: [
                    Expanded(child: call),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      key: ValueKey('voice-chat-panel-$channelId'),
                      width: voiceChatPanelWidth,
                      child: chatBuilder(context),
                    ),
                  ],
                )
              : call,
        );
      },
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
                  ? tr('No one is here yet.')
                  : members.length == 1
                  ? tr('1 person is here')
                  : tr('{count} people are here', {'count': members.length}),
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
                label: Text(tr('Join voice')),
              )
            else
              Text(
                tr("You don't have permission to join this voice channel."),
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
/// show, whether they deafened themselves, and whether a moderator muted or
/// deafened them.
typedef VoiceCallPerson = ({
  String name,
  String? avatarUrl,
  bool selfDeaf,
  bool serverMute,
  bool serverDeaf,
});

/// Everyone in the call: shared screens first and wide, then a tile per
/// person (their camera, or their avatar), outlined while they speak.
/// Right-click or long-press opens a person's menu.
class VoiceCallGrid extends StatelessWidget {
  const VoiceCallGrid({
    required this.session,
    required this.people,
    this.moderation,
    super.key,
  });

  final VoiceSession session;

  /// The server's view of each participant, by user id.
  final Map<String, VoiceCallPerson> people;

  /// What the current user may do to people from their menu.
  final VoiceModeration? moderation;

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
                    label: tr("{name}'s screen", {
                      'name':
                          people[participant.userId]?.name ?? participant.name,
                    }),
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
                      child: VoiceParticipantMenuRegion(
                        person: VoiceMenuPerson(
                          userId: participant.userId,
                          name:
                              people[participant.userId]?.name ??
                              participant.name,
                          isLocal: participant.isLocal,
                          channelId: session.channelId,
                          serverMute:
                              people[participant.userId]?.serverMute ?? false,
                          serverDeaf:
                              people[participant.userId]?.serverDeaf ?? false,
                        ),
                        moderation: moderation,
                        child: _ParticipantTile(
                          participant: participant,
                          name:
                              people[participant.userId]?.name ??
                              participant.name,
                          avatarUrl: people[participant.userId]?.avatarUrl,
                          deafened:
                              (participant.isLocal && session.selfDeaf) ||
                              (people[participant.userId]?.selfDeaf ?? false),
                          serverDeafened:
                              (participant.isLocal && session.serverDeaf) ||
                              (people[participant.userId]?.serverDeaf ?? false),
                          serverMuted:
                              (participant.isLocal && session.serverMute) ||
                              (people[participant.userId]?.serverMute ?? false),
                        ),
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
    this.serverMuted = false,
    this.serverDeafened = false,
  });

  final VoiceCallParticipant participant;
  final String name;
  final String? avatarUrl;
  final bool deafened;
  final bool serverMuted;
  final bool serverDeafened;

  @override
  Widget build(BuildContext context) {
    final camera = participant.cameraView;
    return _Tile(
      key: ValueKey('voice-tile-${participant.userId}'),
      label: participant.isLocal ? tr('{name} (you)', {'name': name}) : name,
      speaking: participant.isSpeaking,
      trailingKey: serverDeafened || serverMuted
          ? const ValueKey('voice-tile-server-silenced')
          : null,
      trailingColor: serverDeafened || serverMuted
          ? Theme.of(context).colorScheme.errorContainer
          : null,
      trailing: deafened || serverDeafened
          ? Icons.headset_off
          : serverMuted || !participant.microphoneEnabled
          ? Icons.mic_off
          : null,
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
    this.trailingColor,
    this.trailingKey,
    super.key,
  });

  final String label;
  final bool speaking;
  final Widget child;
  final IconData? trailing;
  final Color? trailingColor;
  final Key? trailingKey;

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
                          Icon(
                            trailing,
                            key: trailingKey,
                            size: 12,
                            color: trailingColor ?? Colors.white,
                          ),
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

/// Microphone, deafen, camera, screen share (where the platform can), the
/// soundboard (in circle voice channels) and disconnect; with push to talk
/// on a phone (or without a key set), a button to hold while talking.
class VoiceCallControls extends ConsumerStatefulWidget {
  const VoiceCallControls({required this.session, this.soundboard, super.key});

  final VoiceSession session;

  /// The circle's soundboard; none in direct and group calls.
  final SoundboardAccess? soundboard;

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

    final hasKey = ref.watch(
      voiceSettingsProvider.select(
        (settings) => settings.pushToTalkKeyId != null,
      ),
    );
    final holdToTalk =
        session.pushToTalk && (usesTouchInput(context) || !hasKey);

    return Material(
      key: const ValueKey('voice-call-controls'),
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (holdToTalk)
                VoiceHoldToTalkButton(session: session, enabled: !_busy),
              toggle(
                key: const ValueKey('voice-control-mic'),
                tooltip: voiceMuteTooltip(session),
                icon: session.selfMute || session.serverMute
                    ? Icons.mic_off
                    : Icons.mic_none,
                on: session.selfMute || session.serverMute,
                onPressed: session.serverMute
                    ? null
                    : () => _run(
                        controller.toggleMute,
                        tr('Could not change the microphone.'),
                      ),
              ),
              toggle(
                key: const ValueKey('voice-control-deafen'),
                tooltip: voiceDeafenTooltip(session),
                icon: session.selfDeaf || session.serverDeaf
                    ? Icons.headset_off
                    : Icons.headset_outlined,
                on: session.selfDeaf || session.serverDeaf,
                onPressed: session.serverDeaf
                    ? null
                    : () => _run(
                        controller.toggleDeafen,
                        tr('Could not deafen.'),
                      ),
              ),
              toggle(
                key: const ValueKey('voice-control-camera'),
                tooltip: session.video
                    ? tr('Turn off camera')
                    : tr('Turn on camera'),
                icon: session.video
                    ? Icons.videocam_outlined
                    : Icons.videocam_off_outlined,
                on: session.video,
                onPressed: () => _run(
                  controller.toggleCamera,
                  tr('Could not use the camera. Check the camera permission.'),
                ),
              ),
              if (canShareScreen)
                toggle(
                  key: const ValueKey('voice-control-screen'),
                  tooltip: session.screen
                      ? tr('Stop sharing')
                      : tr('Share screen'),
                  icon: session.screen
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
                  on: session.screen,
                  onPressed: () => _run(
                    _toggleScreenShare,
                    tr('Could not share the screen.'),
                  ),
                ),
              if (widget.soundboard case final soundboard?
                  when session.channelId != null)
                toggle(
                  key: const ValueKey('voice-control-soundboard'),
                  tooltip: tr('Soundboard'),
                  icon: Icons.music_note_outlined,
                  on: false,
                  onPressed: () => showSoundboard(
                    context,
                    access: soundboard,
                    channelId: session.channelId!,
                  ),
                ),
              IconButton.filled(
                key: const ValueKey('voice-control-leave'),
                tooltip: tr('Disconnect'),
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

/// Sends while held, for push to talk on touch screens.
class VoiceHoldToTalkButton extends ConsumerWidget {
  const VoiceHoldToTalkButton({
    required this.session,
    this.enabled = true,
    super.key,
  });

  final VoiceSession session;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = ref.read(voiceSessionProvider.notifier);
    final talking = session.transmitting;
    final usable =
        enabled &&
        !session.selfMute &&
        !session.selfDeaf &&
        !session.serverMute &&
        !session.serverDeaf;
    return Semantics(
      button: true,
      label: tr('Hold to talk'),
      child: Listener(
        key: const ValueKey('voice-hold-to-talk'),
        onPointerDown: usable ? (_) => controller.setTransmitting(true) : null,
        onPointerUp: (_) => controller.setTransmitting(false),
        onPointerCancel: (_) => controller.setTransmitting(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: talking
                ? voiceConnectedColor
                : colorScheme.secondaryContainer.withValues(
                    alpha: usable ? 1 : 0.5,
                  ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                talking ? Icons.mic : Icons.mic_none,
                color: talking
                    ? Colors.white
                    : colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                talking ? tr('Talking…') : tr('Hold to talk'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: talking
                      ? Colors.white
                      : colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
