import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/circles/circle_channel_creation_sheet.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/mod_tools/member_tools_screen.dart';
import 'package:wecord/features/circles/mod_tools/mod_notes_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/custom_status_label.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/layout/resizable_panels.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/ui.dart';

typedef CircleChannelViewBuilder =
    Widget Function(
      BuildContext context,
      CircleChannel channel,
      List<Widget> actions,
    );

typedef CircleThreadViewBuilder =
    Widget Function(
      BuildContext context,
      ThreadTarget thread,
      List<Widget> actions,
    );

/// A voice channel's own text chat, shown from its voice view: the
/// channel's conversation, with the channel's send permission, timeout and
/// slowmode.
Widget voiceChannelChat(CircleDetail detail, CircleChannel channel) {
  return ChatThreadScreen(
    key: ValueKey('voice-chat-${channel.conversationId}'),
    conversationId: channel.conversationId,
    title: channel.name,
    conversationType: ConversationType.channel,
    canSendMessages: detail.canInChannel(
      channel,
      CirclePermission.sendMessages,
    ),
    timedOutUntil: detail.currentUserTimedOutUntil,
    slowmodeSeconds: detail.slowmodeFor(channel),
  );
}

/// Wide-screen circle layout beside the shell's rail: channel sidebar, the
/// selected channel or feed, and a toggleable member list. The sidebar
/// (sharing Home's width) and the member list resize by their edges; the
/// member list closes first when the window gets narrow. An open thread
/// takes the member list's place until closed.
class CircleWorkspace extends ConsumerStatefulWidget {
  const CircleWorkspace({
    required this.detail,
    required this.onChanged,
    this.initialConversationId,
    this.channelViewBuilder,
    this.threadViewBuilder,
    super.key,
  });

  /// Width of the thread panel.
  static const threadPanelWidth = 400.0;

  final CircleDetail detail;
  final VoidCallback onChanged;

  /// The channel, or channel thread, to open first (e.g. from a
  /// notification); otherwise the first channel opens.
  final String? initialConversationId;
  final CircleChannelViewBuilder? channelViewBuilder;

  /// Replaces the thread panel's chat, for tests.
  final CircleThreadViewBuilder? threadViewBuilder;

  @override
  ConsumerState<CircleWorkspace> createState() => _CircleWorkspaceState();
}

class _CircleWorkspaceState extends ConsumerState<CircleWorkspace> {
  /// Selected channel id, or null for the feed.
  String? _selectedChannelId;

  /// The member list was opened while there wasn't room for it.
  var _membersForced = false;

  /// The thread open in the right-hand panel.
  ThreadTarget? _openThread;

  /// The forum post open in place of the selected forum's post list.
  ThreadTarget? _openPost;

  @override
  void initState() {
    super.initState();
    // Open the first channel in sidebar order.
    final channels = CircleChannelLayout.fromChannels(
      categories: widget.detail.categories,
      channels: widget.detail.channels,
    ).orderedChannels;
    _selectedChannelId = channels.isEmpty ? null : channels.first.id;
    _openConversation(widget.initialConversationId);
  }

  /// Selects the channel of [conversationId], opening it in the thread
  /// panel when it is one of the channel's threads.
  void _openConversation(String? conversationId) {
    if (conversationId == null) {
      return;
    }
    for (final channel in widget.detail.channels) {
      if (channel.conversationId == conversationId) {
        _selectedChannelId = channel.id;
        _openThread = null;
        _openPost = null;
        return;
      }
    }
    final conversations =
        ref.read(conversationsProvider).value ?? const <ConversationSummary>[];
    for (final conversation in conversations) {
      if (conversation.id == conversationId && conversation.isThread) {
        for (final channel in widget.detail.channels) {
          if (channel.conversationId == conversation.parentConversationId) {
            final target = ThreadTarget(
              conversationId: conversation.id,
              title: conversation.title ?? tr('Thread'),
              threadId: conversation.threadId,
            );
            // Forum posts open in place of the post list.
            _selectedChannelId = channel.id;
            _openThread = channel.isForum ? null : target;
            _openPost = channel.isForum ? target : null;
          }
        }
        return;
      }
    }
  }

