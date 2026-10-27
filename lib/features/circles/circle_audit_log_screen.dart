import 'package:flutter/material.dart';
import 'package:wecord/features/chats/edit_history/circle_edit_window.dart'
    show editWindowLabel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleAuditLogScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleAuditLogScreen(circleId: circleId),
    ),
  );
}

/// The circle's audit log, newest first, loading older entries as the list
/// scrolls. Entries with details expand to show what changed.
class CircleAuditLogScreen extends ConsumerStatefulWidget {
  const CircleAuditLogScreen({
    required this.circleId,
    this.pageSize = 50,
    this.now,
    super.key,
  });

  final String circleId;
  final int pageSize;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<CircleAuditLogScreen> createState() =>
      _CircleAuditLogScreenState();
}

class _CircleAuditLogScreenState extends ConsumerState<CircleAuditLogScreen> {
  final _scrollController = ScrollController();
  final _entries = <CircleAuditEntry>[];
  CircleAuditActionGroup? _filter;
  var _loading = false;
  var _hasMore = true;
  Object? _error;

  /// Bumped on every reload, so pages of an old filter are dropped.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) {
      return;
    }
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(circlesRepositoryProvider)
          .listAuditLog(
            circleId: widget.circleId,
            before: _entries.isEmpty ? null : _entries.last.createdAt,
            limit: widget.pageSize,
            action: _filter?.filter,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length >= widget.pageSize;
        _loading = false;
      });
      // A short first page may not fill the screen enough to scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeLoadMore();
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _setFilter(CircleAuditActionGroup? filter) {
    if (filter == _filter) {
      return;
    }
    setState(() {
      _filter = filter;
      _generation += 1;
      _entries.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadMore();
  }

  Future<void> _pickFilter(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    // -1 is "All actions"; others index the filter groups.
    const all = -1;
    final groups = CircleAuditActionGroup.filters;
    final picked = await showCircleActionMenu<int>(
      context,
      title: tr('Filter by action'),
      position: box?.localToGlobal(box.size.bottomLeft(Offset.zero)),
      items: [
        CircleMenuItem(
          value: all,
          icon: _filter == null ? Icons.check_rounded : Icons.filter_list,
          label: tr('All actions'),
          tone: _filter == null ? SettingsTone.accent : SettingsTone.neutral,
        ),
        for (final (index, group) in groups.indexed)
          CircleMenuItem(
            value: index,
            icon: _filter == group
                ? Icons.check_rounded
                : circleAuditGroupIcon(group),
            label: group.label,
            tone: _filter == group ? SettingsTone.accent : SettingsTone.neutral,
          ),
      ],
    );
    if (picked == null || !mounted) {
      return;
    }
    _setFilter(picked == all ? null : groups.elementAt(picked));
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('Audit log'),
      actions: [
        Builder(
          builder: (buttonContext) => WeCordIconButton(
            tooltip: tr('Filter by action'),
            icon: _filter == null ? Icons.filter_list : Icons.filter_list_alt,
            variant: WeCordButtonVariant.onPaper,
            size: 42,
            selected: _filter != null,
            onPressed: () => _pickFilter(buttonContext),
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_filter case final filter?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: WeCordPressable(
                  key: const ValueKey('circle-audit-filter-chip'),
                  tooltip: tr('Show all actions'),
                  onPressed: () => _setFilter(null),
                  builder: (context, states) => Container(
                    height: 34,
                    padding: const EdgeInsets.only(left: 14, right: 8),
                    decoration: ShapeDecoration(
                      color: c.ink,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.onInk,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.close_rounded, size: 16, color: c.onInk),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: _buildList(now)),
        ],
      ),
    );
  }

  Widget _buildList(DateTime now) {
    if (_entries.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.error_outline,
          title: tr('Could not load the audit log.'),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _loadMore,
          ),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return CircleEmptyState(
        icon: Icons.history,
        title: _filter == null
            ? tr('Nothing has been logged yet.')
            : tr('No {group} actions logged yet.', {
                'group': _filter!.label.toLowerCase(),
              }),
      );
    }
    return ListView.builder(
      key: const ValueKey('circle-audit-log-list'),
      controller: _scrollController,
      padding: circlePagePadding(context),
      itemCount: _entries.length + 1,
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: WeCordButton(
                  label: tr('Could not load more. Retry'),
                  variant: WeCordButtonVariant.onPaper,
                  size: WeCordButtonSize.small,
                  onPressed: _loadMore,
                ),
              ),
            );
          }
          if (_hasMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox(height: 16);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: CircleAuditEntryTile(entry: _entries[index], now: now),
        );
      },
    );
  }
}

/// One audit entry: an icon for the action, "X did Y" and when; entries
/// with details expand to list them.
class CircleAuditEntryTile extends StatefulWidget {
  const CircleAuditEntryTile({
    required this.entry,
    required this.now,
    super.key,
  });

  final CircleAuditEntry entry;
  final DateTime now;

  @override
  State<CircleAuditEntryTile> createState() => _CircleAuditEntryTileState();
}

