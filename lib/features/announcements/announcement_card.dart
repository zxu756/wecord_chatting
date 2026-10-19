import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_providers.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// An official notice in Notifications: the "WeCord team" name and an
/// Official tag, the title and the text in the language of the app, how long
/// ago. Tapping opens the whole text and marks the notice read; the cross
/// takes it off the list. It is a card, not a chat: nobody can reply to it.
class AnnouncementCard extends ConsumerStatefulWidget {
  const AnnouncementCard({required this.announcement, this.now, super.key});

  final Announcement announcement;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<AnnouncementCard> {
  var _expanded = false;
  var _busy = false;

  Future<void> _toggle() async {
    final notice = widget.announcement;
    setState(() => _expanded = !_expanded);
    if (!notice.read) {
      try {
        await ref.read(announcementsRepositoryProvider).markRead(notice.id);
        ref.invalidate(announcementsProvider);
      } on Object {
        // Reading it still works; it stays unread until it can be saved.
      }
    }
  }

  Future<void> _dismiss() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .dismiss(widget.announcement.id);
      ref.invalidate(announcementsProvider);
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Something went wrong. Try again.'))),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final notice = widget.announcement;
    final chinese = AppStrings.isChinese;
    final title = notice.title(chinese: chinese);
    final body = notice.body(chinese: chinese);
    final age = spokenAge(notice.publishedAt, now: widget.now?.call());
    return InboxCardShell(
      key: ValueKey('inbox-announcement-${notice.id}'),
      highlighted: !notice.read,
      onPressed: body.isEmpty ? null : () => unawaited(_toggle()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsIconTile(
            icon: Icons.campaign_outlined,
            tone: SettingsTone.accent,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Wraps instead of overflowing at the largest text size.
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tr('WeCord team'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                    _OfficialTag(),
                    Text(
                      age,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.subtle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: notice.read ? FontWeight.w600 : FontWeight.w800,
                    height: 1.3,
                    color: c.ink,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          WeCordIconButton(
            key: ValueKey('inbox-announcement-dismiss-${notice.id}'),
            icon: Icons.close_rounded,
            tooltip: tr('Dismiss'),
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 18,
            onPressed: _busy ? null : () => unawaited(_dismiss()),
          ),
        ],
      ),
    );
  }
}

class _OfficialTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          tr('Official'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.accentText,
          ),
        ),
      ),
    );
  }
}
