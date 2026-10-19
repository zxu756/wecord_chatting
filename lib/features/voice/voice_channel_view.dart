import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice/background/video_background.dart';
import 'package:wecord/features/voice/call_links/call_link_sheet.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/mini_player/call_surfaces.dart';
import 'package:wecord/features/voice/reactions/floating_reactions.dart';
import 'package:wecord/features/voice/reactions/reaction_tray.dart';
import 'package:wecord/features/voice/screen_zoom/zoom_pan_viewer.dart';
import 'package:wecord/features/voice/soundboard_sheet.dart';
import 'package:wecord/features/voice/stage_channel_view.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_polish.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/ui/ui.dart';

/// From this width the voice view shows its chat beside the call; below
/// it the chat opens full screen.
const voiceChatPanelBreakpoint = 760.0;

/// How wide the chat beside the call is.
const voiceChatPanelWidth = 360.0;

/// A voice channel, as a dark room: while the current user is connected to
/// it, everyone in the call (video when they publish it, the shared screen
/// larger) above a floating glass control bar; otherwise who is there and
/// a Join button. The chat button opens the channel's own text chat,
/// beside the call on wide screens. A stage shows its speakers above its
/// audience instead ([StageView]).
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
    final connected = here && session.isConnected;
    final members = voiceMembersIn(
      watchVoiceStates(ref, widget.circleId),
      channelId,
    );
    final stageLive =
        widget.isStage && watchStage(ref, widget.circleId, channelId) != null;
    // What the channel says about itself (E6); stages have none.
    final channelStatus = widget.isStage
        ? null
        : ref
              .watch(voiceChannelStatusesProvider(widget.circleId))
              .value?[channelId];
    final chatBuilder = widget.chatBuilder;
    final unread = chatBuilder == null
        ? 0
        : (ref.watch(conversationsProvider).value ??
                      const <ConversationSummary>[])
                  .where(
                    (conversation) => conversation.id == widget.conversationId,
                  )
                  .map((conversation) => conversation.unreadCount)
                  .firstOrNull ??
              0;

    final Widget body;
    if (widget.isStage && connected) {
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
    } else if (connected) {
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
      body = const _Connecting();
    } else {
      body = _NotConnected(
        channelName: widget.channelName,
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

    // Shown here, so the mini player stays away.
    final shownBody = connected ? CallSurface(child: body) : body;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= voiceChatPanelBreakpoint;
        final showPanel = wide && _chatOpen && chatBuilder != null;
        final chatTooltip = showPanel ? tr('Hide chat') : tr('Show chat');
        final chatIcon = showPanel
            ? Icons.chat_bubble_rounded
            : Icons.chat_bubble_outline_rounded;
        final chatBadge = unread > 0 && !showPanel ? unread : null;
        const chatBadgeKey = ValueKey('voice-chat-unread-badge');
        // While connected the chat sits in the control bar.
        final chatControl = chatBuilder == null || !connected
            ? null
            : VoiceControl(
                key: const ValueKey('voice-chat-button'),
                icon: chatIcon,
                tooltip: chatTooltip,
                on: showPanel,
                badgeCount: chatBadge,
                badgeKey: chatBadgeKey,
                onPressed: () => _toggleChat(wide),
              );

        final Widget? controls = !connected
            ? null
            : widget.isStage
            ? StageControls(
                session: session,
                circleId: widget.circleId,
                channelId: channelId,
                moderator: widget.stageModerator,
                soundboard: (
                  circleId: widget.circleId,
                  canManage: widget.canManageSounds,
                ),
                chat: chatControl,
              )
            : VoiceCallControls(
                session: session,
                soundboard: (
                  circleId: widget.circleId,
                  canManage: widget.canManageSounds,
                ),
                chat: chatControl,
              );

        final room = VoiceRoomTheme(
          child: Builder(
            builder: (context) {
              final c = context.tokens.colors;
              final count = members.length;
              final String status;
              final Color statusColor;
              if (widget.isStage) {
                status = stageLive
                    ? tr('Stage live · {count}', {'count': count})
                    : tr('Stage');
                statusColor = stageLive ? c.successText : c.muted;
              } else if (connected) {
                status = tr('Voice connected');
                statusColor = c.successText;
              } else {
                status = tr('Voice channel');
                statusColor = c.muted;
              }
              return VoiceRoom(
                header: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoomHeader(
                      title: widget.channelName,
                      status: connected && session.audioOnly
                          ? tr('{status} · Audio only', {'status': status})
                          : status,
                      statusColor: statusColor,
                      isStage: widget.isStage,
                      channelStatus: channelStatus,
                      onEditStatus: connected && !widget.isStage
                          ? () => unawaited(
                              showVoiceStatusSheet(
                                context,
                                ref,
                                circleId: widget.circleId,
                                channelId: channelId,
                                current: channelStatus,
                              ),
                            )
                          : null,
                      onBack: widget.onBack,
                      actions: [
                        if (connected)
                          VoiceHeaderButton(
                            key: const ValueKey('voice-audio-only-button'),
                            icon: session.audioOnly
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_outlined,
                            tooltip: session.audioOnly
                                ? tr('Receive video again')
                                : tr('Audio only'),
                            selected: session.audioOnly,
                            onPressed: () => runVoiceAction(
                              context,
                              () => ref
                                  .read(voiceSessionProvider.notifier)
                                  .setAudioOnly(!session.audioOnly),
                            ),
                          ),
                        if (chatBuilder != null && !connected)
                          VoiceHeaderButton(
                            key: const ValueKey('voice-chat-button'),
                            icon: chatIcon,
                            tooltip: chatTooltip,
                            selected: showPanel,
                            badgeCount: chatBadge,
                            badgeKey: chatBadgeKey,
                            onPressed: () => _toggleChat(wide),
                          ),
                        if (connected)
                          VoiceHeaderButton(
                            key: const ValueKey('voice-call-link-button'),
                            icon: Icons.link_rounded,
                            tooltip: tr('Copy call link'),
                            onPressed: () => showCallLinkSheet(
                              context,
                              target: CallLinkTarget.channel(channelId),
                              name: widget.channelName,
                            ),
                          ),
                        for (final action in widget.actions)
                          VoiceHeaderButton(
                            icon: action.isSelected == true
                                ? action.selectedIcon ?? action.icon
                                : action.icon,
                            tooltip: action.tooltip,
                            selected: action.isSelected == true,
                            onPressed: action.onPressed,
                          ),
                      ],
                    ),
                    if (connected) const VoiceQualityBanner(),
                  ],
                ),
                controls: controls,
                child: shownBody,
              );
            },
          ),
        );

        return Scaffold(
          key: ValueKey('voice-channel-view-$channelId'),
          backgroundColor: WeCordTokens.dark.colors.paper,
          body: showPanel
              ? Row(
                  children: [
                    Expanded(child: room),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: context.tokens.colors.lineSoft,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        key: ValueKey('voice-chat-panel-$channelId'),
                        width: voiceChatPanelWidth,
                        child: chatBuilder(context),
                      ),
                    ),
                  ],
                )
              : room,
        );
      },
    );
  }
}

