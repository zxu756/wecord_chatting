import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_automod_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_emojis_screen.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circle_membership_actions.dart';
import 'package:wecord/features/circles/circle_notification_settings_sheet.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/profile/circle_avatar_sheet.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';

const maxCircleCategoryNameLength = 32;

/// The circle's channel list: header menu, Feed and Events entries, uncategorized
/// channels, then each category. Categories collapse independently (kept per
/// device); a collapsed category still lists the selected channel and
/// channels with unread messages. Members who can manage channels can drag
/// channels and categories into a new order and manage categories. Voice
/// channels list who is connected under them, and while the current user
/// is in a voice call (on wide screens) the "Voice connected" panel sits at
/// the bottom.
class CircleChannelSidebar extends ConsumerStatefulWidget {
  const CircleChannelSidebar({
    required this.detail,
    required this.onSelectChannel,
    required this.onSelectFeed,
    required this.onChangeNickname,
    required this.onChanged,
    this.selectedChannelId,
    this.feedSelected = false,
    this.onSelectThread,
    this.selectedThreadConversationId,
    this.onOpenVoice,
    this.width = defaultWidth,
    super.key,
  });

  static const defaultWidth = 240.0;

  final CircleDetail detail;
  final String? selectedChannelId;
  final bool feedSelected;
  final ValueChanged<CircleChannel> onSelectChannel;
  final VoidCallback onSelectFeed;
  final ValueChanged<CircleMember> onChangeNickname;

  /// Opens a thread listed under its channel. Without it, threads are not
  /// listed.
  final ValueChanged<ConversationSummary>? onSelectThread;

  /// The thread conversation open next to the channel, if any.
  final String? selectedThreadConversationId;

  /// Opens the voice channel of the current call from the voice panel.
  final ValueChanged<VoiceSession>? onOpenVoice;

  /// Reloads the circle after a change made here.
  final VoidCallback onChanged;

  /// Fixed width, or null to fill the available space.
  final double? width;

  @override
  ConsumerState<CircleChannelSidebar> createState() =>
      _CircleChannelSidebarState();
}

class _CircleChannelSidebarState extends ConsumerState<CircleChannelSidebar> {
  var _collapsed = <String>{};

  /// Shown instead of the detail's order while a reorder is saved.
  CircleChannelLayout? _pendingLayout;
  var _savingLayouts = 0;

