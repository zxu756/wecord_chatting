import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_audit_view.dart';
import 'package:wecord/features/admin/admin_feedback_view.dart';
import 'package:wecord/features/admin/admin_flags_view.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_notices_view.dart';
import 'package:wecord/features/admin/admin_report_screen.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The admin console (`/admin`, hidden: Settings lists it only for admins):
/// the report queue, the audit log, and the tabs for feature flags, official
/// notices and feedback. A signed-in person who is not an admin sees an empty
/// page; every call is checked by the server anyway.
class AdminConsoleScreen extends ConsumerStatefulWidget {
  const AdminConsoleScreen({this.pageSize = 30, this.now, super.key});

  static const path = '/admin';

  final int pageSize;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

enum _Tab { reports, audit, flags, notices, feedback }

/// The kinds the queue can filter by. Messages are the reports of direct
/// chats and groups; a circle's message reports go to its moderators.
const _queueKinds = [
  ReportKind.user,
  ReportKind.circle,
  ReportKind.post,
  ReportKind.message,
];

class _AdminConsoleScreenState extends ConsumerState<AdminConsoleScreen> {
  final _scrollController = ScrollController();
  final _reports = <AdminReport>[];
  var _tab = _Tab.reports;
  var _status = ReportQueueStatus.open;
  ReportKind? _kind;
  var _loading = false;
  var _hasMore = true;
  Object? _error;

