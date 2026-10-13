import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_creation_sheet.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

/// Members who have the circle open right now (see
/// [CirclesRepository.circlePresence]). Watching it announces the current
/// user to the rest of the circle.
final circlePresenceProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, circleId) {
      return ref.watch(circlesRepositoryProvider).circlePresence(circleId);
    });

typedef CircleChannelViewBuilder =
    Widget Function(
      BuildContext context,
      CircleChannel channel,
      List<Widget> actions,
    );

/// Wide-screen circle layout: circle rail, channel sidebar, the selected
/// channel or feed, and a toggleable member list.
class CircleWorkspace extends ConsumerStatefulWidget {
  const CircleWorkspace({
    required this.detail,
    required this.onChanged,
    this.channelViewBuilder,
    super.key,
  });

  /// Below this width the member list starts hidden.
  static const memberListBreakpoint = 1280.0;

  final CircleDetail detail;
  final VoidCallback onChanged;
  final CircleChannelViewBuilder? channelViewBuilder;

  @override
  ConsumerState<CircleWorkspace> createState() => _CircleWorkspaceState();
}

class _CircleWorkspaceState extends ConsumerState<CircleWorkspace> {
  /// Selected channel id, or null for the feed.
  String? _selectedChannelId;
  var _channelsCollapsed = false;
  bool? _showMembers;