class _CircleAuditEntryTileState extends State<CircleAuditEntryTile> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final entry = widget.entry;
    final details = circleAuditDetails(entry);
    final expandable = details.isNotEmpty;
    final bodyStyle = TextStyle(fontSize: 14, color: c.ink, height: 1.35);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsIconTile(icon: circleAuditIcon(entry.action), size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                circleAuditSummary(entry, bodyStyle),
                key: ValueKey('circle-audit-summary-${entry.id}'),
                style: bodyStyle,
              ),
              const SizedBox(height: 2),
              Text(
                formatAuditTime(entry.createdAt, now: widget.now),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.subtle,
                ),
              ),
            ],
          ),
        ),
        if (expandable) ...[
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: WeCordMotion.durationOf(context, WeCordMotion.quick),
            child: Icon(Icons.expand_more_rounded, size: 20, color: c.faint),
          ),
        ],
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        if (expandable && _expanded)
          Container(
            margin: const EdgeInsets.fromLTRB(48, 10, 0, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final detail in details)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${detail.label}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          TextSpan(text: detail.value),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    return WeCordPressable(
      key: ValueKey('circle-audit-${entry.id}'),
      onPressed: expandable
          ? () => setState(() => _expanded = !_expanded)
          : null,
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered =
            expandable &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.panel)
                : c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: content,
        );
      },
    );
  }
}

/// The icon shown for a filter group in the filter menu.
IconData circleAuditGroupIcon(CircleAuditActionGroup group) {
  return switch (group) {
    CircleAuditActionGroup.channel => Icons.tag,
    CircleAuditActionGroup.category => Icons.create_new_folder_outlined,
    CircleAuditActionGroup.role => CircleIcons.roles,
    CircleAuditActionGroup.member => Icons.people_outline,
    CircleAuditActionGroup.circle => Icons.swap_horiz,
    CircleAuditActionGroup.invite => Icons.add_link,
    CircleAuditActionGroup.message => Icons.chat_bubble_outline,
    CircleAuditActionGroup.thread => Icons.forum_outlined,
    CircleAuditActionGroup.post => Icons.article_outlined,
    CircleAuditActionGroup.forum => Icons.forum_outlined,
    CircleAuditActionGroup.event => Icons.event_outlined,
    CircleAuditActionGroup.webhook => Icons.smart_toy_outlined,
    CircleAuditActionGroup.discovery => Icons.explore_outlined,
    CircleAuditActionGroup.workflow => Icons.bolt_rounded,
    CircleAuditActionGroup.join => Icons.how_to_reg_outlined,
    _ => Icons.history,
  };
}

