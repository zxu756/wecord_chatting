import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/urgent/urgent_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// "Urgent" in the message menu, between Forward (300) and Translate (400):
/// the user's own messages that have somebody to be urgent for, which are not
/// deleted, still being sent, held for review or system notices. The note to
/// yourself has no one else. In a circle channel it is left out as well: the
/// people there are too many to pick from, and a channel is no place to ring
/// someone's phone.
final urgentMessageAction = MessageActionContribution(
  id: 'urgent',
  order: 350,
  build: (ctx) {
    final message = ctx.message;
    if (!ctx.isCurrentUser ||
        ctx.isRecalled ||
        ctx.isPending ||
        ctx.circleId != null ||
        message.type == MessageType.system ||
        message.reviewState != null ||
        message.webhookName != null) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-action-urgent'),
        icon: Icons.priority_high_rounded,
        label: tr('Urgent'),
        onSelected: () => unawaited(showUrgentSheet(ctx.context, message)),
      ),
    ];
  },
);