  @override
  void initState() {
    super.initState();
    final channels = widget.detail.channels;
    _selectedChannelId = channels.isEmpty ? null : channels.first.id;
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
    final unreadCounts = {
      for (final conversation
          in ref.watch(conversationsProvider).valueOrNull ??
              const <ConversationSummary>[])
        conversation.id: conversation.unreadCount,
    };
    final memberToggle = IconButton(
      tooltip: showMembers ? 'Hide member list' : 'Show member list',
      isSelected: showMembers,
      icon: const Icon(Icons.people_outline),
      selectedIcon: const Icon(Icons.people),
      onPressed: () => setState(() => _showMembers = !showMembers),
    );
    final selectedChannel = _selectedChannel;
    final onlineUserIds =
        ref.watch(circlePresenceProvider(detail.circle.id)).valueOrNull ??
        const <String>{};

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleRail(selectedCircleId: detail.circle.id),
          _ChannelSidebar(
            detail: detail,
            onChangeNickname: _changeNickname,
            selectedChannelId: selectedChannel?.id,
            unreadCounts: unreadCounts,
            collapsed: _channelsCollapsed,
            onToggleCollapsed: () {
              setState(() => _channelsCollapsed = !_channelsCollapsed);
            },
            onSelectChannel: (channel) {
              setState(() => _selectedChannelId = channel?.id);
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedChannel == null
                ? Scaffold(
                    appBar: AppBar(
                      title: const Text('Feed'),
                      actions: [memberToggle],
                    ),
                    body: CircleFeedView(
                      circleId: detail.circle.id,
                      posts: detail.posts,
                      onChanged: widget.onChanged,
                    ),
                  )
                : (widget.channelViewBuilder ?? _defaultChannelView)(
                    context,
                    selectedChannel,
                    [memberToggle],
                  ),
          ),
          if (showMembers) ...[
            const VerticalDivider(width: 1),
            _MemberList(
              detail: detail,
              onlineUserIds: onlineUserIds,
              onChangeNickname: _changeNickname,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changeNickname(CircleMember member) async {
    final nickname = await showCircleNicknameDialog(
      context,
      member: member,
      isSelf: member.isCurrentUser,
    );
    if (nickname == null || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(circlesRepositoryProvider)
          .setNickname(
            circleId: widget.detail.circle.id,
            userId: member.profile.id,
            nickname: nickname.isEmpty ? null : nickname,
          );
      widget.onChanged();
      // Open channel threads show nicknames on messages and mentions.
      ref.invalidate(chatThreadProvider);
      ref.invalidate(groupDetailProvider);
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not change nickname. Try again.')),
      );
    }
  }

  Widget _defaultChannelView(
    BuildContext context,
    CircleChannel channel,
    List<Widget> actions,
  ) {
    return ChatThreadScreen(
      key: ValueKey(channel.conversationId),
      conversationId: channel.conversationId,
      title: '# ${channel.name}',
      conversationType: ConversationType.channel,
      extraActions: actions,
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
      title: Text(widget.isSelf ? 'Change my nickname' : 'Change nickname'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSelf
                ? 'Only shown in this circle.'
                : 'Only shown in this circle for $fallbackName.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxCircleNicknameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Nickname',
              hintText: fallbackName,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.member.nickname != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Reset'),
          ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

const maxCircleNicknameLength = 32;

void showCircleInviteSheet(BuildContext context, CircleDetail detail) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => CircleInviteSheet(detail: detail),
  );
}

void showCircleChannelCreationSheet(BuildContext context, String circleId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => CircleChannelCreationSheet(circleId: circleId),
  );
}

class _ChannelSidebar extends StatelessWidget {
  const _ChannelSidebar({
    required this.detail,
    required this.onChangeNickname,
    required this.selectedChannelId,
    required this.unreadCounts,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onSelectChannel,
  });

  static const width = 240.0;

  final CircleDetail detail;
  final ValueChanged<CircleMember> onChangeNickname;
  final String? selectedChannelId;
  final Map<String, int> unreadCounts;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<CircleChannel?> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A collapsed category still shows the channel you are in.
    final visibleChannels = collapsed
        ? detail.channels.where((channel) => channel.id == selectedChannelId)
        : detail.channels;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarHeader(detail: detail, onChangeNickname: onChangeNickname),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  _ChannelRow(
                    icon: Icons.dynamic_feed_outlined,
                    label: 'Feed',
                    selected: selectedChannelId == null,
                    onTap: () => onSelectChannel(null),
                  ),
                  const SizedBox(height: 12),
                  _CategoryHeader(
                    label: 'Text Channels',
                    collapsed: collapsed,
                    onToggle: onToggleCollapsed,
                    onCreate: detail.canManageCircle
                        ? () => showCircleChannelCreationSheet(
                            context,
                            detail.circle.id,
                          )
                        : null,
                  ),
                  for (final channel in visibleChannels)
                    _ChannelRow(
                      icon: Icons.tag,
                      label: channel.name,
                      selected: channel.id == selectedChannelId,
                      unread: (unreadCounts[channel.conversationId] ?? 0) > 0,
                      onTap: () => onSelectChannel(channel),
                    ),
                  if (detail.channels.isEmpty && !collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: Text(
                        'No channels yet',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.detail, required this.onChangeNickname});

  final CircleDetail detail;
  final ValueChanged<CircleMember> onChangeNickname;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      detail.circle.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    CircleMember? currentMember;
    for (final member in detail.members) {
      if (member.isCurrentUser) {
        currentMember = member;
        break;
      }
    }
    final canManage = detail.canManageCircle;

    if (!canManage && currentMember == null) {
      return SizedBox(
        height: kToolbarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(alignment: Alignment.centerLeft, child: title),
        ),
      );
    }

    return SizedBox(
      height: kToolbarHeight,
      child: PopupMenuButton<_CircleMenuAction>(
        tooltip: 'Circle menu',
        position: PopupMenuPosition.under,
        onSelected: (action) {
          switch (action) {
            case _CircleMenuAction.invite:
              showCircleInviteSheet(context, detail);
            case _CircleMenuAction.createChannel:
              showCircleChannelCreationSheet(context, detail.circle.id);
            case _CircleMenuAction.changeNickname:
              onChangeNickname(currentMember!);
          }
        },
        itemBuilder: (context) => [
          if (canManage) ...const [
            PopupMenuItem(
              value: _CircleMenuAction.invite,
              child: ListTile(
                leading: Icon(Icons.person_add_alt_1_outlined),
                title: Text('Invite friends'),
              ),
            ),
            PopupMenuItem(
              value: _CircleMenuAction.createChannel,
              child: ListTile(
                leading: Icon(Icons.add_comment_outlined),
                title: Text('Create channel'),
              ),
            ),
          ],
          if (currentMember != null)
            const PopupMenuItem(
              value: _CircleMenuAction.changeNickname,
              child: ListTile(
                leading: Icon(Icons.badge_outlined),
                title: Text('Change my nickname'),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: title),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CircleMenuAction { invite, createChannel, changeNickname }

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.label,
    required this.collapsed,
    required this.onToggle,
    this.onCreate,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.expand_more,
                      size: 14,
                      color: style?.color,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(label.toUpperCase(), style: style),
                ],
              ),
            ),
          ),
        ),
        if (onCreate != null)
          IconButton(
            tooltip: 'Create channel',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.add),
            onPressed: onCreate,
          ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.unread = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final emphasized = selected || unread;
    final foreground = emphasized
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Stack(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Material(
            color: selected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: emphasized
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (unread && !selected)
          Positioned(
            left: -8,
            child: Container(
              key: const ValueKey('channel-unread-pill'),
              width: 4,
              height: 8,
              decoration: BoxDecoration(
                color: colorScheme.onSurface,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.detail,
    required this.onlineUserIds,
    required this.onChangeNickname,
  });

  static const width = 240.0;

  final CircleDetail detail;
  final Set<String> onlineUserIds;
  final ValueChanged<CircleMember> onChangeNickname;

  @override
  Widget build(BuildContext context) {
    final online = <CircleMember>[];
    final offline = <CircleMember>[];
    for (final member in detail.members) {
      (onlineUserIds.contains(member.profile.id) ? online : offline).add(
        member,
      );
    }
    online.sort((left, right) {
      final byRole = _roleRank(left.role).compareTo(_roleRank(right.role));
      return byRole != 0 ? byRole : _compareNames(left, right);
    });
    offline.sort(_compareNames);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          children: [
            for (final (label, groupMembers, isOnline) in [
              ('Online', online, true),
              ('Offline', offline, false),
            ])
              if (groupMembers.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    '${label.toUpperCase()} — ${groupMembers.length}',
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
                    onChangeNickname: detail.canChangeNickname(member)
                        ? () => onChangeNickname(member)
                        : null,
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

int _roleRank(String role) {
  return switch (role) {
    'owner' => 0,
    'admin' => 1,
    _ => 2,
  };
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
    this.onChangeNickname,
  });

  final CircleMember member;
  final bool isOnline;

  /// Null when the current user may not change this member's nickname.
  final VoidCallback? onChangeNickname;

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
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: roleIcon == null
              ? null
              : Tooltip(
                  message: member.role == 'owner' ? 'Owner' : 'Admin',
                  child: Icon(roleIcon, size: 16),
                ),
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
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('View profile'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openProfile(context);
                },
              ),
              if (onChangeNickname != null)
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Change nickname'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onChangeNickname!();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