IconData circleAuditIcon(String action) {
  return switch (action) {
    'channel_create' => Icons.add_comment_outlined,
    'channel_reorder' => Icons.swap_vert,
    'channel_permissions_update' => Icons.lock_person_outlined,
    'channel_privacy_update' => Icons.lock_outline,
    'channel_slowmode_update' => Icons.timer_outlined,
    'channel_user_limit_update' => Icons.group_outlined,
    'member_voice_mute' => Icons.mic_off_outlined,
    'member_voice_unmute' => Icons.mic_none,
    'member_voice_deafen' => Icons.headset_off_outlined,
    'member_voice_undeafen' => Icons.headset_outlined,
    'member_voice_disconnect' => Icons.call_end,
    'member_voice_move' => Icons.move_up,
    'stage_start' => Icons.podcasts,
    'stage_update' => Icons.edit_note,
    'stage_end' => Icons.stop_circle_outlined,
    'sound_create' => Icons.library_music_outlined,
    'sound_delete' => Icons.music_off_outlined,
    'channel_update' => Icons.edit_note,
    'channel_delete' => Icons.delete_sweep_outlined,
    'category_create' => Icons.create_new_folder_outlined,
    'category_rename' => Icons.drive_file_rename_outline,
    'category_delete' => Icons.folder_delete_outlined,
    'role_create' => Icons.add_moderator_outlined,
    'role_update' => CircleIcons.roles,
    'role_delete' => Icons.remove_moderator_outlined,
    'role_reorder' => Icons.swap_vert,
    'member_add' => Icons.person_add_alt_1_outlined,
    'member_roles_update' => Icons.badge_outlined,
    'member_nickname_update' => Icons.edit_outlined,
    'member_title_update' => Icons.military_tech_outlined,
    'honors_update' => Icons.emoji_events_outlined,
    'member_kick' => Icons.person_remove_outlined,
    'member_ban' => Icons.block,
    'member_unban' => Icons.lock_open_outlined,
    'member_timeout' => Icons.timer_outlined,
    'member_timeout_remove' => Icons.timer_off_outlined,
    'member_leave' => Icons.logout,
    'circle_ownership_transfer' => Icons.swap_horiz,
    'invite_create' => Icons.add_link,
    'invite_revoke' => Icons.link_off,
    'message_pin' => Icons.push_pin_outlined,
    'message_unpin' => Icons.push_pin,
    'message_delete' => Icons.delete_outline,
    'thread_archive' => Icons.archive_outlined,
    'thread_unarchive' => Icons.unarchive_outlined,
    'post_delete' => Icons.delete_outline,
    'post_feature' => Icons.star_rounded,
    'post_unfeature' => Icons.star_outline_rounded,
    'forum_tag_create' => Icons.new_label_outlined,
    'forum_tag_update' => Icons.label_outline,
    'forum_tag_delete' => Icons.label_off_outlined,
    'forum_tag_reorder' => Icons.swap_vert,
    'forum_post_pin' => Icons.push_pin_outlined,
    'forum_post_unpin' => Icons.push_pin,
    'forum_post_solved' => Icons.check_circle_outline_rounded,
    'forum_post_reopened' => Icons.help_outline_rounded,
    'event_create' => Icons.event_outlined,
    'event_update' => Icons.edit_calendar_outlined,
    'event_cancel' => Icons.event_busy_outlined,
    'webhook_create' => Icons.smart_toy_outlined,
    'webhook_update' => Icons.drive_file_rename_outline,
    'webhook_regenerate' => Icons.key_outlined,
    'webhook_delete' => Icons.delete_outline,
    'automod_rule_create' => Icons.add_moderator_outlined,
    'automod_rule_update' => CircleIcons.autoMod,
    'automod_rule_delete' => Icons.remove_moderator_outlined,
    'automod_block' => Icons.block,
    'automod_alert' => Icons.campaign_outlined,
    'automod_timeout' => Icons.timer_outlined,
    'guard_update' => CircleIcons.aiGuard,
    'guard_hold' => Icons.pause_circle_outline,
    'guard_flag' => Icons.flag_outlined,
    'guard_approve' => Icons.check_circle_outline,
    'guard_remove' => Icons.delete_outline,
    'guard_item_flag' => Icons.flag_outlined,
    'guard_item_dismiss' => Icons.check_circle_outline,
    'onboarding_update' => Icons.rule,
    'kb_page_create' => Icons.note_add_outlined,
    'kb_page_move' => Icons.drive_file_move_outlined,
    'kb_page_delete' => Icons.delete_outline,
    'kb_page_access' => Icons.manage_accounts_outlined,
    'onboarding_roles' => Icons.badge_outlined,
    'join_request_approve' => Icons.how_to_reg_outlined,
    'join_request_deny' => Icons.person_off_outlined,
    'join_settings_update' => Icons.how_to_reg_outlined,
    'invite_skip_review' => Icons.add_link,
    'member_unban_auto' => Icons.lock_open_outlined,
    'member_batch_action' => Icons.groups_2_outlined,
    'thread_lock' => Icons.lock_outline,
    'thread_unlock' => Icons.lock_open_outlined,
    'mod_note_add' || 'mod_note_delete' => Icons.sticky_note_2_outlined,
    'mod_warn' => Icons.warning_amber_rounded,
    'ban_appeal_submit' => Icons.mark_email_unread_outlined,
    'ban_appeal_approve' => Icons.lock_open_outlined,
    'ban_appeal_deny' => Icons.block,
    'raid_lockdown' => Icons.shield_outlined,
    'raid_release' => Icons.shield_moon_outlined,
    'raid_settings_update' => Icons.shield_outlined,
    'invites_pause' => Icons.pause_circle_outline,
    'invites_resume' => Icons.play_circle_outline,
    'discovery_update' => Icons.explore_outlined,
    'workflow_create' || 'workflow_update' => Icons.bolt_rounded,
    'workflow_pause' => Icons.pause_circle_outline,
    'workflow_resume' => Icons.play_circle_outline,
    'workflow_delete' => Icons.delete_outline,
    'slug_update' => Icons.link_rounded,
    'edit_window_update' => Icons.history_toggle_off,
    'bot_callback_set' ||
    'bot_callback_rotate' ||
    'bot_callback_clear' => Icons.webhook_outlined,
    'bot_events_set' ||
    'bot_events_rotate' ||
    'bot_events_clear' => Icons.bolt_rounded,
    'bot_open_update' => Icons.smart_toy_outlined,
    'emoji_create' || 'sticker_create' => Icons.add_reaction_outlined,
    'emoji_update' || 'sticker_update' => Icons.drive_file_rename_outline,
    'emoji_delete' || 'sticker_delete' => Icons.delete_outline,
    _ => Icons.history,
  };
}