  @override
  void didUpdateWidget(CircleWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialConversationId != oldWidget.initialConversationId) {
      _openConversation(widget.initialConversationId);
    }
    final selectedId = _selectedChannelId;
    if (selectedId == null ||
        widget.detail.channels.any((channel) => channel.id == selectedId)) {
      return;
    }
    // The open channel was deleted (or hidden): open the first remaining
    // channel, or the feed when none is left.
    final channels = CircleChannelLayout.fromChannels(
      categories: widget.detail.categories,
      channels: widget.detail.channels,
    ).orderedChannels;
    _selectedChannelId = channels.isEmpty ? null : channels.first.id;
    _openThread = null;
    _openPost = null;
  }

  CircleChannel? get _selectedChannel {
    for (final channel in widget.detail.channels) {
      if (channel.id == _selectedChannelId) {
        return channel;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final layout = ref.watch(
      panelLayoutProvider.select(
        (layout) =>
            (width: layout.membersWidth, collapsed: layout.membersCollapsed),
      ),
    );
    final closeThread = ChatThreadAction(
      tooltip: tr('Close thread'),
      icon: Icons.close,
      primary: true,
      onPressed: () => setState(() => _openThread = null),
    );
    final selectedChannel = _selectedChannel;
    final channelSettings =
        selectedChannel != null && detail.canOpenChannelSettings
        ? ChatThreadAction(
            tooltip: tr('Channel settings'),
            icon: Icons.settings_outlined,
            onPressed: () => openCircleChannelSettings(
              context,
              circleId: detail.circle.id,
              channelId: selectedChannel.id,
            ),
          )
        : null;
    final followChannel =
        selectedChannel != null && selectedChannel.isAnnouncement
        ? ChatThreadAction(
            tooltip: tr('Follow'),
            icon: Icons.campaign_outlined,
            onPressed: () =>
                showFollowChannelSheet(context, channel: selectedChannel),
          )
        : null;
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};

    final c = context.tokens.colors;
    final edge = BorderSide(color: c.lineSoft);
    final sidebar = ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(WeCordRadii.xl),
      ),
      child: CircleChannelSidebar(
        detail: detail,
        width: null,
        onChangeNickname: _changeNickname,
        onChanged: widget.onChanged,
        selectedChannelId: selectedChannel?.id,
        feedSelected: selectedChannel == null,
        selectedThreadConversationId: _openThread?.conversationId,
        onSelectChannel: (channel) {
          setState(() {
            _selectedChannelId = channel.id;
            _openThread = null;
            _openPost = null;
          });
          // Like Discord, clicking a voice channel joins it.
          if (channel.isVoice) {
            _joinVoice(channel);
          }
        },
        onOpenVoice: _openVoice,
        onSelectFeed: () => setState(() {
          _selectedChannelId = null;
          _openThread = null;
          _openPost = null;
        }),
        onSelectThread: _selectThread,
      ),
    );

    // Everything right of the sidebar: the member list closes first when
    // the window is too narrow for the chosen widths.
    final main = LayoutBuilder(
      builder: (context, constraints) {
        SidePanelPlacement place({
          required bool collapsed,
          bool forced = false,
        }) => resolveSidePanel(
          ResizablePanel.members,
          width: layout.width,
          collapsed: collapsed,
          rowWidth: constraints.maxWidth,
          forced: forced,
        );
        final fits = place(collapsed: false).shown;
        if (fits) {
          // There is room again; closing for lack of room applies again.
          _membersForced = false;
        }
        final placement = place(
          collapsed: layout.collapsed,
          forced: _membersForced,
        );
        final showMembers = placement.shown;
        final memberToggle = ChatThreadAction(
          tooltip: showMembers
              ? tr('Hide member list')
              : tr('Show member list'),
          isSelected: showMembers,
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          primary: true,
          onPressed: () => _toggleMembers(open: !showMembers, fits: fits),
        );
        final thread = _openThread;
        return ResizableSidePanelRow(
          panel: ResizablePanel.members,
          placement: placement,
          content: DecoratedBox(
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(left: edge),
            ),
            child: selectedChannel == null
                ? Scaffold(
                    backgroundColor: c.panel,
                    appBar: AppBar(
                      toolbarHeight: 58,
                      titleSpacing: 22,
                      shape: Border(bottom: BorderSide(color: c.lineSoft)),
                      title: Row(
                        children: [
                          Icon(
                            Icons.dynamic_feed_outlined,
                            size: 18,
                            color: c.muted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            tr('Feed'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        memberToggle.toIconButton(),
                        const SizedBox(width: 10),
                      ],
                    ),
                    body: CircleFeedView(
                      circleId: detail.circle.id,
                      posts: detail.posts,
                      onChanged: widget.onChanged,
                    ),
                  )
                : widget.channelViewBuilder?.call(context, selectedChannel, [
                        ?followChannel?.toIconButton(),
                        memberToggle.toIconButton(),
                        ?channelSettings?.toIconButton(),
                      ]) ??
                      _defaultChannelView(selectedChannel, [
                        ?followChannel,
                        memberToggle,
                        ?channelSettings,
                      ]),
          ),
          fixedSideWidth: CircleWorkspace.threadPanelWidth,
          fixedSide: thread == null
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.panel,
                    border: Border(left: edge),
                  ),
                  child: SizedBox(
                    key: const ValueKey('circle-thread-panel'),
                    width: CircleWorkspace.threadPanelWidth,
                    child:
                        widget.threadViewBuilder?.call(context, thread, [
                          closeThread.toIconButton(),
                        ]) ??
                        _defaultThreadView(thread, [closeThread]),
                  ),
                ),
          side: DecoratedBox(
            decoration: BoxDecoration(border: Border(left: edge)),
            child: CircleMemberList(
              detail: detail,
              width: null,
              onlineUserIds: onlineUserIds,
              onChangeNickname: _changeNickname,
            ),
          ),
        );
      },
    );

    // The shell already keeps the gap above the sidebar.
    return Scaffold(
      backgroundColor: c.rail,
      body: ResizableSidebarRow(sidebar: sidebar, content: main),
    );
  }

  /// Opens or closes the member list from the header. Opened while there
  /// isn't room, it shows anyway (at its narrowest) until closed.
  void _toggleMembers({required bool open, required bool fits}) {
    setState(() => _membersForced = open && !fits);
    ref
        .read(panelLayoutProvider.notifier)
        .setCollapsed(ResizablePanel.members, !open);
  }

  void _joinVoice(CircleChannel channel) {
    final detail = widget.detail;
    if (!detail.canInChannel(channel, CirclePermission.connectVoice) ||
        ref.read(voiceSessionProvider)?.channelId == channel.id) {
      return;
    }
    joinVoiceChannel(
      context,
      ref,
      circleId: detail.circle.id,
      channelId: channel.id,
      conversationId: channel.conversationId,
      channelName: channel.name,
    );
  }

  /// Shows the current call's channel: here when it is in this circle,
  /// otherwise on its own page.
  void _openVoice(VoiceSession session) {
    if (session.circleId == widget.detail.circle.id &&
        widget.detail.channels.any(
          (channel) => channel.id == session.channelId,
        )) {
      setState(() {
        _selectedChannelId = session.channelId;
        _openThread = null;
        _openPost = null;
      });
      return;
    }
    GoRouter.maybeOf(context)?.push(voiceSessionPath(session));
  }

  /// Opens a thread from the sidebar next to its channel.
  void _selectThread(ConversationSummary thread) {
    setState(() {
      for (final channel in widget.detail.channels) {
        if (channel.conversationId == thread.parentConversationId) {
          _selectedChannelId = channel.id;
        }
      }
      _openThread = ThreadTarget(
        conversationId: thread.id,
        title: thread.title ?? tr('Thread'),
        threadId: thread.threadId,
      );
    });
  }

  Future<void> _changeNickname(CircleMember member) {
    return changeCircleNickname(
      context,
      ref,
      circleId: widget.detail.circle.id,
      member: member,
      onChanged: widget.onChanged,
    );
  }

  Widget _defaultChannelView(
    CircleChannel channel,
    List<ChatThreadAction> actions,
  ) {
    if (channel.isForum) {
      return _forumView(channel, actions);
    }
    if (channel.isVoice) {
      return VoiceChannelView(
        key: ValueKey('voice-${channel.id}'),
        circleId: widget.detail.circle.id,
        channelId: channel.id,
        conversationId: channel.conversationId,
        channelName: channel.name,
        canConnect: widget.detail.canInChannel(
          channel,
          CirclePermission.connectVoice,
        ),
        actions: actions,
        moderation: VoiceModeration.forCircle(widget.detail),
        chatBuilder: (context) => voiceChannelChat(widget.detail, channel),
        isStage: channel.isStage,
        stageModerator: widget.detail.canModerateStage(channel),
        canManageSounds: widget.detail.canManageEmojis,
      );
    }
    return ChatThreadScreen(
      key: ValueKey(channel.conversationId),
      conversationId: channel.conversationId,
      title: '# ${channel.name}',
      conversationType: ConversationType.channel,
      extraActions: actions,
      canSendMessages: widget.detail.canInChannel(
        channel,
        CirclePermission.sendMessages,
      ),
      timedOutUntil: widget.detail.currentUserTimedOutUntil,
      slowmodeSeconds: widget.detail.slowmodeFor(channel),
      topic: channel.topic,
      circleMemberIds: {
        for (final member in widget.detail.members) member.profile.id,
      },
      isAnnouncementChannel: channel.isAnnouncement,
      onOpenThread: (thread) => setState(() => _openThread = thread),
    );
  }

  /// A forum's posts, or the open post with a way back to them.
  Widget _forumView(CircleChannel channel, List<ChatThreadAction> actions) {
    final post = _openPost;
    if (post != null) {
      return ChatThreadScreen(
        key: ValueKey(post.conversationId),
        conversationId: post.conversationId,
        title: post.title,
        conversationType: ConversationType.thread,
        forumPost: true,
        onBack: () => setState(() => _openPost = null),
        extraActions: actions,
        canSendMessages: widget.detail.canInChannel(
          channel,
          CirclePermission.sendMessages,
        ),
        timedOutUntil: widget.detail.currentUserTimedOutUntil,
        // Posts have no slowmode of their own.
        slowmodeSeconds: 0,
      );
    }
    return CircleForumView(
      key: ValueKey('forum-${channel.id}'),
      detail: widget.detail,
      channel: channel,
      actions: actions,
      onOpenPost: (post) async => setState(
        () => _openPost = ThreadTarget(
          conversationId: post.conversationId,
          title: post.title,
          threadId: post.id,
        ),
      ),
    );
  }

  Widget _defaultThreadView(
    ThreadTarget thread,
    List<ChatThreadAction> actions,
  ) {
    // Threads open next to their channel and share its permissions.
    final channel = _selectedChannel;
    return ChatThreadScreen(
      key: ValueKey(thread.conversationId),
      conversationId: thread.conversationId,
      title: thread.title,
      conversationType: ConversationType.thread,
      extraActions: actions,
      canSendMessages: channel == null
          ? null
          : widget.detail.canInChannel(channel, CirclePermission.sendMessages),
      timedOutUntil: widget.detail.currentUserTimedOutUntil,
      // Threads have no slowmode of their own.
      slowmodeSeconds: 0,
    );
  }
}