  String get _circleId => widget.detail.circle.id;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  @override
  void didUpdateWidget(CircleChannelSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.circle.id != _circleId) {
      _collapsed = <String>{};
      _pendingLayout = null;
      _loadCollapsed();
    } else if (!identical(oldWidget.detail, widget.detail) &&
        _savingLayouts == 0) {
      // Fresh data from the server replaces the optimistic order.
      _pendingLayout = null;
    }
  }

  Future<void> _loadCollapsed() async {
    final circleId = _circleId;
    Set<String> collapsed;
    try {
      collapsed = await ref
          .read(circleCategoryCollapseStoreProvider)
          .load(circleId);
    } catch (_) {
      return;
    }
    if (mounted && circleId == _circleId) {
      setState(() => _collapsed = collapsed);
    }
  }

  void _toggleCategory(String categoryId) {
    setState(() {
      _collapsed = {..._collapsed};
      if (!_collapsed.remove(categoryId)) {
        _collapsed.add(categoryId);
      }
    });
    _saveCollapsed();
  }

  void _saveCollapsed() {
    ref
        .read(circleCategoryCollapseStoreProvider)
        .save(_circleId, _collapsed)
        .catchError((Object _) {});
  }

  CircleChannelLayout get _layout {
    return _pendingLayout ??
        CircleChannelLayout.fromChannels(
          categories: widget.detail.categories,
          channels: widget.detail.channels,
        );
  }

  List<_SidebarEntry> _entries(
    CircleChannelLayout layout,
    Map<String, int> unreadCounts,
    Map<String, List<ConversationSummary>> threadsByParent,
  ) {
    bool unread(CircleChannel channel) =>
        (unreadCounts[channel.conversationId] ?? 0) > 0;
    bool threadStandsOut(ConversationSummary thread) =>
        thread.unreadCount > 0 ||
        thread.id == widget.selectedThreadConversationId;
    List<ConversationSummary> threads(CircleChannel channel, bool collapsed) {
      // Forum posts live in the forum, not the sidebar.
      if (channel.isForum) {
        return const [];
      }
      final all = threadsByParent[channel.conversationId] ?? const [];
      return collapsed ? all.where(threadStandsOut).toList() : all;
    }

    return [
      for (final channel in layout.uncategorized)
        _ChannelEntry(
          channel,
          unread: unread(channel),
          threads: threads(channel, false),
        ),
      for (final category in layout.categories) ...[
        _CategoryEntry(category),
        for (final channel in layout.channelsIn(category.id))
          if (!_collapsed.contains(category.id) ||
              channel.id == widget.selectedChannelId ||
              unread(channel) ||
              threads(channel, true).isNotEmpty)
            _ChannelEntry(
              channel,
              unread: unread(channel),
              threads: threads(channel, _collapsed.contains(category.id)),
            ),
      ],
    ];
  }

  /// [newIndex] is the moved entry's index once it has been removed from
  /// [oldIndex].
  void _reorder(List<_SidebarEntry> entries, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) {
      return;
    }
    final layout = _layout;
    final reordered = [...entries];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final before = reordered.take(newIndex);

    final CircleChannelLayout next;
    switch (moved) {
      case _CategoryEntry(:final category):
        next = layout.moveCategory(
          category.id,
          before.whereType<_CategoryEntry>().length,
        );
      case _ChannelEntry(:final channel):
        // The channel joins the category whose header is above it, right
        // after the visible channel above it (hidden channels of a
        // collapsed category keep their place).
        String? categoryId;
        for (final entry in before) {
          if (entry is _CategoryEntry) {
            categoryId = entry.category.id;
          }
        }
        final previous = newIndex == 0 ? null : reordered[newIndex - 1];
        var index = 0;
        if (previous is _ChannelEntry) {
          final siblings = layout
              .channelsIn(categoryId)
              .where((sibling) => sibling.id != channel.id)
              .toList();
          index =
              siblings.indexWhere(
                (sibling) => sibling.id == previous.channel.id,
              ) +
              1;
        }
        next = layout.moveChannel(
          channel.id,
          categoryId: categoryId,
          index: index,
        );
    }
    if (_sameLayout(next, layout)) {
      return;
    }
    _saveLayout(next);
  }

  Future<void> _saveLayout(CircleChannelLayout layout) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _pendingLayout = layout;
      _savingLayouts += 1;
    });
    try {
      await ref
          .read(circlesRepositoryProvider)
          .reorderChannels(circleId: _circleId, layout: layout);
      if (!mounted) {
        return;
      }
      setState(() => _savingLayouts -= 1);
      widget.onChanged();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingLayouts -= 1;
        // Roll back to the last order the server confirmed.
        if (identical(_pendingLayout, layout)) {
          _pendingLayout = null;
        }
      });
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not reorder channels. Try again.'))),
      );
    }
  }

  Future<void> _createCategory() async {
    final name = await showCircleCategoryNameDialog(context);
    if (name == null || !mounted) {
      return;
    }
    await _runCategoryAction(
      () => ref
          .read(circlesRepositoryProvider)
          .createChannelCategory(circleId: _circleId, name: name),
      failure: tr('Could not create category. Try again.'),
    );
  }

  Future<void> _renameCategory(CircleChannelCategory category) async {
    final name = await showCircleCategoryNameDialog(
      context,
      initialName: category.name,
    );
    if (name == null || name == category.name || !mounted) {
      return;
    }
    await _runCategoryAction(
      () => ref
          .read(circlesRepositoryProvider)
          .renameChannelCategory(categoryId: category.id, name: name),
      failure: tr('Could not rename category. Try again.'),
    );
  }

  Future<void> _deleteCategory(CircleChannelCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete category')),
        content: Text(
          tr(
            'Delete "{name}"? Its channels move to the top of the channel '
            'list.',
            {'name': category.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = await _runCategoryAction(
      () => ref
          .read(circlesRepositoryProvider)
          .deleteChannelCategory(category.id),
      failure: tr('Could not delete category. Try again.'),
    );
    if (deleted && _collapsed.contains(category.id)) {
      _collapsed = {..._collapsed}..remove(category.id);
      _saveCollapsed();
    }
  }

  Future<bool> _runCategoryAction(
    Future<Object?> Function() action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      widget.onChanged();
      return true;
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
      return false;
    }
  }

  Future<void> _showChannelMenu(
    CircleChannel channel,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_ChannelMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _ChannelMenuAction.settings,
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(tr('Channel settings')),
          ),
        ),
      ],
    );
    if (action == _ChannelMenuAction.settings && mounted) {
      openCircleChannelSettings(
        context,
        circleId: _circleId,
        channelId: channel.id,
      );
    }
  }

  void _createChannel({String? categoryId}) {
    showCircleChannelCreationSheet(
      context,
      _circleId,
      categories: _layout.categories,
      initialCategoryId: categoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = widget.detail;
    final canManage = detail.canManageChannels;
    final conversations =
        ref.watch(conversationsProvider).valueOrNull ??
        const <ConversationSummary>[];
    final unreadCounts = <String, int>{
      for (final conversation in conversations)
        conversation.id: conversation.unreadCount,
    };
    // A forum is unread while any of its posts is.
    for (final channel in detail.channels) {
      if (!channel.isForum) {
        continue;
      }
      var unread = 0;
      for (final conversation in conversations) {
        if (conversation.parentConversationId == channel.conversationId) {
          unread += conversation.unreadCount;
        }
      }
      unreadCounts[channel.conversationId] = unread;
    }
    final threadsByParent = widget.onSelectThread == null
        ? const <String, List<ConversationSummary>>{}
        : activeThreadsByParent(conversations, now: DateTime.now());
    // Only circles with voice channels ask who is in them.
    final hasVoice = detail.channels.any((channel) => channel.isVoice);
    final voiceStates = hasVoice
        ? watchVoiceStates(ref, _circleId)
        : const <VoiceMemberState>[];
    final userLimits = hasVoice
        ? ref.watch(voiceChannelUserLimitsProvider(_circleId)).valueOrNull ??
              const <String, int>{}
        : const <String, int>{};
    final voiceModeration = hasVoice ? VoiceModeration.forCircle(detail) : null;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final showVoicePanel = ref.watch(voiceSessionProvider) != null && wide;
    final layout = _layout;
    final entries = _entries(layout, unreadCounts, threadsByParent);
    final dragOnLongPress = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    Widget draggable(int index, Widget child) {
      if (!canManage) {
        return child;
      }
      return dragOnLongPress
          ? ReorderableDelayedDragStartListener(index: index, child: child)
          : ReorderableDragStartListener(index: index, child: child);
    }

    final list = ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleChannelRow(
              icon: Icons.dynamic_feed_outlined,
              label: tr('Feed'),
              selected: widget.feedSelected,
              onTap: widget.onSelectFeed,
            ),
            CircleEventsEntry(
              circleId: _circleId,
              builder: (context, label, live) => CircleChannelRow(
                key: const ValueKey('circle-events-entry'),
                icon: Icons.event_outlined,
                label: label,
                selected: false,
                unread: live,
                trailing: live ? const _LiveNowPill() : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        CircleEventsScreen(circleId: _circleId),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      footer: detail.channels.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(
                tr('No channels yet'),
                style: theme.textTheme.bodySmall,
              ),
            )
          : null,
      itemCount: entries.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(entries, oldIndex, newIndex),
      itemBuilder: (context, index) {
        switch (entries[index]) {
          case _CategoryEntry(:final category):
            final collapsed = _collapsed.contains(category.id);
            return KeyedSubtree(
              key: ValueKey('circle-category-${category.id}'),
              child: draggable(
                index,
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                  child: CircleCategoryHeader(
                    label: category.name,
                    collapsed: collapsed,
                    onToggle: () => _toggleCategory(category.id),
                    onCreate: canManage
                        ? () => _createChannel(categoryId: category.id)
                        : null,
                    onRename: canManage
                        ? () => _renameCategory(category)
                        : null,
                    onDelete: canManage
                        ? () => _deleteCategory(category)
                        : null,
                  ),
                ),
              ),
            );
          case _ChannelEntry(:final channel, :final unread, :final threads):
            final voiceMembers = channel.isVoice
                ? voiceMembersIn(voiceStates, channel.id)
                : const <VoiceMemberState>[];
            final channelRow = CircleChannelRow(
              key: ValueKey('circle-channel-row-${channel.id}'),
              icon: switch (channel.kind) {
                CircleChannelKind.forum => Icons.forum_outlined,
                CircleChannelKind.voice => Icons.volume_up_outlined,
                CircleChannelKind.text => Icons.tag,
              },
              label: channel.name,
              locked: channel.isPrivate,
              trailing: switch (userLimits[channel.id]) {
                final limit? when channel.isVoice => VoiceUserLimitBadge(
                  count: voiceMembers.length,
                  limit: limit,
                ),
                _ => null,
              },
              selected:
                  channel.id == widget.selectedChannelId &&
                  widget.selectedThreadConversationId == null,
              unread: unread,
              onTap: () => widget.onSelectChannel(channel),
              // Long presses drag channels for members who can sort them.
              onContextMenu: detail.canOpenChannelSettings
                  ? (position) => _showChannelMenu(channel, position)
                  : null,
              longPressOpensMenu: !(canManage && dragOnLongPress),
            );
            return KeyedSubtree(
              key: ValueKey('circle-channel-${channel.id}'),
              child: draggable(
                index,
                voiceMembers.isNotEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          channelRow,
                          VoiceChannelMembers(
                            channelId: channel.id,
                            members: voiceMembers,
                            moderation: voiceModeration,
                          ),
                        ],
                      )
                    : threads.isEmpty
                    ? channelRow
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          channelRow,
                          for (final thread in threads)
                            CircleChannelRow(
                              key: ValueKey('circle-thread-${thread.id}'),
                              icon: Icons.forum_outlined,
                              label: thread.title ?? tr('Thread'),
                              indent: 20,
                              selected:
                                  thread.id ==
                                  widget.selectedThreadConversationId,
                              unread: thread.unreadCount > 0,
                              onTap: () => widget.onSelectThread!(thread),
                            ),
                        ],
                      ),
              ),
            );
        }
      },
    );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarHeader(
              detail: detail,
              onChangeNickname: widget.onChangeNickname,
              onCreateChannel: _createChannel,
              onCreateCategory: _createCategory,
              onLeave: () => leaveCircle(context, detail: detail),
              onTransferOwnership: () =>
                  transferCircleOwnership(context, detail: detail),
            ),
            const Divider(height: 1),
            Expanded(child: list),
            if (showVoicePanel) ...[
              const Divider(height: 1),
              VoiceConnectedPanel(onOpen: widget.onOpenVoice),
            ],
            if (wide) ...[const Divider(height: 1), const UserPanel()],
          ],
        ),
      ),
    );
  }
}

