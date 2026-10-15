import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_role.dart';

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

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Audit log')),
        actions: [
          PopupMenuButton<CircleAuditActionGroup?>(
            tooltip: tr('Filter by action'),
            icon: Icon(
              _filter == null ? Icons.filter_list : Icons.filter_list_alt,
            ),
            onSelected: _setFilter,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<CircleAuditActionGroup?>(
                value: null,
                checked: _filter == null,
                child: Text(tr('All actions')),
              ),
              for (final group in CircleAuditActionGroup.filters)
                CheckedPopupMenuItem<CircleAuditActionGroup?>(
                  value: group,
                  checked: _filter == group,
                  child: Text(group.label),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_filter case final filter?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(filter.label),
                  onDeleted: () => _setFilter(null),
                  deleteButtonTooltipMessage: tr('Show all actions'),
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
        return _Message(
          text: tr('Could not load the audit log.'),
          action: TextButton(onPressed: _loadMore, child: Text(tr('Retry'))),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return _Message(
        text: _filter == null
            ? tr('Nothing has been logged yet.')
            : tr('No {group} actions logged yet.', {
                'group': _filter!.label.toLowerCase(),
              }),
      );
    }
    return ListView.builder(
      key: const ValueKey('circle-audit-log-list'),
      controller: _scrollController,
      itemCount: _entries.length + 1,
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          if (_error != null) {
            return Center(
              child: TextButton(
                onPressed: _loadMore,
                child: Text(tr('Could not load more. Retry')),
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
        return CircleAuditEntryTile(entry: _entries[index], now: now);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// One audit entry: an icon for the action, "X did Y" and when; entries
/// with details expand to list them.
class CircleAuditEntryTile extends StatelessWidget {
  const CircleAuditEntryTile({
    required this.entry,
    required this.now,
    super.key,
  });

  final CircleAuditEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = circleAuditDetails(entry);
    final leading = CircleAvatar(
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundColor: theme.colorScheme.onSecondaryContainer,
      child: Icon(circleAuditIcon(entry.action), size: 20),
    );
    final title = Text.rich(
      circleAuditSummary(entry, theme.textTheme.bodyMedium),
      key: ValueKey('circle-audit-summary-${entry.id}'),
    );
    final subtitle = Text(
      formatAuditTime(entry.createdAt, now: now),
      style: theme.textTheme.bodySmall,
    );
    if (details.isEmpty) {
      return ListTile(
        key: ValueKey('circle-audit-${entry.id}'),
        leading: leading,
        title: title,
        subtitle: subtitle,
      );
    }
    return ExpansionTile(
      key: ValueKey('circle-audit-${entry.id}'),
      leading: leading,
      title: title,
      subtitle: subtitle,
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${detail.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: detail.value),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
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
    'channel_update' => Icons.edit_note,
    'channel_delete' => Icons.delete_sweep_outlined,
    'category_create' => Icons.create_new_folder_outlined,
    'category_rename' => Icons.drive_file_rename_outline,
    'category_delete' => Icons.folder_delete_outlined,
    'role_create' => Icons.add_moderator_outlined,
    'role_update' => Icons.shield_outlined,
    'role_delete' => Icons.remove_moderator_outlined,
    'role_reorder' => Icons.swap_vert,
    'member_add' => Icons.person_add_alt_1_outlined,
    'member_roles_update' => Icons.badge_outlined,
    'member_nickname_update' => Icons.edit_outlined,
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
    'forum_tag_create' => Icons.new_label_outlined,
    'forum_tag_update' => Icons.label_outline,
    'forum_tag_delete' => Icons.label_off_outlined,
    'forum_tag_reorder' => Icons.swap_vert,
    'forum_post_pin' => Icons.push_pin_outlined,
    'forum_post_unpin' => Icons.push_pin,
    'event_create' => Icons.event_outlined,
    'event_update' => Icons.edit_calendar_outlined,
    'event_cancel' => Icons.event_busy_outlined,
    'webhook_create' => Icons.smart_toy_outlined,
    'webhook_update' => Icons.drive_file_rename_outline,
    'webhook_regenerate' => Icons.key_outlined,
    'webhook_delete' => Icons.delete_outline,
    'automod_rule_create' => Icons.add_moderator_outlined,
    'automod_rule_update' => Icons.gpp_maybe_outlined,
    'automod_rule_delete' => Icons.remove_moderator_outlined,
    'automod_block' => Icons.block,
    'automod_alert' => Icons.campaign_outlined,
    'automod_timeout' => Icons.timer_outlined,
    'onboarding_update' => Icons.rule,
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
    'onboarding_update' => (tr('{actor} updated the onboarding'), {}),
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
  if ((key == 'slowmode_seconds' ||
          key == 'window_seconds' ||
          key == 'timeout_seconds') &&
      value is num) {
    return _formatSeconds(value);
  }
  if (key == 'kind' && value is String) {
    return switch (value) {
      'keyword' => tr('Custom keywords'),
      'mention_spam' => tr('Mention spam'),
      'spam' => tr('Spam'),
      _ => value,
    };
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
