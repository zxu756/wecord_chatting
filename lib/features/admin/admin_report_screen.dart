import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_audit_view.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_reason_dialog.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/reports/message_reports.dart'
    show attachmentLabel;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One report in full: the report, a copy of what was reported, the
/// person or circle as it is now, what happened before, and the actions.
final adminReportDetailProvider = FutureProvider.autoDispose
    .family<AdminReportDetail, ({String id, bool message})>((ref, key) {
      return ref
          .watch(adminRepositoryProvider)
          .reportDetail(key.id, message: key.message);
    });

class AdminReportScreen extends ConsumerStatefulWidget {
  const AdminReportScreen({
    required this.reportId,
    this.message = false,
    this.now,
    super.key,
  });

  final String reportId;

  /// The report is of a message in a direct chat or a group (it has its own
  /// functions); the others are users, circles and posts.
  final bool message;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends ConsumerState<AdminReportScreen> {
  var _busy = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  ({String id, bool message}) get _key =>
      (id: widget.reportId, message: widget.message);

  void _refresh() => ref.invalidate(adminReportDetailProvider(_key));

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action]; says [done] when it worked or why it did not.
  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      _say(done);
    } catch (error) {
      if (mounted) {
        _say(adminErrorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

  // --- actions -----------------------------------------------------------

  Future<void> _close(AdminReportDetail detail, {required bool dismissed}) {
    final report = detail.report;
    if (report.kind == ReportKind.message) {
      return _run(
        () => _repository.resolveMessageReport(
          reportId: report.id,
          action: 'dismiss',
        ),
        tr('Report dismissed.'),
      );
    }
    return _run(
      () => _repository.resolveReport(
        reportId: report.id,
        dismissed: dismissed,
        resolution: dismissed
            ? ReportResolution.noViolation
            : ReportResolution.other,
      ),
      dismissed ? tr('Report dismissed.') : tr('Report marked as handled.'),
    );
  }

  /// Deletes the reported message of a direct chat or a group for everyone.
  Future<void> _deleteMessage(AdminReportDetail detail) async {
    final result = await askAdminReason(
      context,
      title: tr('Delete this message?'),
      message: tr('It is deleted for everyone in the chat.'),
      confirmLabel: tr('Continue'),
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    final sure = await confirmCircleAction(
      context,
      title: tr('Delete this message?'),
      message: tr('This cannot be undone.'),
      confirmLabel: tr('Delete message'),
    );
    if (!sure || !mounted) {
      return;
    }
    await _run(
      () => _repository.resolveMessageReport(
        reportId: detail.report.id,
        action: 'delete_message',
        note: result.reason,
      ),
      tr('The message was deleted.'),
    );
  }

  Future<void> _suspendPerson(
    AdminReportDetail detail,
    AdminPerson person,
  ) async {
    final result = await askAdminReason(
      context,
      title: tr('Suspend {name}?', {'name': person.name}),
      message: tr(
        'They are signed out everywhere and cannot sign in until the '
        'suspension ends.',
      ),
      confirmLabel: tr('Continue'),
      withDuration: true,
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    final until = result.until;
    final sure = await confirmCircleAction(
      context,
      title: tr('Suspend {name}?', {'name': person.name}),
      message: until == null
          ? tr('{name} will be signed out and banned for good.', {
              'name': person.name,
            })
          : tr('{name} will be signed out and banned until {date}.', {
              'name': person.name,
              'date': adminDateTime(until),
            }),
      confirmLabel: tr('Suspend'),
    );
    if (!sure || !mounted) {
      return;
    }
    final isMessage = detail.report.kind == ReportKind.message;
    await _run(() async {
      await _repository.suspendUser(
        userId: person.id,
        reason: result.reason,
        until: until,
        // A message report is closed below, once the person is suspended.
        reportId: detail.report.isOpen && !isMessage ? detail.report.id : null,
      );
      if (isMessage && detail.report.isOpen) {
        await _repository.resolveMessageReport(
          reportId: detail.report.id,
          action: 'suspend',
          note: result.reason,
        );
      }
    }, tr('{name} was suspended.', {'name': person.name}));
  }

  Future<void> _liftSuspension(AdminPerson person) async {
    final result = await askAdminReason(
      context,
      title: tr('Lift the suspension of {name}?', {'name': person.name}),
      message: tr('They can sign in and use WeCord again.'),
      confirmLabel: tr('Lift suspension'),
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    await _run(
      () => _repository.unsuspendUser(userId: person.id, reason: result.reason),
      tr('The suspension was lifted.'),
    );
  }

  Future<void> _deletePost(AdminReportDetail detail) async {
    final postId = detail.report.subjectId;
    if (postId == null) {
      return;
    }
    final result = await askAdminReason(
      context,
      title: tr('Delete this post?'),
      message: tr('It disappears for everyone in the circle.'),
      confirmLabel: tr('Continue'),
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    final sure = await confirmCircleAction(
      context,
      title: tr('Delete this post?'),
      message: tr('This cannot be undone.'),
      confirmLabel: tr('Delete post'),
    );
    if (!sure || !mounted) {
      return;
    }
    await _run(
      () => _repository.deletePost(
        postId: postId,
        reason: result.reason,
        reportId: detail.report.isOpen ? detail.report.id : null,
      ),
      tr('The post was deleted.'),
    );
  }

  Future<void> _takeCircleDown(
    AdminReportDetail detail,
    CircleTakedownMode mode,
  ) async {
    final circleId = detail.circleId;
    if (circleId == null) {
      return;
    }
    final name = detail.kind == ReportKind.circle
        ? '${detail.snapshot['name'] ?? ''}'
        : '${detail.subject['circle_name'] ?? ''}';
    final suspend = mode == CircleTakedownMode.suspend;
    final result = await askAdminReason(
      context,
      title: suspend
          ? tr('Suspend {name}?', {'name': name})
          : tr('Delist {name}?', {'name': name}),
      message: suspend
          ? tr(
              'Nobody can enter or read it. Members see "This circle was '
              'suspended".',
            )
          : tr(
              'It disappears from Discover and takes no new members. People '
              'who are in it keep using it.',
            ),
      confirmLabel: suspend ? tr('Continue') : tr('Delist'),
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    if (suspend) {
      final sure = await confirmCircleAction(
        context,
        title: tr('Suspend {name}?', {'name': name}),
        message: tr('Its members lose access right away.'),
        confirmLabel: tr('Suspend circle'),
      );
      if (!sure || !mounted) {
        return;
      }
    }
    await _run(
      () => _repository.disableCircle(
        circleId: circleId,
        mode: mode,
        reason: result.reason,
        reportId: detail.report.isOpen && detail.kind == ReportKind.circle
            ? detail.report.id
            : null,
      ),
      suspend
          ? tr('The circle was suspended.')
          : tr('The circle was delisted.'),
    );
  }

  Future<void> _restoreCircle(AdminReportDetail detail) async {
    final circleId = detail.circleId;
    if (circleId == null) {
      return;
    }
    final result = await askAdminReason(
      context,
      title: tr('Restore this circle?'),
      message: tr(
        'It comes back to Discover (if it is public) and takes members again.',
      ),
      confirmLabel: tr('Restore circle'),
      reasonRequired: false,
      now: _now,
    );
    if (result == null || !mounted) {
      return;
    }
    await _run(
      () => _repository.enableCircle(circleId: circleId, reason: result.reason),
      tr('The circle was restored.'),
    );
  }

  // --- layout ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(adminReportDetailProvider(_key));
    final role = ref.watch(adminRoleProvider).value;
    return CirclePageScaffold(
      title: tr('Report'),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the report.'),
          message: adminErrorText(error),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _refresh,
          ),
        ),
        data: (detail) => ListView(
          key: const ValueKey('admin-report-detail'),
          padding: circlePagePadding(context),
          children: [
            _SummaryCard(detail: detail, now: _now),
            _SnapshotCard(detail: detail),
            _NowCard(detail: detail),
            _HistoryCard(detail: detail, now: _now),
            _ActionsCard(
              detail: detail,
              role: role,
              busy: _busy,
              onClose: (dismissed) => _close(detail, dismissed: dismissed),
              onSuspendPerson: (person) => _suspendPerson(detail, person),
              onLiftSuspension: _liftSuspension,
              onDeletePost: () => _deletePost(detail),
              onDeleteMessage: () => _deleteMessage(detail),
              onTakeCircleDown: (mode) => _takeCircleDown(detail, mode),
              onRestoreCircle: () => _restoreCircle(detail),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Cards
// --------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail, required this.now});

  final AdminReportDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final report = detail.report;
    final title = report.title.isEmpty ? report.kind.singular : report.title;
    final resolution = report.resolution;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CircleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsIconTile(
                  icon: adminKindIcon(report.kind),
                  tone: adminKindTone(report.kind),
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          AdminStateTag(label: report.kind.singular),
                          AdminStateTag(label: report.reasonLabel),
                          if (report.isOpen)
                            AdminStateTag(
                              label: trIn('Admin', 'Open'),
                              tone: SettingsTone.warning,
                            )
                          else
                            AdminStateTag(
                              label: resolution?.label ?? tr('Handled'),
                              tone: SettingsTone.success,
                            ),
                          if (report.isOpen && report.repeatCount > 1)
                            AdminStateTag(
                              label: tr('{count} open reports', {
                                'count': report.repeatCount,
                              }),
                              tone: SettingsTone.danger,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdminFact(label: tr('Reported by'), value: report.reporterName),
            AdminFact(
              label: tr('When'),
              value:
                  '${adminDateTime(report.createdAt)} · '
                  '${formatAuditTime(report.createdAt, now: now)}',
            ),
            if (detail.reporterTotal > 1)
              AdminFact(
                label: tr('Their reports'),
                value: tr('{total} filed, {dismissed} dismissed', {
                  'total': detail.reporterTotal,
                  'dismissed': detail.reporterDismissed,
                }),
              ),
            if (!report.isOpen && report.handledAt != null)
              AdminFact(
                label: tr('Handled'),
                value: report.handledBy == null
                    ? adminDateTime(report.handledAt!)
                    : tr('{date} by {name}', {
                        'date': adminDateTime(report.handledAt!),
                        'name': '@${report.handledBy}',
                      }),
              ),
            if (report.details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                tr("Reporter's note"),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
              const SizedBox(height: 6),
              AdminQuote(text: report.details),
            ],
          ],
        ),
      ),
    );
  }
}

/// What was reported, as it was when the report came in.
class _SnapshotCard extends ConsumerStatefulWidget {
  const _SnapshotCard({required this.detail});

  final AdminReportDetail detail;

  @override
  ConsumerState<_SnapshotCard> createState() => _SnapshotCardState();
}

class _SnapshotCardState extends ConsumerState<_SnapshotCard> {
  String? _pictureUrl;
  var _loadingPicture = false;
  Object? _pictureError;

  Future<void> _showPicture() async {
    setState(() {
      _loadingPicture = true;
      _pictureError = null;
    });
    try {
      final url = await ref
          .read(adminRepositoryProvider)
          .attachmentUrl(widget.detail.report.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _pictureUrl = url;
        _pictureError = url == null ? 'none' : null;
        _loadingPicture = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pictureError = error;
        _loadingPicture = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final detail = widget.detail;
    final snapshot = detail.snapshot;
    String text(String key) => '${snapshot[key] ?? ''}';
    DateTime? time(String key) => snapshot[key] is String
        ? DateTime.tryParse(snapshot[key] as String)
        : null;

    final children = <Widget>[];
    if (snapshot['missing'] == true || snapshot.isEmpty) {
      children.add(
        Text(
          tr('There is no copy: what was reported no longer exists.'),
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    } else {
      switch (detail.kind) {
        case ReportKind.user:
          children.addAll([
            AdminFact(label: tr('Name'), value: text('display_name')),
            AdminFact(label: tr('Username'), value: '@${text('username')}'),
            if (time('created_at') case final joined?)
              AdminFact(label: tr('Joined'), value: adminDate(joined)),
            if (text('bio').isNotEmpty) ...[
              const SizedBox(height: 8),
              AdminQuote(text: text('bio')),
            ],
          ]);
        case ReportKind.circle:
          children.addAll([
            AdminFact(label: tr('Name'), value: text('name')),
            AdminFact(
              label: tr('Owner'),
              value: text('owner_username').isEmpty
                  ? tr('Unknown')
                  : '@${text('owner_username')}',
            ),
            AdminFact(label: tr('Members'), value: text('member_count')),
            AdminFact(
              label: tr('Visibility'),
              value: snapshot['is_public'] == true
                  ? tr('Public')
                  : tr('Private'),
            ),
            if (time('created_at') case final created?)
              AdminFact(label: tr('Created'), value: adminDate(created)),
            if (text('description').isNotEmpty) ...[
              const SizedBox(height: 8),
              AdminQuote(text: text('description')),
            ],
          ]);
        case ReportKind.post:
          children.addAll([
            AdminFact(
              label: tr('Author'),
              value: text('author_username').isEmpty
                  ? tr('Unknown')
                  : '${text('author_display_name')} (@${text('author_username')})',
            ),
            AdminFact(label: tr('Circle'), value: text('circle_name')),
            if (time('created_at') case final posted?)
              AdminFact(label: tr('Posted'), value: adminDateTime(posted)),
            if (text('body').isNotEmpty) ...[
              const SizedBox(height: 8),
              AdminQuote(text: text('body')),
            ],
            if (snapshot['attachment'] != null) ...[
              const SizedBox(height: 10),
              _picture(context),
            ],
          ]);
        case ReportKind.message:
          children.addAll([
            AdminFact(
              label: tr('Sender'),
              value: text('sender_username').isEmpty
                  ? tr('Unknown')
                  : '${text('sender_display_name')} (@${text('sender_username')})',
            ),
            AdminFact(
              label: tr('Chat'),
              value: text('conversation_type') == 'group'
                  ? tr('Group {name}', {'name': text('conversation_title')})
                  : tr('Direct chat'),
            ),
            if (time('created_at') case final sent?)
              AdminFact(label: tr('Sent'), value: adminDateTime(sent)),
            if (text('body').isNotEmpty) ...[
              const SizedBox(height: 8),
              AdminQuote(text: text('body')),
            ],
            if (attachmentLabel(snapshot['attachment']) case final label?) ...[
              const SizedBox(height: 8),
              Text(
                label,
                key: const ValueKey('admin-message-attachment'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
            ],
            if (detail.contextMessages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr('Messages around it'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
              const SizedBox(height: 6),
              for (final item in detail.contextMessages)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${item.senderName}: '
                    '${item.body.isNotEmpty ? item.body : (item.attachment ?? '')}',
                    key: const ValueKey('admin-message-context'),
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
                  ),
                ),
            ],
          ]);
      }
    }
    return AdminSection(
      title: tr('What was reported'),
      caption: tr('A copy taken when it was reported.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _picture(BuildContext context) {
    final c = context.tokens.colors;
    final url = _pictureUrl;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Image.network(
            url,
            key: const ValueKey('admin-report-picture'),
            fit: BoxFit.contain,
            semanticLabel: tr('The picture of the reported post'),
            errorBuilder: (context, error, stack) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr('The picture could not be shown.'),
                style: TextStyle(color: c.muted),
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: WeCordButton(
            key: const ValueKey('admin-show-picture'),
            label: tr('Show the picture'),
            icon: Icons.image_outlined,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.small,
            loading: _loadingPicture,
            onPressed: _showPicture,
          ),
        ),
        if (_pictureError != null) ...[
          const SizedBox(height: 6),
          Text(
            _pictureError == 'none'
                ? tr('The picture is no longer there.')
                : adminErrorText(_pictureError!),
            style: TextStyle(fontSize: 13, color: c.dangerText),
          ),
        ],
      ],
    );
  }
}

/// The subject as it is now: suspended, taken down, deleted.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.detail});

  final AdminReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final person = detail.responsible;
    final tags = <Widget>[];
    final lines = <Widget>[];

    if (detail.circleMode case final mode?) {
      tags.add(
        AdminStateTag(
          label: mode == CircleTakedownMode.suspend
              ? tr('Circle suspended')
              : tr('Circle delisted'),
          tone: SettingsTone.warning,
        ),
      );
    }
    if (detail.kind == ReportKind.post) {
      tags.add(
        AdminStateTag(
          label: detail.postDeleted ? tr('Post deleted') : tr('Post is live'),
          tone: detail.postDeleted
              ? SettingsTone.success
              : SettingsTone.neutral,
        ),
      );
    }
    if (detail.kind == ReportKind.message && !detail.subjectMissing) {
      tags.add(
        AdminStateTag(
          label: detail.postDeleted
              ? tr('Message deleted')
              : tr('Message is live'),
          tone: detail.postDeleted
              ? SettingsTone.success
              : SettingsTone.neutral,
        ),
      );
    }
    if (person != null) {
      if (person.isSuspended) {
        final until = person.suspendedUntil;
        tags.add(
          AdminStateTag(
            label: until == null
                ? tr('{name} suspended for good', {'name': person.name})
                : tr('{name} suspended until {date}', {
                    'name': person.name,
                    'date': adminDate(until),
                  }),
            tone: SettingsTone.danger,
          ),
        );
        if (person.suspensionReason case final reason? when reason.isNotEmpty) {
          lines.add(AdminFact(label: tr('Reason'), value: reason));
        }
      }
      if (person.isAdmin) {
        tags.add(
          AdminStateTag(label: tr('{name} is an admin', {'name': person.name})),
        );
      }
      lines.add(
        AdminFact(
          label: switch (detail.kind) {
            ReportKind.circle => tr('Owner'),
            ReportKind.post => tr('Author'),
            ReportKind.message => tr('Sender'),
            _ => tr('Person'),
          },
          value: '${person.name} (@${person.username})',
        ),
      );
      lines.add(
        AdminFact(
          label: tr('Reports'),
          value: tr('{total} in all, {open} open', {
            'total': person.reportsAgainst,
            'open': person.openReportsAgainst,
          }),
        ),
      );
    }
    if (detail.subjectMissing) {
      lines.add(
        Text(
          tr('This no longer exists.'),
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    }
    return AdminSection(
      title: tr('Right now'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: tags),
            ),
          ...lines,
        ],
      ),
    );
  }
}

/// Earlier reports about the same subject, and what admins did.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.detail, required this.now});

  final AdminReportDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final empty = detail.history.isEmpty && detail.actions.isEmpty;
    return AdminSection(
      title: tr('History'),
      child: empty
          ? Text(
              tr('No other reports or actions about this.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in detail.history)
                  _HistoryRow(
                    icon: Icons.flag_outlined,
                    text: tr('{reason} report, {state}', {
                      'reason': entry.reasonLabel,
                      'state': entry.status == 'open'
                          ? tr('open')
                          : (entry.resolution?.label.toLowerCase() ??
                                tr('handled')),
                    }),
                    time: formatAuditTime(entry.createdAt, now: now),
                  ),
                for (final entry in detail.actions)
                  _HistoryRow(
                    icon: adminAuditIcon(entry.action),
                    text: adminAuditSummary(entry),
                    time: formatAuditTime(entry.createdAt, now: now),
                  ),
              ],
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.text,
    required this.time,
  });

  final IconData icon;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: c.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: c.ink, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: TextStyle(fontSize: 12, color: c.subtle)),
        ],
      ),
    );
  }
}

/// The things an admin can do. Red is only for what bans, suspends or
/// deletes, and each of those asks twice.
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.detail,
    required this.role,
    required this.busy,
    required this.onClose,
    required this.onSuspendPerson,
    required this.onLiftSuspension,
    required this.onDeletePost,
    required this.onDeleteMessage,
    required this.onTakeCircleDown,
    required this.onRestoreCircle,
  });

  final AdminReportDetail detail;
  final AdminRole? role;
  final bool busy;
  final ValueChanged<bool> onClose;
  final ValueChanged<AdminPerson> onSuspendPerson;
  final ValueChanged<AdminPerson> onLiftSuspension;
  final VoidCallback onDeletePost;
  final VoidCallback onDeleteMessage;
  final ValueChanged<CircleTakedownMode> onTakeCircleDown;
  final VoidCallback onRestoreCircle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final report = detail.report;
    final person = detail.responsible;
    final canSanction = role?.canSanction ?? false;
    final mode = detail.circleMode;

    Widget button(
      String key,
      String label,
      VoidCallback onPressed, {
      WeCordButtonVariant variant = WeCordButtonVariant.secondary,
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: WeCordButton(
        key: ValueKey(key),
        label: label,
        icon: icon,
        variant: variant,
        expand: true,
        onPressed: busy ? null : onPressed,
      ),
    );

    final closing = <Widget>[
      if (report.isOpen) ...[
        button(
          'admin-action-dismiss',
          tr('No violation'),
          () => onClose(true),
          icon: Icons.check_rounded,
        ),
        // A message report ends in "No violation", deleting the message or
        // suspending the sender.
        if (detail.kind != ReportKind.message)
          button(
            'admin-action-handled',
            tr('Mark as handled'),
            () => onClose(false),
            icon: Icons.task_alt_rounded,
          ),
      ],
    ];

    final sanctions = <Widget>[];
    final undo = <Widget>[];
    if (canSanction) {
      if (detail.kind == ReportKind.post &&
          !detail.postDeleted &&
          !detail.subjectMissing) {
        sanctions.add(
          button(
            'admin-action-delete-post',
            tr('Delete post'),
            onDeletePost,
            variant: WeCordButtonVariant.danger,
            icon: Icons.delete_outline_rounded,
          ),
        );
      }
      if (detail.kind == ReportKind.message &&
          report.isOpen &&
          !detail.postDeleted &&
          !detail.subjectMissing) {
        sanctions.add(
          button(
            'admin-action-delete-message',
            tr('Delete message'),
            onDeleteMessage,
            variant: WeCordButtonVariant.danger,
            icon: Icons.delete_outline_rounded,
          ),
        );
      }
      if (detail.kind == ReportKind.circle && !detail.subjectMissing) {
        if (mode != CircleTakedownMode.delist) {
          sanctions.add(
            button(
              'admin-action-delist',
              mode == null ? tr('Delist circle') : tr('Delist instead'),
              () => onTakeCircleDown(CircleTakedownMode.delist),
              icon: Icons.visibility_off_outlined,
            ),
          );
        }
        if (mode != CircleTakedownMode.suspend) {
          sanctions.add(
            button(
              'admin-action-suspend-circle',
              tr('Suspend circle'),
              () => onTakeCircleDown(CircleTakedownMode.suspend),
              variant: WeCordButtonVariant.danger,
              icon: Icons.block_rounded,
            ),
          );
        }
        if (mode != null) {
          undo.add(
            button(
              'admin-action-restore-circle',
              tr('Restore circle'),
              onRestoreCircle,
              icon: Icons.restore_rounded,
            ),
          );
        }
      }
      if (person != null && !person.isAdmin) {
        final label = switch (detail.kind) {
          ReportKind.circle => tr('Suspend owner'),
          ReportKind.post => tr('Suspend author'),
          ReportKind.message => tr('Suspend sender'),
          _ => tr('Suspend person'),
        };
        if (person.isSuspended) {
          undo.add(
            button(
              'admin-action-lift',
              tr('Lift suspension'),
              () => onLiftSuspension(person),
              icon: Icons.lock_open_rounded,
            ),
          );
        } else {
          sanctions.add(
            button(
              'admin-action-suspend-person',
              label,
              () => onSuspendPerson(person),
              variant: WeCordButtonVariant.danger,
              icon: Icons.person_off_outlined,
            ),
          );
        }
      }
    }

    final nothing = closing.isEmpty && sanctions.isEmpty && undo.isEmpty;
    return AdminSection(
      title: tr('Actions'),
      caption: sanctions.isEmpty
          ? null
          : tr(
              'Red actions sign people out or remove things. You will be asked to confirm.',
            ),
      child: nothing
          ? Text(
              canSanction
                  ? tr('Nothing left to do here.')
                  : tr('This report is closed.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...closing, ...sanctions, ...undo],
            ),
    );
  }
}
