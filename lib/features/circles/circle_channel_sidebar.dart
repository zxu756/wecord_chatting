import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ai_guard_screen.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_automod_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_emojis_screen.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circle_membership_actions.dart';
import 'package:wecord/features/circles/circle_notification_settings_sheet.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/onboarding/guide_page.dart';
import 'package:wecord/features/circles/onboarding/guide_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/circle_avatar_sheet.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/features/voice/voice_participant_menu.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    this.color,
    this.listBottomPadding = 0,
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

  /// The background; surfaceContainerLow by default.
  final Color? color;

  /// Extra space below the channel list, e.g. for the phone's floating
  /// user panel.
  final double listBottomPadding;

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
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete category'),
      message: tr(
        'Delete "{name}"? Its channels move to the top of the channel '
        'list.',
        {'name': category.name},
      ),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) {
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
    final action = await showCircleActionMenu<_ChannelMenuAction>(
      context,
      title: channel.name,
      position: globalPosition,
      items: [
        CircleMenuItem(
          value: _ChannelMenuAction.settings,
          icon: Icons.settings_outlined,
          label: tr('Channel settings'),
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
        ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
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
        ? ref.watch(voiceChannelUserLimitsProvider(_circleId)).value ??
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

    final tokens = context.tokens;
    final c = tokens.colors;
    final mutedConversations = <String>{
      for (final conversation in conversations)
        if (conversation.isMuted) conversation.id,
    };
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final onlineCount = detail.members
        .where((member) => onlineUserIds.contains(member.profile.id))
        .length;
    final session = ref.watch(voiceSessionProvider);

    final list = ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
        wide ? 6 : 4,
        0,
        wide ? 6 : 4,
        12 + widget.listBottomPadding,
      ),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.md),
            boxShadow: tokens.shadows.menu,
          ),
          child: child,
        ),
      ),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleBannerCard(
              detail: detail,
              onlineCount: onlineCount,
              compact: wide,
              reviewCount: _reviewCount(detail, watch: true),
              onMenu: (position) => _openCircleMenu(position),
            ),
            CircleEventsEntry(
              circleId: _circleId,
              builder: (context, label, live, next) => wide
                  ? CircleChannelRow(
                      key: const ValueKey('circle-events-entry'),
                      icon: Icons.event_outlined,
                      label: label,
                      selected: false,
                      emphasized: true,
                      trailing: live
                          ? const _LiveNowPill()
                          : next != null && _isToday(next.startsAt)
                          ? CircleTag(
                              label: tr('Today'),
                              background: c.warningSoft,
                              foreground: c.warningText,
                            )
                          : null,
                      onTap: () => _openEvents(context),
                    )
                  : CircleEventCard(
                      key: const ValueKey('circle-events-entry'),
                      label: label,
                      live: live,
                      next: next,
                      onTap: () => _openEvents(context),
                    ),
            ),
            CircleChannelRow(
              icon: Icons.dynamic_feed_outlined,
              label: tr('Feed'),
              selected: widget.feedSelected,
              onTap: widget.onSelectFeed,
            ),
          ],
        ),
      ),
      footer: detail.channels.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                tr('No channels yet'),
                style: TextStyle(fontSize: 13, color: c.muted),
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
                  padding: EdgeInsets.only(top: index == 0 ? 4 : 10),
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
            final limitBadge = switch (userLimits[channel.id]) {
              final limit? when channel.isVoice => VoiceUserLimitBadge(
                count: voiceMembers.length,
                limit: limit,
              ),
              _ => null,
            };
            final selected =
                channel.id == widget.selectedChannelId &&
                widget.selectedThreadConversationId == null;
            void onContextMenu(Offset position) =>
                _showChannelMenu(channel, position);
            final contextMenu = detail.canOpenChannelSettings
                ? onContextMenu
                : null;
            final Widget channelRow;
            if (!wide && channel.isVoice && voiceMembers.isNotEmpty) {
              // Phones show a live card for a voice channel people are in.
              channelRow = CircleVoiceLiveCard(
                key: ValueKey('circle-channel-row-${channel.id}'),
                channel: channel,
                members: voiceMembers,
                speaking: voiceSpeakingUserIds(session, channel.id),
                joined: session?.channelId == channel.id,
                trailing: limitBadge,
                onTap: () => widget.onSelectChannel(channel),
                onContextMenu: contextMenu,
                longPressOpensMenu: !(canManage && dragOnLongPress),
              );
            } else {
              channelRow = CircleChannelRow(
                key: ValueKey('circle-channel-row-${channel.id}'),
                icon: circleChannelIcon(channel.kind),
                label: channel.name,
                conversationId: channel.isVoice ? null : channel.conversationId,
                locked: channel.isPrivate,
                trailing: limitBadge,
                selected: selected,
                unread: unread,
                muted: mutedConversations.contains(channel.conversationId),
                onTap: () => widget.onSelectChannel(channel),
                // Long presses drag channels for members who can sort them.
                onContextMenu: contextMenu,
                longPressOpensMenu: !(canManage && dragOnLongPress),
              );
            }
            final showMembers =
                voiceMembers.isNotEmpty && channelRow is CircleChannelRow;
            return KeyedSubtree(
              key: ValueKey('circle-channel-${channel.id}'),
              child: draggable(
                index,
                showMembers
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
                              icon: Icons.subdirectory_arrow_right_rounded,
                              label: thread.title ?? tr('Thread'),
                              conversationId: thread.id,
                              indent: 18,
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
      color: widget.color ?? c.sidebar,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            if (showVoicePanel)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: VoiceConnectedPanel(onOpen: widget.onOpenVoice),
              ),
            // The shell floats the user panel over this space.
            if (wide) const SizedBox(height: UserPanel.reservedHeight),
          ],
        ),
      ),
    );
  }

  void _openEvents(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CircleEventsScreen(circleId: _circleId),
      ),
    );
  }

  /// How many messages wait in the Review queue, for members who moderate.
  int _reviewCount(CircleDetail detail, {bool watch = false}) {
    if (!detail.canOpenReview) {
      return 0;
    }
    final count = messageReviewCountProvider(detail.circle.id);
    return (watch ? ref.watch(count) : ref.read(count)).value ?? 0;
  }

  Future<void> _openCircleMenu(Offset? position) async {
    final detail = widget.detail;
    final currentMember = detail.currentMember;
    final canManageChannels = detail.canManageChannels;
    final reviewCount = _reviewCount(detail);
    final hasGuide =
        ref.read(circleGuideProvider(detail.circle.id)).value?.enabled ?? false;
    // The circle's support page, for members; hidden on iPhone.
    String? supportUrl;
    if (supportLinksAvailable()) {
      try {
        supportUrl = await ref
            .read(circleSupportUrlProvider(detail.circle.id).future)
            .timeout(const Duration(seconds: 2));
      } on Object {
        supportUrl = null;
      }
      if (!mounted) {
        return;
      }
    }
    // What members use every day, what runs the circle, what keeps it safe;
    // a section with nothing for this member does not show.
    final everyday = <CircleMenuItem<_CircleMenuAction>>[
      if (detail.canCreateInvites)
        CircleMenuItem(
          value: _CircleMenuAction.invite,
          icon: Icons.person_add_alt_1_outlined,
          label: tr('Invite friends'),
          tone: SettingsTone.accent,
        ),
      CircleMenuItem(
        value: _CircleMenuAction.notificationSettings,
        icon: Icons.notifications_outlined,
        label: tr('Notification settings'),
      ),
      if (supportUrl != null)
        CircleMenuItem(
          value: _CircleMenuAction.support,
          icon: Icons.favorite_border_rounded,
          label: tr('Support this circle'),
        ),
      if (currentMember != null)
        CircleMenuItem(
          value: _CircleMenuAction.emojis,
          icon: Icons.emoji_emotions_outlined,
          label: tr('Emoji & stickers'),
        ),
      if (currentMember != null)
        CircleMenuItem(
          value: _CircleMenuAction.changeNickname,
          icon: Icons.badge_outlined,
          label: tr('Change my nickname'),
        ),
      if (currentMember != null)
        CircleMenuItem(
          value: _CircleMenuAction.changeCircleAvatar,
          icon: Icons.face_retouching_natural_outlined,
          label: tr('Change circle avatar'),
        ),
      // The circle has a guide (onboarding 2.0): questions or tasks.
      if (currentMember != null && hasGuide)
        CircleMenuItem(
          value: _CircleMenuAction.guide,
          icon: Icons.explore_outlined,
          label: tr('Member guide'),
        ),
    ];
    final manage = <CircleMenuItem<_CircleMenuAction>>[
      if (canManageChannels) ...[
        CircleMenuItem(
          value: _CircleMenuAction.createChannel,
          icon: Icons.add_comment_outlined,
          label: tr('Create channel'),
        ),
        CircleMenuItem(
          value: _CircleMenuAction.createCategory,
          icon: Icons.create_new_folder_outlined,
          label: tr('Create category'),
        ),
      ],
      if (canOpenCircleSettings(detail))
        CircleMenuItem(
          value: _CircleMenuAction.circleSettings,
          icon: Icons.tune,
          label: tr('Circle settings'),
        ),
      if (detail.canManageCircle)
        CircleMenuItem(
          value: _CircleMenuAction.onboarding,
          icon: Icons.rule,
          label: tr('Onboarding'),
        ),
    ];
    final safety = <CircleMenuItem<_CircleMenuAction>>[
      if (detail.canManageRoles)
        CircleMenuItem(
          value: _CircleMenuAction.roles,
          icon: CircleIcons.roles,
          label: tr('Roles'),
        ),
      if (detail.canBanMembers)
        CircleMenuItem(
          value: _CircleMenuAction.bans,
          icon: Icons.block,
          label: tr('Bans'),
        ),
      if (detail.canManageCircle)
        CircleMenuItem(
          value: _CircleMenuAction.autoMod,
          icon: CircleIcons.autoMod,
          label: tr('AutoMod'),
        ),
      if (detail.canManageCircle)
        CircleMenuItem(
          value: _CircleMenuAction.aiGuard,
          icon: CircleIcons.aiGuard,
          label: tr('AI guard'),
        ),
      if (detail.canOpenReview)
        CircleMenuItem(
          value: _CircleMenuAction.review,
          icon: Icons.fact_check_outlined,
          label: tr('Review'),
          tone: SettingsTone.warning,
          badge: reviewCount,
        ),
      if (detail.canViewAuditLog)
        CircleMenuItem(
          value: _CircleMenuAction.auditLog,
          icon: Icons.history,
          label: tr('Audit log'),
        ),
    ];
    // Leaving (or handing the circle on) stands apart, without a title.
    final account = <CircleMenuItem<_CircleMenuAction>>[
      if (detail.isOwner)
        CircleMenuItem(
          value: _CircleMenuAction.transferOwnership,
          icon: Icons.swap_horiz,
          label: tr('Transfer ownership'),
        )
      else if (currentMember != null)
        CircleMenuItem(
          value: _CircleMenuAction.leave,
          icon: Icons.logout,
          label: tr('Leave circle'),
          destructive: true,
        ),
    ];
    final sections = [
      (tr('Everyday'), everyday),
      (tr('Manage'), manage),
      (tr('Moderation & safety'), safety),
      (null, account),
    ].where((section) => section.$2.isNotEmpty).toList();
    final action = await showCircleActionMenu<_CircleMenuAction>(
      context,
      items: [for (final section in sections) ...section.$2],
      position: position,
      header: _CircleMenuHeader(detail: detail),
      groups: [for (final section in sections) section.$2.length],
      groupTitles: [for (final section in sections) section.$1],
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _CircleMenuAction.invite:
        showCircleInviteSheet(context, detail);
      case _CircleMenuAction.createChannel:
        _createChannel();
      case _CircleMenuAction.createCategory:
        _createCategory();
      case _CircleMenuAction.roles:
        openCircleRolesScreen(context, detail.circle.id);
      case _CircleMenuAction.circleSettings:
        openCircleSettingsScreen(context, detail.circle.id);
      case _CircleMenuAction.auditLog:
        openCircleAuditLogScreen(context, detail.circle.id);
      case _CircleMenuAction.bans:
        openCircleBansScreen(context, detail.circle.id);
      case _CircleMenuAction.autoMod:
        openCircleAutoModScreen(context, detail);
      case _CircleMenuAction.aiGuard:
        openCircleAiGuardScreen(context, detail);
      case _CircleMenuAction.review:
        openCircleReviewScreen(context, detail.circle.id);
      case _CircleMenuAction.onboarding:
        openCircleOnboardingSettings(context, detail);
      case _CircleMenuAction.emojis:
        openCircleEmojisScreen(context, detail.circle.id);
      case _CircleMenuAction.guide:
        openCircleGuide(
          context,
          circleId: detail.circle.id,
          circleName: detail.circle.name,
          channels: detail.channels,
        );
      case _CircleMenuAction.changeNickname:
        widget.onChangeNickname(currentMember!);
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
      case _CircleMenuAction.support:
        if (supportUrl != null) {
          openSupportLink(context, supportUrl);
        }
      case _CircleMenuAction.transferOwnership:
        transferCircleOwnership(context, detail: detail);
      case _CircleMenuAction.leave:
        leaveCircle(context, detail: detail);
    }
  }
}