/// "Ada created channel #general", with names in bold.
TextSpan circleAuditSummary(CircleAuditEntry entry, TextStyle? style) {
  final bold = (style ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w600,
  );
  final actor = entry.actor?.name ?? tr('Someone');
  final target = entry.targetLabel ?? tr('something');
  final channel = '#$target';
  final changes = entry.changes;
  final inChannel = switch (changes['channel_name']) {
    final String channelName => '#$channelName',
    _ => null,
  };
  final oldName = _formatValue('name', _oldValue(changes['name']));

  final (String template, Map<String, String> names) = switch (entry.action) {
    'channel_create' => (
      tr('{actor} created channel {channel}'),
      {'channel': channel},
    ),
    'channel_reorder' => (tr('{actor} reordered channels'), {}),
    'channel_permissions_update' => switch (changes['target_name']) {
      final String targetName => (
        tr('{actor} updated permissions for {name} in {channel}'),
        {'name': targetName, 'channel': channel},
      ),
      _ => (
        tr('{actor} updated permissions in {channel}'),
        {'channel': channel},
      ),
    },
    'channel_privacy_update' => (
      tr('{actor} changed the privacy of {channel}'),
      {'channel': channel},
    ),
    'channel_slowmode_update' => (
      tr('{actor} set slowmode in {channel} to {duration}'),
      {
        'channel': channel,
        'duration': _formatSeconds(_newValue(changes['slowmode_seconds'])),
      },
    ),
    'channel_user_limit_update' => switch (_newValue(changes['user_limit'])) {
      final int limit when limit > 0 => (
        tr('{actor} set the user limit of {target} to {limit}'),
        {'limit': '$limit'},
      ),
      _ => (tr('{actor} removed the user limit of {target}'), {}),
    },
    'member_voice_mute' => (tr('{actor} server muted {target}'), {}),
    'member_voice_unmute' => (tr('{actor} server unmuted {target}'), {}),
    'member_voice_deafen' => (tr('{actor} server deafened {target}'), {}),
    'member_voice_undeafen' => (tr('{actor} server undeafened {target}'), {}),
    'member_voice_disconnect' => (
      tr('{actor} disconnected {target} from voice'),
      {},
    ),
    'member_voice_move' => switch (changes['channel_name']) {
      final String channelName => (
        tr('{actor} moved {target} to {channel}'),
        {'channel': channelName},
      ),
      _ => (tr('{actor} moved {target} to another voice channel'), {}),
    },
    'channel_update' => switch (changes['name']) {
      {'old': final String oldName} => (
        tr('{actor} renamed channel {old} to {channel}'),
        {'old': '#$oldName', 'channel': channel},
      ),
      _ => (tr('{actor} updated channel {channel}'), {'channel': channel}),
    },
    'channel_delete' => (
      tr('{actor} deleted channel {channel}'),
      {'channel': channel},
    ),
    'category_create' => (tr('{actor} created category {target}'), {}),
    'category_rename' => (
      tr('{actor} renamed category {old} to {target}'),
      {'old': oldName},
    ),
    'category_delete' => (tr('{actor} deleted category {target}'), {}),
    'role_create' => (tr('{actor} created role {target}'), {}),
    'role_update' => (tr('{actor} updated role {target}'), {}),
    'role_delete' => (tr('{actor} deleted role {target}'), {}),
    'role_reorder' => (tr('{actor} reordered roles'), {}),
    'member_add' => (tr('{actor} added {target} to the circle'), {}),
    'member_roles_update' => (tr('{actor} updated the roles of {target}'), {}),
    'member_nickname_update' => (
      tr('{actor} changed the nickname of {target}'),
      {},
    ),
    'member_title_update' => switch (_newValue(changes['title'])) {
      final String title when title.isNotEmpty => (
        tr('{actor} gave {target} the title {title}'),
        {'title': title},
      ),
      _ => (tr('{actor} removed the title of {target}'), {}),
    },
    'honors_update' => switch (_newValue(changes['enabled'])) {
      false => (tr('{actor} turned member honors off'), {}),
      _ => (tr('{actor} turned member honors on'), {}),
    },
    'member_kick' => (tr('{actor} kicked {target}'), {}),
    'member_ban' => (tr('{actor} banned {target}'), {}),
    'member_unban' => (tr('{actor} unbanned {target}'), {}),
    'member_timeout' => (tr('{actor} timed out {target}'), {}),
    'member_timeout_remove' => (
      tr('{actor} removed the timeout of {target}'),
      {},
    ),
    'member_leave' => (tr('{actor} left the circle'), {}),
    'circle_ownership_transfer' => (
      tr('{actor} transferred ownership to {target}'),
      {},
    ),
    'invite_create' => (tr('{actor} created invite {target}'), {}),
    'invite_revoke' => (tr('{actor} revoked invite {target}'), {}),
    'message_pin' => (
      tr('{actor} pinned a message in {channel}'),
      {'channel': channel},
    ),
    'message_unpin' => (
      tr('{actor} unpinned a message in {channel}'),
      {'channel': channel},
    ),
    'message_delete' =>
      inChannel == null
          ? (tr('{actor} deleted a message by {target}'), {})
          : (
              tr('{actor} deleted a message by {target} in {channel}'),
              {'channel': inChannel},
            ),
    'thread_archive' => (tr('{actor} archived thread {target}'), {}),
    'thread_unarchive' => (tr('{actor} unarchived thread {target}'), {}),
    'post_delete' => (tr('{actor} deleted a post by {target}'), {}),
    'post_feature' => (tr('{actor} featured a post by {target}'), {}),
    'post_unfeature' => (
      tr('{actor} removed a post by {target} from Featured'),
      {},
    ),
    'forum_tag_create' =>
      inChannel == null
          ? (tr('{actor} created tag {target}'), {})
          : (
              tr('{actor} created tag {target} in {channel}'),
              {'channel': inChannel},
            ),
    'forum_tag_update' =>
      inChannel == null
          ? (tr('{actor} updated tag {target}'), {})
          : (
              tr('{actor} updated tag {target} in {channel}'),
              {'channel': inChannel},
            ),
    'forum_tag_delete' =>
      inChannel == null
          ? (tr('{actor} deleted tag {target}'), {})
          : (
              tr('{actor} deleted tag {target} in {channel}'),
              {'channel': inChannel},
            ),
    'forum_tag_reorder' => (
      tr('{actor} reordered the tags of {channel}'),
      {'channel': channel},
    ),
    'forum_post_pin' =>
      inChannel == null
          ? (tr('{actor} pinned post {target}'), {})
          : (
              tr('{actor} pinned post {target} in {channel}'),
              {'channel': inChannel},
            ),
    'forum_post_unpin' =>
      inChannel == null
          ? (tr('{actor} unpinned post {target}'), {})
          : (
              tr('{actor} unpinned post {target} in {channel}'),
              {'channel': inChannel},
            ),
    'forum_post_solved' =>
      inChannel == null
          ? (tr('{actor} marked question {target} as solved'), {})
          : (
              tr('{actor} marked question {target} in {channel} as solved'),
              {'channel': inChannel},
            ),
    'forum_post_reopened' =>
      inChannel == null
          ? (tr('{actor} reopened question {target}'), {})
          : (
              tr('{actor} reopened question {target} in {channel}'),
              {'channel': inChannel},
            ),
    'event_create' => (tr('{actor} scheduled event {target}'), {}),
    'event_update' => switch (changes['title']) {
      {'old': final String oldTitle} => (
        tr('{actor} renamed event {old} to {target}'),
        {'old': oldTitle},
      ),
      _ => (tr('{actor} updated event {target}'), {}),
    },
    'event_cancel' => (tr('{actor} cancelled event {target}'), {}),
    'webhook_create' =>
      inChannel == null
          ? (tr('{actor} created webhook {target}'), {})
          : (
              tr('{actor} created webhook {target} in {channel}'),
              {'channel': inChannel},
            ),
    'webhook_update' => switch (changes['name']) {
      {'old': final String oldName} => (
        tr('{actor} renamed webhook {old} to {target}'),
        {'old': oldName},
      ),
      _ => (tr('{actor} updated webhook {target}'), {}),
    },
    'webhook_regenerate' => (
      tr('{actor} regenerated the URL of webhook {target}'),
      {},
    ),
    'webhook_delete' =>
      inChannel == null
          ? (tr('{actor} deleted webhook {target}'), {})
          : (
              tr('{actor} deleted webhook {target} in {channel}'),
              {'channel': inChannel},
            ),
    'emoji_create' => (
      tr('{actor} added emoji {emoji}'),
      {'emoji': ':$target:'},
    ),
    'emoji_update' => (
      tr('{actor} renamed emoji {old} to {emoji}'),
      {'old': ':$oldName:', 'emoji': ':$target:'},
    ),
    'emoji_delete' => (
      tr('{actor} deleted emoji {emoji}'),
      {'emoji': ':$target:'},
    ),
    'sticker_create' => (tr('{actor} added sticker {target}'), {}),
    'sticker_update' => (
      tr('{actor} renamed sticker {old} to {target}'),
      {'old': oldName},
    ),
    'sticker_delete' => (tr('{actor} deleted sticker {target}'), {}),
    'stage_start' => switch (changes['topic']) {
      final String topic => (
        tr('{actor} started a stage in {target}: {topic}'),
        {'topic': topic},
      ),
      _ => (tr('{actor} started a stage in {target}'), {}),
    },
    'stage_update' => (tr('{actor} changed the stage topic in {target}'), {}),
    'stage_end' => (tr('{actor} ended the stage in {target}'), {}),
    'sound_create' => (tr('{actor} added sound {target}'), {}),
    'sound_delete' => (tr('{actor} deleted sound {target}'), {}),
    'automod_rule_create' => (tr('{actor} created AutoMod rule {target}'), {}),
    'automod_rule_update' => switch (changes['name']) {
      {'old': final String oldName} => (
        tr('{actor} renamed AutoMod rule {old} to {target}'),
        {'old': oldName},
      ),
      _ => (tr('{actor} updated AutoMod rule {target}'), {}),
    },
    'automod_rule_delete' => (tr('{actor} deleted AutoMod rule {target}'), {}),
    'automod_block' =>
      inChannel == null
          ? (tr('AutoMod blocked a message by {target}'), {})
          : (
              tr('AutoMod blocked a message by {target} in {channel}'),
              {'channel': inChannel},
            ),
    'automod_alert' =>
      inChannel == null
          ? (tr('AutoMod sent an alert about {target}'), {})
          : (
              tr('AutoMod sent an alert about {target} in {channel}'),
              {'channel': inChannel},
            ),
    'automod_timeout' => (tr('AutoMod timed out {target}'), {}),
    'guard_update' => (tr('{actor} updated the AI guard'), {}),
    'guard_hold' =>
      inChannel == null
          ? (tr('AI guard held a message by {target}'), {})
          : (
              tr('AI guard held a message by {target} in {channel}'),
              {'channel': inChannel},
            ),
    'guard_flag' =>
      inChannel == null
          ? (tr('AI guard flagged a message by {target}'), {})
          : (
              tr('AI guard flagged a message by {target} in {channel}'),
              {'channel': inChannel},
            ),
    'guard_approve' => (
      tr('{actor} approved a message by {target} from the review queue'),
      {},
    ),
    'guard_remove' => (
      tr('{actor} removed a message by {target} from the review queue'),
      {},
    ),
    'guard_item_flag' => switch (changes['item_type']) {
      'circle_event' => (tr('AI guard flagged an event by {target}'), {}),
      'note' => (tr('AI guard flagged a note by {target}'), {}),
      'circle_post' => (tr('AI guard flagged a post by {target}'), {}),
      'task_list' ||
      'task_item' => (tr('AI guard flagged a task by {target}'), {}),
      _ => (tr('AI guard flagged something made by {target}'), {}),
    },
    'guard_item_dismiss' => (
      tr('{actor} dismissed a flagged item by {target} from the review queue'),
      {},
    ),
    'onboarding_update' => (tr('{actor} updated the onboarding'), {}),
    'kb_page_create' => (
      (entry.targetLabel ?? '').isEmpty
          ? tr('{actor} added a knowledge base page')
          : tr('{actor} added the knowledge base page {target}'),
      {},
    ),
    'kb_page_move' => (
      (entry.targetLabel ?? '').isEmpty
          ? tr('{actor} moved a knowledge base page')
          : tr('{actor} moved the knowledge base page {target}'),
      {},
    ),
    'kb_page_delete' => (
      (entry.targetLabel ?? '').isEmpty
          ? tr('{actor} deleted a knowledge base page')
          : tr('{actor} deleted the knowledge base page {target}'),
      {},
    ),
    'kb_page_access' => (
      tr('{actor} changed who can read or edit a knowledge base page'),
      {},
    ),
    'onboarding_roles' => (tr('{target} chose roles through onboarding'), {}),
    'edit_window_update' => switch (_newValue(changes['edit_window_seconds'])) {
      final int seconds when seconds > 0 => (
        tr('{actor} set the edit time limit to {time}'),
        {'time': editWindowLabel(seconds)},
      ),
      _ => (tr('{actor} removed the edit time limit'), {}),
    },
    'join_request_approve' => (
      tr('{actor} approved the request of {target} to join'),
      {},
    ),
    'join_request_deny' => (
      tr('{actor} turned down the request of {target} to join'),
      {},
    ),
    'join_settings_update' => switch (_newValue(changes['join_mode'])) {
      'apply' => (tr('{actor} made the circle apply to join'), {}),
      'invite_only' => (tr('{actor} made the circle invite only'), {}),
      'open' => (tr('{actor} opened the circle to everyone'), {}),
      _ => (tr('{actor} updated the join questions'), {}),
    },
    'invite_skip_review' => (
      tr('{actor} made invite {target} skip review'),
      {},
    ),
    'member_unban_auto' => (tr('The ban on {target} ended'), {}),
    'member_batch_action' => switch (changes['action']) {
      'timeout' => (tr('{actor} timed out several members at once'), {}),
      'untimeout' => (
        tr('{actor} ended the timeout of several members at once'),
        {},
      ),
      'kick' => (tr('{actor} kicked several members at once'), {}),
      'ban' => (tr('{actor} banned several members at once'), {}),
      _ => (tr('{actor} acted on several members at once'), {}),
    },
    'thread_lock' => (tr('{actor} locked thread {target}'), {}),
    'thread_unlock' => (tr('{actor} unlocked thread {target}'), {}),
    'mod_note_add' => (tr('{actor} added a note about {target}'), {}),
    'mod_warn' => (tr('{actor} warned {target}'), {}),
    'mod_note_delete' => (tr('{actor} deleted a note about {target}'), {}),
    'ban_appeal_submit' => (tr('{target} appealed their ban'), {}),
    'ban_appeal_approve' => (
      tr('{actor} approved the ban appeal of {target}'),
      {},
    ),
    'ban_appeal_deny' => (
      tr('{actor} turned down the ban appeal of {target}'),
      {},
    ),
    'raid_lockdown' => switch (changes['source']) {
      'auto' => (tr('Raid protection locked down joining'), {}),
      _ => (tr('{actor} locked down joining'), {}),
    },
    'raid_release' => switch (changes['source']) {
      'expired' => (tr('The lockdown ended by itself'), {}),
      _ => (tr('{actor} ended the lockdown'), {}),
    },
    'raid_settings_update' => (
      tr('{actor} changed the raid protection settings'),
      {},
    ),
    'invites_pause' => (tr('{actor} paused invites'), {}),
    'invites_resume' => (tr('{actor} resumed invites'), {}),
    'discovery_update' => switch (_newValue(changes['is_public'])) {
      true => (tr('{actor} made the circle public'), {}),
      false => (tr('{actor} made the circle private'), {}),
      _ => (tr('{actor} updated the discovery settings'), {}),
    },
    'workflow_create' => (tr('{actor} created the workflow {target}'), {}),
    'workflow_update' => (tr('{actor} changed the workflow {target}'), {}),
    'workflow_pause' => (tr('{actor} paused the workflow {target}'), {}),
    'workflow_resume' => (tr('{actor} resumed the workflow {target}'), {}),
    'workflow_delete' => (tr('{actor} deleted the workflow {target}'), {}),
    'slug_update' => (tr("{actor} changed the circle's short link"), {}),
    'bot_callback_set' => (
      tr('{actor} set the callback address of bot {target}'),
      {},
    ),
    'bot_callback_rotate' => (
      tr('{actor} reset the callback secret of bot {target}'),
      {},
    ),
    'bot_callback_clear' => (
      tr('{actor} removed the callback of bot {target}'),
      {},
    ),
    'bot_events_set' => (
      tr('{actor} set the event address of bot {target}'),
      {},
    ),
    'bot_events_rotate' => (
      tr('{actor} reset the event secret of bot {target}'),
      {},
    ),
    'bot_events_clear' => (
      tr('{actor} removed the event address of bot {target}'),
      {},
    ),
    'bot_open_update' => (tr('{actor} changed who can use bot {target}'), {}),
    _ => (
      tr('{actor} did {action} to {target}', {
        'action': entry.action.replaceAll('_', ' '),
      }),
      {},
    ),
  };
  return TextSpan(
    style: style,
    children: _fillNames(template, {
      'actor': actor,
      'target': target,
      ...names,
    }, bold),
  );
}