  /// Bumped on every reload, so pages of an old filter are dropped.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    // Only an admin asks for reports (the server refuses anybody else).
    ref.read(adminRoleProvider.future).then((role) {
      if (mounted && role != null) {
        _loadMore();
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _tab != _Tab.reports) {
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
          .read(adminRepositoryProvider)
          .listReports(
            kind: _kind,
            status: _status,
            before: _reports.isEmpty ? null : _reports.last.createdAt,
            pageSize: widget.pageSize,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _reports.addAll(page);
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

  void _reload({ReportQueueStatus? status, Object? kind = _keep}) {
    setState(() {
      _status = status ?? _status;
      if (!identical(kind, _keep)) {
        _kind = kind as ReportKind?;
      }
      _generation += 1;
      _reports.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadMore();
  }

  Future<void> _open(AdminReport report) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AdminReportScreen(
          reportId: report.id,
          message: report.kind == ReportKind.message,
        ),
      ),
    );
    // What was done there changes the queue.
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(adminRoleProvider);
    final now = widget.now?.call() ?? DateTime.now();
    return role.when(
      loading: () => CirclePageScaffold(
        title: tr('Admin console'),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _NotAnAdmin(),
      data: (role) {
        if (role == null) {
          return const _NotAnAdmin();
        }
        return CirclePageScaffold(
          title: tr('Admin console'),
          subtitle: role.label,
          actions: [
            WeCordIconButton(
              key: const ValueKey('admin-refresh'),
              tooltip: tr('Refresh'),
              icon: Icons.refresh_rounded,
              variant: WeCordButtonVariant.onPaper,
              size: 42,
              onPressed: _tab == _Tab.reports ? _reload : null,
            ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                // Five tabs do not fit a phone as one segmented control: a
                // row of chips that scrolls sideways.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final (index, tab) in _Tab.values.indexed) ...[
                        if (index > 0) const SizedBox(width: 8),
                        Builder(
                          builder: (chipContext) => WeCordChip(
                            key: ValueKey('admin-tab-${tab.name}'),
                            label: _tabLabel(tab),
                            selected: _tab == tab,
                            onPaper: true,
                            onPressed: () {
                              setState(() => _tab = tab);
                              // A tab at the edge of a phone comes into view.
                              unawaited(
                                Scrollable.ensureVisible(
                                  chipContext,
                                  alignment: 0.5,
                                  duration: WeCordMotion.durationOf(
                                    chipContext,
                                    WeCordMotion.quick,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: switch (_tab) {
                  _Tab.reports => _buildQueue(now),
                  _Tab.audit => AdminAuditView(now: widget.now),
                  _Tab.flags => const AdminFlagsView(),
                  _Tab.notices => AdminNoticesView(now: widget.now),
                  _Tab.feedback => AdminFeedbackView(now: widget.now),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _tabLabel(_Tab tab) => switch (tab) {
    _Tab.reports => tr('Reports'),
    _Tab.audit => tr('Audit log'),
    _Tab.flags => tr('Flags'),
    _Tab.notices => tr('Notices'),
    _Tab.feedback => tr('Feedback'),
  };

  Widget _buildQueue(DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Filters(
          status: _status,
          kind: _kind,
          onStatus: (status) {
            if (status != _status) {
              _reload(status: status);
            }
          },
          onKind: (kind) {
            if (kind != _kind) {
              _reload(kind: kind);
            }
          },
        ),
        Expanded(child: _buildList(now)),
      ],
    );
  }

  Widget _buildList(DateTime now) {
    if (_reports.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the reports.'),
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
        icon: _status == ReportQueueStatus.open
            ? Icons.task_alt_rounded
            : Icons.inbox_outlined,
        title: _status == ReportQueueStatus.open
            ? tr('No open reports.')
            : tr('No handled reports yet.'),
        message: _status == ReportQueueStatus.open
            ? tr('New reports show up here.')
            : null,
      );
    }
    return ListView.builder(
      key: const ValueKey('admin-report-list'),
      controller: _scrollController,
      padding: circlePagePadding(context),
      itemCount: _reports.length + 1,
      itemBuilder: (context, index) {
        if (index == _reports.length) {
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
        final report = _reports[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ReportTile(
            report: report,
            now: now,
            onTap: () => _open(report),
          ),
        );
      },
    );
  }
}

const _keep = Object();

class _NotAnAdmin extends StatelessWidget {
  const _NotAnAdmin();

  @override
  Widget build(BuildContext context) {
    return CirclePageScaffold(
      title: tr('Admin console'),
      body: CircleEmptyState(
        icon: Icons.lock_outline_rounded,
        title: tr('Nothing here'),
        message: tr('This page is for the people who run WeCord.'),
      ),
    );
  }
}

/// Open or handled, and the kind of report.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.status,
    required this.kind,
    required this.onStatus,
    required this.onKind,
  });

  final ReportQueueStatus status;
  final ReportKind? kind;
  final ValueChanged<ReportQueueStatus> onStatus;
  final ValueChanged<ReportKind?> onKind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final item in ReportQueueStatus.values)
            WeCordChip(
              key: ValueKey('admin-status-${item.value}'),
              label: item.label,
              selected: status == item,
              onPaper: true,
              onPressed: () => onStatus(item),
            ),
          Container(width: 1, height: 20, color: context.tokens.colors.line),
          WeCordChip(
            key: const ValueKey('admin-kind-all'),
            label: tr('All'),
            selected: kind == null,
            onPaper: true,
            onPressed: () => onKind(null),
          ),
          for (final item in _queueKinds)
            WeCordChip(
              key: ValueKey('admin-kind-${item.value}'),
              label: item.label,
              selected: kind == item,
              onPaper: true,
              onPressed: () => onKind(item),
            ),
        ],
      ),
    );
  }
}

/// One report in the queue.
class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.now,
    required this.onTap,
  });

  final AdminReport report;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = report.title.isEmpty ? report.kind.singular : report.title;
    final meta = tr('{reason} · reported by {name} · {time}', {
      'reason': report.reasonLabel,
      'name': report.reporterName,
      'time': formatAuditTime(report.createdAt, now: now),
    });
    final resolution = report.resolution;
    return WeCordPressable(
      key: ValueKey('admin-report-${report.id}'),
      onPressed: onTap,
      semanticLabel: '${report.kind.singular}: $title. $meta',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.panel)
                : c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIconTile(
                icon: adminKindIcon(report.kind),
                tone: adminKindTone(report.kind),
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.muted,
                        height: 1.3,
                      ),
                    ),
                    if (report.details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        report.details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: c.ink,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (!report.isOpen && resolution != null) ...[
                      const SizedBox(height: 8),
                      AdminStateTag(
                        label: report.handledBy == null
                            ? resolution.label
                            : tr('{resolution} by {name}', {
                                'resolution': resolution.label,
                                'name': '@${report.handledBy}',
                              }),
                        tone: SettingsTone.neutral,
                      ),
                    ],
                  ],
                ),
              ),
              if (report.isOpen && report.repeatCount > 1) ...[
                const SizedBox(width: 8),
                CountBadge(
                  count: report.repeatCount,
                  tone: BadgeTone.unread,
                  semanticLabel: tr('{count} open reports about this', {
                    'count': report.repeatCount,
                  }),
                ),
              ],
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.faint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