/// A dark voice room: the soft glows, a [header] under the status bar,
/// [child] filling the rest, and the floating [controls] at the bottom
/// (the child gets the room they take as bottom padding).
class VoiceRoom extends StatelessWidget {
  const VoiceRoom({
    required this.header,
    required this.child,
    this.controls,
    super.key,
  });

  final Widget header;
  final Widget child;
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomGap = math.max(media.padding.bottom - 6, 14.0);
    final controls = this.controls;
    return VoiceRoomBackground(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: media.padding.top,
              left: media.padding.left,
              right: media.padding.right,
            ),
            child: header,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: MediaQuery(
                    data: media.copyWith(
                      padding: media.padding.copyWith(
                        top: 0,
                        bottom: controls == null
                            ? media.padding.bottom
                            : bottomGap + VoiceControlBar.reservedHeight,
                      ),
                    ),
                    child: child,
                  ),
                ),
                if (controls != null)
                  Positioned(
                    left: 14 + media.padding.left,
                    right: 14 + media.padding.right,
                    bottom: bottomGap,
                    child: controls,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.isStage,
    required this.actions,
    this.channelStatus,
    this.onEditStatus,
    this.onBack,
  });

  final String title;
  final String status;
  final Color statusColor;
  final bool isStage;
  final List<Widget> actions;

  /// What the channel says about itself, under the title.
  final String? channelStatus;

  /// Opens the box to change the status; null where the person is not in
  /// the channel.
  final VoidCallback? onEditStatus;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final touch = usesTouchInput(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final back = onBack ?? (canPop ? () => Navigator.maybePop(context) : null);
    return Padding(
      padding: EdgeInsets.fromLTRB(touch ? 12 : 16, 10, touch ? 12 : 14, 6),
      child: Row(
        children: [
          if (back != null) ...[
            VoiceHeaderButton(
              icon: Icons.arrow_back_rounded,
              tooltip: tr('Back'),
              onPressed: back,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                VoiceStatusLine(
                  text: status,
                  color: statusColor,
                  dotColor: statusColor == c.muted ? c.faint : c.success,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      isStage
                          ? Icons.podcasts_rounded
                          : Icons.volume_up_rounded,
                      size: touch ? 19 : 18,
                      color: c.muted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: touch ? 19 : 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                if (onEditStatus != null)
                  WeCordPressable(
                    key: const ValueKey('voice-status-button'),
                    onPressed: onEditStatus,
                    hint: tr('Channel status'),
                    shape: const StadiumBorder(),
                    pressedScale: 0.98,
                    builder: (context, states) => Padding(
                      padding: EdgeInsets.only(
                        left: touch ? 25 : 24,
                        top: 1,
                        bottom: 1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              channelStatus ?? tr('Add a status'),
                              key: const ValueKey('voice-channel-status'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: channelStatus == null
                                    ? c.faint
                                    : c.muted,
                                decoration: channelStatus == null
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit_outlined, size: 13, color: c.muted),
                        ],
                      ),
                    ),
                  )
                else if (channelStatus != null)
                  VoiceChannelStatusText(
                    text: channelStatus!,
                    padding: EdgeInsets.only(left: touch ? 25 : 24, top: 1),
                  ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 6), action],
        ],
      ),
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      key: const ValueKey('voice-connecting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: c.ink),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Connecting…'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({
    required this.channelName,
    required this.members,
    required this.canConnect,
    required this.onJoin,
  });

  final String channelName;
  final List<VoiceMemberState> members;
  final bool canConnect;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      key: const ValueKey('voice-not-connected'),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThingAvatar(
                size: 84,
                radius: 28,
                icon: Icons.volume_up_rounded,
                color: c.ink.withValues(alpha: 0.08),
                foregroundColor: c.ink,
              ),
              const SizedBox(height: 18),
              Text(
                members.isEmpty
                    ? tr('No one is here yet.')
                    : members.length == 1
                    ? tr('1 person is here')
                    : tr('{count} people are here', {'count': members.length}),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                members.isEmpty
                    ? tr('Join and others will see you in {channel}.', {
                        'channel': channelName,
                      })
                    : tr('Hop in and say hi.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 12,
                  children: [
                    for (final member in members)
                      SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VoiceAvatar(
                              name: member.name,
                              avatarUrl: member.avatarUrl,
                              size: 52,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              member.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              if (canConnect)
                WeCordButton(
                  key: const ValueKey('voice-join-button'),
                  label: tr('Join voice'),
                  icon: Icons.call_rounded,
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.large,
                  onPressed: () {
                    WeCordHaptics.medium();
                    onJoin();
                  },
                )
              else
                Text(
                  tr("You don't have permission to join this voice channel."),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
            ],
          ),
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

/// Everyone in the call: shared screens first and across the width, then
/// a rounded tile per person (their camera, or their avatar), ringed while
/// they speak. Right-click or long-press opens a person's menu.
///
/// Shared screens zoom and pan ([ZoomPanViewer]). Tapping a tile (or its
/// "Focus this tile" button) puts it in the spotlight: large, with everyone
/// else in a strip below; tapping it again shows everyone.
class VoiceCallGrid extends StatefulWidget {
  const VoiceCallGrid({
    required this.session,
    required this.people,
    this.moderation,
    this.shrinkWrap = false,
    super.key,
  });

  final VoiceSession session;

  /// The server's view of each participant, by user id.
  final Map<String, VoiceCallPerson> people;

  /// What the current user may do to people from their menu.
  final VoiceModeration? moderation;

  /// Sizes to its tiles instead of filling (and centering in) the height
  /// it gets, for the call strip above a chat.
  final bool shrinkWrap;

  @override
  State<VoiceCallGrid> createState() => _VoiceCallGridState();
}

class _VoiceCallGridState extends State<VoiceCallGrid> {
  /// The tile in the spotlight: `screen:<user id>` or `user:<user id>`.
  String? _spotlight;

  /// Shared screens zoomed in, by `screen:<user id>`. While one is, the
  /// page doesn't scroll, so a finger drags the picture instead.
  final _zoomed = <String>{};

  static const _spacing = 10.0;
  static const _stripHeight = 92.0;
  static const _stripTileWidth = 148.0;

  void _toggleSpotlight(String key) {
    setState(() => _spotlight = _spotlight == key ? null : key);
  }

  String _nameOf(VoiceCallParticipant participant) =>
      widget.people[participant.userId]?.name ?? participant.name;

  Widget _screenTile(
    BuildContext context,
    VoiceCallParticipant participant, {
    bool interactive = true,
  }) {
    final key = 'screen:${participant.userId}';
    return _Tile(
      key: ValueKey('voice-screen-tile-${participant.userId}'),
      label: tr("{name}'s screen", {'name': _nameOf(participant)}),
      labelIcon: Icons.screen_share_rounded,
      speaking: false,
      dark: true,
      child: interactive
          ? ZoomPanViewer(
              key: ValueKey('voice-screen-zoom-${participant.userId}'),
              focused: _spotlight == key,
              onFocus: () => _toggleSpotlight(key),
              onZoomedChanged: (zoomed) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  if (zoomed) {
                    _zoomed.add(key);
                  } else {
                    _zoomed.remove(key);
                  }
                });
              },
              child: participant.screenView!(context),
            )
          : participant.screenView!(context),
    );
  }

  Widget _personTile(BuildContext context, VoiceCallParticipant participant) {
    final people = widget.people;
    final session = widget.session;
    final key = 'user:${participant.userId}';
    return VoiceParticipantMenuRegion(
      person: VoiceMenuPerson(
        userId: participant.userId,
        name: _nameOf(participant),
        isLocal: participant.isLocal,
        channelId: session.channelId,
        serverMute: people[participant.userId]?.serverMute ?? false,
        serverDeaf: people[participant.userId]?.serverDeaf ?? false,
      ),
      moderation: widget.moderation,
      child: _ParticipantTile(
        participant: participant,
        name: _nameOf(participant),
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
        focused: _spotlight == key,
        onFocus: () => _toggleSpotlight(key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.session.participants;
    final shrinkWrap = widget.shrinkWrap;
    final screens = [
      for (final participant in participants)
        if (participant.screenView != null) participant,
    ];
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final locked = screens.any(
      (participant) => _zoomed.contains('screen:${participant.userId}'),
    );

    VoiceCallParticipant? spotlightScreen;
    VoiceCallParticipant? spotlightPerson;
    final spotlight = _spotlight;
    if (spotlight != null) {
      final id = spotlight.substring(spotlight.indexOf(':') + 1);
      final matches = spotlight.startsWith('screen:') ? screens : participants;
      final found = matches.where((p) => p.userId == id).firstOrNull;
      if (spotlight.startsWith('screen:')) {
        spotlightScreen = found;
      } else {
        spotlightPerson = found;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 14.0 : 20.0;

        if (spotlightScreen != null || spotlightPerson != null) {
          return _spotlightView(
            context,
            constraints,
            padding: padding,
            bottomInset: bottomInset,
            screens: screens,
            screen: spotlightScreen,
            person: spotlightPerson,
            locked: locked,
          );
        }

        final width = constraints.maxWidth - padding * 2;
        final aspect = width < 420 && !shrinkWrap ? 1.0 : 16 / 10;
        final count = math.max(participants.length, 1);
        final maxColumns = width < 420
            ? 2
            : width < 760
            ? 3
            : 4;
        var tileWidth =
            (width - _spacing * (math.min(maxColumns, count) - 1)) /
            math.min(maxColumns, count);
        final height = constraints.maxHeight - bottomInset - 8 - padding;
        if (!shrinkWrap && constraints.hasBoundedHeight && screens.isEmpty) {
          // Pick the column count that gives the biggest tiles while
          // everyone fits on screen; scroll only when tiles would get
          // too small.
          var best = 0.0;
          for (var columns = 1; columns <= count; columns++) {
            final rows = (count / columns).ceil();
            final byWidth = (width - _spacing * (columns - 1)) / columns;
            final byHeight = (height - _spacing * (rows - 1)) / rows * aspect;
            best = math.max(best, math.min(byWidth, byHeight));
          }
          if (best >= 140) {
            tileWidth = math.min(best, 560);
          }
        } else if (!shrinkWrap && constraints.hasBoundedHeight) {
          tileWidth = math.min(tileWidth, math.max(140, height * 0.5 * aspect));
        }
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final participant in screens) ...[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _screenTile(context, participant),
              ),
              const SizedBox(height: _spacing),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: _spacing,
              runSpacing: _spacing,
              children: [
                for (final participant in participants)
                  SizedBox(
                    width: tileWidth,
                    height: tileWidth / aspect,
                    child: _personTile(context, participant),
                  ),
              ],
            ),
          ],
        );
        final scrollPadding = EdgeInsets.fromLTRB(
          padding,
          shrinkWrap ? padding : 8,
          padding,
          padding + bottomInset,
        );
        final physics = locked ? const NeverScrollableScrollPhysics() : null;
        if (shrinkWrap || !constraints.hasBoundedHeight) {
          return SingleChildScrollView(
            key: const ValueKey('voice-call-grid'),
            padding: scrollPadding,
            physics: physics,
            child: content,
          );
        }
        return SingleChildScrollView(
          key: const ValueKey('voice-call-grid'),
          padding: scrollPadding,
          physics: physics,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - scrollPadding.vertical,
              ),
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  /// One tile large (a shared screen or a person) with everyone else in a
  /// strip below it.
  Widget _spotlightView(
    BuildContext context,
    BoxConstraints constraints, {
    required double padding,
    required double bottomInset,
    required List<VoiceCallParticipant> screens,
    required bool locked,
    VoiceCallParticipant? screen,
    VoiceCallParticipant? person,
  }) {
    final participants = widget.session.participants;
    final main = screen != null
        ? _screenTile(context, screen)
        : _personTile(context, person!);
    final others = <Widget>[
      for (final other in screens)
        if (other != screen)
          _StripTile(
            key: ValueKey('voice-strip-screen-${other.userId}'),
            label: tr("{name}'s screen", {'name': _nameOf(other)}),
            onPressed: () => _toggleSpotlight('screen:${other.userId}'),
            child: _screenTile(context, other, interactive: false),
          ),
      for (final other in participants)
        if (other != person)
          KeyedSubtree(
            key: ValueKey('voice-strip-user-${other.userId}'),
            child: _personTile(context, other),
          ),
    ];
    final bounded = constraints.hasBoundedHeight && !widget.shrinkWrap;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (bounded)
          Expanded(child: main)
        else
          AspectRatio(
            aspectRatio: screen != null ? 16 / 9 : 16 / 10,
            child: main,
          ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: _spacing),
          SizedBox(
            height: _stripHeight,
            child: ListView.separated(
              key: const ValueKey('voice-spotlight-strip'),
              scrollDirection: Axis.horizontal,
              itemCount: others.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) =>
                  SizedBox(width: _stripTileWidth, child: others[index]),
            ),
          ),
        ],
      ],
    );
    final scrollPadding = EdgeInsets.fromLTRB(
      padding,
      widget.shrinkWrap ? padding : 8,
      padding,
      padding + bottomInset,
    );
    if (bounded) {
      return Padding(
        key: const ValueKey('voice-call-grid'),
        padding: scrollPadding,
        child: column,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('voice-call-grid'),
      padding: scrollPadding,
      physics: locked ? const NeverScrollableScrollPhysics() : null,
      child: column,
    );
  }
}

/// A small tile in the spotlight's strip that puts its content in the
/// spotlight when tapped.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.label,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      semanticLabel: label,
      hint: tr('Focus this tile'),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl + 2),
      ),
      pressedScale: 1,
      minTapSize: Size.zero,
      onPressed: onPressed,
      builder: (context, states) => child,
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
    this.focused = false,
    this.onFocus,
  });

  final VoiceCallParticipant participant;
  final String name;
  final String? avatarUrl;
  final bool deafened;
  final bool serverMuted;
  final bool serverDeafened;

  /// In the spotlight.
  final bool focused;

  /// Puts the tile in the spotlight, or takes it out.
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final camera = participant.cameraView;
    final silenced = serverDeafened || serverMuted;
    final tile = _Tile(
      key: ValueKey('voice-tile-${participant.userId}'),
      label: participant.isLocal ? tr('{name} (you)', {'name': name}) : name,
      speaking: participant.isSpeaking,
      dark: camera != null,
      labelIconKey: silenced
          ? const ValueKey('voice-tile-server-silenced')
          : null,
      labelIconColor: silenced ? c.dangerText : null,
      labelIcon: deafened || serverDeafened
          ? Icons.headset_off_rounded
          : serverMuted || !participant.microphoneEnabled
          ? Icons.mic_off_rounded
          : null,
      overlay: FloatingReactions(
        userId: participant.userId,
        name: name,
        child: const SizedBox.shrink(),
      ),
      // Your own connection, on your own tile (E6).
      topRight: participant.isLocal
          ? Consumer(
              builder: (context, ref, _) => VoiceQualityBadge(
                quality:
                    ref.watch(
                      voiceSessionProvider.select(
                        (session) => session?.quality,
                      ),
                    ) ??
                    VoiceConnectionQuality.unknown,
              ),
            )
          : null,
      child: camera != null
          ? camera(context)
          // Above the name label at the bottom.
          : Align(
              alignment: const Alignment(0, -0.15),
              child: LayoutBuilder(
                builder: (context, constraints) => VoiceAvatar(
                  name: name,
                  avatarUrl: avatarUrl,
                  speaking: participant.isSpeaking,
                  size: (constraints.biggest.shortestSide * 0.4).clamp(
                    28.0,
                    104.0,
                  ),
                ),
              ),
            ),
    );
    if (onFocus == null) {
      return tile;
    }
    return WeCordPressable(
      key: ValueKey('voice-tile-focus-${participant.userId}'),
      hint: focused ? tr('Show everyone') : tr('Focus this tile'),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl + 2),
      ),
      pressedScale: 1,
      minTapSize: Size.zero,
      selected: focused,
      onPressed: onFocus,
      builder: (context, states) => tile,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.speaking,
    required this.child,
    this.dark = false,
    this.labelIcon,
    this.labelIconColor,
    this.labelIconKey,
    this.overlay,
    this.topRight,
    super.key,
  });

  final String label;
  final bool speaking;
  final Widget child;

  /// Video under it: a darker fill behind it.
  final bool dark;
  final IconData? labelIcon;
  final Color? labelIconColor;
  final Key? labelIconKey;

  /// Drawn over everything else in the tile (floating reactions).
  final Widget? overlay;

  /// A small badge in the tile's top right corner.
  final Widget? topRight;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl + 2),
    );
    return AnimatedContainer(
      duration: WeCordMotion.durationOf(context, WeCordMotion.quick),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: shape,
        color: dark
            ? c.paper
            : speaking
            ? c.success.withValues(alpha: 0.16)
            : c.ink.withValues(alpha: 0.07),
      ),
      foregroundDecoration: ShapeDecoration(
        shape: shape.copyWith(
          side: BorderSide(
            color: speaking
                ? c.successText.withValues(alpha: 0.75)
                : c.ink.withValues(alpha: 0.05),
            width: speaking ? 2 : 1,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (speaking)
            const SizedBox.shrink(key: ValueKey('voice-tile-speaking')),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                decoration: BoxDecoration(
                  color: c.paper.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(WeCordRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (labelIcon != null) ...[
                      Icon(
                        labelIcon,
                        key: labelIconKey,
                        size: 13,
                        color: labelIconColor ?? c.ink,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (topRight != null) Positioned(top: 8, right: 8, child: topRight!),
          ?overlay,
        ],
      ),
    );
  }
}

/// Microphone, deafen, camera, screen share (where the platform can), the
/// soundboard (in circle voice channels), the chat and disconnect, in the
/// floating glass bar; with push to talk on a phone (or without a key
/// set), a button to hold while talking above it.
class VoiceCallControls extends ConsumerStatefulWidget {
  const VoiceCallControls({
    required this.session,
    this.soundboard,
    this.chat,
    super.key,
  });

  final VoiceSession session;

  /// The circle's soundboard; none in direct and group calls.
  final SoundboardAccess? soundboard;

  /// The chat button, when the call has a chat to open.
  final VoiceControl? chat;

  @override
  ConsumerState<VoiceCallControls> createState() => _VoiceCallControlsState();
}

class _VoiceCallControlsState extends ConsumerState<VoiceCallControls> {
  var _busy = false;
  var _reactionsOpen = false;

  /// Sends [emoji]; the tray closes once it went out.
  Future<bool> _react(String emoji) async {
    final sent = await ref
        .read(voiceSessionProvider.notifier)
        .sendReaction(emoji);
    if (sent) {
      WeCordHaptics.light();
      if (mounted) {
        setState(() => _reactionsOpen = false);
      }
    }
    return sent;
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            error is BackgroundBlurUnavailable ? error.toString() : failure,
          ),
        ),
      );
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
    final canShareScreen = ref.watch(voiceScreenShareSupportedProvider);
    final hasKey = ref.watch(
      voiceSettingsProvider.select(
        (settings) => settings.pushToTalkKeyId != null,
      ),
    );
    final holdToTalk =
        session.pushToTalk && (usesTouchInput(context) || !hasKey);
    final muted = session.selfMute || session.serverMute;
    final deafened = session.selfDeaf || session.serverDeaf;

    VoidCallback? guard(VoidCallback? action) => _busy ? null : action;

    return KeyedSubtree(
      key: const ValueKey('voice-call-controls'),
      child: VoiceControlBar(
        above: holdToTalk || _reactionsOpen
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_reactionsOpen) ReactionTray(onPick: _react),
                  if (_reactionsOpen && holdToTalk) const SizedBox(height: 10),
                  if (holdToTalk)
                    VoiceHoldToTalkButton(session: session, enabled: !_busy),
                ],
              )
            : null,
        controls: [
          VoiceControl(
            key: const ValueKey('voice-control-mic'),
            tooltip: voiceMuteTooltip(session),
            icon: muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            on: muted,
            onPressed: guard(
              session.serverMute
                  ? null
                  : () => _run(
                      controller.toggleMute,
                      tr('Could not change the microphone.'),
                    ),
            ),
          ),
          VoiceControl(
            key: const ValueKey('voice-control-deafen'),
            tooltip: voiceDeafenTooltip(session),
            icon: deafened ? Icons.headset_off_rounded : Icons.headset_outlined,
            on: deafened,
            onPressed: guard(
              session.serverDeaf
                  ? null
                  : () =>
                        _run(controller.toggleDeafen, tr('Could not deafen.')),
            ),
          ),
          VoiceControl(
            key: const ValueKey('voice-control-camera'),
            tooltip: session.video
                ? tr('Turn off camera')
                : tr('Turn on camera'),
            icon: session.video
                ? Icons.videocam_rounded
                : Icons.videocam_off_outlined,
            on: session.video,
            onPressed: guard(
              () => _run(
                controller.toggleCamera,
                tr('Could not use the camera. Check the camera permission.'),
              ),
            ),
          ),
          if (session.video &&
              session.backgroundSupport != VideoBackgroundSupport.none)
            VoiceControl(
              key: const ValueKey('voice-control-blur'),
              tooltip: switch (session.backgroundSupport) {
                VideoBackgroundSupport.system => tr('Video effects'),
                _ =>
                  session.backgroundBlur
                      ? tr('Turn off background blur')
                      : tr('Blur background'),
              },
              icon: Icons.blur_on_rounded,
              on: session.backgroundBlur,
              onPressed: guard(
                () => _run(
                  controller.toggleBackgroundBlur,
                  tr('Could not change the background.'),
                ),
              ),
            ),
          if (canShareScreen)
            VoiceControl(
              key: const ValueKey('voice-control-screen'),
              tooltip: session.screen ? tr('Stop sharing') : tr('Share screen'),
              icon: session.screen
                  ? Icons.stop_screen_share_outlined
                  : Icons.screen_share_outlined,
              on: session.screen,
              onPressed: guard(
                () =>
                    _run(_toggleScreenShare, tr('Could not share the screen.')),
              ),
            ),
          if (widget.soundboard case final soundboard?
              when session.channelId != null)
            VoiceControl(
              key: const ValueKey('voice-control-soundboard'),
              tooltip: tr('Soundboard'),
              icon: Icons.music_note_rounded,
              onPressed: guard(
                () => showSoundboard(
                  context,
                  access: soundboard,
                  channelId: session.channelId!,
                ),
              ),
            ),
          VoiceControl(
            key: const ValueKey('voice-control-reactions'),
            tooltip: tr('Reactions'),
            icon: Icons.add_reaction_outlined,
            on: _reactionsOpen,
            onPressed: () => setState(() => _reactionsOpen = !_reactionsOpen),
          ),
          ?widget.chat,
        ],
        leaveLabel: tr('Leave'),
        leaveTooltip: tr('Disconnect'),
        onLeave: controller.leave,
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
    final c = context.tokens.colors;
    final controller = ref.read(voiceSessionProvider.notifier);
    final talking = session.transmitting;
    final usable =
        enabled &&
        !session.selfMute &&
        !session.selfDeaf &&
        !session.serverMute &&
        !session.serverDeaf;
    final foreground = talking ? c.onInk : c.ink;
    return Semantics(
      button: true,
      label: tr('Hold to talk'),
      child: Listener(
        key: const ValueKey('voice-hold-to-talk'),
        onPointerDown: usable
            ? (_) {
                WeCordHaptics.medium();
                controller.setTransmitting(true);
              }
            : null,
        onPointerUp: (_) => controller.setTransmitting(false),
        onPointerCancel: (_) => controller.setTransmitting(false),
        child: AnimatedScale(
          scale: talking && !WeCordMotion.reduceMotion(context) ? 1.04 : 1,
          duration: WeCordMotion.snappy.duration,
          curve: WeCordMotion.snappy.curve,
          child: AnimatedOpacity(
            opacity: usable ? 1 : 0.5,
            duration: WeCordMotion.quick,
            child: WeCordGlass(
              borderRadius: BorderRadius.circular(WeCordRadii.pill),
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                constraints: const BoxConstraints(minHeight: 52, minWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                color: talking ? c.success : c.success.withValues(alpha: 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      talking ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      talking ? tr('Talking…') : tr('Hold to talk'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
