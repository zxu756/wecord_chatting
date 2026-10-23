// How check-ins plug into the chat page: the "Check-in" entry of the
// composer's "+" menu (registered in composer_menu_registrations.dart). The
// card itself is drawn by CheckInCardView; message_content.dart shows it for a
// message whose attachment is {kind: 'check_in'}, as it does for chains and
// forms.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart'
    show chatThreadProvider;
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/check_in/check_in_create_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Daily check-in" in the "+" menu, between Form (450) and Contact card (500). Not
/// for direct chats, like chains and forms.
final checkInComposerEntry = ComposerMenuContribution(
  id: 'check-in',
  order: 460,
  build: (ctx) => ctx.isDirect
      ? null
      : GlassMenuEntry(
          key: const ValueKey('composer-check-in-entry'),
          icon: Icons.event_available_outlined,
          label: tr('Daily check-in'),
          onSelected: () =>
              unawaited(_openCreate(ctx.context, ctx.conversationId, ctx)),
        ),
);

Future<void> _openCreate(
  BuildContext context,
  String conversationId,
  ComposerMenuContext ctx,
) async {
  final container = ctx.container;
  final posted = await showCheckInCreate(
    context,
    conversationId: conversationId,
  );
  if (posted == true) {
    // The card is a message: read the chat again so it shows at once.
    unawaited(
      container.read(chatThreadProvider(conversationId).notifier).refresh(),
    );
  }
}
