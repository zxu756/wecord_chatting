import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notes/note_comments_panel.dart'
    show noteTimeText;
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Mentions of me in comments on notes, and replies to my comments.
final noteCommentNotificationsProvider =
    FutureProvider.autoDispose<List<NoteCommentNotification>>(
      (ref) => ref.watch(notes2RepositoryProvider).listCommentNotifications(),
    );

/// How many of them are unread, for the Notifications badge.
final noteCommentNotificationsUnreadProvider = Provider.autoDispose<int>(
  (ref) =>
      ref
          .watch(noteCommentNotificationsProvider)
          .value
          ?.where((notification) => notification.isUnread)
          .length ??
      0,
);

/// A mention or a reply in the comments of a note, in the notifications:
/// who, what they wrote and a way to open the note. Like the task cards: the
/// ring is the accent color while it is unread, never red.
class NoteCommentNotificationCard extends ConsumerWidget {
  const NoteCommentNotificationCard({
    required this.notification,
    this.conversationName,
    super.key,
  });

  final NoteCommentNotification notification;

  /// "#channel · Circle" or a group's name; null for direct messages.
  final String? conversationName;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (notification.isUnread) {
      try {
        await ref.read(notes2RepositoryProvider).markCommentNotificationsRead([
          notification.id,
        ]);
        ref.invalidate(noteCommentNotificationsProvider);
      } on Object {
        // Opening still works.
      }
    }
    if (!context.mounted) {
      return;
    }
    openWorkspace(
      context,
      conversationId: notification.conversationId,
      tab: WorkspaceTab.notes,
      noteId: notification.noteId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final actor = notification.actorName;
    final headline = notification.isReply
        ? tr('replied to your comment')
        : tr('mentioned you in a comment');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    return WeCordPressable(
      key: ValueKey('inbox-note-comment-${notification.id}'),
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
                name: actor,
                avatarUrl: notification.actorAvatarUrl,
                badge: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.panel, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.mode_comment_outlined,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: actor,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: ' $headline'),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.4,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (notification.isUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '${notification.noteIcon} '
                      '${notification.noteTitle.isEmpty ? tr('Untitled') : notification.noteTitle}'
                      '${conversationName == null || conversationName!.isEmpty ? '' : ' · $conversationName'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                      ),
                      child: Text(
                        notification.snippet,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        WeCordButton(
                          key: ValueKey(
                            'inbox-note-comment-open-${notification.id}',
                          ),
                          label: tr('Open note'),
                          size: WeCordButtonSize.small,
                          variant: WeCordButtonVariant.secondary,
                          onPressed: () => unawaited(_open(context, ref)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              noteTimeText(context, notification.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
