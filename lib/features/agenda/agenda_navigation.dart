import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/later/later_cards.dart' show openMessage;
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/shared/models/conversation.dart';

/// Opens what [item] is about: the chat of an event or a scheduled message,
/// the message of a reminder, the task in its list, a circle's event.
void openAgendaItem(BuildContext context, WidgetRef ref, AgendaItem item) {
  final conversationId = item.conversationId;
  final conversation = conversationId == null
      ? null
      : (ref.read(conversationsProvider).value ?? const <ConversationSummary>[])
            .where((candidate) => candidate.id == conversationId)
            .firstOrNull;
  switch (item.kind) {
    case AgendaKind.circleEvent:
      final circleId = item.circleId;
      if (circleId != null) {
        openPage(
          context,
          CircleEventsScreen.pathFor(circleId, eventId: item.targetId),
        );
      }
    case AgendaKind.task:
      if (conversationId != null) {
        openWorkspace(
          context,
          conversationId: conversationId,
          tab: WorkspaceTab.lists,
          listId: item.parentId,
          itemId: item.targetId,
          title: item.placeName,
        );
      }
    case AgendaKind.reminder:
      if (conversationId != null) {
        openMessage(
          context,
          ref,
          conversationId: conversationId,
          messageId: item.parentId,
          conversation: conversation,
        );
      }
    case AgendaKind.chatEvent || AgendaKind.scheduledMessage:
      if (conversationId != null) {
        openMessage(
          context,
          ref,
          conversationId: conversationId,
          conversation: conversation,
        );
      }
  }
}