bool _isToday(DateTime time) {
  final local = time.toLocal();
  return DateUtils.isSameDay(local, DateTime.now());
}

/// The icon of a channel of [kind] in lists.
IconData circleChannelIcon(CircleChannelKind kind) => switch (kind) {
  CircleChannelKind.forum => Icons.forum_outlined,
  CircleChannelKind.voice => Icons.volume_up_outlined,
  CircleChannelKind.stage => Icons.podcasts,
  CircleChannelKind.text => Icons.tag,
  CircleChannelKind.announcement => Icons.campaign_outlined,
};

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

/// Asks for a category name. Returns the trimmed name, or null when
/// cancelled.
Future<String?> showCircleCategoryNameDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showCircleDialog<String>(
    context,
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
    return CircleDialog(
      title: renaming ? tr('Rename category') : tr('Create category'),
      content: WeCordTextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxCircleCategoryNameLength,
        label: tr('Category name'),
        errorText: _errorText,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          label: renaming ? tr('Save') : tr('Create'),
          onPressed: _save,
        ),
      ],
    );
  }
}

/// The circle's name and avatar above its menu.
class _CircleMenuHeader extends StatelessWidget {
  const _CircleMenuHeader({required this.detail});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final circle = detail.circle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          CircleNetworkAvatar(
            name: circle.name,
            size: 44,
            url: circle.avatarUrl,
            thing: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  circle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                ),
                Text(
                  tr('{count} members', {'count': detail.members.length}),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CircleMenuAction {
  review,
  aiGuard,
  invite,
  createChannel,
  createCategory,
  circleSettings,
  roles,
  auditLog,
  bans,
  autoMod,
  onboarding,
  guide,
  emojis,
  notificationSettings,
  support,
  changeNickname,
  changeCircleAvatar,
  transferOwnership,
  leave,
}

enum _CategoryMenuAction { rename, delete }

enum _ChannelMenuAction { settings }

/// The circle's cover at the top of its channel list: a colored card with
/// the name, member and online counts, and the circle menu.
class CircleBannerCard extends StatelessWidget {
  const CircleBannerCard({
    required this.detail,
    required this.onlineCount,
    required this.onMenu,
    this.compact = false,
    this.reviewCount = 0,
    super.key,
  });

  final CircleDetail detail;
  final int onlineCount;

  /// Messages waiting in the Review queue (moderators only): a badge on the
  /// menu button, where the moderation tools are.
  final int reviewCount;

  /// Opens the circle menu; with the button's position on wide screens.
  final ValueChanged<Offset?> onMenu;

  /// The smaller desktop banner.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final circle = detail.circle;
    // A shade deeper than the avatar color, so the white counts clear 4.5:1
    // even across the stripes.
    final fill = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.1),
      WeCordAvatarColors.forSeed(circle.name),
    );
    final memberCount = detail.members.length;
    final subtitle = [
      tr('{count} members', {'count': memberCount}),
      if (onlineCount > 0) tr('{count} online', {'count': onlineCount}),
    ].join(' · ');
    final buttonSize = compact ? 30.0 : 34.0;

