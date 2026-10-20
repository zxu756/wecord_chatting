import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_alerts_models.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_stats_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The latest result of every check, and when they last ran.
final opsChecksProvider = FutureProvider.autoDispose<OpsChecks>((ref) {
  return ref.watch(adminStatsRepositoryProvider).checks();
});

/// The biggest groups of error reports of the last day.
final opsErrorGroupsProvider = FutureProvider.autoDispose<List<OpsErrorGroup>>((
  ref,
) {
  return ref.watch(adminStatsRepositoryProvider).errorGroups();
});

/// The console's "Alerts" tab (K3, K5): what the monitoring found, whether
/// the checks are still running, the alerts (open or closed) and the error
/// reports grouped by cause. Everything it watches is WeCord's own data; no
/// third party sees any of it.
class AdminAlertsView extends ConsumerStatefulWidget {
  const AdminAlertsView({this.pageSize = 30, this.now, super.key});

  final int pageSize;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AdminAlertsView> createState() => _AdminAlertsViewState();
}

class _AdminAlertsViewState extends ConsumerState<AdminAlertsView> {
  final _alerts = <OpsAlert>[];
  var _resolved = false;
  var _loading = false;
  var _hasMore = true;
  Object? _error;
  final _busy = <String>{};

  /// Bumped on every reload, so pages of an old filter are dropped.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  void _reload({bool? resolved}) {
    setState(() {
      _resolved = resolved ?? _resolved;
      _generation += 1;
      _alerts.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    ref
      ..invalidate(opsChecksProvider)
      ..invalidate(opsErrorGroupsProvider);
    unawaited(_loadMore());
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
          .read(adminStatsRepositoryProvider)
          .alerts(
            resolved: _resolved,
            before: _alerts.isEmpty ? null : _alerts.last.openedAt,
            pageSize: widget.pageSize,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _alerts.addAll(page);
        _hasMore = page.length >= widget.pageSize;
        _loading = false;
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

  Future<void> _act(OpsAlert alert, {required bool resolve}) async {
    if (_busy.contains(alert.id)) {
      return;
    }
    setState(() => _busy.add(alert.id));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final repository = ref.read(adminStatsRepositoryProvider);
      if (resolve) {
        await repository.resolve(alert.id);
      } else {
        await repository.acknowledge(alert.id);
      }
      if (mounted) {
        setState(() => _busy.remove(alert.id));
        _reload();
      }
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(adminErrorText(error))));
      if (mounted) {
        setState(() => _busy.remove(alert.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    final role = ref.watch(adminRoleProvider).value;
    final canAct = role?.canSanction ?? false;
    final checks = ref.watch(opsChecksProvider);
    final groups = ref.watch(opsErrorGroupsProvider);
    return ListView(
      key: const ValueKey('admin-alerts-list'),
      padding: circlePagePadding(context),
      children: [
        SettingsSectionHeader(tr('Checks')),
        checks.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => CircleEmptyState(
            icon: Icons.error_outline_rounded,
            title: tr('Could not load the checks.'),
            message: adminErrorText(error),
            action: WeCordButton(
              label: tr('Retry'),
              variant: WeCordButtonVariant.onPaper,
              onPressed: () => ref.invalidate(opsChecksProvider),
            ),
          ),
          data: (data) => _ChecksCard(checks: data),
        ),
        SettingsSectionHeader(tr('Alerts')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WeCordChip(
              key: const ValueKey('admin-alerts-open'),
              label: trIn('Alerts', 'Open'),
              selected: !_resolved,
              onPaper: true,
              onPressed: () {
                if (_resolved) {
                  _reload(resolved: false);
                }
              },
            ),
            WeCordChip(
              key: const ValueKey('admin-alerts-resolved'),
              label: trIn('Alerts', 'Closed'),
              selected: _resolved,
              onPaper: true,
              onPressed: () {
                if (!_resolved) {
                  _reload(resolved: true);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._alertWidgets(context, now, canAct),
        SettingsSectionHeader(tr('Errors in the last day')),
        groups.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => CircleEmptyState(
            icon: Icons.error_outline_rounded,
            title: tr('Could not load the errors.'),
            message: adminErrorText(error),
            action: WeCordButton(
              label: tr('Retry'),
              variant: WeCordButtonVariant.onPaper,
              onPressed: () => ref.invalidate(opsErrorGroupsProvider),
            ),
          ),
          data: (data) => _ErrorGroups(groups: data, now: now),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 16),
          child: Text(
            tr(
              'The checks run every 5 minutes inside WeCord’s own '
              'database. Nothing is sent to a third-party service.',
            ),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: context.tokens.colors.muted,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _alertWidgets(BuildContext context, DateTime now, bool canAct) {
    if (_alerts.isEmpty) {
      if (_error != null) {
        return [
          CircleEmptyState(
            icon: Icons.error_outline_rounded,
            title: tr('Could not load the alerts.'),
            message: adminErrorText(_error!),
            action: WeCordButton(
              label: tr('Retry'),
              variant: WeCordButtonVariant.onPaper,
              onPressed: _loadMore,
            ),
          ),
        ];
      }
      if (_loading || _hasMore) {
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      return [
        CircleEmptyState(
          icon: _resolved ? Icons.inbox_outlined : Icons.task_alt_rounded,
          title: _resolved
              ? tr('No closed alerts yet.')
              : tr('No open alerts.'),
          message: _resolved
              ? null
              : tr('Anything that goes wrong shows up here.'),
        ),
      ];
    }
    return [
      for (final alert in _alerts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _AlertTile(
            alert: alert,
            now: now,
            canAct: canAct && alert.isOpen,
            busy: _busy.contains(alert.id),
            onAcknowledge: () => unawaited(_act(alert, resolve: false)),
            onClose: () => unawaited(_act(alert, resolve: true)),
          ),
        ),
      if (_hasMore || _error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : WeCordButton(
                    label: _error != null
                        ? tr('Could not load more. Retry')
                        : tr('Load more'),
                    variant: WeCordButtonVariant.onPaper,
                    size: WeCordButtonSize.small,
                    onPressed: _loadMore,
                  ),
          ),
        ),
    ];
  }
}

/// Whether the checks are running, and what each one found.
class _ChecksCard extends StatelessWidget {
  const _ChecksCard({required this.checks});

  final OpsChecks checks;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final minutes = checks.minutesSinceHeartbeat;
    final String status;
    if (checks.heartbeatAt == null) {
      status = tr('The checks have not run yet.');
    } else if (checks.stale) {
      status = tr(
        'The checks have not run for {minutes} minutes. If this goes on, '
        'scheduled tasks may have stopped.',
        {'minutes': minutes ?? 0},
      );
    } else {
      status = minutes == null || minutes < 1
          ? tr('The checks ran a moment ago.')
          : tr('The checks ran {minutes} minutes ago.', {'minutes': minutes});
    }
    return CircleCard(
      key: const ValueKey('admin-alerts-checks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIconTile(
                icon: checks.stale
                    ? Icons.warning_amber_rounded
                    : Icons.monitor_heart_outlined,
                tone: checks.stale
                    ? SettingsTone.warning
                    : SettingsTone.success,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    status,
                    key: const ValueKey('admin-alerts-heartbeat'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: checks.stale ? c.warningText : c.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (checks.checks.isNotEmpty) const SizedBox(height: 10),
          for (final check in checks.checks) _CheckRow(check: check),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final OpsCheck check;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tone = switch (check.status) {
      OpsCheckStatus.ok => SettingsTone.success,
      OpsCheckStatus.warn => SettingsTone.warning,
      OpsCheckStatus.fail => SettingsTone.danger,
      OpsCheckStatus.unknown => SettingsTone.neutral,
    };
    return Padding(
      key: ValueKey('admin-check-${check.key}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        container: true,
        label: '${check.label}: ${check.status.label}. ${check.summary}',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      check.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (check.summary.isNotEmpty)
                      Text(
                        check.summary,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AdminStateTag(label: check.status.label, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.alert,
    required this.now,
    required this.canAct,
    required this.busy,
    required this.onAcknowledge,
    required this.onClose,
  });

  final OpsAlert alert;
  final DateTime now;
  final bool canAct;
  final bool busy;
  final VoidCallback onAcknowledge;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final chinese = AppStrings.isChinese;
    final title = alert.title(chinese: chinese);
    final body = alert.body(chinese: chinese);
    final tone = !alert.isOpen
        ? SettingsTone.neutral
        : alert.isFailure
        ? SettingsTone.danger
        : SettingsTone.warning;
    final meta = alert.isOpen
        ? tr('Since {time}', {
            'time': formatAuditTime(alert.openedAt, now: now),
          })
        : tr('{time} · {how}', {
            'time': formatAuditTime(
              alert.resolvedAt ?? alert.openedAt,
              now: now,
            ),
            'how': alert.resolution == 'manual'
                ? tr('closed by @{name}', {'name': alert.resolvedBy ?? '?'})
                : tr('recovered'),
          });
    return CircleCard(
      key: ValueKey('admin-alert-${alert.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIconTile(
                icon: alert.isEvent
                    ? Icons.bug_report_outlined
                    : Icons.notifications_active_outlined,
                tone: tone,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: TextStyle(fontSize: 12.5, color: c.subtle),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (alert.isOpen)
                AdminStateTag(
                  label: alert.isFailure ? tr('Failing') : tr('Warning'),
                  tone: tone,
                ),
              if (alert.isEvent) AdminStateTag(label: tr('New error')),
              if (alert.acknowledgedAt != null)
                AdminStateTag(
                  label: tr('Seen by @{name}', {
                    'name': alert.acknowledgedBy ?? '?',
                  }),
                  tone: SettingsTone.success,
                ),
              if (alert.reopenCount > 0)
                AdminStateTag(
                  label: tr('Reopened {count} times', {
                    'count': alert.reopenCount,
                  }),
                ),
            ],
          ),
          if (canAct) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!alert.isEvent && alert.acknowledgedAt == null)
                  WeCordButton(
                    key: ValueKey('admin-alert-ack-${alert.id}'),
                    label: tr('I have seen it'),
                    variant: WeCordButtonVariant.onPaper,
                    size: WeCordButtonSize.small,
                    onPressed: busy ? null : onAcknowledge,
                  ),
                WeCordButton(
                  key: ValueKey('admin-alert-close-${alert.id}'),
                  label: tr('Close'),
                  variant: WeCordButtonVariant.onPaper,
                  size: WeCordButtonSize.small,
                  onPressed: busy ? null : onClose,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorGroups extends StatelessWidget {
  const _ErrorGroups({required this.groups, required this.now});

  final List<OpsErrorGroup> groups;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (groups.isEmpty) {
      return CircleCard(
        key: const ValueKey('admin-alerts-errors'),
        child: Text(
          tr('No error reports in the last day.'),
          style: TextStyle(fontSize: 13.5, color: c.muted),
        ),
      );
    }
    return CircleCard(
      key: const ValueKey('admin-alerts-errors'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups) _ErrorGroupRow(group: group, now: now),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(
                'Grouped by kind, type and the first line of WeCord’s own '
                'code in the stack. To read a stack, use tool/errors_report.sh.',
              ),
              style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorGroupRow extends StatelessWidget {
  const _ErrorGroupRow({required this.group, required this.now});

  final OpsErrorGroup group;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final meta = [
      tr('{count} times', {'count': group.occurrencesText}),
      tr('{count} people', {'count': group.people}),
      if (group.firstVersion.isNotEmpty)
        tr('first in {version}', {'version': group.firstVersion}),
      if (group.lastSeenAt != null)
        formatAuditTime(group.lastSeenAt!, now: now),
    ].join(' · ');
    return Padding(
      key: ValueKey('admin-error-${group.groupKey}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Semantics(
        container: true,
        label: '${group.kind}. ${group.what}. $meta',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminStateTag(label: group.kind),
                  if (group.isNew)
                    AdminStateTag(label: tr('New'), tone: SettingsTone.warning),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                group.what,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                style: TextStyle(fontSize: 12.5, height: 1.3, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