bool _sameLayout(CircleChannelLayout left, CircleChannelLayout right) {
  final a = left.toJson();
  final b = right.toJson();
  return listEquals(a['categories'] as List, b['categories'] as List) &&
      listEquals(
        [
          for (final channel in a['channels'] as List)
            '${channel['id']}/${channel['category_id']}',
        ],
        [
          for (final channel in b['channels'] as List)
            '${channel['id']}/${channel['category_id']}',
        ],
      );
}

sealed class _SidebarEntry {
  const _SidebarEntry();
}

class _CategoryEntry extends _SidebarEntry {
  const _CategoryEntry(this.category);

  final CircleChannelCategory category;
}

class _ChannelEntry extends _SidebarEntry {
  const _ChannelEntry(
    this.channel, {
    required this.unread,
    this.threads = const [],
  });

  final CircleChannel channel;
  final bool unread;

  /// Active threads listed under the channel.
  final List<ConversationSummary> threads;
}

/// How long a thread stays in the sidebar after its last activity.
const sidebarThreadActivityWindow = Duration(days: 7);

/// Unarchived threads active within [sidebarThreadActivityWindow] of [now],
/// keyed by parent conversation id, most recently active first.
Map<String, List<ConversationSummary>> activeThreadsByParent(
  List<ConversationSummary> conversations, {
  required DateTime now,
}) {
  final cutoff = now.toUtc().subtract(sidebarThreadActivityWindow);
  final byParent = <String, List<ConversationSummary>>{};
  for (final conversation in conversations) {
    final parentId = conversation.parentConversationId;
    final activity =
        conversation.threadLastActivityAt ?? conversation.lastMessageAt;
    if (!conversation.isThread ||
        parentId == null ||
        conversation.threadArchivedAt != null ||
        activity == null ||
        activity.isBefore(cutoff)) {
      continue;
    }
    byParent.putIfAbsent(parentId, () => []).add(conversation);
  }
  for (final threads in byParent.values) {
    threads.sort((left, right) {
      final leftActivity = left.threadLastActivityAt ?? left.lastMessageAt!;
      final rightActivity = right.threadLastActivityAt ?? right.lastMessageAt!;
      return rightActivity.compareTo(leftActivity);
    });
  }
  return byParent;
}