/// [template] as spans, with each `{placeholder}` replaced by its bold
/// value from [names].
List<TextSpan> _fillNames(
  String template,
  Map<String, String> names,
  TextStyle bold,
) {
  final spans = <TextSpan>[];
  var start = 0;
  for (final match in RegExp(r'\{(\w+)\}').allMatches(template)) {
    final value = names[match.group(1)];
    if (value == null) {
      continue;
    }
    if (match.start > start) {
      spans.add(TextSpan(text: template.substring(start, match.start)));
    }
    spans.add(TextSpan(text: value, style: bold));
    start = match.end;
  }
  if (start < template.length) {
    spans.add(TextSpan(text: template.substring(start)));
  }
  return spans;
}

typedef CircleAuditDetail = ({String label, String value});

/// The entry's changes as readable lines; ids are left out.
List<CircleAuditDetail> circleAuditDetails(CircleAuditEntry entry) {
  final details = <CircleAuditDetail>[];
  for (final MapEntry(:key, :value) in entry.changes.entries) {
    if (key == 'id' ||
        key.endsWith('_id') ||
        key == 'created_by' ||
        (key == 'channel_name' &&
            (entry.action.startsWith('forum_') ||
                entry.action.startsWith('automod_') ||
                entry.action.startsWith('guard_') ||
                entry.action == 'message_delete')) ||
        (key == 'target_name' &&
            entry.action == 'channel_permissions_update')) {
      continue;
    }
    final label = _labelFor(key);
    if (value is Map<String, dynamic> && value.containsKey('new')) {
      details.add((
        label: label,
        value:
            '${_formatValue(key, value['old'])} → ${_formatValue(key, value['new'])}',
      ));
    } else if (value is List) {
      if (value.isEmpty) {
        continue;
      }
      details.add((label: label, value: _formatList(value)));
    } else {
      details.add((label: label, value: _formatValue(key, value)));
    }
  }
  return details;
}

