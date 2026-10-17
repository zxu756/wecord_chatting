import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_patch_store.dart';
import 'package:wecord/features/lists/task_patch_sync.dart';

import '../workspace/workspace_fakes.dart';

class _SignedIn implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'me');

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The background retry of kept task changes: at start, when the connection
/// returns, and while the server is out of reach.
void main() {
  late FakeListsRepository repository;
  late InMemoryTaskPatchStore store;
  late StreamController<bool> connectivity;
  late ProviderContainer container;

  setUp(() async {
    repository = FakeListsRepository();
    repository.lists['list-1'] = TaskList(
      id: 'list-1',
      conversationId: 'conv-1',
      title: 'Launch',
      icon: 'x',
      statuses: TaskStatus.defaults,
      canEdit: true,
      canManage: true,
    );
    repository.items['a'] = TaskItem(
      id: 'a',
      listId: 'list-1',
      title: 'Write copy',
      status: 'todo',
    );
    store = InMemoryTaskPatchStore();
    await store.save(
      const TaskListDraft(
        userId: 'me',
        listId: 'list-1',
        patches: {
          'a': {'status': 'done'},
        },
      ),
    );
    connectivity = StreamController<bool>();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SignedIn()),
        listsRepositoryProvider.overrideWithValue(repository),
        taskPatchStoreProvider.overrideWithValue(store),
        deviceConnectivityProvider.overrideWith((ref) => connectivity.stream),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await connectivity.close();
  });

  Future<void> pause() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  test('changes left from the last run are sent when the app starts', () async {
    container.listen(taskPatchSyncProvider, (previous, next) {});
    await pause();
    expect(repository.items['a']!.status, 'done');
    expect(store.entries, isEmpty);
  });

  test('and again when the connection comes back', () async {
    repository.failUpserts = true;
    container.listen(taskPatchSyncProvider, (previous, next) {});
    connectivity.add(true);
    await pause();
    expect(repository.items['a']!.status, 'todo');
    expect(store.entries, hasLength(1));

    // The device goes offline, then online again.
    connectivity.add(false);
    await pause();
    repository.failUpserts = false;
    connectivity.add(true);
    await pause();
    expect(repository.items['a']!.status, 'done');
    expect(store.entries, isEmpty);
  });
}
