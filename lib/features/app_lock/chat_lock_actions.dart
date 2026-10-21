import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/lock_prompts.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Lock chat" or "Unlock chat".
String chatLockLabel({required bool locked}) =>
    locked ? tr('Unlock chat') : tr('Lock chat');

/// Locks the chat, or unlocks it after the person proves who they are.
///
/// Locking needs a way to ask later: Face ID, Touch ID or the passcode, or
/// else a PIN, which the person makes first. The lock list is kept on the
/// server so that notifications hide the text on every device; when the
/// server cannot be reached nothing changes and the person is told.
Future<void> toggleChatLock(
  BuildContext context,
  WidgetRef ref,
  String conversationId,
) async {
  final chatLock = ref.read(chatLockProvider.notifier);
  final locked = ref.read(chatLockProvider).lockedIds.contains(conversationId);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (locked) {
      final ok = await verifyOwner(
        context,
        ref,
        reason: tr('Unlock this chat'),
      );
      if (!ok) {
        return;
      }
      await chatLock.unlock(conversationId);
      await tidyLockCredentials(ref);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Chat unlocked'))));
    } else {
      if (!await ensureLockReady(context, ref)) {
        return;
      }
      await chatLock.lock(conversationId);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Chat locked. It asks to be unlocked, and notifications hide it.',
            ),
          ),
        ),
      );
    }
  } on Object {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tr('Could not change the lock. Check your connection and try again.'),
        ),
      ),
    );
  }
}

/// Drops the PIN when nothing uses it any more: no chat is locked and the app
/// lock is off.
Future<void> tidyLockCredentials(WidgetRef ref) async {
  final app = ref.read(appLockProvider);
  final chats = ref.read(chatLockProvider);
  if (app.hasPin && !app.enabled && chats.lockedIds.isEmpty) {
    await ref.read(appLockProvider.notifier).removePin();
  }
}

/// "Lock chat" in the header's More menu of a direct chat or a group, after
/// Summarize (1200) and Auto-translate (1250).
final HeaderActionContribution chatLockHeaderAction = HeaderActionContribution(
  id: 'chat-lock',
  order: 1300,
  build: (ctx) {
    if (ctx.isNoteToSelf || !ctx.isDirectOrGroup) {
      return null;
    }
    final locked = ctx.ref.watch(
      chatLockProvider.select(
        (state) => state.lockedIds.contains(ctx.conversationId),
      ),
    );
    return ChatThreadAction(
      id: 'chat-lock',
      tooltip: chatLockLabel(locked: locked),
      icon: Icons.lock_outline_rounded,
      selectedIcon: Icons.lock_rounded,
      isSelected: locked,
      menuOnly: true,
      onPressed: () =>
          unawaited(toggleChatLock(ctx.context, ctx.ref, ctx.conversationId)),
    );
  },
);
