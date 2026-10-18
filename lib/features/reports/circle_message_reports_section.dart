import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_ai_guard_repository.dart'
    show messageReviewCountProvider;
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/reports/message_reports.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A heading in the Review queue ("User reports", "Held by the AI guard"),
/// with a red count of what waits under it.
class ReviewSectionHeader extends StatelessWidget {
  const ReviewSectionHeader({required this.title, this.count, super.key});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            CountBadge(count: count, tone: BadgeTone.mention),
          ],
        ],
      ),
    );
  }
}

/// One report of a message in a circle, with what moderators can do:
/// Dismiss, Delete message, Time out and Ban. The server checks each
/// permission; a moderator who may not do something is told so.
class MessageReportCard extends ConsumerStatefulWidget {
  const MessageReportCard({
    required this.report,
    required this.circleId,
    this.now,
    super.key,
  });

  final CircleMessageReport report;
  final String circleId;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<MessageReportCard> createState() => _MessageReportCardState();
}

class _MessageReportCardState extends ConsumerState<MessageReportCard> {
  MessageReportAction? _busy;
  var _showContext = false;

  Future<void> _run(
    MessageReportAction action, {
    Duration? timeout,
    required String done,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = action);
    try {
      await ref
          .read(messageReportsRepositoryProvider)
          .resolve(widget.report.id, action, timeout: timeout);
      ref.invalidate(circleMessageReportsProvider(widget.circleId));
      ref.invalidate(messageReviewCountProvider(widget.circleId));
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      // The card goes away with the refreshed queue; if it stays, it is
      // usable again.
      if (mounted) {
        setState(() => _busy = null);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = null);
      }
      // Somebody else may have handled it first.
      ref.invalidate(circleMessageReportsProvider(widget.circleId));
      final denied = error is PostgrestException && error.code == '42501';
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? tr("You don't have permission to do that.")
                : tr("Couldn't update this report. It may already be handled."),
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete this message?'),
      message: tr('It is deleted for everyone.'),
      confirmLabel: tr('Delete message'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(MessageReportAction.deleteMessage, done: tr('Message deleted.'));
  }

  Future<void> _timeOut() async {
    final duration = await showWeCordSheet<Duration>(
      context,
      title: tr('Time out {name}', {'name': widget.report.reportedName}),
      builder: (context, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SettingsGroup(
            color: context.tokens.colors.well,
            children: [
              for (final choice in messageReportTimeoutChoices)
                SettingsRow(
                  key: ValueKey('report-timeout-${choice.inHours}h'),
                  title: _durationLabel(choice),
                  onTap: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        ),
      ),
    );
    if (duration == null || !mounted) {
      return;
    }
    await _run(
      MessageReportAction.timeout,
      timeout: duration,
      done: tr('{name} was timed out.', {'name': widget.report.reportedName}),
    );
  }

  Future<void> _ban() async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Ban {name}?', {'name': widget.report.reportedName}),
      message: tr('They are removed from the circle and cannot join again.'),
      confirmLabel: tr('Ban'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      MessageReportAction.ban,
      done: tr('{name} was banned.', {'name': widget.report.reportedName}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final report = widget.report;
    final when = formatAuditTime(
      report.createdAt,
      now: (widget.now ?? DateTime.now)(),
    );
    final busy = _busy != null;
    final channel = report.channelName;
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: report.reportedName,
                size: 40,
                image: report.reportedAvatarUrl == null
                    ? null
                    : NetworkImage(report.reportedAvatarUrl!),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.reportedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      channel == null ? when : '#$channel · $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('report-reason-pill'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(WeCordRadii.pill),
                ),
                child: Text(
                  report.reason.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.dangerText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('report-body'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (report.body.isNotEmpty)
                  Text(
                    report.body,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.ink, height: 1.45),
                  ),
                if (report.attachment != null)
                  Padding(
                    padding: EdgeInsets.only(top: report.body.isEmpty ? 0 : 6),
                    child: Text(
                      report.attachment!,
                      style: TextStyle(fontSize: 13.5, color: c.muted),
                    ),
                  ),
                if (report.body.isEmpty && report.attachment == null)
                  Text(
                    tr('No text.'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.repeatCount > 1
                ? tr('Reported by {name} and {count} others', {
                    'name': report.reporterName,
                    'count': report.repeatCount - 1,
                  })
                : tr('Reported by {name}', {'name': report.reporterName}),
            key: const ValueKey('report-reporter'),
            style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
          ),
          if (report.details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '“${report.details}”',
              key: const ValueKey('report-details-text'),
              style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.4),
            ),
          ],
          if (report.context.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                key: const ValueKey('report-toggle-context'),
                label: _showContext
                    ? tr('Hide context')
                    : tr('Show context ({count})', {
                        'count': report.context.length,
                      }),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () => setState(() => _showContext = !_showContext),
              ),
            ),
            if (_showContext) _ContextList(report: report),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WeCordButton(
                key: const ValueKey('report-dismiss'),
                label: tr('Dismiss report'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                icon: Icons.check_rounded,
                loading: _busy == MessageReportAction.dismiss,
                onPressed: busy
                    ? null
                    : () => unawaited(
                        _run(
                          MessageReportAction.dismiss,
                          done: tr('Report dismissed.'),
                        ),
                      ),
              ),
              if (report.messageAvailable)
                WeCordButton(
                  key: const ValueKey('report-delete'),
                  label: tr('Delete message'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  icon: Icons.delete_outline_rounded,
                  loading: _busy == MessageReportAction.deleteMessage,
                  onPressed: busy ? null : () => unawaited(_delete()),
                ),
              if (report.reportedUserId != null) ...[
                WeCordButton(
                  key: const ValueKey('report-timeout'),
                  label: tr('Time out'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  icon: Icons.timer_outlined,
                  loading: _busy == MessageReportAction.timeout,
                  onPressed: busy ? null : () => unawaited(_timeOut()),
                ),
                WeCordButton(
                  key: const ValueKey('report-ban'),
                  label: tr('Ban'),
                  variant: WeCordButtonVariant.danger,
                  size: WeCordButtonSize.small,
                  icon: Icons.block_rounded,
                  loading: _busy == MessageReportAction.ban,
                  onPressed: busy ? null : () => unawaited(_ban()),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _durationLabel(Duration duration) {
  if (duration.inDays >= 7 && duration.inDays % 7 == 0) {
    return tr('{count} week', {'count': duration.inDays ~/ 7});
  }
  if (duration.inHours >= 24 && duration.inHours % 24 == 0) {
    return tr('{count} day', {'count': duration.inHours ~/ 24});
  }
  return tr('{count} hour', {'count': duration.inHours});
}

/// The messages around the reported one, as the reporter saw them.
class _ContextList extends StatelessWidget {
  const _ContextList({required this.report});

  final CircleMessageReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final before = [
      for (final item in report.context)
        if (!item.isAfter) item,
    ];
    final after = [
      for (final item in report.context)
        if (item.isAfter) item,
    ];
    Widget line(ReportContextMessage item) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${item.senderName}: ',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
            ),
            TextSpan(
              text: item.body.isNotEmpty ? item.body : (item.attachment ?? ''),
              style: TextStyle(color: c.muted),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13.5, height: 1.4),
      ),
    );
    return Container(
      key: const ValueKey('report-context'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in before) line(item),
          // The reported message, between what came before and after it.
          Container(
            key: const ValueKey('report-context-reported'),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.sm),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${report.reportedName}: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: report.body.isNotEmpty
                        ? report.body
                        : (report.attachment ?? ''),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: c.dangerText,
              ),
            ),
          ),
          for (final item in after) line(item),
        ],
      ),
    );
  }
}
