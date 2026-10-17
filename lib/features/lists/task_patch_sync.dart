import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_patch_store.dart';

/// Where task changes that could not be sent are kept between runs.
final taskPatchStoreProvider = Provider<TaskPatchStore>(
  (ref) => const SharedPreferencesTaskPatchStore(),
);

/// Sends the task changes that were left in a [TaskPatchStore] by a list
/// that was closed, or an app that was, before they got through.
///
/// A list that is open owns its own patches (its controller keeps them in
/// the store and sends them), so it is skipped. For the others each stored
/// patch goes to `upsert_task_item` as it is: the server applies it field by
/// field, so it never overwrites fields someone else changed since. What the
/// server refuses (the item was deleted, the list is no longer editable) is
/// dropped; what could not be tried because the server cannot be reached
/// stays for the next round.
class TaskPatchSync {
  const TaskPatchSync({
    required this.store,
    required this.repository,
    required this.userId,
    this.isOpen = TaskListController.isListOpen,
  });

  final TaskPatchStore store;
  final ListsRepository repository;
  final String userId;
  final bool Function(String listId) isOpen;

  /// Tries every stored patch once. Returns how many are still waiting.
  Future<int> sweep() async {
    var waiting = 0;
    for (final listId in await store.listIds(userId)) {
      if (isOpen(listId)) {
        continue;
      }
      final draft = await store.load(userId, listId);
      if (draft == null) {
        continue;
      }
      final remaining = {...draft.patches};
      var reachable = true;
      for (final entry in draft.patches.entries) {
        final fields = {...entry.value, 'id': entry.key};
        try {
          await repository.upsertItem(listId, fields);
          remaining.remove(entry.key);
          final assignees = fields['assignees'];
          if (assignees is List && assignees.isNotEmpty) {
            unawaited(repository.notifyAssignments(entry.key));
          }
        } on Object catch (error) {
          if (isTaskPatchRefusal(error)) {
            remaining.remove(entry.key);
          } else {
            reachable = false;
            break;
          }
        }
      }
      // The list was opened meanwhile: its controller keeps the store from
      // now on.
      if (!isOpen(listId)) {
        await store.save(
          TaskListDraft(
            userId: userId,
            listId: listId,
            patches: remaining,
            created: {
              for (final entry in draft.created.entries)
                if (remaining.containsKey(entry.key)) entry.key: entry.value,
            },
          ),
        );
      }
      waiting += remaining.length;
      if (!reachable) {
        // The other lists would only fail the same way; the next round
        // tries them.
        return waiting;
      }
    }
    return waiting;
  }
}

/// Retries stored task changes while the app runs: once at start, when the
/// device gets its connection back, when another account signs in, and every
/// minute for as long as something is still waiting. Watched by the offline
/// session guard.
final taskPatchSyncProvider = Provider<void>((ref) {
  Timer? retry;
  var running = false;
  var disposed = false;

  Future<void> sweep() async {
    if (running || disposed) {
      return;
    }
    running = true;
    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) {
        return;
      }
      final waiting = await TaskPatchSync(
        store: ref.read(taskPatchStoreProvider),
        repository: ref.read(listsRepositoryProvider),
        userId: userId,
      ).sweep();
      retry?.cancel();
      if (waiting > 0 && !disposed) {
        retry = Timer(const Duration(minutes: 1), () => unawaited(sweep()));
      }
    } on Object {
      // Storage or the backend is not there; the next trigger tries again.
    } finally {
      running = false;
    }
  }

  ref.onDispose(() {
    disposed = true;
    retry?.cancel();
  });
  ref.listen<AsyncValue<bool>>(deviceConnectivityProvider, (previous, next) {
    if (next.value == true && previous?.value == false) {
      unawaited(sweep());
    }
  });
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
    if (next.value != null && next.value?.id != previous?.value?.id) {
      unawaited(sweep());
    }
  });
  unawaited(sweep());
});