/// Asks for [member]'s new nickname and saves it, then calls [onChanged].
Future<void> changeCircleNickname(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
  required VoidCallback onChanged,
}) async {
  final nickname = await showCircleNicknameDialog(
    context,
    member: member,
    isSelf: member.isCurrentUser,
  );
  if (nickname == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(circlesRepositoryProvider)
        .setNickname(
          circleId: circleId,
          userId: member.profile.id,
          nickname: nickname.isEmpty ? null : nickname,
        );
    onChanged();
    // Open channel threads show nicknames on messages and mentions.
    ref.invalidate(chatThreadProvider);
    ref.invalidate(groupDetailProvider);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not change nickname. Try again.'))),
    );
  }
}

/// Asks to confirm, then kicks [member] out of the circle.
Future<void> kickCircleMember(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
}) async {
  final name = member.displayName;
  final confirmed = await confirmCircleAction(
    context,
    title: tr('Kick {name}', {'name': name}),
    message: tr(
      'Remove {name} from this circle and all of its channels? They can '
      'rejoin with an invite.',
      {'name': name},
    ),
    confirmLabel: tr('Kick'),
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(circlesRepositoryProvider)
        .kickMember(circleId: circleId, userId: member.profile.id);
    ref.invalidate(circleDetailProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Kicked {name}.', {'name': name}))),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(tr('Could not kick {name}. Try again.', {'name': name})),
      ),
    );
  }
}

