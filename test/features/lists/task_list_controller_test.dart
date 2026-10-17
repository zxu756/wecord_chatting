import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';

import '../workspace/workspace_fakes.dart';

TaskItem item(
  String id,
  String title, {
  String status = 'todo',
  String pos = 'V',
  List<String> assignees = const [],
  DateTime? dueAt,
  TaskPriority priority = TaskPriority.none,
  DateTime? createdAt,
}) {
  return TaskItem(
    id: id,
    listId: 'list-1',
    title: title,
    status: status,
    pos: pos,
    assignees: assignees,
    dueAt: dueAt,
    priority: priority,
    createdAt: createdAt ?? DateTime(2026, 10, 1),
    completedAt: status == 'done' ? DateTime(2026, 10, 2) : null,
  );
}

void main() {
  late FakeListsRepository repository;
  late TaskListController controller;
  final now = DateTime(2026, 10, 17, 12);
  var ids = 0;

  setUp(() {
    repository = FakeListsRepository();
    final list = TaskList(
      id: 'list-1',
      conversationId: 'conv-1',
      title: 'Launch',
      icon: 'x',
      statuses: TaskStatus.defaults,
      canEdit: true,
      canManage: true,
    );
    repository.lists['list-1'] = list;
    final items = [
      item(
        'a',
        'Write copy',
        pos: 'a',
        assignees: ['me'],
        dueAt: DateTime(2026, 10, 16),
      ),
      item(
        'b',
        'Design',
        pos: 'b',
        assignees: ['you'],
        priority: TaskPriority.high,
      ),
      item(
        'c',
        'Review',
        status: 'doing',
        pos: 'a',
        dueAt: DateTime(2026, 10, 20),
      ),
      item('d', 'Ship', status: 'done', pos: 'a'),
    ];
    for (final i in items) {
      repository.items[i.id] = i;
    }
    controller = TaskListController(
      repository: repository,
      currentUserId: 'me',
      newId: () => 'new-${ids++}',
      clock: () => now,
      retryAfter: const Duration(milliseconds: 10),
    )..load(TaskSnapshot(list: list, items: items));
  });

  tearDown(() => controller.dispose());

  test('items are grouped by status in manual order', () {
    expect(controller.itemsIn('todo').map((i) => i.title), [
      'Write copy',
      'Design',
    ]);
    expect(controller.itemsIn('doing').single.title, 'Review');
  });

  test('filters: mine, overdue, open', () {
    controller.setFilter(TaskFilter.mine);
    expect(controller.itemsIn('todo').map((i) => i.id), ['a']);
    expect(controller.itemsIn('doing'), isEmpty);
    controller.setFilter(TaskFilter.overdue);
    expect(controller.itemsIn('todo').map((i) => i.id), ['a']);
    controller.setFilter(TaskFilter.open);
    expect(controller.itemsIn('done'), isEmpty);
    expect(controller.count(TaskFilter.mine), 1);
    expect(controller.count(TaskFilter.overdue), 1);
    expect(controller.count(TaskFilter.open), 3);
  });

  test(
    'sorting by due date puts undated items last; by priority high first',
    () {
      controller.setSort(TaskSort.dueDate);
      expect(controller.itemsIn('todo').map((i) => i.id), ['a', 'b']);
      controller.setSort(TaskSort.priority);
      expect(controller.itemsIn('todo').map((i) => i.id), ['b', 'a']);
      controller.setSort(TaskSort.newest);
      expect(controller.itemsIn('todo').length, 2);
    },
  );

  test('checking off moves the item to Done and sends one patch', () async {
    controller.setDone('a', true);
    expect(controller.itemById('a')!.status, 'done');
    expect(controller.itemById('a')!.isDone, isTrue);
    await controller.flush();
    expect(repository.upserts.single['status'], 'done');
    expect(repository.items['a']!.status, 'done');
    // And back.
    controller.setDone('a', false);
    expect(controller.itemById('a')!.status, 'todo');
    expect(controller.itemById('a')!.isDone, isFalse);
  });

  test(
    'dragging to another column sets its status and a key between neighbours',
    () async {
      repository.items['e'] = item('e', 'Test', status: 'doing', pos: 'c');
      controller.load(await repository.getList('list-1'));
      // Between "Review" (a) and "Test" (c) in In progress.
      controller.moveItem('b', 'doing', 1);
      final moved = controller.itemById('b')!;
      expect(moved.status, 'doing');
      expect(moved.pos.compareTo('a'), greaterThan(0));
      expect(moved.pos.compareTo('c'), lessThan(0));
      expect(controller.itemsIn('doing').map((i) => i.id), ['c', 'b', 'e']);
      await controller.flush();
      expect(repository.items['b']!.status, 'doing');
      expect(repository.items['b']!.pos, moved.pos);
    },
  );

  test('moving within a column reorders it', () {
    controller.moveItem('a', 'todo', 1);
    expect(controller.itemsIn('todo').map((i) => i.id), ['b', 'a']);
    controller.moveItem('a', 'todo', 0);
    expect(controller.itemsIn('todo').map((i) => i.id), ['a', 'b']);
  });

  test('moving to the top and bottom of an empty column', () {
    controller.moveItem('d', 'todo', 0);
    expect(controller.itemsIn('todo').first.id, 'd');
    controller.moveItem('d', 'doing', 5);
    expect(controller.itemsIn('doing').last.id, 'd');
  });

  test(
    'a new task goes to the end of its column and is created on the server',
    () async {
      final created = controller.createItem(
        'Book venue',
        assignees: const ['you'],
        dueAt: DateTime.utc(2026, 10, 30, 10),
        dueHasTime: true,
      );
      expect(controller.itemsIn('todo').last.id, created.id);
      await controller.flush();
      final saved = repository.items[created.id]!;
      expect(saved.title, 'Book venue');
      expect(saved.assignees, ['you']);
      expect(saved.dueHasTime, isTrue);
      // The assignee is told.
      expect(repository.pushed, [created.id]);
    },
  );

  test('patches to the same item are sent together', () async {
    controller.patchItem('a', {'title': 'Write the copy'});
    controller.patchItem('a', {'priority': 3});
    controller.patchItem('a', {'due_at': null});
    await controller.flush();
    expect(repository.upserts.length, 1);
    expect(repository.upserts.single['title'], 'Write the copy');
    expect(repository.upserts.single['priority'], 3);
    expect(repository.items['a']!.dueAt, isNull);
  });

  test(
    'changes made offline are kept and sent when the connection returns',
    () async {
      repository.failUpserts = true;
      controller.setDone('a', true);
      await controller.flush();
      expect(controller.isOffline, isTrue);
      expect(controller.hasPending, isTrue);
      expect(controller.itemById('a')!.isDone, isTrue);
      repository.failUpserts = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.isOffline, isFalse);
      expect(controller.hasPending, isFalse);
      expect(repository.items['a']!.status, 'done');
    },
  );

  test('a late echo from the server does not undo a local drag', () {
    controller.patchItem('b', {'status': 'doing', 'pos': 'm'});
    // The server's old row arrives while the patch is waiting.
    repository.failUpserts = true;
    controller.receiveItem(item('b', 'Design', pos: 'b', assignees: ['you']));
    expect(controller.itemById('b')!.status, 'doing');
    expect(controller.itemById('b')!.pos, 'm');
    // The assignees (not part of a row) are kept.
    expect(controller.itemById('b')!.assignees, ['you']);
  });

  test('other people\'s changes show up', () {
    controller.receiveItem(
      item('a', 'Write the copy today', pos: 'a', status: 'doing'),
    );
    expect(controller.itemById('a')!.title, 'Write the copy today');
    expect(controller.itemById('a')!.status, 'doing');
    controller.receiveItem(
      item('a', 'Write the copy today', pos: 'a').copyWith(deleted: true),
    );
    expect(controller.itemById('a'), isNull);
  });

  test('deleting removes the item and tells the server', () async {
    repository.items['a'] = item('a', 'Write copy', pos: 'a');
    controller.deleteItem('a');
    expect(controller.itemById('a'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(repository.items['a']!.deleted, isTrue);
  });

  test('many drags into one gap renumber the column', () {
    for (var i = 0; i < 80; i++) {
      controller.moveItem(i.isEven ? 'a' : 'b', 'doing', 1);
    }
    for (final i in controller.items) {
      expect(i.pos.length, lessThanOrEqualTo(64));
    }
  });
}
