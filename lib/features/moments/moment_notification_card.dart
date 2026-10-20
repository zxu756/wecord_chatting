import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A like, comment or reply on the person's Moments, as a card in
/// Notifications like the others: who, what they did, the words, and the
/// first picture of the Moment. Opens the Moment.
class MomentNotificationCard extends ConsumerWidget {
  const MomentNotificationCard({required this.notification, super.key});

  final MomentNotification notification;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (notification.isUnread) {
      try {
        await ref.read(momentsRepositoryProvider).markNotificationsRead([
          notification.id,
        ]);
        ref.invalidate(momentNotificationsProvider);
      } on Object {
        // Opening still works.
      }
    }
    if (context.mounted) {
      unawaited(context.push('${MomentsScreen.path}/${notification.postId}'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final kind = notification.kind;
    final headline = switch (kind) {
      MomentNotificationKind.like => tr('liked your Moment'),
      MomentNotificationKind.comment => tr('commented on your Moment'),
      MomentNotificationKind.reply => tr('replied to your comment'),
      MomentNotificationKind.mention => tr('reminded you to read their Moment'),
    };
    final (badgeColor, badgeIcon) = switch (kind) {
      MomentNotificationKind.like => (c.accent, Icons.favorite_rounded),
      MomentNotificationKind.comment => (c.success, Icons.chat_bubble_rounded),
      MomentNotificationKind.reply => (c.warning, Icons.reply_rounded),
      MomentNotificationKind.mention => (
        c.accent,
        Icons.alternate_email_rounded,
      ),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    // A like has no words and a reminder carries the post's own start, which
    // the card already shows; a comment that is only a picture says so.
    final quote =
        kind == MomentNotificationKind.like ||
            kind == MomentNotificationKind.mention
        ? ''
        : notification.snippet.isEmpty && notification.hasImage
        ? tr('[Picture]')
        : notification.snippet;
    final age = spokenAge(notification.createdAt);
    return WeCordPressable(
      key: ValueKey('inbox-moment-${notification.id}'),
      onPressed: () => unawaited(_open(context, ref)),
      shape: shape,
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: notification.isUnread
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                name: notification.actorName,
                avatarUrl: notification.actorAvatarUrl,
                badge: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.panel, width: 2.5),
                  ),
                  child: Icon(badgeIcon, size: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: notification.actorName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' '),
                          TextSpan(text: headline),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: c.ink,
                      ),
                    ),
                    if (quote.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.well,
                          borderRadius: BorderRadius.circular(WeCordRadii.md),
                        ),
                        child: Text(
                          quote,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      [age, tr('Moments')].join(' · '),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (notification.postThumb != null)
                SizedBox.square(
                  dimension: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                    child: MomentImage(path: notification.postThumb!),
                  ),
                )
              else if (notification.postExcerpt.isNotEmpty)
                SizedBox(
                  width: 64,
                  child: Text(
                    notification.postExcerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.3, color: c.muted),
                  ),
                ),
              if (notification.isUnread)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