/// Asks for a circle nickname. Returns the trimmed nickname, an empty string
/// to clear it, or null when cancelled.
Future<String?> showCircleNicknameDialog(
  BuildContext context, {
  required CircleMember member,
  required bool isSelf,
}) {
  return showCircleDialog<String>(
    context,
    builder: (context) => _NicknameDialog(member: member, isSelf: isSelf),
  );
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.member, required this.isSelf});

  final CircleMember member;
  final bool isSelf;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.member.nickname);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.member.profile;
    final fallbackName = profile.displayName.trim().isEmpty
        ? profile.username
        : profile.displayName;
    return CircleDialog(
      title: widget.isSelf ? tr('Change my nickname') : tr('Change nickname'),
      message: widget.isSelf
          ? tr('Only shown in this circle.')
          : tr('Only shown in this circle for {name}.', {'name': fallbackName}),
      content: WeCordTextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxCircleNicknameLength,
        label: tr('Nickname'),
        hint: fallbackName,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.member.nickname != null)
          CircleDialogAction(
            label: tr('Reset'),
            onPressed: () => Navigator.of(context).pop(''),
          ),
        CircleDialogAction.primary(label: tr('Save'), onPressed: _save),
      ],
    );
  }
}

const maxCircleNicknameLength = 32;

void showCircleInviteSheet(BuildContext context, CircleDetail detail) {
  showWeCordSheet<void>(
    context,
    builder: (context, _) => CircleInviteSheet(detail: detail),
  );
}

