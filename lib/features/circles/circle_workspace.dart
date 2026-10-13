import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_creation_sheet.dart';
import 'package:wecord/features/circles/circle_feed_view.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

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

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleRail(selectedCircleId: detail.circle.id),
          _ChannelSidebar(
            detail: detail,
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
            _MemberList(members: detail.members),
          ],
        ],
      ),
    );
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
    required this.selectedChannelId,
    required this.unreadCounts,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onSelectChannel,
  });

  static const width = 240.0;

  final CircleDetail detail;
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
            _SidebarHeader(detail: detail),
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
  const _SidebarHeader({required this.detail});

  final CircleDetail detail;

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

    return SizedBox(
      height: kToolbarHeight,
      child: detail.canManageCircle
          ? PopupMenuButton<_CircleMenuAction>(
              tooltip: 'Circle menu',
              position: PopupMenuPosition.under,
              onSelected: (action) {
                switch (action) {
                  case _CircleMenuAction.invite:
                    showCircleInviteSheet(context, detail);
                  case _CircleMenuAction.createChannel:
                    showCircleChannelCreationSheet(context, detail.circle.id);
                }
              },
              itemBuilder: (context) => const [
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: title),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
    );
  }
}

enum _CircleMenuAction { invite, createChannel }

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
  const _MemberList({required this.members});

  static const width = 240.0;

  final List<CircleMember> members;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CircleMember>>{
      'Owner': [],
      'Admins': [],
      'Members': [],
    };
    for (final member in members) {
      final group = switch (member.role) {
        'owner' => 'Owner',
        'admin' => 'Admins',
        _ => 'Members',
      };
      groups[group]!.add(member);
    }
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          children: [
            for (final MapEntry(key: label, value: groupMembers)
                in groups.entries)
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
                for (final member in groupMembers) _MemberRow(member: member),
              ],
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member});

  final CircleMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = member.profile;
    final avatarUrl = ref
        .watch(avatarDisplayUrlProvider(profile.avatarUrl))
        .valueOrNull;
    final name = profile.displayName.trim().isEmpty
        ? profile.username
        : profile.displayName;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        child: avatarUrl == null
            ? Text(name.characters.first.toUpperCase())
            : null,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => context.push('${UserProfileScreen.path}/${profile.id}'),
    );
  }
}
