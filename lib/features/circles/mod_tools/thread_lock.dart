import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Lock thread" / "Unlock thread" in the More menu of a circle thread (or
/// forum post), for members who manage messages in the channel. A locked
/// thread can be read and reacted to, but only moderators can post in it.
final threadLockHeaderAction = HeaderActionContribution(
  id: 'lock-thread',
  order: 1150,
  build: (ctx) {
    if (ctx.threadId == null) {
      return null;
    }
    final lock = ctx.ref.watch(threadLockProvider(ctx.conversationId)).value;
    if (lock == null || !lock.canLock) {
      return null;
    }
    return ChatThreadAction(
      id: 'lock-thread',
      tooltip: switch ((lock.locked, ctx.forumPost)) {
        (true, true) => tr('Unlock post'),
        (true, false) => tr('Unlock thread'),
        (false, true) => tr('Lock post'),
        (false, false) => tr('Lock thread'),
      },
      icon: lock.locked ? Icons.lock_open_outlined : Icons.lock_outline,
      onPressed: () =>
          unawaited(_setLocked(ctx, lock.threadId, locked: !lock.locked)),
    );
  },
);

Future<void> _setLocked(
  HeaderActionContext ctx,
  String threadId, {
  required bool locked,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(ctx.context);
  try {
    await ctx.ref
        .read(modToolsRepositoryProvider)
        .setThreadLocked(threadId, locked: locked);
    ctx.ref.invalidate(threadLockProvider(ctx.conversationId));
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          locked
              ? tr('Locked. Only moderators can reply.')
              : tr('Unlocked. Everyone can reply again.'),
        ),
      ),
    );
  } on Object {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          locked
              ? tr('Could not lock this. Try again.')
              : tr('Could not unlock this. Try again.'),
        ),
      ),
    );
  }
}