/// Opens the channel creation sheet. With [categories] it offers a category
/// picker, starting at [initialCategoryId].
void showCircleChannelCreationSheet(
  BuildContext context,
  String circleId, {
  List<CircleChannelCategory> categories = const [],
  String? initialCategoryId,
}) {
  showCircleChannelPanel<void>(
    context,
    title: tr('Create channel'),
    builder: (context) => CircleChannelCreationSheet(
      circleId: circleId,
      categories: categories,
      initialCategoryId: initialCategoryId,
    ),
  );
}

/// Circle members split into groups: online members under their highest
/// hoisted role (highest role first), the remaining online members, then
/// everyone offline. Names take their highest coloured role's colour; a
/// menu views profiles, changes nicknames, manages roles and kicks.
class CircleMemberList extends ConsumerWidget {
  const CircleMemberList({
    required this.detail,
    required this.onlineUserIds,
    required this.onChangeNickname,
    this.width = defaultWidth,
    this.color,
    this.scrollController,
    this.compact = true,
    super.key,
  });

  static const defaultWidth = WeCordSizes.memberListDefault;

  final CircleDetail detail;
  final Set<String> onlineUserIds;
  final ValueChanged<CircleMember> onChangeNickname;

  /// Fixed width, or null to fill the available space.
  final double? width;

