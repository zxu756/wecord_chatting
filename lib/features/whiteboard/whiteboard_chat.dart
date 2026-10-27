// How whiteboards plug into the chat page: the "Whiteboard" entry of the
// composer's "+" menu (registered in composer_menu_registrations.dart), which
// opens the chat's list of boards.
import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Whiteboard" in the "+" menu, after Send GIF (1300): the menu scrolls, and
/// the entries people use most (stickers, GIFs) keep their places.
final whiteboardComposerEntry = ComposerMenuContribution(
  id: 'whiteboard',
  order: 1400,
  build: (ctx) => GlassMenuEntry(
    key: const ValueKey('composer-whiteboard-entry'),
    icon: Icons.draw_outlined,
    label: tr('Whiteboard'),
    onSelected: () => openWhiteboards(ctx.context, ctx.conversationId),
  ),
);
