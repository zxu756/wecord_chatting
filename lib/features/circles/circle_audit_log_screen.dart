import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';
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
        title: const Text('Audit log'),
        actions: [
          PopupMenuButton<CircleAuditActionGroup?>(
            tooltip: 'Filter by action',
            icon: Icon(
              _filter == null ? Icons.filter_list : Icons.filter_list_alt,
            ),
            onSelected: _setFilter,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<CircleAuditActionGroup?>(
                value: null,
                checked: _filter == null,
                child: const Text('All actions'),
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
                  deleteButtonTooltipMessage: 'Show all actions',
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
          text: 'Could not load the audit log.',
          action: TextButton(onPressed: _loadMore, child: const Text('Retry')),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return _Message(
        text: _filter == null
            ? 'Nothing has been logged yet.'
            : 'No ${_filter!.label.toLowerCase()} actions logged yet.',
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
                child: const Text('Could not load more. Retry'),
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
  final actor = entry.actor?.name ?? 'Someone';
  final target = entry.targetLabel ?? 'something';
  TextSpan name(String text) => TextSpan(text: text, style: bold);
  TextSpan text(String text) => TextSpan(text: text);
  final changes = entry.changes;

  final List<TextSpan> rest = switch (entry.action) {
    'channel_create' => [text(' created channel '), name('#$target')],
    'channel_reorder' => [text(' reordered channels')],
    'channel_permissions_update' => [
      text(' updated permissions'),
      if (changes['target_name'] case final String targetName) ...[
        text(' for '),
        name(targetName),
      ],
      text(' in '),
      name('#$target'),
    ],
    'channel_privacy_update' => [
      text(' changed the privacy of '),
      name('#$target'),
    ],
    'channel_slowmode_update' => [
      text(' set slowmode in '),
      name('#$target'),
      text(' to '),
      name(_formatSeconds(_newValue(changes['slowmode_seconds']))),
    ],
    'channel_update' => [
      if (changes['name'] case {'old': final String oldName}) ...[
        text(' renamed channel '),
        name('#$oldName'),
        text(' to '),
        name('#$target'),
      ] else ...[
        text(' updated channel '),
        name('#$target'),
      ],
    ],
    'channel_delete' => [text(' deleted channel '), name('#$target')],
    'category_create' => [text(' created category '), name(target)],
    'category_rename' => [
      text(' renamed category '),
      name(_formatValue('name', _oldValue(changes['name']))),
      text(' to '),
      name(target),
    ],
    'category_delete' => [text(' deleted category '), name(target)],
    'role_create' => [text(' created role '), name(target)],
    'role_update' => [text(' updated role '), name(target)],
    'role_delete' => [text(' deleted role '), name(target)],
    'role_reorder' => [text(' reordered roles')],
    'member_add' => [text(' added '), name(target), text(' to the circle')],
    'member_roles_update' => [text(' updated the roles of '), name(target)],
    'member_nickname_update' => [
      text(' changed the nickname of '),
      name(target),
    ],
    'member_kick' => [text(' kicked '), name(target)],
    'member_ban' => [text(' banned '), name(target)],
    'member_unban' => [text(' unbanned '), name(target)],
    'member_timeout' => [text(' timed out '), name(target)],
    'member_timeout_remove' => [text(' removed the timeout of '), name(target)],
    'member_leave' => [text(' left the circle')],
    'circle_ownership_transfer' => [
      text(' transferred ownership to '),
      name(target),
    ],
    'invite_create' => [text(' created invite '), name(target)],
    'invite_revoke' => [text(' revoked invite '), name(target)],
    'message_pin' => [text(' pinned a message in '), name('#$target')],
    'message_unpin' => [text(' unpinned a message in '), name('#$target')],
    'message_delete' => [
      text(' deleted a message by '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'thread_archive' => [text(' archived thread '), name(target)],
    'thread_unarchive' => [text(' unarchived thread '), name(target)],
    'post_delete' => [text(' deleted a post by '), name(target)],
    'forum_tag_create' => [
      text(' created tag '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'forum_tag_update' => [
      text(' updated tag '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'forum_tag_delete' => [
      text(' deleted tag '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'forum_tag_reorder' => [text(' reordered the tags of '), name('#$target')],
    'forum_post_pin' => [
      text(' pinned post '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'forum_post_unpin' => [
      text(' unpinned post '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'event_create' => [text(' scheduled event '), name(target)],
    'event_update' => [
      if (changes['title'] case {'old': final String oldTitle}) ...[
        text(' renamed event '),
        name(oldTitle),
        text(' to '),
        name(target),
      ] else ...[
        text(' updated event '),
        name(target),
      ],
    ],
    'event_cancel' => [text(' cancelled event '), name(target)],
    'webhook_create' => [
      text(' created webhook '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'webhook_update' => [
      if (changes['name'] case {'old': final String oldName}) ...[
        text(' renamed webhook '),
        name(oldName),
        text(' to '),
        name(target),
      ] else ...[
        text(' updated webhook '),
        name(target),
      ],
    ],
    'webhook_regenerate' => [
      text(' regenerated the URL of webhook '),
      name(target),
    ],
    'webhook_delete' => [
      text(' deleted webhook '),
      name(target),
      ..._inChannel(changes, name, text),
    ],
    'emoji_create' => [text(' added emoji '), name(':$target:')],
    'emoji_update' => [
      text(' renamed emoji '),
      name(':${_formatValue('name', _oldValue(changes['name']))}:'),
      text(' to '),
      name(':$target:'),
    ],
    'emoji_delete' => [text(' deleted emoji '), name(':$target:')],
    'sticker_create' => [text(' added sticker '), name(target)],
    'sticker_update' => [
      text(' renamed sticker '),
      name(_formatValue('name', _oldValue(changes['name']))),
      text(' to '),
      name(target),
    ],
    'sticker_delete' => [text(' deleted sticker '), name(target)],
    _ => [text(' did ${entry.action.replaceAll('_', ' ')} to '), name(target)],
  };
  return TextSpan(style: style, children: [name(actor), ...rest]);
}

/// " in #channel" when the entry names its channel.
List<TextSpan> _inChannel(
  Map<String, dynamic> changes,
  TextSpan Function(String text) name,
  TextSpan Function(String text) text,
) {
  final channelName = changes['channel_name'];
  if (channelName is! String) {
    return const [];
  }
  return [text(' in '), name('#$channelName')];
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
    'slowmode_seconds' => 'Slowmode',
    'read_only' => 'Read-only',
    'channels_moved' => 'Channels moved',
    'member_count' => 'Members',
    'max_uses' => 'Max uses',
    'expires_at' => 'Expires',
    'starts_at' => 'Starts',
    'ends_at' => 'Ends',
    'previous_owner_name' => 'Previous owner',
    'until' => 'Until',
    'seconds' => 'Duration',
    'deleted_messages' => 'Messages deleted',
    'allow' => 'Allowed',
    'deny' => 'Denied',
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
    return 'none';
  }
  if (value is bool) {
    return value ? 'on' : 'off';
  }
  if (key == 'slowmode_seconds' && value is num) {
    return _formatSeconds(value);
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
    return names.isEmpty ? 'none' : names.join(', ');
  }
  if (key == 'seconds' && value is num) {
    final seconds = value.toInt();
    return seconds >= 86400 && seconds % 86400 == 0
        ? '${seconds ~/ 86400}d'
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
    return 'off';
  }
  if (seconds < 60) {
    return '${seconds}s';
  }
  if (seconds < 3600) {
    return seconds % 60 == 0
        ? '${seconds ~/ 60}m'
        : '${seconds ~/ 60}m ${seconds % 60}s';
  }
  return seconds % 3600 == 0
      ? '${seconds ~/ 3600}h'
      : '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// "just now", "5m ago", "3h ago", "2d ago", then the date.
String formatAuditTime(DateTime value, {required DateTime now}) {
  final difference = now.difference(value);
  if (difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}
