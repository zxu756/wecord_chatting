import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_patch_store.dart';
import 'package:wecord/features/lists/task_patch_sync.dart';

import '../workspace/workspace_fakes.dart';

TaskItem item(
  String id,
  String title, {
  String status = 'todo',
  String pos = 'V',
  List<String> assignees = const [],
}) {
  return TaskItem(
    id: id,
    listId: 'list-1',
    title: title,
    status: status,
    pos: pos,
    assignees: assignees,
    createdAt: DateTime(2026, 10, 1),
    completedAt: status == 'done' ? DateTime(2026, 10, 2) : null,
  );
}

/// The state of a list as the server has it, and what a device that was
/// closed and opened again does with the kept changes.
void main() {
  late FakeListsRepository repository;
  late InMemoryTaskPatchStore store;
  late TaskList list;
  final controllers = <TaskListController>[];
  var ids = 0;

  setUp(() {
    repository = FakeListsRepository();
    store = InMemoryTaskPatchStore();
    list = TaskList(
      id: 'list-1',
      conversationId: 'conv-1',
      title: 'Launch',
      icon: 'x',
      statuses: TaskStatus.defaults,
      canEdit: true,
      canManage: true,
    );
    repository.lists['list-1'] = list;
    for (final i in [
      item('a', 'Write copy', pos: 'a'),
      item('b', 'Design', pos: 'b'),
      item('d', 'Ship', status: 'done', pos: 'a'),
    ]) {
      repository.items[i.id] = i;
    }
  });

  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });

  /// Opens the list the way the page does: the server's snapshot with the
  /// kept draft (null when there is none).
  Future<TaskListController> open({String userId = 'me'}) async {
    final controller = TaskListController(
      repository: repository,
      currentUserId: userId,
      newId: () => 'new-${ids++}',
      store: store,
      clock: () => DateTime(2026, 10, 17, 12),
      retryAfter: const Duration(milliseconds: 10),
    );
    controllers.add(controller);
    final draft = await store.load(userId, 'list-1');
    controller.load(await repository.getList('list-1'), draft: draft);
    return controller;
  }

  /// Closing the app: the controller goes away, memory with it. Only the
  /// store is left.
  void closeApp(TaskListController controller) {
    controller.dispose();
    controllers.remove(controller);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  test('an offline change is kept and sent after a restart', () async {
    final first = await open();
    repository.failUpserts = true;
    first.setDone('a', true);
    await first.flush();
    expect(first.isOffline, isTrue);
    expect(store.entries, hasLength(1));
    closeApp(first);
    await settle();

    // The app is opened again, with the connection back.
    repository.failUpserts = false;
    final second = await open();
    expect(second.itemById('a')!.status, 'done');
    expect(second.hasPending, isTrue);
    await settle();
    expect(repository.items['a']!.status, 'done');
    expect(second.hasPending, isFalse);
    expect(store.entries, isEmpty);
  });

  test('only the changed fields are sent after a restart', () async {
    final first = await open();
    repository.failUpserts = true;
    first.patchItem('a', {'priority': 3});
    await first.flush();
    closeApp(first);
    await settle();

    // Meanwhile someone else renamed it.
    repository.items['a'] = repository.items['a']!.copyWith(
      title: 'Write the copy',
    );
    repository.failUpserts = false;
    final second = await open();
    // The server's title shows, with the kept priority on top.
    expect(second.itemById('a')!.title, 'Write the copy');
    expect(second.itemById('a')!.priority, TaskPriority.high);
    await settle();
    expect(repository.upserts.single.keys.toSet(), {
      'id',
      'priority',
      'list_id',
    });
    expect(repository.items['a']!.title, 'Write the copy');
    expect(repository.items['a']!.priority, TaskPriority.high);
  });

  test('a task made offline comes back and is created', () async {
    final first = await open();
    repository.failUpserts = true;
    first.createItem(
      'Book venue',
      assignees: const ['you'],
      dueAt: DateTime.utc(2026, 10, 30, 10),
      dueHasTime: true,
      priority: TaskPriority.medium,
      details: 'Ask about parking',
    );
    first.patchItem('new-${ids - 1}', {'title': 'Book the venue'});
    await first.flush();
    closeApp(first);
    await settle();

    expect(repository.items.keys, isNot(contains('new-${ids - 1}')));
    repository.failUpserts = false;
    final second = await open();
    final restored = second.itemById('new-${ids - 1}')!;
    expect(restored.title, 'Book the venue');
    expect(restored.assignees, ['you']);
    expect(restored.dueHasTime, isTrue);
    expect(restored.priority, TaskPriority.medium);
    expect(restored.details, 'Ask about parking');
    expect(restored.createdBy, 'me');
    expect(second.itemsIn('todo').last.id, restored.id);
    await settle();
    final saved = repository.items[restored.id]!;
    expect(saved.title, 'Book the venue');
    expect(saved.assignees, ['you']);
    // The assignee is told once it is stored.
    expect(repository.pushed, [restored.id]);
    expect(store.entries, isEmpty);
  });

  test('a restored change for an item that was deleted is dropped', () async {
    final first = await open();
    repository.failUpserts = true;
    first.patchItem('b', {'title': 'Design the banner'});
    await first.flush();
    closeApp(first);
    await settle();

    repository.items['b'] = repository.items['b']!.copyWith(deleted: true);
    repository.failUpserts = false;
    final second = await open();
    expect(second.itemById('b'), isNull);
    expect(second.hasPending, isFalse);
    await settle();
    expect(repository.upserts, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('an item that is gone from the list is not made again', () async {
    final first = await open();
    repository.failUpserts = true;
    first.patchItem('b', {'title': 'Design the banner'});
    await first.flush();
    closeApp(first);
    await settle();

    repository.items.remove('b');
    repository.failUpserts = false;
    final second = await open();
    expect(second.itemById('b'), isNull);
    await settle();
    expect(repository.upserts, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('a refusal after a restart drops the change for good', () async {
    final first = await open();
    repository.failUpserts = true;
    first.setDone('a', true);
    await first.flush();
    closeApp(first);
    await settle();

    // The list stopped being editable for this person.
    repository.failUpserts = false;
    repository.refuseUpserts = true;
    final second = await open();
    await settle();
    expect(second.hasPending, isFalse);
    expect(second.lastError, isNotNull);
    expect(store.entries, isEmpty);
    // Nothing comes back the next time either.
    closeApp(second);
    repository.refuseUpserts = false;
    final third = await open();
    expect(third.hasPending, isFalse);
    expect(third.itemById('a')!.status, 'todo');
  });

  test('changes stay stored while the server cannot be reached', () async {
    final first = await open();
    repository.failUpserts = true;
    first.patchItem('a', {'title': 'Write more'});
    await first.flush();
    closeApp(first);
    await settle();

    // Opened again, still offline: shown, kept, and tried again later.
    final second = await open();
    expect(second.itemById('a')!.title, 'Write more');
    await settle();
    expect(second.isOffline, isTrue);
    expect(store.entries, hasLength(1));
    repository.failUpserts = false;
    await settle();
    expect(repository.items['a']!.title, 'Write more');
    expect(store.entries, isEmpty);
  });

  test('closing the list sends what it can and keeps the rest', () async {
    final first = await open();
    first.patchItem('a', {'title': 'Sent on close'});
    closeApp(first);
    await settle();
    expect(repository.items['a']!.title, 'Sent on close');
    expect(store.entries, isEmpty);

    final second = await open();
    repository.failUpserts = true;
    second.patchItem('b', {'title': 'Kept on close'});
    closeApp(second);
    await settle();
    expect(repository.items['b']!.title, 'Design');
    expect(store.entries, hasLength(1));
  });

  test('deleting a task made offline forgets it', () async {
    final first = await open();
    repository.failUpserts = true;
    final created = first.createItem('Never mind');
    await first.flush();
    expect(store.entries, hasLength(1));
    first.deleteItem(created.id);
    await settle();
    expect(store.entries, isEmpty);
  });

  test('another account does not send the changes', () async {
    final first = await open();
    repository.failUpserts = true;
    first.setDone('a', true);
    await first.flush();
    closeApp(first);
    await settle();

    repository.failUpserts = false;
    final other = await open(userId: 'someone-else');
    expect(other.hasPending, isFalse);
    expect(other.itemById('a')!.status, 'todo');
    await settle();
    expect(repository.upserts, isEmpty);
    expect(await store.listIds('me'), ['list-1']);
    expect(await store.listIds('someone-else'), isEmpty);
  });

  test('the draft survives the JSON a real store keeps', () {
    final draft = TaskListDraft(
      userId: 'me',
      listId: 'list-1',
      patches: {
        'a': {
          'title': 'x',
          'priority': 2,
          'due_at': null,
          'due_has_time': true,
          'assignees': ['you', 'me'],
        },
      },
      created: {'a': DateTime.utc(2026, 10, 17, 12)},
    );
    final back = TaskListDraft.fromJson(
      jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
    );
    expect(back.patches, draft.patches);
    expect(back.created, draft.created);
  });

  group('SharedPreferencesTaskPatchStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps drafts by user and list', () async {
      const keeper = SharedPreferencesTaskPatchStore();
      await keeper.save(
        TaskListDraft(
          userId: 'me',
          listId: 'list-1',
          patches: {
            'a': {'status': 'done'},
          },
        ),
      );
      await keeper.save(
        TaskListDraft(
          userId: 'me',
          listId: 'list-2',
          patches: {
            'x': {'title': 'y'},
          },
        ),
      );
      await keeper.save(
        TaskListDraft(
          userId: 'you',
          listId: 'list-1',
          patches: {
            'a': {'title': 'z'},
          },
        ),
      );
      expect((await keeper.load('me', 'list-1'))!.patches['a'], {
        'status': 'done',
      });
      expect(await keeper.listIds('me'), unorderedEquals(['list-1', 'list-2']));
      expect(await keeper.listIds('you'), ['list-1']);

      // Saving nothing removes the entry.
      await keeper.save(const TaskListDraft(userId: 'me', listId: 'list-2'));
      expect(await keeper.listIds('me'), ['list-1']);

      await keeper.clearAll();
      expect(await keeper.listIds('me'), isEmpty);
      expect(await keeper.listIds('you'), isEmpty);
    });

    test('unreadable entries are ignored', () async {
      SharedPreferences.setMockInitialValues({
        'wecord.lists.patches.me.list-1': 'not json',
      });
      const keeper = SharedPreferencesTaskPatchStore();
      expect(await keeper.load('me', 'list-1'), isNull);
    });
  });

  group('TaskPatchSync (changes left by lists that are closed)', () {
    Future<void> leave(Map<String, Map<String, Object?>> patches) {
      return store.save(
        TaskListDraft(
          userId: 'me',
          listId: 'list-1',
          patches: patches,
          created: {
            for (final id in patches.keys)
              if (id.startsWith('new')) id: DateTime(2026, 10, 17),
          },
        ),
      );
    }

    TaskPatchSync sync({bool Function(String)? isOpen}) => TaskPatchSync(
      store: store,
      repository: repository,
      userId: 'me',
      isOpen: isOpen ?? (_) => false,
    );

    test('sends the kept patches and forgets them', () async {
      await leave({
        'a': {'status': 'done'},
        'new-1': {
          'title': 'Made offline',
          'status': 'todo',
          'assignees': ['you'],
        },
      });
      expect(await sync().sweep(), 0);
      expect(repository.items['a']!.status, 'done');
      expect(repository.items['new-1']!.title, 'Made offline');
      expect(repository.pushed, ['new-1']);
      expect(store.entries, isEmpty);
    });

    test(
      'keeps what could not be sent while the server is unreachable',
      () async {
        await leave({
          'a': {'status': 'done'},
          'b': {'title': 'Design the banner'},
        });
        repository.failUpserts = true;
        expect(await sync().sweep(), 2);
        expect(store.entries, hasLength(1));
        repository.failUpserts = false;
        expect(await sync().sweep(), 0);
        expect(repository.items['b']!.title, 'Design the banner');
        expect(store.entries, isEmpty);
      },
    );

    test('drops what the server refuses', () async {
      await leave({
        'a': {'status': 'done'},
      });
      repository.refuseUpserts = true;
      expect(await sync().sweep(), 0);
      expect(store.entries, isEmpty);
      expect(repository.items['a']!.status, 'todo');
    });

    test('leaves a list that is open to its controller', () async {
      await leave({
        'a': {'status': 'done'},
      });
      expect(await sync(isOpen: (id) => id == 'list-1').sweep(), 0);
      expect(repository.upserts, isEmpty);
      expect(store.entries, hasLength(1));
    });

    test('opening a list during the sweep keeps its store', () async {
      await leave({
        'a': {'status': 'done'},
      });
      var calls = 0;
      // Closed when the sweep starts, open when it is done.
      await sync(isOpen: (_) => ++calls > 1).sweep();
      expect(store.entries, hasLength(1));
    });

    test('knows which lists have a controller on screen', () async {
      expect(TaskListController.isListOpen('list-1'), isFalse);
      final controller = await open();
      expect(TaskListController.isListOpen('list-1'), isTrue);
      closeApp(controller);
      expect(TaskListController.isListOpen('list-1'), isFalse);
    });
  });
}
