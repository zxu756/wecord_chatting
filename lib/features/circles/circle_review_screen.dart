import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/circles/guard2/guard_items_section.dart';
import 'package:wecord/features/circles/guard2/review_media.dart';
import 'package:wecord/features/circles/mod_tools/ban_appeals_section.dart';
import 'package:wecord/features/reports/circle_message_reports_section.dart';
import 'package:wecord/features/reports/message_reports.dart';
import 'package:wecord/features/circles/join_requests/join_requests_section.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleReviewScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleReviewScreen(circleId: circleId),
    ),
  );
}

/// The circle's Review queue: messages people reported, and messages the AI
/// guard held back or flagged, with the AI's category and reason, for
/// moderators to handle. Reports come first; their count is part of the
/// red badge on the circle's moderation tools.
class CircleReviewScreen extends ConsumerWidget {
  const CircleReviewScreen({required this.circleId, this.now, super.key});

  final String circleId;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(messageReviewsProvider(circleId));
    // A moderator who cannot read reports (or no connection) just sees none.
    final reports =
        ref.watch(circleMessageReportsProvider(circleId)).value ??
        const <CircleMessageReport>[];
    // Events, notes and tasks the AI flagged (it cannot hide them, so they
    // are cards of their own); none when they cannot be read.
    final flagged =
        ref.watch(guardItemReviewsProvider(circleId)).value ??
        const <GuardItemReview>[];
    return CirclePageScaffold(
      title: tr('Review'),
      // The raid banner and ban appeals, then the circle's join requests, sit
      // above the reports and the AI guard's queue.
      body: ModToolsReviewHost(
        circleId: circleId,
        now: now,
        child: JoinRequestsHost(
          circleId: circleId,
          now: now,
          child: reviews.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => CircleEmptyState(
              icon: Icons.fact_check_outlined,
              title: tr('Could not load the review queue.'),
              action: WeCordButton(
                label: tr('Try again'),
                onPressed: () {
                  ref.invalidate(messageReviewsProvider(circleId));
                  ref.invalidate(circleMessageReportsProvider(circleId));
                },
              ),
            ),
            data: (items) => items.isEmpty && reports.isEmpty && flagged.isEmpty
                ? CircleEmptyState(
                    key: const ValueKey('review-empty'),
                    icon: Icons.verified_user_outlined,
                    title: tr('Nothing to review'),
                    message: tr(
                      'Messages the AI guard holds back or flags, and messages '
                      'people report, show up here.',
                    ),
                  )
                : ListView(
                    padding: circlePagePadding(context),
                    children: [
                      if (reports.isNotEmpty) ...[
                        ReviewSectionHeader(
                          key: const ValueKey('review-reports-header'),
                          title: tr('User reports'),
                          count: reports.length,
                        ),
                        const SizedBox(height: 4),
                        for (final report in reports) ...[
                          const SizedBox(height: 8),
                          MessageReportCard(
                            key: ValueKey('report-${report.id}'),
                            report: report,
                            circleId: circleId,
                            now: now,
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                      if (flagged.isNotEmpty) ...[
                        GuardItemsList(
                          circleId: circleId,
                          items: flagged,
                          now: now,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (items.isNotEmpty) ...[
                        if (reports.isNotEmpty || flagged.isNotEmpty)
                          ReviewSectionHeader(
                            key: const ValueKey('review-guard-header'),
                            title: tr('Held or flagged by the AI guard'),
                            count: items.length,
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                          child: Text(
                            tr(
                              'Held messages are hidden from everyone but their '
                              'author until you approve them. Flagged messages '
                              'are already visible.',
                            ),
                            style: TextStyle(
                              fontSize: 13.5,
                              color: context.tokens.colors.muted,
                              height: 1.4,
                            ),
                          ),
                        ),
                        for (final item in items) ...[
                          const SizedBox(height: 12),
                          ReviewCard(
                            key: ValueKey('review-${item.messageId}'),
                            review: item,
                            circleId: circleId,
                            now: now,
                          ),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// One message in the queue with its Approve and Remove buttons.
class ReviewCard extends ConsumerStatefulWidget {
  const ReviewCard({
    required this.review,
    required this.circleId,
    this.now,
    super.key,
  });

  final MessageReview review;
  final String circleId;
  final DateTime Function()? now;

  @override
  ConsumerState<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<ReviewCard> {
  /// 'approve' or 'remove' while the request runs.
  String? _busy;

  Future<void> _decide({required bool approve}) async {
    final review = widget.review;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!approve) {
      final confirmed = await confirmCircleAction(
        context,
        title: tr('Remove this message?'),
        message: review.held
            ? tr('It is deleted and nobody else will ever see it.')
            : tr('It is deleted for everyone.'),
        confirmLabel: tr('Remove'),
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() => _busy = approve ? 'approve' : 'remove');
    final repository = ref.read(circleAiGuardRepositoryProvider);
    try {
      if (approve) {
        await repository.approve(review.messageId);
      } else {
        await repository.remove(review.messageId);
      }
      ref.invalidate(messageReviewsProvider(widget.circleId));
      ref.invalidate(messageReviewCountProvider(widget.circleId));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            approve ? tr('Message approved.') : tr('Message removed.'),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _busy = null);
      }
      // Somebody else may have decided first.
      ref.invalidate(messageReviewsProvider(widget.circleId));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr("Couldn't update this message. It may already be reviewed."),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final review = widget.review;
    final channel = review.channelName;
    final when = formatAuditTime(
      review.sentAt,
      now: (widget.now ?? DateTime.now)(),
    );
    final busy = _busy != null;
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: review.senderName,
                size: 40,
                image: review.senderAvatarUrl == null
                    ? null
                    : NetworkImage(review.senderAvatarUrl!),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.senderName,
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
              _StatePill(held: review.held),
            ],
          ),
          const SizedBox(height: 12),
          if (review.body.trim().isNotEmpty ||
              !ReviewMedia(type: review.type, media: review.media).hasContent)
            Container(
              key: const ValueKey('review-body'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Text(
                review.body,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: c.ink, height: 1.45),
              ),
            ),
          // A held picture, or a poll's options (AI guard 2.0).
          ReviewMedia(type: review.type, media: review.media),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: c.dangerText),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  key: const ValueKey('review-verdict'),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: review.verdict.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.dangerText,
                        ),
                      ),
                      if (review.localizedReason case final reason?
                          when reason.isNotEmpty)
                        TextSpan(
                          text: ' · $reason',
                          style: TextStyle(color: c.muted),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('review-remove'),
                  label: tr('Remove'),
                  variant: WeCordButtonVariant.secondary,
                  icon: Icons.delete_outline_rounded,
                  loading: _busy == 'remove',
                  onPressed: busy
                      ? null
                      : () => unawaited(_decide(approve: false)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('review-approve'),
                  label: tr('Approve'),
                  icon: Icons.check_rounded,
                  loading: _busy == 'approve',
                  onPressed: busy
                      ? null
                      : () => unawaited(_decide(approve: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Held" (hidden from others) or "Flagged" (visible).
class _StatePill extends StatelessWidget {
  const _StatePill({required this.held});

  final bool held;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: ValueKey(held ? 'review-held' : 'review-flagged'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: held ? c.warningSoft : c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Text(
        held ? tr('Held') : tr('Flagged'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: held ? c.warningText : c.muted,
        ),
      ),
    );
  }
}
