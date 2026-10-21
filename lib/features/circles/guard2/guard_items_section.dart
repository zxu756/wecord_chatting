import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/knowledge_base/kb_screen.dart';
import 'package:wecord/features/reports/circle_message_reports_section.dart'
    show ReviewSectionHeader;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Events, notes and tasks flagged by the AI guard": cards for the things a
/// new member made that the AI found worrying. They are not hidden; a
/// moderator opens one, deals with it with the usual tools and dismisses the
/// card. A column for the Review list, which puts it between the reports and
/// the held messages.
class GuardItemsList extends StatelessWidget {
  const GuardItemsList({
    required this.circleId,
    required this.items,
    this.now,
    super.key,
  });

  final String circleId;
  final List<GuardItemReview> items;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('review-items'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewSectionHeader(
          key: const ValueKey('review-items-header'),
          title: tr('Events, notes and tasks flagged by the AI guard'),
          count: items.length,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Text(
            tr(
              'These are visible to everyone. Open one to deal with it, '
              'then dismiss the card.',
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
          GuardItemCard(
            key: ValueKey('review-item-${item.id}'),
            item: item,
            circleId: circleId,
            now: now,
          ),
        ],
      ],
    );
  }
}

/// One flagged item with the AI's category and reason, Open and Dismiss.
class GuardItemCard extends ConsumerStatefulWidget {
  const GuardItemCard({
    required this.item,
    required this.circleId,
    this.now,
    super.key,
  });

  final GuardItemReview item;
  final String circleId;
  final DateTime Function()? now;

  @override
  ConsumerState<GuardItemCard> createState() => _GuardItemCardState();
}

class _GuardItemCardState extends ConsumerState<GuardItemCard> {
  var _busy = false;

  void _open() {
    final item = widget.item;
    final router = GoRouter.of(context);
    if (item.type == GuardItemType.circleEvent) {
      unawaited(
        router.push(
          CircleEventsScreen.pathFor(widget.circleId, eventId: item.itemId),
        ),
      );
      return;
    }
    final conversationId = item.conversationId;
    if (conversationId != null) {
      unawaited(
        router.push(
          '/circles/${widget.circleId}/channels/$conversationId',
          extra: item.channelName,
        ),
      );
    } else if (item.type == GuardItemType.note) {
      // A page of the knowledge base belongs to the circle, not a channel.
      unawaited(
        router.push(
          KnowledgeBaseScreen.pathFor(widget.circleId, pageId: item.itemId),
        ),
      );
    }
  }

  Future<void> _dismiss() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await ref.read(guard2RepositoryProvider).dismiss(widget.item.id);
      ref.invalidate(guardItemReviewsProvider(widget.circleId));
      ref.invalidate(guardItemCountProvider(widget.circleId));
      ref.invalidate(messageReviewCountProvider(widget.circleId));
      messenger?.showSnackBar(SnackBar(content: Text(tr('Card dismissed.'))));
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
      }
      ref.invalidate(guardItemReviewsProvider(widget.circleId));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr("Couldn't update this card. It may already be reviewed."),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final item = widget.item;
    final channel = item.channelName;
    final when = formatAuditTime(
      item.flaggedAt,
      now: (widget.now ?? DateTime.now)(),
    );
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: item.actorName,
                size: 40,
                image: item.actorAvatarUrl == null
                    ? null
                    : NetworkImage(item.actorAvatarUrl!),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.actorName,
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
                key: const ValueKey('review-item-type'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.pill),
                ),
                child: Text(
                  item.type.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('review-item-body'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    height: 1.4,
                  ),
                ),
                if (item.detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: c.dangerText),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  key: const ValueKey('review-item-verdict'),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: item.verdict.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.dangerText,
                        ),
                      ),
                      if (item.localizedReason case final reason?
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
                  key: const ValueKey('review-item-open'),
                  label: tr('Open'),
                  variant: WeCordButtonVariant.secondary,
                  icon: Icons.open_in_new_rounded,
                  onPressed: _busy ? null : _open,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('review-item-dismiss'),
                  label: tr('Dismiss'),
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_dismiss()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