Object? _oldValue(Object? change) =>
    change is Map<String, dynamic> ? change['old'] : null;

Object? _newValue(Object? change) =>
    change is Map<String, dynamic> ? change['new'] : change;

String _labelFor(String key) {
  return switch (key) {
    'slowmode_seconds' => tr('Slowmode'),
    'read_only' => tr('Read-only'),
    'channels_moved' => tr('Channels moved'),
    'member_count' => tr('Members'),
    'max_uses' => tr('Max uses'),
    'expires_at' => tr('Expires'),
    'starts_at' => tr('Starts'),
    'ends_at' => tr('Ends'),
    'previous_owner_name' => tr('Previous owner'),
    'until' => tr('Until'),
    'seconds' => tr('Duration'),
    'deleted_messages' => tr('Messages deleted'),
    'allow' => tr('Allowed'),
    'mentionable' => tr('Anyone can mention'),
    'rule_name' => tr('Rule'),
    'verdict' => tr('AI found'),
    'reason' => tr('Reason'),
    'was' => tr('Before'),
    'new_rule' => tr('Who counts as new'),
    'joined_days' => tr('Joined less than (days)'),
    'message_count' => tr('Fewer than (messages)'),
    'action' => tr('When flagged'),
    'content' => tr('Message'),
    'alert_channel_name' => tr('Alert channel'),
    'kind' => tr('Type'),
    'enabled' => tr('Enabled'),
    'keyword_count' => tr('Keywords'),
    'pattern_count' => tr('Patterns'),
    'mention_limit' => tr('Mention limit'),
    'message_limit' => tr('Message limit'),
    'window_seconds' => tr('Time window'),
    'block_message' => tr('Block message'),
    'block_reason' => tr('Custom message'),
    'timeout_seconds' => tr('Timeout'),
    'exempt_role_count' => tr('Exempt roles'),
    'exempt_channel_count' => tr('Exempt channels'),
    'keywords_changed' => tr('Keywords changed'),
    'patterns_changed' => tr('Patterns changed'),
    'exemptions_changed' => tr('Exemptions changed'),
    'rule_count' => tr('Rules'),
    'welcome_message_changed' => tr('Welcome message changed'),
    'deny' => tr('Denied'),
    'is_public' => tr('Public'),
    'description' => tr('Description'),
    'category' => tr('Category'),
    'language' => tr('Language'),
    'tags' => tr('Tags'),
    'hours' => tr('Hours'),
    'source' => tr('Started by'),
    'joins' => tr('Joined or asked'),
    'new_accounts' => tr('New accounts'),
    'join_mode_switched' => tr('Switched to apply'),
    'join_mode_restored' => tr('Join mode put back'),
    'requested' => tr('Chosen'),
    'done' => tr('Done'),
    'warnings' => tr('Warnings'),
    'threshold' => tr('Threshold'),
    'expired_at' => tr('Ended'),
    'capacity' => tr('Seats'),
    'recurrence' => tr('Repeat'),
    'questions' => tr('Questions'),
    'series' => tr('Whole series'),
    _ =>
      key.isEmpty
          ? key
          : '${key[0].toUpperCase()}${key.substring(1).replaceAll('_', ' ')}',
  };
}