  /// The background; the sidebar color by default.
  final Color? color;

  /// Drives the list, e.g. inside a sheet with detents.
  final ScrollController? scrollController;

  /// Desktop density (32 avatars); phones use roomier rows.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoisted = <String, List<CircleMember>>{};
    final online = <CircleMember>[];
    final offline = <CircleMember>[];
    for (final member in detail.members) {
      if (!onlineUserIds.contains(member.profile.id)) {
        offline.add(member);
        continue;
      }
      final role = detail.hoistedRoleOf(member);
      if (role == null) {
        online.add(member);
      } else {
        hoisted.putIfAbsent(role.id, () => []).add(member);
      }
    }
    int byRank(CircleMember left, CircleMember right) {
      final rank = detail.rankOf(right).compareTo(detail.rankOf(left));
      return rank != 0 ? rank : _compareNames(left, right);
    }

    for (final members in hoisted.values) {
      members.sort(byRank);
    }
    online.sort(byRank);
    offline.sort(_compareNames);
    final c = context.tokens.colors;
    final background = color ?? c.sidebar;
    final presenceStatuses = ref.watch(presenceStatusesProvider).value;
    final circleAvatars =
        ref.watch(circleMemberAvatarsProvider(detail.circle.id)).value ??
        const <String, String>{};
    final groups = [
      for (final role in detail.roles)
        if (hoisted[role.id] case final members?) (role.name, members, true),
      (tr('Online'), online, true),
      (tr('Offline'), offline, false),
    ];

