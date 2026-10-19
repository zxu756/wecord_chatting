import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What an audit entry says, as a sentence: "mia suspended @eve".
String adminAuditSummary(AdminAuditEntry entry) {
  final actor = entry.actor.isEmpty ? tr('Someone') : '@${entry.actor}';
  final title = entry.title;
  final args = {'actor': actor, 'title': title};
  return switch (entry.action) {
    'suspend_user' => tr('{actor} suspended {title}', args),
    'unsuspend_user' => tr('{actor} lifted the suspension of {title}', args),
    'disable_circle' =>
      entry.details['mode'] == 'suspend'
          ? tr('{actor} suspended the circle {title}', args)
          : tr('{actor} delisted the circle {title}', args),
    'enable_circle' => tr('{actor} restored the circle {title}', args),
    'delete_circle_post' => tr('{actor} deleted the post "{title}"', args),
    'resolve_message_report' => switch (entry.details['action']) {
      'delete_message' => tr(
        '{actor} deleted a reported message: {title}',
        args,
      ),
      'suspend' => tr(
        '{actor} suspended the sender of a reported message',
        args,
      ),
      _ => tr('{actor} dismissed a message report', args),
    },
    'resolve_story_report' => switch (entry.details['action']) {
      'delete_story' => tr('{actor} deleted a reported daily: {title}', args),
      'suspend' => tr('{actor} suspended the author of a reported daily', args),
      _ => tr('{actor} dismissed a daily report', args),
    },
    'set_feature_flag' =>
      entry.details['created'] == true
          ? tr('{actor} created the flag {title}', args)
          : tr('{actor} changed the flag {title}', args),
    'delete_feature_flag' => tr('{actor} deleted the flag {title}', args),
    'set_min_version' =>
      (entry.details['min_version'] as String? ?? '').isEmpty
          ? tr('{actor} removed the minimum version for {title}', args)
          : tr('{actor} set the minimum version for {title} to {version}', {
              ...args,
              'version': entry.details['min_version'],
            }),
    'publish_announcement' => tr(
      '{actor} published the notice “{title}”',
      args,
    ),
    'retract_announcement' => tr(
      '{actor} took back the notice “{title}”',
      args,
    ),
    'reply_feedback' => tr('{actor} replied to the feedback of {title}', args),
    'close_feedback' => tr('{actor} closed the feedback of {title}', args),
    'reopen_feedback' => tr(
      '{actor} opened the feedback of {title} again',
      args,
    ),
    'resolve_report' => tr('{actor} closed a report: {resolution}', {
      'actor': actor,
      'resolution':
          ReportResolution.parse(entry.details['resolution'])?.label ??
          tr('Handled'),
    }),
    _ => tr('{actor} did {action}', {'actor': actor, 'action': entry.action}),
  };
}

IconData adminAuditIcon(String action) => switch (action) {
  'suspend_user' => Icons.block_rounded,
  'unsuspend_user' => Icons.lock_open_rounded,
  'disable_circle' => Icons.visibility_off_outlined,
  'enable_circle' => Icons.visibility_outlined,
  'delete_circle_post' => Icons.delete_outline_rounded,
  'resolve_report' ||
  'resolve_message_report' ||
  'resolve_story_report' => Icons.task_alt_rounded,
  'set_feature_flag' || 'delete_feature_flag' => Icons.flag_outlined,
  'set_min_version' => Icons.system_update_alt_rounded,
  'publish_announcement' || 'retract_announcement' => Icons.campaign_outlined,
  'reply_feedback' ||
  'close_feedback' ||
  'reopen_feedback' => Icons.chat_bubble_outline_rounded,
  _ => Icons.history_rounded,
};

SettingsTone adminAuditTone(String action) => switch (action) {
  'suspend_user' || 'delete_circle_post' => SettingsTone.danger,
  'disable_circle' ||
  'set_min_version' ||
  'retract_announcement' => SettingsTone.warning,
  'enable_circle' || 'unsuspend_user' => SettingsTone.success,
  _ => SettingsTone.neutral,
};

/// The audit log of everything admins did, newest first, loading older
/// entries as the list scrolls.
class AdminAuditView extends ConsumerStatefulWidget {
  const AdminAuditView({this.pageSize = 50, this.now, super.key});

  final int pageSize;
  final DateTime Function()? now;

  @override
  ConsumerState<AdminAuditView> createState() => _AdminAuditViewState();
}

class _AdminAuditViewState extends ConsumerState<AdminAuditView> {
  final _scrollController = ScrollController();
  final _entries = <AdminAuditEntry>[];
  var _loading = false;
  var _hasMore = true;
  Object? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(adminRepositoryProvider)
          .listAuditLog(
            before: _entries.isEmpty ? null : _entries.last.createdAt,
            pageSize: widget.pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length >= widget.pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    if (_entries.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the audit log.'),
          message: adminErrorText(_error!),
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
        icon: Icons.history_rounded,
        title: tr('Nothing has been logged yet.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('admin-audit-list'),
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
          child: AdminAuditTile(entry: _entries[index], now: now),
        );
      },
    );
  }
}

/// One audit entry: an icon for the action, who did what to whom, the
/// reason they gave and when.
class AdminAuditTile extends StatelessWidget {
  const AdminAuditTile({required this.entry, required this.now, super.key});

  final AdminAuditEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final reason = entry.reason;
    final role = entry.actorRole;
    return Container(
      key: ValueKey('admin-audit-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsIconTile(
            icon: adminAuditIcon(entry.action),
            tone: adminAuditTone(entry.action),
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminAuditSummary(entry),
                  style: TextStyle(fontSize: 14, color: c.ink, height: 1.35),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.muted,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  role == null
                      ? formatAuditTime(entry.createdAt, now: now)
                      : '${role.label} · '
                            '${formatAuditTime(entry.createdAt, now: now)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.subtle,
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