/// Asks for a category name. Returns the trimmed name, or null when
/// cancelled.
Future<String?> showCircleCategoryNameDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CategoryNameDialog(initialName: initialName),
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({this.initialName});

  final String? initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = tr('Category name is required.'));
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final renaming = widget.initialName != null;
    return AlertDialog(
      scrollable: true,
      title: Text(renaming ? tr('Rename category') : tr('Create category')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxCircleCategoryNameLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: tr('Category name'),
          errorText: _errorText,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(renaming ? tr('Save') : tr('Create')),
        ),
      ],
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.detail,
    required this.onChangeNickname,
    required this.onCreateChannel,
    required this.onCreateCategory,
    required this.onLeave,
    required this.onTransferOwnership,
  });

  final CircleDetail detail;
  final ValueChanged<CircleMember> onChangeNickname;
  final VoidCallback onCreateChannel;
  final VoidCallback onCreateCategory;
  final VoidCallback onLeave;
  final VoidCallback onTransferOwnership;

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
    final currentMember = detail.currentMember;
    final canManageChannels = detail.canManageChannels;

    return SizedBox(
      height: kToolbarHeight,
      child: PopupMenuButton<_CircleMenuAction>(
        tooltip: tr('Circle menu'),
        position: PopupMenuPosition.under,
        onSelected: (action) {
          switch (action) {
            case _CircleMenuAction.invite:
              showCircleInviteSheet(context, detail);
            case _CircleMenuAction.createChannel:
              onCreateChannel();
            case _CircleMenuAction.createCategory:
              onCreateCategory();
            case _CircleMenuAction.roles:
              openCircleRolesScreen(context, detail.circle.id);
            case _CircleMenuAction.auditLog:
              openCircleAuditLogScreen(context, detail.circle.id);
            case _CircleMenuAction.bans:
              openCircleBansScreen(context, detail.circle.id);
            case _CircleMenuAction.autoMod:
              openCircleAutoModScreen(context, detail);
            case _CircleMenuAction.onboarding:
              openCircleOnboardingSettings(context, detail);
            case _CircleMenuAction.emojis:
              openCircleEmojisScreen(context, detail.circle.id);
            case _CircleMenuAction.changeNickname:
              onChangeNickname(currentMember!);
            case _CircleMenuAction.changeCircleAvatar:
              showCircleAvatarSheet(
                context,
                circleId: detail.circle.id,
                member: currentMember!,
              );
            case _CircleMenuAction.notificationSettings:
              showCircleNotificationSettingsSheet(
                context,
                circleId: detail.circle.id,
                circleName: detail.circle.name,
              );
            case _CircleMenuAction.transferOwnership:
              onTransferOwnership();
            case _CircleMenuAction.leave:
              onLeave();
          }
        },
        itemBuilder: (context) => [
          if (detail.canCreateInvites)
            PopupMenuItem(
              value: _CircleMenuAction.invite,
              child: ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: Text(tr('Invite friends')),
              ),
            ),
          if (canManageChannels) ...[
            PopupMenuItem(
              value: _CircleMenuAction.createChannel,
              child: ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: Text(tr('Create channel')),
              ),
            ),
            PopupMenuItem(
              value: _CircleMenuAction.createCategory,
              child: ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(tr('Create category')),
              ),
            ),
          ],
          if (detail.canManageRoles)
            PopupMenuItem(
              value: _CircleMenuAction.roles,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(tr('Roles')),
              ),
            ),
          if (detail.canBanMembers)
            PopupMenuItem(
              value: _CircleMenuAction.bans,
              child: ListTile(
                leading: const Icon(Icons.block),
                title: Text(tr('Bans')),
              ),
            ),
          if (detail.canManageCircle)
            PopupMenuItem(
              value: _CircleMenuAction.autoMod,
              child: ListTile(
                leading: const Icon(Icons.gpp_maybe_outlined),
                title: Text(tr('AutoMod')),
              ),
            ),
          if (detail.canManageCircle)
            PopupMenuItem(
              value: _CircleMenuAction.onboarding,
              child: ListTile(
                leading: const Icon(Icons.rule),
                title: Text(tr('Onboarding')),
              ),
            ),
          if (detail.canViewAuditLog)
            PopupMenuItem(
              value: _CircleMenuAction.auditLog,
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(tr('Audit log')),
              ),
            ),
          if (currentMember != null)
            PopupMenuItem(
              value: _CircleMenuAction.emojis,
              child: ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: Text(tr('Emoji & stickers')),
              ),
            ),
          PopupMenuItem(
            value: _CircleMenuAction.notificationSettings,
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(tr('Notification settings')),
            ),
          ),
          if (currentMember != null)
            PopupMenuItem(
              value: _CircleMenuAction.changeNickname,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(tr('Change my nickname')),
              ),
            ),
          if (currentMember != null)
            PopupMenuItem(
              value: _CircleMenuAction.changeCircleAvatar,
              child: ListTile(
                leading: const Icon(Icons.face_retouching_natural_outlined),
                title: Text(tr('Change circle avatar')),
              ),
            ),
          if (detail.isOwner)
            PopupMenuItem(
              value: _CircleMenuAction.transferOwnership,
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(tr('Transfer ownership')),
              ),
            )
          else if (currentMember != null)
            PopupMenuItem(
              value: _CircleMenuAction.leave,
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  tr('Leave circle'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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

enum _CircleMenuAction {
  invite,
  createChannel,
  createCategory,
  roles,
  auditLog,
  bans,
  autoMod,
  onboarding,
  emojis,
  notificationSettings,
  changeNickname,
  changeCircleAvatar,
  transferOwnership,
  leave,
}

enum _CategoryMenuAction { rename, delete }

enum _ChannelMenuAction { settings }

/// Collapsible category title. Managers get a create-channel button and a
/// menu (also on right click) to rename or delete the category.
class CircleCategoryHeader extends StatelessWidget {
  const CircleCategoryHeader({
    required this.label,
    required this.collapsed,
    required this.onToggle,
    this.onCreate,
    this.onRename,
    this.onDelete,
    super.key,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onCreate;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  void _onMenu(_CategoryMenuAction action) {
    switch (action) {
      case _CategoryMenuAction.rename:
        onRename?.call();
      case _CategoryMenuAction.delete:
        onDelete?.call();
    }
  }

  List<PopupMenuEntry<_CategoryMenuAction>> _menuItems() {
    return [
      PopupMenuItem(
        value: _CategoryMenuAction.rename,
        child: ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(tr('Rename category')),
        ),
      ),
      PopupMenuItem(
        value: _CategoryMenuAction.delete,
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(tr('Delete category')),
        ),
      ),
    ];
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_CategoryMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: _menuItems(),
    );
    if (action != null) {
      _onMenu(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasMenu = onRename != null || onDelete != null;
    final touch = usesTouchInput(context);

    return GestureDetector(
      onSecondaryTapUp: hasMenu
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onToggle,
              child: Container(
                constraints: BoxConstraints(
                  minHeight: touch ? minTouchTargetSize : 0,
                ),
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
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onCreate != null)
            IconButton(
              tooltip: tr('Create channel'),
              visualDensity: touch ? null : VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.add),
              onPressed: onCreate,
            ),
          if (hasMenu)
            PopupMenuButton<_CategoryMenuAction>(
              tooltip: tr('Category options'),
              iconSize: 16,
              style: ButtonStyle(
                visualDensity: touch ? null : VisualDensity.compact,
              ),
              icon: const Icon(Icons.more_horiz),
              onSelected: _onMenu,
              itemBuilder: (context) => _menuItems(),
            ),
        ],
      ),
    );
  }
}