    return Container(
      key: const ValueKey('circle-banner'),
      margin: EdgeInsets.fromLTRB(
        compact ? 4 : 6,
        compact ? 4 : 10,
        compact ? 4 : 6,
        compact ? 6 : 10,
      ),
      height: compact ? 96 : 118,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BannerStripesPainter()),
          ),
          if (circle.avatarUrl != null)
            Positioned(
              left: compact ? 12 : 14,
              top: compact ? 12 : 14,
              child: CircleNetworkAvatar(
                name: circle.name,
                size: compact ? 30 : 36,
                url: circle.avatarUrl,
                thing: true,
              ),
            ),
          Positioned(
            left: compact ? 12 : 14,
            right: compact ? 10 : 12,
            bottom: compact ? 10 : 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          circle.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 17 : 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11.5 : 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (buttonContext) => WeCordPressable(
                    tooltip: tr('Circle menu'),
                    semanticLabel: reviewCount > 0
                        ? tr('Circle menu, {count} waiting for review', {
                            'count': reviewCount,
                          })
                        : tr('Circle menu'),
                    shape: const CircleBorder(),
                    pressedScale: 0.92,
                    onPressed: () {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      onMenu(
                        box?.localToGlobal(box.size.bottomRight(Offset.zero)),
                      );
                    },
                    builder: (context, states) {
                      final hovered =
                          states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed);
                      return SizedBox.square(
                        dimension: usesTouchInput(context)
                            ? minTouchTargetSize
                            : buttonSize,
                        child: Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: WeCordMotion.quick,
                                width: buttonSize,
                                height: buttonSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(
                                    alpha: hovered ? 0.36 : 0.25,
                                  ),
                                ),
                                child: Icon(
                                  Icons.more_horiz_rounded,
                                  size: compact ? 18 : 20,
                                  color: Colors.white,
                                ),
                              ),
                              if (reviewCount > 0)
                                Positioned(
                                  right: -4,
                                  top: -5,
                                  child: ExcludeSemantics(
                                    child: CountBadge(
                                      key: const ValueKey(
                                        'circle-review-badge',
                                      ),
                                      count: reviewCount,
                                      tone: BadgeTone.mention,
                                      size: 16,
                                      ringColor: fill,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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

/// Thin diagonal lines over a banner's color.
class _BannerStripesPainter extends CustomPainter {
  const _BannerStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 2;
    const gap = 18.0;
    // Lines at about 60 degrees, filling the card.
    const slope = 0.58;
    for (var x = -size.height / slope; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height / slope, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BannerStripesPainter oldDelegate) => false;
}

/// The phone's events card under the banner: the next event with its time,
/// or a plain Events entry when nothing is planned.
class CircleEventCard extends StatelessWidget {
  const CircleEventCard({
    required this.label,
    required this.live,
    required this.onTap,
    this.next,
    super.key,
  });

  final String label;
  final bool live;
  final CircleEvent? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final next = this.next;
    if (next == null) {
      return CircleChannelRow(
        icon: Icons.event_outlined,
        label: label,
        selected: false,
        onTap: onTap,
      );
    }
    final localizations = MaterialLocalizations.of(context);
    final start = next.startsAt.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(start).difference(today).inDays;
    final day = switch (days) {
      0 => tr('Today'),
      1 => tr('Tomorrow'),
      _ when days < 0 => tr('Now'),
      _ => localizations.narrowWeekdays[start.weekday % 7],
    };
    final time = days > 6
        ? '${start.month}/${start.day}'
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(start),
            alwaysUse24HourFormat: true,
          );
    final details = [
      label,
      if (next.interestedCount > 0)
        tr('{count} interested', {'count': next.interestedCount}),
      next.locationLabel,
    ].join(' · ');
    final fill = live ? c.liveSoft : c.warningSoft;
    final tileFill = live
        ? c.live.withValues(alpha: 0.18)
        : c.warning.withValues(alpha: 0.28);
    final tileText = live ? c.liveText : c.warningText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: WeCordPressable(
        onPressed: onTap,
        semanticLabel: '$label: ${next.title}',
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: ShapeDecoration(
                  color: tileFill,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.all(3),
                // Scales down rather than overflowing with large text.
                child: FittedBox(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tileText,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        time,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: tileText,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              if (live) const _LiveNowPill(),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// A voice channel people are in, on phones: who is there (speakers
/// ringed) and a way to join.
class CircleVoiceLiveCard extends StatelessWidget {
  const CircleVoiceLiveCard({
    required this.channel,
    required this.members,
    required this.speaking,
    required this.joined,
    required this.onTap,
    this.trailing,
    this.onContextMenu,
    this.longPressOpensMenu = true,
    super.key,
  });

  final CircleChannel channel;
  final List<VoiceMemberState> members;
  final Set<String> speaking;

  /// Whether the current user is in this channel.
  final bool joined;
  final VoidCallback onTap;
  final Widget? trailing;
  final ValueChanged<Offset>? onContextMenu;
  final bool longPressOpensMenu;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final speakers = [
      for (final member in members)
        if (speaking.contains(member.userId)) member,
    ];
    final status = speakers.isNotEmpty
        ? tr('{name} is speaking', {'name': speakers.first.name})
        : members.map((member) => member.name).join(', ');
    final action = joined
        ? tr('Joined')
        : tr('{count} · Join', {'count': members.length});

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapUp: onContextMenu == null
            ? null
            : (details) => onContextMenu!(details.globalPosition),
        child: WeCordPressable(
          onPressed: onTap,
          onLongPress: onContextMenu == null || !longPressOpensMenu
              ? null
              : () {
                  final box = context.findRenderObject()! as RenderBox;
                  onContextMenu!(
                    box.localToGlobal(box.size.centerLeft(Offset.zero)),
                  );
                },
          semanticLabel: '${channel.name}, $action',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          builder: (context, states) => Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
            decoration: BoxDecoration(
              color: c.successSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      circleChannelIcon(channel.kind),
                      size: 19,
                      color: c.successText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      trailing!,
                      const SizedBox(width: 6),
                    ],
                    Text(
                      action,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.successText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  key: ValueKey('voice-channel-members-${channel.id}'),
                  children: [
                    for (final (index, member) in members.take(_shown).indexed)
                      Transform.translate(
                        offset: Offset(-4.0 * index, 0),
                        child: _LiveAvatar(
                          member: member,
                          speaking: speaking.contains(member.userId),
                          ringColor: c.successSoft,
                        ),
                      ),
                    if (members.length > _shown)
                      Transform.translate(
                        offset: const Offset(-4.0 * _shown, 0),
                        child: Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.panel,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '+${members.length - _shown}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveAvatar extends StatelessWidget {
  const _LiveAvatar({
    required this.member,
    required this.speaking,
    required this.ringColor,
  });

  final VoiceMemberState member;
  final bool speaking;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: ValueKey('voice-live-avatar-${member.userId}'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ringColor,
        shape: BoxShape.circle,
        boxShadow: speaking
            ? [BoxShadow(color: c.success, spreadRadius: 2)]
            : null,
      ),
      child: CircleNetworkAvatar(
        name: member.name,
        size: 28,
        url: member.avatarUrl,
      ),
    );
  }
}

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

  Future<void> _showMenu(BuildContext context, Offset? position) async {
    final action = await showCircleActionMenu<_CategoryMenuAction>(
      context,
      title: label,
      position: position,
      items: [
        CircleMenuItem(
          value: _CategoryMenuAction.rename,
          icon: Icons.edit_outlined,
          label: tr('Rename category'),
        ),
        CircleMenuItem(
          value: _CategoryMenuAction.delete,
          icon: Icons.delete_outline,
          label: tr('Delete category'),
          destructive: true,
        ),
      ],
    );
    switch (action) {
      case _CategoryMenuAction.rename:
        onRename?.call();
      case _CategoryMenuAction.delete:
        onDelete?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = circleWideLayout(context);
    final hasMenu = onRename != null || onDelete != null;
    final touch = usesTouchInput(context);

    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapUp: hasMenu
          ? (details) => _showMenu(context, details.globalPosition)
          : null,
      child: Row(
        children: [
          Expanded(
            child: WeCordPressable(
              onPressed: onToggle,
              pressedScale: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
              ),
              builder: (context, states) => Container(
                constraints: BoxConstraints(
                  minHeight: touch ? minTouchTargetSize : 28,
                ),
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: wide ? 11.5 : 12,
                          fontWeight: FontWeight.w700,
                          color: c.subtle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: WeCordMotion.durationOf(
                        context,
                        WeCordMotion.quick,
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 14,
                        color: c.subtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasMenu)
            WeCordIconButton(
              tooltip: tr('Category options'),
              icon: Icons.more_horiz_rounded,
              variant: WeCordButtonVariant.ghost,
              size: 26,
              iconSize: 16,
              onPressed: () {
                final box = context.findRenderObject() as RenderBox?;
                _showMenu(
                  context,
                  box?.localToGlobal(box.size.centerRight(Offset.zero)),
                );
              },
            ),
          if (onCreate != null)
            WeCordIconButton(
              tooltip: tr('Create channel'),
              icon: Icons.add_rounded,
              variant: WeCordButtonVariant.ghost,
              size: 26,
              iconSize: 16,
              onPressed: onCreate,
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
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('circle-events-live'),
      padding: const EdgeInsets.only(right: 6),
      child: CircleTag(
        label: tr('Live now'),
        background: c.live,
        foreground: c.onLive,
      ),
    );
  }
}

/// A row of the channel list: icon, name, and an unread dot, lock or
/// [trailing] badge. Selected rows are raised (white on desktop); unread
/// rows are bold ink; muted rows are dimmed.
class CircleChannelRow extends StatelessWidget {
  const CircleChannelRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.unread = false,
    this.muted = false,
    this.emphasized = false,
    this.indent = 0,
    this.locked = false,
    this.onContextMenu,
    this.longPressOpensMenu = true,
    this.conversationId,
    super.key,
  });

  final IconData icon;
  final String label;

  /// The channel's or thread's conversation, whose unsent composer text
  /// shows after the name ("Draft half written").
  final String? conversationId;
  final bool selected;
  final bool unread;

  /// Notifications are muted: the row is dimmed.
  final bool muted;

  /// Ink text without the unread dot (the Events entry).
  final bool emphasized;
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
    final tokens = context.tokens;
    final c = tokens.colors;
    final wide = circleWideLayout(context);
    final touch = usesTouchInput(context);
    final showUnread = unread && !selected;
    final Color foreground;
    if (muted && !selected) {
      foreground = c.faint;
    } else if (selected || unread || emphasized) {
      foreground = c.ink;
    } else {
      foreground = c.muted;
    }
    final weight = unread && !muted
        ? FontWeight.w700
        : selected
        ? FontWeight.w600
        : FontWeight.w500;
    final radius = BorderRadius.circular(wide ? WeCordRadii.sm : 12);
    // Touch screens keep 44 at any density.
    final height = touch
        ? math.max(minTouchTargetSize, context.density.rowHeight(40))
        : context.density.rowHeight(wide ? 34 : 40);

    return Padding(
      padding: EdgeInsets.only(left: indent + 2, right: 2, top: 1, bottom: 1),
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapUp: onContextMenu == null
            ? null
            : (details) => onContextMenu!(details.globalPosition),
        child: WeCordPressable(
          onPressed: onTap,
          onLongPress: onContextMenu == null || !longPressOpensMenu
              ? null
              : () {
                  final box = context.findRenderObject()! as RenderBox;
                  onContextMenu!(
                    box.localToGlobal(box.size.centerLeft(Offset.zero)),
                  );
                },
          selected: selected,
          pressedScale: 0.98,
          shape: RoundedRectangleBorder(borderRadius: radius),
          builder: (context, states) {
            final hovered =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed);
            final Color fill;
            if (selected) {
              fill = wide ? c.panel : c.raised;
            } else if (hovered) {
              fill = c.ink.withValues(alpha: 0.05);
            } else {
              fill = c.ink.withValues(alpha: 0);
            }
            return AnimatedContainer(
              duration: WeCordMotion.quick,
              curve: WeCordMotion.standard,
              // A minimum, so large text grows the row instead of clipping.
              constraints: BoxConstraints(minHeight: height),
              padding: EdgeInsets.only(
                left: wide ? 10 : 12,
                right: 8,
                top: 4,
                bottom: 4,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                boxShadow: selected && wide ? tokens.shadows.hairline : null,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: indent > 0 ? 16 : (wide ? 18 : 19),
                    color: foreground,
                  ),
                  SizedBox(width: wide ? 9 : 10),
                  Expanded(
                    child: _ChannelRowLabel(
                      label: label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: indent > 0 ? 13.5 : (wide ? 14 : 15),
                        fontWeight: weight,
                      ),
                      // The open channel's draft is right there in its
                      // composer on desktop.
                      draftConversationId: selected && wide
                          ? null
                          : conversationId,
                    ),
                  ),
                  ?trailing,
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        key: const ValueKey('channel-lock-icon'),
                        size: 14,
                        color: c.subtle,
                      ),
                    ),
                  if (showUnread)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      child: Container(
                        key: const ValueKey('channel-unread-pill'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: muted ? c.faint : c.ink,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A channel row's name, then its draft when there is one: "Draft" in the
/// danger color and the text, muted. The name keeps at least 55% of the
/// row (all of it it needs when short); the draft takes the rest.
class _ChannelRowLabel extends ConsumerWidget {
  const _ChannelRowLabel({
    required this.label,
    required this.style,
    required this.draftConversationId,
  });

  final String label;
  final TextStyle style;
  final String? draftConversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final id = draftConversationId;
    if (id == null) {
      return name;
    }
    final draft = ref.watch(
      composerDraftsProvider.select((drafts) => drafts[id]),
    );
    if (draft == null || !draft.hasText) {
      return name;
    }
    final c = context.tokens.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.55,
              ),
              child: name,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                key: const ValueKey('channel-draft'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: tr('Draft'),
                      style: TextStyle(
                        color: c.dangerText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' ${draft.text.trim().replaceAll(RegExp(r'\s+'), ' ')}',
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (style.fontSize ?? 14) - 1.5,
                  fontWeight: FontWeight.w400,
                  color: c.muted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
