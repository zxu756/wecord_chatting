// How "Help me reply" (roadmap F6) plugs into the chat page's composer menu
// (see "Chat page extension points" in docs/design/wecord-design-language.md).
//
// On a phone the sparkle button next to the message box only shows once there
// is a draft, so the "+" menu carries the way in for an empty box. Wider
// screens always have the sparkle button, whose sheet lists "Help me reply"
// first. Both end in the same sheet (draft_reply_sheet.dart), which fills the
// message box and never sends.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Help me reply" in the composer's "+" menu on phones, after Ask WeCord AI
/// (1350).
final draftReplyComposerEntry = ComposerMenuContribution(
  id: 'ai-draft-reply',
  order: 1360,
  build: (ctx) {
    final open = ctx.actions.draftReply;
    if (!ctx.compact ||
        open == null ||
        !ctx.container.read(aiAvailableProvider(null))) {
      return null;
    }
    return GlassMenuEntry(
      key: const ValueKey('composer-draft-reply-entry'),
      icon: Icons.reply_all_rounded,
      label: tr('Help me reply'),
      onSelected: () => unawaited(open()),
    );
  },
);
