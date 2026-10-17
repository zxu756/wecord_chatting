import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// The two halves of a conversation's workspace.
enum WorkspaceTab { notes, lists }

/// Asks the open chat of [conversationId] to show its workspace panel (on
/// wide layouts, where the panel sits beside the chat).
class WorkspaceRequest {
  const WorkspaceRequest({
    required this.conversationId,
    required this.tab,
    this.noteId,
    this.listId,
    this.itemId,
  });

  final String conversationId;
  final WorkspaceTab tab;
  final String? noteId;
  final String? listId;
  final String? itemId;
}

final workspaceRequestProvider = StateProvider<WorkspaceRequest?>(
  (ref) => null,
);

/// The page of a conversation's notes and lists, optionally with a note, a
/// list or one of its tasks open.
String workspaceLocation(
  String conversationId, {
  WorkspaceTab tab = WorkspaceTab.notes,
  String? noteId,
  String? listId,
  String? itemId,
}) {
  return Uri(
    path: '/chats/$conversationId/workspace',
    queryParameters: {
      'tab': tab.name,
      'note': ?noteId,
      'list': ?listId,
      'item': ?itemId,
    },
  ).toString();
}

/// Opens a conversation's workspace. Beside the open chat on wide layouts
/// (the right-hand panel), otherwise as a page: pushed over the chat on
/// phones, in place of it on wide layouts.
void openWorkspace(
  BuildContext context, {
  required String conversationId,
  WorkspaceTab tab = WorkspaceTab.notes,
  String? noteId,
  String? listId,
  String? itemId,
  String? title,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final wide = isWideLayout(MediaQuery.sizeOf(context).width);
  if (wide && container.read(activeConversationIdProvider) == conversationId) {
    container.read(workspaceRequestProvider.notifier).state = WorkspaceRequest(
      conversationId: conversationId,
      tab: tab,
      noteId: noteId,
      listId: listId,
      itemId: itemId,
    );
    return;
  }
  final location = workspaceLocation(
    conversationId,
    tab: tab,
    noteId: noteId,
    listId: listId,
    itemId: itemId,
  );
  if (wide) {
    context.go(location, extra: title);
  } else {
    context.push(location, extra: title);
  }
}
