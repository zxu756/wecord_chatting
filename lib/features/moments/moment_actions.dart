import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Shows a short failure message.
void momentsFailureSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

/// Likes or unlikes [post].
Future<void> toggleMomentLike(
  BuildContext context,
  WidgetRef ref,
  MomentPost post,
) async {
  try {
    await ref
        .read(momentPostsStoreProvider.notifier)
        .setLiked(post.id, liked: !post.likedByMe);
  } on Object {
    if (context.mounted) {
      momentsFailureSnack(context, tr('Could not update the like. Try again.'));
    }
  }
}

/// Asks, then deletes the person's own Moment. True when it was deleted.
Future<bool> confirmDeleteMoment(
  BuildContext context,
  WidgetRef ref,
  MomentPost post,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Delete this Moment?')),
      content: Text(
        tr('Its photos, likes and comments are deleted for everyone.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          key: const ValueKey('moment-delete-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Delete')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }
  try {
    await ref.read(momentPostsStoreProvider.notifier).deletePost(post.id);
    return true;
  } on Object {
    if (context.mounted) {
      momentsFailureSnack(context, tr('Could not delete. Try again.'));
    }
    return false;
  }
}

/// The actions on a comment: reply to somebody else's, delete the person's
/// own, or, on the person's own Moment, anybody's.
Future<void> showMomentCommentMenu(
  BuildContext context,
  WidgetRef ref, {
  required MomentPost post,
  required MomentComment comment,
  required String? myUserId,
  required ValueChanged<MomentComment> onReply,
}) async {
  final mine = comment.userId == myUserId;
  final canDelete = mine || post.authorId == myUserId;
  if (mine && !canDelete) {
    return;
  }
  await showWeCordSheet<void>(
    context,
    title: comment.name,
    builder: (sheetContext, _) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SettingsGroup(
          color: sheetContext.tokens.colors.well,
          children: [
            if (!mine)
              SettingsRow(
                key: const ValueKey('comment-reply'),
                icon: Icons.reply_rounded,
                title: tr('Reply'),
                showChevron: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onReply(comment);
                },
              ),
            if (canDelete)
              SettingsRow(
                key: const ValueKey('comment-delete'),
                icon: Icons.delete_outline_rounded,
                title: tr('Delete comment'),
                destructive: true,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_deleteComment(context, ref, post, comment));
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _deleteComment(
  BuildContext context,
  WidgetRef ref,
  MomentPost post,
  MomentComment comment,
) async {
  try {
    await ref
        .read(momentPostsStoreProvider.notifier)
        .deleteComment(post.id, comment.id);
  } on Object {
    if (context.mounted) {
      momentsFailureSnack(context, tr('Could not delete. Try again.'));
    }
  }
}
