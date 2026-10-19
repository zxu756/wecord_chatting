import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/urgent/urgent_banner.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The cards of Notifications → "To confirm": an urgent message nobody has
/// confirmed, and a group announcement that asks for a confirmation. Both are
/// red or accent "needs you" cards that go away when confirmed.

/// An urgent message waiting for a confirmation.
class UrgentInboxCard extends ConsumerStatefulWidget {
  const UrgentInboxCard({
    required this.urgent,
    required this.place,
    required this.onOpen,
    super.key,
  });

  final PendingUrgent urgent;

  /// The group's or chat's name.
  final String? place;
  final VoidCallback onOpen;

  @override
  ConsumerState<UrgentInboxCard> createState() => _UrgentInboxCardState();
}

class _UrgentInboxCardState extends ConsumerState<UrgentInboxCard> {
  var _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await confirmUrgent(ref, widget.urgent);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final urgent = widget.urgent;
    final time = describeWhen(
      MaterialLocalizations.of(context),
      urgent.createdAt.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final name = urgent.senderName.isEmpty ? tr('Someone') : urgent.senderName;
    return LaterCard(
      key: ValueKey('urgent-card-${urgent.messageId}'),
      highlighted: true,
      onPressed: widget.onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: urgent.senderAvatarUrl,
            badge: LaterAvatarBadge(
              color: c.danger,
              icon: Icons.priority_high_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        tr('{name} marked a message urgent', {'name': name}),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: c.dangerText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.place case final place? when place.isNotEmpty)
                  Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                const SizedBox(height: 8),
                LaterMessagePreview(
                  available: true,
                  text: laterPreview(
                    conversationId: urgent.conversationId,
                    body: urgent.body,
                    type: urgent.type,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    WeCordButton(
                      key: ValueKey('urgent-card-confirm-${urgent.messageId}'),
                      label: tr('Got it'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.danger,
                      loading: _busy,
                      onPressed: _busy ? null : () => unawaited(_confirm()),
                    ),
                    WeCordButton(
                      key: ValueKey('urgent-card-open-${urgent.messageId}'),
                      label: tr('Jump'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.secondary,
                      onPressed: widget.onOpen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A group announcement that waits for the current user's confirmation.
class AnnouncementAckCard extends ConsumerStatefulWidget {
  const AnnouncementAckCard({
    required this.pending,
    required this.onOpen,
    super.key,
  });

  final PendingAnnouncementAck pending;
  final VoidCallback onOpen;

  @override
  ConsumerState<AnnouncementAckCard> createState() =>
      _AnnouncementAckCardState();
}

class _AnnouncementAckCardState extends ConsumerState<AnnouncementAckCard> {
  var _busy = false;

  Future<void> _confirm() async {
    final id = widget.pending.conversationId;
    setState(() => _busy = true);
    try {
      await ref.read(urgentRepositoryProvider).acknowledgeAnnouncement(id);
      ref
        ..invalidate(pendingAnnouncementAcksProvider)
        ..invalidate(announcementAckStateProvider(id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Something went wrong. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final pending = widget.pending;
    final title = pending.title.isEmpty ? tr('Group') : pending.title;
    return LaterCard(
      key: ValueKey('announcement-ack-card-${pending.conversationId}'),
      highlighted: true,
      onPressed: widget.onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: pending.askedByName ?? title,
            avatarUrl: pending.askedByAvatarUrl,
            badge: LaterAvatarBadge(color: c.danger, icon: Icons.campaign),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('{group} needs you to confirm its announcement', {
                    'group': title,
                  }),
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: c.dangerText,
                  ),
                ),
                const SizedBox(height: 8),
                LaterMessagePreview(
                  available: true,
                  text: pending.announcement.replaceAll(RegExp(r'\s+'), ' '),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    WeCordButton(
                      key: ValueKey(
                        'announcement-ack-confirm-${pending.conversationId}',
                      ),
                      label: tr('Confirm'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.danger,
                      loading: _busy,
                      onPressed: _busy ? null : () => unawaited(_confirm()),
                    ),
                    WeCordButton(
                      key: ValueKey(
                        'announcement-ack-open-${pending.conversationId}',
                      ),
                      label: tr('Open group'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.secondary,
                      onPressed: widget.onOpen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