String _formatList(List<dynamic> items) {
  return items
      .map((item) {
        if (item is Map<String, dynamic>) {
          final name = item['name'] as String? ?? '?';
          final position = item['position'];
          if (position is Map<String, dynamic>) {
            return '$name (${position['old']} → ${position['new']})';
          }
          return name;
        }
        return '$item';
      })
      .join(', ');
}

String _formatValue(String key, Object? value) {
  if (value == null) {
    return tr('none');
  }
  if (value is bool) {
    return value ? tr('on') : tr('off');
  }
  if (value is List) {
    return value.isEmpty ? tr('none') : value.join(', ');
  }
  if (key == 'category' && value is String) {
    return DiscoveryCategory.fromJson(value)?.label ?? value;
  }
  if (key == 'language' && value is String) {
    return DiscoveryLanguages.label(value);
  }
  if ((key == 'slowmode_seconds' ||
          key == 'window_seconds' ||
          key == 'timeout_seconds') &&
      value is num) {
    return _formatSeconds(value);
  }
  if (key == 'verdict' && value is String) {
    return AiGuardVerdict.fromKey(value).label;
  }
  if (key == 'was' && value is String) {
    return value == 'held' ? tr('Held') : tr('Flagged');
  }
  if (key == 'new_rule' && value is String) {
    return AiGuardNewRule.fromKey(value) == AiGuardNewRule.joinedDays
        ? tr('Recently joined')
        : tr('Few messages');
  }
  if (key == 'action' && (value == 'flag' || value == 'hold')) {
    return value == 'flag' ? tr('Flag only') : tr('Hold for review');
  }
  if (key == 'source' && value is String) {
    return switch (value) {
      'auto' => tr('Raid protection'),
      'expired' => tr('The clock'),
      _ => tr('A moderator'),
    };
  }
  if (key == 'kind' && value is String) {
    return switch (value) {
      'keyword' => tr('Custom keywords'),
      'mention_spam' => tr('Mention spam'),
      'spam' => tr('Spam'),
      _ => value,
    };
  }
  if (key == 'recurrence' && value is String) {
    return EventRecurrence.fromJson(value).label;
  }
  if (key == 'color' && value is num) {
    return '#${value.toInt().toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
  if ((key == 'permissions' || key == 'allow' || key == 'deny') &&
      value is num) {
    final bits = value.toInt();
    final names = [
      for (final permission in CirclePermission.values)
        if (bits & permission.bit != 0) permission.label,
    ];
    return names.isEmpty ? tr('none') : names.join(', ');
  }
  if (key == 'seconds' && value is num) {
    final seconds = value.toInt();
    return seconds >= 86400 && seconds % 86400 == 0
        ? tr('{days}d', {'days': seconds ~/ 86400})
        : _formatSeconds(seconds);
  }
  if ((key == 'expires_at' ||
          key == 'starts_at' ||
          key == 'ends_at' ||
          key == 'expired_at' ||
          key == 'until') &&
      value is String) {
    final time = DateTime.tryParse(value)?.toLocal();
    if (time != null) {
      return '${time.year}-${_two(time.month)}-${_two(time.day)} '
          '${_two(time.hour)}:${_two(time.minute)}';
    }
  }
  return '$value';
}

String _formatSeconds(Object? value) {
  final seconds = value is num ? value.toInt() : 0;
  if (seconds <= 0) {
    return tr('off');
  }
  if (seconds < 60) {
    return tr('{seconds}s', {'seconds': seconds});
  }
  if (seconds < 3600) {
    return seconds % 60 == 0
        ? tr('{minutes}m', {'minutes': seconds ~/ 60})
        : tr('{minutes}m {seconds}s', {
            'minutes': seconds ~/ 60,
            'seconds': seconds % 60,
          });
  }
  return seconds % 3600 == 0
      ? tr('{hours}h', {'hours': seconds ~/ 3600})
      : tr('{hours}h {minutes}m', {
          'hours': seconds ~/ 3600,
          'minutes': (seconds % 3600) ~/ 60,
        });
}

String _two(int value) => value.toString().padLeft(2, '0');

/// "just now", "5m ago", "3h ago", "2d ago", then the date.
String formatAuditTime(DateTime value, {required DateTime now}) {
  final difference = now.difference(value);
  if (difference.inMinutes < 1) {
    return tr('just now');
  }
  if (difference.inHours < 1) {
    return tr('{minutes}m ago', {'minutes': difference.inMinutes});
  }
  if (difference.inDays < 1) {
    return tr('{hours}h ago', {'hours': difference.inHours});
  }
  if (difference.inDays < 7) {
    return tr('{days}d ago', {'days': difference.inDays});
  }
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}
