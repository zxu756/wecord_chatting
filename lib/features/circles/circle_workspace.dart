import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_creation_sheet.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/custom_status_label.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';

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

/// Wide-screen circle layout beside the shell's rail: channel sidebar, the
/// selected channel or feed, and a toggleable member list. An open thread takes the
/// member list's place until closed.
class CircleWorkspace extends ConsumerStatefulWidget {
  const CircleWorkspace({
    required this.detail,
    required this.onChanged,
    this.initialConversationId,
    this.channelViewBuilder,
    this.threadViewBuilder,
    super.key,
  });

  /// Below this width the member list starts hidden.
  static const memberListBreakpoint = 1280.0;

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
  bool? _showMembers;

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
        ref.read(conversationsProvider).valueOrNull ??
        const <ConversationSummary>[];
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
    final showMembers =
        _showMembers ??
        MediaQuery.sizeOf(context).width >=
            CircleWorkspace.memberListBreakpoint;
    final memberToggle = ChatThreadAction(
      tooltip: showMembers ? tr('Hide member list') : tr('Show member list'),
      isSelected: showMembers,
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      onPressed: () => setState(() => _showMembers = !showMembers),
    );
    final closeThread = ChatThreadAction(
      tooltip: tr('Close thread'),
      icon: Icons.close,
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
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleChannelSidebar(
            detail: detail,
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
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedChannel == null
                ? Scaffold(
                    appBar: AppBar(
                      title: Text(tr('Feed')),
                      actions: [memberToggle.toIconButton()],
                    ),
                    body: CircleFeedView(
                      circleId: detail.circle.id,
                      posts: detail.posts,
                      onChanged: widget.onChanged,
                    ),
                  )
                : widget.channelViewBuilder?.call(context, selectedChannel, [
                        memberToggle.toIconButton(),
                        ?channelSettings?.toIconButton(),
                      ]) ??
                      _defaultChannelView(selectedChannel, [
                        memberToggle,
                        ?channelSettings,
                      ]),
          ),
          if (_openThread case final thread?) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              key: const ValueKey('circle-thread-panel'),
              width: CircleWorkspace.threadPanelWidth,
              child:
                  widget.threadViewBuilder?.call(context, thread, [
                    closeThread.toIconButton(),
                  ]) ??
                  _defaultThreadView(thread, [closeThread]),
            ),
          ] else if (showMembers) ...[
            const VerticalDivider(width: 1),
            CircleMemberList(
              detail: detail,
              onlineUserIds: onlineUserIds,
              onChangeNickname: _changeNickname,
            ),
          ],
        ],
      ),
    );
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(tr('Kick {name}', {'name': name})),
      content: Text(
        tr(
          'Remove {name} from this circle and all of its channels? They can '
          'rejoin with an invite.',
          {'name': name},
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Kick')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
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
  return showDialog<String>(
    context: context,
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
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.isSelf ? tr('Change my nickname') : tr('Change nickname'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSelf
                ? tr('Only shown in this circle.')
                : tr('Only shown in this circle for {name}.', {
                    'name': fallbackName,
                  }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxCircleNicknameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Nickname'),
              hintText: fallbackName,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        if (widget.member.nickname != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(tr('Reset')),
          ),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ],
    );
  }
}

const maxCircleNicknameLength = 32;

void showCircleInviteSheet(BuildContext context, CircleDetail detail) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => CircleInviteSheet(detail: detail),
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
    super.key,
  });

  static const defaultWidth = 240.0;

  final CircleDetail detail;
  final Set<String> onlineUserIds;
  final ValueChanged<CircleMember> onChangeNickname;

  /// Fixed width, or null to fill the available space.
  final double? width;

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
    final theme = Theme.of(context);
    final groups = [
      for (final role in detail.roles)
        if (hoisted[role.id] case final members?) (role.name, members, true),
      (tr('Online'), online, true),
      (tr('Offline'), offline, false),
    ];

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          children: [
            for (final (label, groupMembers, isOnline) in groups)
              if (groupMembers.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    '${label.toUpperCase()} — ${groupMembers.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final member in groupMembers)
                  _MemberRow(
                    member: member,
                    isOnline: isOnline,
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
    this.roleColor,
    this.onChangeNickname,
    this.onManageRoles,
    this.onKick,
    this.onTimeOut,
    this.onRemoveTimeout,
    this.onBan,
  });

  final CircleMember member;
  final bool isOnline;

  /// The member's highest coloured role, as 0xRRGGBB.
  final int? roleColor;

  /// Null when the current user may not change this member's nickname.
  final VoidCallback? onChangeNickname;

  /// Null when the current user may not change this member's roles.
  final VoidCallback? onManageRoles;

  /// Null when the current user may not kick this member.
  final VoidCallback? onKick;
  final VoidCallback? onTimeOut;
  final VoidCallback? onRemoveTimeout;
  final VoidCallback? onBan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = member.profile;
    final avatarUrl = ref
        .watch(avatarDisplayUrlProvider(profile.avatarUrl))
        .valueOrNull;
    final name = member.displayName;
    final roleIcon = switch (member.role) {
      'owner' => Icons.workspace_premium_outlined,
      'admin' => Icons.shield_outlined,
      _ => null,
    };

    return GestureDetector(
      onSecondaryTap: () => _showActions(context),
      child: Opacity(
        opacity: isOnline ? 1 : 0.55,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: avatarUrl == null
                    ? null
                    : NetworkImage(avatarUrl),
                onBackgroundImageError: avatarUrl == null
                    ? null
                    : (_, _) => refreshAvatarDisplayUrl(ref, profile.avatarUrl),
                child: avatarUrl == null
                    ? Text(name.characters.first.toUpperCase())
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  key: ValueKey(
                    isOnline
                        ? 'member-online-${profile.id}'
                        : 'member-offline-${profile.id}',
                  ),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? Colors.green : colorScheme.outline,
                    border: Border.all(
                      color: colorScheme.surfaceContainerLow,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: switch (roleColor) {
              final color? => TextStyle(color: circleRoleColor(color)),
              null => null,
            },
          ),
          subtitle: activeCustomStatus(profile.customStatus) == null
              ? null
              : CustomStatusLabel(status: profile.customStatus),
          trailing: switch ((member.activeTimeoutUntil, roleIcon)) {
            (final until?, _) => Tooltip(
              message: tr('Timed out until {time}', {
                'time': formatTimeoutEnd(until),
              }),
              child: Icon(
                Icons.timer_outlined,
                key: ValueKey('member-timed-out-${profile.id}'),
                size: 16,
                color: colorScheme.error,
              ),
            ),
            (null, final icon?) => Tooltip(
              message: member.role == 'owner' ? tr('Owner') : tr('Admin'),
              child: Icon(icon, size: 16),
            ),
            (null, null) => null,
          },
          onTap: () => _openProfile(context),
          onLongPress: () => _showActions(context),
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    context.push('${UserProfileScreen.path}/${member.profile.id}');
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        // Scrolls when a moderator's actions don't fit short phones.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(tr('View profile')),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openProfile(context);
                  },
                ),
                if (onChangeNickname != null)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(tr('Change nickname')),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onChangeNickname!();
                    },
                  ),
                if (onManageRoles != null)
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(tr('Manage roles')),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onManageRoles!();
                    },
                  ),
                if (onTimeOut != null)
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(tr('Time out')),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onTimeOut!();
                    },
                  ),
                if (onRemoveTimeout != null)
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: Text(tr('Remove timeout')),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onRemoveTimeout!();
                    },
                  ),
                if (onKick != null)
                  ListTile(
                    leading: Icon(
                      Icons.person_remove_outlined,
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                    title: Text(
                      tr('Kick'),
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onKick!();
                    },
                  ),
                if (onBan != null)
                  ListTile(
                    leading: Icon(
                      Icons.block,
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                    title: Text(
                      tr('Ban'),
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onBan!();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
