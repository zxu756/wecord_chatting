import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/models/group.dart';

/// Re-runs a provider when [changes] fires, at most every 300 ms.
void _invalidateOnChanges(Ref ref, Stream<void> changes) {
  Timer? pending;
  final subscription = changes.listen((_) {
    pending ??= Timer(const Duration(milliseconds: 300), () {
      pending = null;
      ref.invalidateSelf();
    });
  }, onError: (Object _) {});
  ref.onDispose(() {
    pending?.cancel();
    unawaited(subscription.cancel());
  });
}

/// Counts and the pinned note of a conversation. Providers fail (and the
/// UI shows nothing) where there is no backend.
final conversationWorkspaceProvider = FutureProvider.autoDispose
    .family<ConversationWorkspace, String>((ref, conversationId) {
      final notes = ref.watch(notesRepositoryProvider);
      _invalidateOnChanges(ref, notes.listChanges(conversationId));
      return notes.getWorkspace(conversationId);
    });

/// The notes of a conversation, pinned first.
final notesListProvider = FutureProvider.autoDispose
    .family<List<NoteSummary>, String>((ref, conversationId) {
      final notes = ref.watch(notesRepositoryProvider);
      _invalidateOnChanges(ref, notes.listChanges(conversationId));
      return notes.listNotes(conversationId);
    });

/// The task lists of a conversation, with counts.
final taskListsProvider = FutureProvider.autoDispose
    .family<List<TaskListSummary>, String>((ref, conversationId) {
      final lists = ref.watch(listsRepositoryProvider);
      _invalidateOnChanges(ref, lists.conversationChanges(conversationId));
      return lists.listLists(conversationId);
    });

/// The tasks made from messages of a conversation, by message id.
final messageTasksProvider = FutureProvider.autoDispose
    .family<Map<String, MessageTask>, String>((ref, conversationId) async {
      final lists = ref.watch(listsRepositoryProvider);
      _invalidateOnChanges(ref, lists.conversationChanges(conversationId));
      final tasks = await lists.messageTasks(conversationId);
      return {for (final task in tasks) task.messageId: task};
    });

/// The people of a conversation, for mentions and assignments.
final conversationMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>((ref, conversationId) async {
      final detail = await ref.watch(
        groupDetailProvider(conversationId).future,
      );
      return detail.members;
    });

/// Notes found by title, for the quick switcher.
final noteSearchProvider = FutureProvider.autoDispose
    .family<List<NoteSearchHit>, String>((ref, query) async {
      final text = query.trim();
      if (text.isEmpty) {
        return const [];
      }
      return ref.watch(notesRepositoryProvider).searchNotes(text);
    });

/// Assignments and due reminders for the notifications page.
final taskNotificationsProvider =
    FutureProvider.autoDispose<List<TaskNotification>>((ref) {
      final lists = ref.watch(listsRepositoryProvider);
      _invalidateOnChanges(ref, lists.notificationChanges());
      return lists.notifications();
    });
