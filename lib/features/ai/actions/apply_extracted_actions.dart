import 'dart:async';

import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What happened to one confirmed item.
sealed class ApplyOutcome {
  const ApplyOutcome();
}

/// Made a task (`upsert_task_item`) in the list [listId].
class TaskCreated extends ApplyOutcome {
  const TaskCreated({required this.listId, required this.itemId});

  final String listId;
  final String itemId;
}

/// Made a chat event (`create_chat_event`).
class EventCreated extends ApplyOutcome {
  const EventCreated(this.eventId);

  final String eventId;
}

/// The server refused, or the network failed.
class ApplyFailed extends ApplyOutcome {
  const ApplyFailed(this.error);

  final Object error;
}

/// The end of the day a date-only due date falls on, as the task sheet's
/// own date picker stores it.
DateTime endOfDueDay(DateTime day) =>
    DateTime(day.year, day.month, day.day, 23, 59, 59);

/// Creates what the person confirmed, one by one, reusing the existing
/// repositories: a task goes through `upsert_task_item` into the
/// conversation's first list they can edit (a list called "Tasks" is made when
/// there is none), an event through `create_chat_event`. An item that cannot
/// be made does not stop the rest; its outcome is an [ApplyFailed]. The
/// result lines up with [actions].
///
/// [newId] makes the client id of a task, so asking again after a lost answer
/// never duplicates it.
Future<List<ApplyOutcome>> applyExtractedActions({
  required ListsRepository lists,
  required ChatEventsRepository events,
  required String conversationId,
  required List<ExtractedAction> actions,
  required String Function() newId,
  List<String>? taskIds,
}) async {
  final outcomes = <ApplyOutcome>[];
  String? listId;
  Object? listError;

  Future<String> taskList() async {
    if (listError != null) {
      throw listError!;
    }
    if (listId != null) {
      return listId!;
    }
    try {
      final summaries = await lists.listLists(conversationId);
      final editable = summaries.where((list) => list.canEdit).firstOrNull;
      listId =
          editable?.id ??
          (await lists.createList(conversationId, title: tr('Tasks'))).id;
      return listId!;
    } on Object catch (error) {
      listError = error;
      rethrow;
    }
  }

  for (final (index, action) in actions.indexed) {
    try {
      if (action.kind == ExtractedKind.event && action.canBeEvent) {
        final event = await events.createEvent(
          conversationId,
          ChatEventDraft(title: action.title, startsAt: action.due!),
        );
        outcomes.add(EventCreated(event.id));
        continue;
      }
      final target = await taskList();
      final due = action.due;
      final item = await lists.upsertItem(target, {
        'id': taskIds != null && index < taskIds.length
            ? taskIds[index]
            : newId(),
        'title': action.title,
        if (action.assignees.isNotEmpty) 'assignees': action.assignees,
        if (due != null) ...{
          'due_at': (action.dueHasTime ? due : endOfDueDay(due))
              .toUtc()
              .toIso8601String(),
          'due_has_time': action.dueHasTime,
        },
        if (action.sourceMessageId != null)
          'source_message_id': action.sourceMessageId,
      });
      if (action.assignees.isNotEmpty) {
        unawaited(lists.notifyAssignments(item.id));
      }
      outcomes.add(TaskCreated(listId: target, itemId: item.id));
    } on Object catch (error) {
      outcomes.add(ApplyFailed(error));
    }
  }
  return outcomes;
}
