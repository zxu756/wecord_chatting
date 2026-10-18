import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/reports/report_message_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// "Report" in the message menu (between Remove embed, 1600, and Delete,
/// 1700). Not on your own messages, deleted ones, system notices or messages
/// still being sent: nothing to report there.
final reportMessageAction = MessageActionContribution(
  id: 'report',
  order: 1650,
  build: (ctx) {
    final message = ctx.message;
    if (ctx.isCurrentUser ||
        ctx.isRecalled ||
        ctx.isPending ||
        message.type == MessageType.system) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-report'),
        icon: Icons.flag_outlined,
        label: tr('Report'),
        destructive: true,
        onSelected: () => unawaited(
          showReportMessageSheet(
            ctx.context,
            message: message,
            senderName: _senderName(message),
            circleId: ctx.circleId,
          ).then((sent) {
            if (sent == true && ctx.context.mounted) {
              ScaffoldMessenger.maybeOf(ctx.context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      tr(
                        'Report sent. Thank you for helping keep WeCord safe.',
                      ),
                    ),
                  ),
                );
            }
          }),
        ),
      ),
    ];
  },
);

String _senderName(ChatMessage message) {
  final nickname = message.senderNickname?.trim() ?? '';
  if (nickname.isNotEmpty) {
    return nickname;
  }
  final webhook = message.webhookName?.trim() ?? '';
  if (webhook.isNotEmpty) {
    return webhook;
  }
  return message.sender?.displayLabel ?? tr('the sender');
}
