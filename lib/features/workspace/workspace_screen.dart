import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A conversation's notes and lists as a page: full screen on phones, in
/// the content area on wide layouts (when it was opened as a page rather
/// than as the panel beside the chat).
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({
    required this.conversationId,
    this.title,
    this.tab = WorkspaceTab.notes,
    this.noteId,
    this.listId,
    this.itemId,
    super.key,
  });

  final String conversationId;
  final String? title;
  final WorkspaceTab tab;
  final String? noteId;
  final String? listId;
  final String? itemId;

  /// Reads the page's query (`tab`, `note`, `list`, `item`).
  static WorkspaceTab tabFrom(Map<String, String> query) {
    return query['tab'] == WorkspaceTab.lists.name
        ? WorkspaceTab.lists
        : WorkspaceTab.notes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.tokens.colors.panel,
      body: WorkspacePanel(
        // Opening something else (a link from a card) starts it afresh.
        key: ValueKey('$conversationId-$noteId-$listId-$itemId-${tab.name}'),
        conversationId: conversationId,
        title: title,
        initialTab: tab,
        initialNoteId: noteId,
        initialListId: listId,
        initialItemId: itemId,
        pageMode: true,
        onClose: () {
          final router = GoRouter.of(context);
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/chats/$conversationId', extra: title);
          }
        },
      ),
    );
  }
}