/// "Live now" next to the Events entry while an event is on.
class _LiveNowPill extends StatelessWidget {
  const _LiveNowPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('circle-events-live'),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tr('Live now'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CircleChannelRow extends StatelessWidget {
  const CircleChannelRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.unread = false,
    this.indent = 0,
    this.locked = false,
    this.onContextMenu,
    this.longPressOpensMenu = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  /// Shown at the end of the row, such as a badge.
  final Widget? trailing;

  /// Extra left inset, for threads under their channel.
  final double indent;

  /// A private channel, marked with a lock.
  final bool locked;

  /// Opens the row's menu at a global position, on right click (and on long
  /// press when [longPressOpensMenu]).
  final ValueChanged<Offset>? onContextMenu;
  final bool longPressOpensMenu;

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
          padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
          child: Material(
            color: selected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              onSecondaryTapUp: onContextMenu == null
                  ? null
                  : (details) => onContextMenu!(details.globalPosition),
              onLongPress: onContextMenu == null || !longPressOpensMenu
                  ? null
                  : () {
                      final box = context.findRenderObject()! as RenderBox;
                      onContextMenu!(
                        box.localToGlobal(box.size.centerLeft(Offset.zero)),
                      );
                    },
              child: SizedBox(
                // Discord-dense with a mouse, finger-sized on touch screens.
                height: usesTouchInput(context) ? minTouchTargetSize : 34,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Icon(icon, size: indent > 0 ? 16 : 18, color: foreground),
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
                    ?trailing,
                    if (locked)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.lock_outline,
                          key: const ValueKey('channel-lock-icon'),
                          size: 14,
                          color: foreground,
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
