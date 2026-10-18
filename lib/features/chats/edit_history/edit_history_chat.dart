// How edit history plugs into the chat page (see "Chat page extension
// points" in docs/design/wecord-design-language.md):
//
//  * the "edited" mark after a message's text is the built-in bubble footer
//    entry `edited` (thread/registry/bubble_footer_builtin.dart); it is
//    tappable through [openEditHistoryFor] and opens the history sheet;
//  * [editHistoryAction] adds "Edit history" to the message menu, which is
//    also how screen readers and keyboards reach it (a message reads as one
//    node there), registered in message_actions_registrations.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/edit_history/edit_history_sheet.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// Whether [message] has an edit history to show: it was edited and is
/// still there (deleting a message deletes its history).
bool hasEditHistory(ChatMessage message) =>
    message.editedAt != null && message.recalledAt == null;

/// Opens the history of [message]; what the "edited" mark does when tapped.
void openEditHistoryFor(BuildContext context, ChatMessage message) {
  unawaited(showEditHistory(context, message));
}

/// "Edit history" in the message menu, between Edit (600) and Create task
/// (700).
final editHistoryAction = MessageActionContribution(
  id: 'edit-history',
  order: 650,
  build: (ctx) => [
    if (hasEditHistory(ctx.message) && !ctx.isPending)
      MessageAction(
        key: const ValueKey('message-action-edit-history'),
        icon: Icons.history,
        label: tr('Edit history'),
        onSelected: () => openEditHistoryFor(ctx.context, ctx.message),
      ),
  ],
);