    return Material(
      color: background,
      child: SizedBox(
        width: width,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            10,
            compact ? 14 : 4,
            10,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            for (final (index, (label, groupMembers, isOnline))
                in groups.indexed)
              if (groupMembers.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(8, index == 0 ? 4 : 12, 8, 4),
                  child: Semantics(
                    header: true,
                    child: Text(
                      '$label — ${groupMembers.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 11.5 : 12,
                        fontWeight: FontWeight.w700,
                        color: c.subtle,
                      ),
                    ),
                  ),
                ),
                for (final member in groupMembers)
                  _MemberRow(
                    member: member,
                    isOnline: isOnline,
                    compact: compact,
                    background: background,
                    circleAvatarUrl: circleAvatars[member.profile.id],
                    presence: presenceOf(
                      member.profile.id,
                      onlineUserIds: onlineUserIds,
                      statuses: presenceStatuses,
                    ),
                    roleColor: detail.roleColorOf(member),
                    onChangeNickname: detail.canChangeNickname(member)
                        ? () => onChangeNickname(member)
                        : null,
                    onManageRoles: detail.canManageRolesOf(member)
                        ? () => showCircleMemberRolesSheet(
                            context,
                            detail: detail,
                            member: member,
                          )
                        : null,
                    onModNotes: detail.canNoteAbout(member)
                        ? () => openModNotes(
                            context,
                            circleId: detail.circle.id,
                            userId: member.profile.id,
                            name: member.displayName,
                          )
                        : null,
                    onKick: detail.canKick(member)
                        ? () => kickCircleMember(
                            context,
                            ref,
                            circleId: detail.circle.id,
                            member: member,
                          )
                        : null,
                    onTimeOut:
                        detail.canTimeOut(member) &&
                            member.activeTimeoutUntil == null
                        ? () => timeOutCircleMember(
                            context,
                            ref,
                            circleId: detail.circle.id,
                            member: member,
                          )
                        : null,
                    onRemoveTimeout:
                        detail.canTimeOut(member) &&
                            member.activeTimeoutUntil != null
                        ? () => removeCircleMemberTimeout(
                            context,
                            ref,
                            circleId: detail.circle.id,
                            member: member,
                          )
                        : null,
                    onBan: detail.canBan(member)
                        ? () => banCircleMember(
                            context,
                            ref,
                            circleId: detail.circle.id,
                            member: member,
                          )
                        : null,
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

int _compareNames(CircleMember left, CircleMember right) {
  return left.displayName.toLowerCase().compareTo(
    right.displayName.toLowerCase(),
  );
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.isOnline,
    required this.compact,
    required this.background,
    this.presence,
    this.circleAvatarUrl,
    this.roleColor,
    this.onChangeNickname,
    this.onManageRoles,
    this.onModNotes,
    this.onKick,
    this.onTimeOut,
    this.onRemoveTimeout,
    this.onBan,
  });

  final CircleMember member;
  final bool isOnline;
  final bool compact;

  /// What the row sits on, for the presence dot's ring.
  final Color background;

  /// Online, Idle or Do Not Disturb; null while offline.
  final PresenceStatus? presence;

  /// The member's avatar for this circle, shown instead of their usual one.
  final String? circleAvatarUrl;

  /// The member's highest coloured role, as 0xRRGGBB.
  final int? roleColor;

  /// Null when the current user may not change this member's nickname.
  final VoidCallback? onChangeNickname;

  /// Null when the current user may not change this member's roles.
  final VoidCallback? onManageRoles;

  /// Null when the current user may not kick this member.
  /// Null when the current user may not write notes about this member.
  final VoidCallback? onModNotes;
  final VoidCallback? onKick;
  final VoidCallback? onTimeOut;
  final VoidCallback? onRemoveTimeout;
  final VoidCallback? onBan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final profile = member.profile;
    final storedAvatarUrl = circleAvatarUrl ?? profile.avatarUrl;
    final name = member.displayName;
    final roleIcon = switch (member.role) {
      'owner' => Icons.workspace_premium_outlined,
      'admin' => CircleIcons.roles,
      _ => null,
    };
    final presenceColor = switch (isOnline
        ? presence ?? PresenceStatus.online
        : null) {
      PresenceStatus.online => c.success,
      PresenceStatus.idle => c.warning,
      PresenceStatus.doNotDisturb => c.danger,
      _ => null,
    };
    final density = context.density;
    final avatarSize = density.avatar(compact ? 32 : 40);
    final avatar = CircleNetworkAvatar(
      name: name,
      size: avatarSize,
      url: storedAvatarUrl,
      badge: presenceColor == null
          ? Semantics(
              label: tr('Offline'),
              child: SizedBox.shrink(
                key: ValueKey('member-offline-${profile.id}'),
              ),
            )
          : PresenceDot(
              key: ValueKey('member-online-${profile.id}'),
              semanticLabel: (presence ?? PresenceStatus.online).label,
              shape: presenceShapeOf(presence ?? PresenceStatus.online),
              color: presenceColor,
              size: avatarSize < 30
                  ? 10
                  : compact
                  ? 12
                  : 14,
              ringColor: background,
            ),
    );
    final status = activeCustomStatus(profile.customStatus) == null
        ? null
        : CustomStatusLabel(status: profile.customStatus);
    final trailing = switch ((member.activeTimeoutUntil, roleIcon)) {
      (final until?, _) => Tooltip(
        message: tr('Timed out until {time}', {
          'time': formatTimeoutEnd(until),
        }),
        child: Icon(
          Icons.timer_outlined,
          key: ValueKey('member-timed-out-${profile.id}'),
          size: 16,
          color: c.dangerText,
        ),
      ),
      (null, final icon?) => Tooltip(
        message: member.role == 'owner' ? tr('Owner') : tr('Admin'),
        child: Icon(icon, size: 15, color: c.subtle),
      ),
      (null, null) => null,
    };

    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapUp: (details) =>
          _showActions(context, details.globalPosition),
      child: Opacity(
        opacity: isOnline ? 1 : 0.55,
        child: WeCordPressable(
          onPressed: () => _openProfile(context),
          onLongPress: () => _showActions(context, null),
          pressedScale: 0.98,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.sm),
          ),
          builder: (context, states) {
            final hovered =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            return AnimatedContainer(
              duration: WeCordMotion.quick,
              constraints: BoxConstraints(minHeight: density.minRowHeight),
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: density.space(compact ? 5 : 6),
              ),
              decoration: BoxDecoration(
                color: hovered
                    ? c.ink.withValues(alpha: 0.05)
                    : c.ink.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
              ),
              child: Row(
                children: [
                  avatar,
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 13.5 : 15,
                                  fontWeight: roleColor == null
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                  color: switch (roleColor) {
                                    final color? => circleRoleColor(color),
                                    null => c.ink,
                                  },
                                ),
                              ),
                            ),
                            ProfileNameBadges(userId: profile.id),
                          ],
                        ),
                        if (status != null)
                          DefaultTextStyle.merge(
                            style: TextStyle(fontSize: 11.5, color: c.muted),
                            child: status,
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 6), trailing],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    context.push(
      userProfileLocation(member.profile.id, source: FriendSource.circle),
    );
  }

  Future<void> _showActions(BuildContext context, Offset? position) async {
    final action = await showCircleActionMenu<_MemberAction>(
      context,
      title: member.displayName,
      position: position,
      items: [
        CircleMenuItem(
          value: _MemberAction.profile,
          icon: Icons.person_outline,
          label: tr('View profile'),
        ),
        if (onChangeNickname != null)
          CircleMenuItem(
            value: _MemberAction.nickname,
            icon: Icons.badge_outlined,
            label: tr('Change nickname'),
          ),
        if (onManageRoles != null)
          CircleMenuItem(
            value: _MemberAction.roles,
            icon: CircleIcons.roles,
            label: tr('Manage roles'),
          ),
        if (onModNotes != null)
          CircleMenuItem(
            value: _MemberAction.modNotes,
            icon: Icons.sticky_note_2_outlined,
            label: tr('Moderator notes'),
          ),
        if (onTimeOut != null)
          CircleMenuItem(
            value: _MemberAction.timeOut,
            icon: Icons.timer_outlined,
            label: tr('Time out'),
          ),
        if (onRemoveTimeout != null)
          CircleMenuItem(
            value: _MemberAction.removeTimeout,
            icon: Icons.timer_off_outlined,
            label: tr('Remove timeout'),
          ),
        if (onKick != null)
          CircleMenuItem(
            value: _MemberAction.kick,
            icon: Icons.person_remove_outlined,
            label: tr('Kick'),
            destructive: true,
          ),
        if (onBan != null)
          CircleMenuItem(
            value: _MemberAction.ban,
            icon: Icons.block,
            label: tr('Ban'),
            destructive: true,
          ),
      ],
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case _MemberAction.profile:
        _openProfile(context);
      case _MemberAction.nickname:
        onChangeNickname?.call();
      case _MemberAction.roles:
        onManageRoles?.call();
      case _MemberAction.modNotes:
        onModNotes?.call();
      case _MemberAction.timeOut:
        onTimeOut?.call();
      case _MemberAction.removeTimeout:
        onRemoveTimeout?.call();
      case _MemberAction.kick:
        onKick?.call();
      case _MemberAction.ban:
        onBan?.call();
      case null:
        break;
    }
  }
}

enum _MemberAction {
  profile,
  nickname,
  roles,
  modNotes,
  timeOut,
  removeTimeout,
  kick,
  ban,
}
