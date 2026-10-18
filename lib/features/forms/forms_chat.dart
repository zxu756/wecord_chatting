// How forms plug into the chat page: the "Form" entry of the composer's "+"
// menu (registered in composer_menu_registrations.dart). The card itself is
// drawn by FormCardView; message_content.dart shows it for a message whose
// attachment is {kind: 'form'}, as it does for chains.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart'
    show chatThreadProvider;
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/forms/form_builder_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Form" in the "+" menu, between Chain (400) and Contact card (500). Not
/// for direct chats, like chains.
final formComposerEntry = ComposerMenuContribution(
  id: 'form',
  order: 450,
  build: (ctx) => ctx.isDirect
      ? null
      : GlassMenuEntry(
          key: const ValueKey('composer-form-entry'),
          icon: Icons.assignment_outlined,
          label: tr('Form'),
          onSelected: () =>
              unawaited(_openFormBuilder(ctx.context, ctx.conversationId, ctx)),
        ),
);

Future<void> _openFormBuilder(
  BuildContext context,
  String conversationId,
  ComposerMenuContext ctx,
) async {
  final container = ctx.container;
  final posted = await showFormBuilder(context, conversationId: conversationId);
  if (posted == true) {
    // The card is a message: read the chat again so it shows at once.
    unawaited(
      container.read(chatThreadProvider(conversationId).notifier).refresh(),
    );
  }
}
