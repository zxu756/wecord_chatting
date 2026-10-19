import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_patch_store.dart';
import 'package:wecord/features/lists/task_patch_sync.dart';

import '../workspace/workspace_fakes.dart';

const _fields = [
  TaskFieldDef(id: 'cost', name: 'Cost', type: TaskFieldType.number),
  TaskFieldDef(
    id: 'area',
    name: 'Area',
    type: TaskFieldType.select,
    options: [
      TaskFieldOption(id: 'home', name: 'Home'),
      TaskFieldOption(id: 'work', name: 'Work'),
    ],
  ),
  TaskFieldDef(id: 'site', name: 'Site', type: TaskFieldType.link),
  TaskFieldDef(id: 'who', name: 'Owner', type: TaskFieldType.person),
];

TaskItem item(
  String id,
  String title, {
  String status = 'todo',
  String pos = 'V',
  String? parentId,
  DateTime? dueAt,
  List<String> assignees = const [],
  Map<String, Object?> custom = const {},
  TaskRecurrence? recurrence,
}) {
  return TaskItem(
    id: id,
    listId: 'list-1',
    title: title,
    status: status,
    pos: pos,
    parentId: parentId,
    dueAt: dueAt,
    assignees: assignees,
    custom: custom,
    recurrence: recurrence,
    createdAt: DateTime(2026, 10, 1),
    completedAt: status == 'done' ? DateTime(2026, 10, 2) : null,
  );
}

void main() {
  late FakeListsRepository repository;
  late TaskList list;
  late TaskListController controller;
  late InMemoryTaskPatchStore store;
  final now = DateTime(2026, 10, 17, 12);
  var ids = 0;

  setUp(() {
    repository = FakeListsRepository();
    store = InMemoryTaskPatchStore();
    list = TaskList(
      id: 'list-1',
      conversationId: 'conv-1',
      title: 'Home',
      icon: 'x',
      statuses: TaskStatus.defaults,
      fieldDefs: _fields,
      canEdit: true,
      canManage: true,
    );
    repository.lists['list-1'] = list;
    final items = [
      item('bins', 'Bins', pos: 'a', dueAt: DateTime(2026, 10, 20, 23, 59)),
      item('glass', 'Glass', pos: 'a', parentId: 'bins'),
      item('paper', 'Paper', pos: 'b', parentId: 'bins', status: 'done'),
      item('shop', 'Shopping', pos: 'b', assignees: ['me']),
      item('mop', 'Mop', pos: 'c', parentId: 'shop', assignees: ['me']),
      item('done', 'Old', status: 'done', pos: 'a'),
    ];
    for (final i in items) {
      repository.items[i.id] = i;
    }
    controller = TaskListController(
      repository: repository,
      currentUserId: 'me',
      newId: () => 'new-${ids++}',
      store: store,
      clock: () => now,
      retryAfter: const Duration(milliseconds: 10),
    )..load(TaskSnapshot(list: list, items: items));
  });

  tearDown(() => controller.dispose());

  group('what the server sends', () {
    test('an old row without the new columns still reads', () {
      final old = TaskItem.fromJson({
        'id': 'i',
        'list_id': 'l',
        'title': 'Old row',
        'status': 'todo',
      });
      expect(old.custom, isEmpty);
      expect(old.parentId, isNull);
      expect(old.recurrence, isNull);
      expect(old.isSubtask, isFalse);
      final oldList = TaskList.fromJson({
        'id': 'l',
        'conversation_id': 'c',
        'statuses': [
          {'id': 'todo', 'name': 'To do', 'kind': 'todo'},
        ],
      });
      expect(oldList.fieldDefs, isEmpty);
    });

    test('fields, values, the parent and the repeat rule are read', () {
      final parsed = TaskItem.fromJson({
        'id': 'i',
        'list_id': 'l',
        'title': 'Bins',
        'status': 'todo',
        'custom': {'cost': 12.5, 'area': 'home', 'gone': null},
        'parent_id': 'p',
        'recurrence': {'freq': 'weekly', 'interval': 2, 'tz_offset': 480},
      });
      expect(parsed.custom, {'cost': 12.5, 'area': 'home'});
      expect(parsed.parentId, 'p');
      expect(parsed.recurrence!.unit, TaskRepeatUnit.weekly);
      expect(parsed.recurrence!.interval, 2);
      expect(parsed.recurrence!.tzOffset, 480);
      expect(parsed.recurrence!.label, 'Every 2 weeks');
      final defs = TaskList.fromJson({
        'id': 'l',
        'conversation_id': 'c',
        'statuses': [],
        'field_defs': [
          {
            'id': 'area',
            'name': 'Area',
            'type': 'select',
            'options': [
              {'id': 'home', 'name': 'Home'},
            ],
          },
          {'id': 'weird', 'name': 'Weird', 'type': 'hologram'},
        ],
      }).fieldDefs;
      expect(defs.length, 1);
      expect(defs.single.optionById('home')!.name, 'Home');
    });

    test('a repeat rule reads from the JSON a realtime row carries', () {
      final rule = TaskRecurrence.tryFromJson('{"freq":"daily","interval":3}');
      expect(rule!.interval, 3);
      expect(TaskRecurrence.tryFromJson('nonsense'), isNull);
      expect(TaskRecurrence.tryFromJson({'freq': 'hourly'}), isNull);
      expect(
        TaskRecurrence.tryFromJson({
          'freq': 'daily',
          'interval': 500,
        })!.interval,
        99,
      );
    });
  });

  group('subtasks', () {
    test('a list shows tasks, and their subtasks under them', () {
      expect(controller.rootsIn('todo').map((i) => i.id), ['bins', 'shop']);
      expect(controller.subtasksOf('bins').map((i) => i.id), [
        'glass',
        'paper',
      ]);
      expect(controller.subtaskProgress('bins'), (done: 1, total: 2));
      expect(controller.subtaskProgress('shop'), (done: 0, total: 1));
    });

    test('a filter keeps a task whose subtask matches', () {
      controller.setFilter(TaskFilter.mine);
      // "Bins" is nobody's, "Shopping" and its subtask are mine.
      expect(controller.rootsIn('todo').map((i) => i.id), ['shop']);
      controller.setFilter(TaskFilter.open);
      expect(controller.rootsIn('done').map((i) => i.id), isEmpty);
      final bins = controller.itemById('bins')!;
      // The task matches the filter, so all its subtasks are shown.
      expect(controller.visibleSubtasks(bins).map((i) => i.id), [
        'glass',
        'paper',
      ]);
    });

    test('a filter on a subtask alone shows only that subtask', () {
      repository.items['glass'] = item(
        'glass',
        'Glass',
        pos: 'a',
        parentId: 'bins',
        assignees: ['me'],
      );
      controller.load(
        TaskSnapshot(
          list: list,
          items: [
            for (final i in repository.items.values)
              if (!i.deleted) i,
          ],
        ),
      );
      controller.setFilter(TaskFilter.mine);
      expect(controller.rootsIn('todo').map((i) => i.id), ['bins', 'shop']);
      final bins = controller.itemById('bins')!;
      expect(controller.visibleSubtasks(bins).map((i) => i.id), ['glass']);
    });

    test('a subtask whose task is gone stands on its own', () {
      controller.load(
        TaskSnapshot(
          list: list,
          items: [item('lost', 'Lost step', parentId: 'nowhere')],
        ),
      );
      expect(controller.rootsIn('todo').map((i) => i.id), ['lost']);
      expect(controller.isNested(controller.itemById('lost')!), isFalse);
    });

    test('a new subtask goes at the end of its task and is sent', () async {
      final created = controller.createItem('Cans', parentId: 'bins');
      expect(created.parentId, 'bins');
      expect(controller.subtasksOf('bins').last.id, created.id);
      // It is not a card of its own.
      expect(
        controller.rootsIn('todo').map((i) => i.id),
        isNot(contains(created.id)),
      );
      await controller.flush();
      expect(repository.items[created.id]!.parentId, 'bins');
      expect(repository.upserts.last['parent_id'], 'bins');
    });

    test('moving a task counts tasks, not subtasks', () {
      // Roots of To do: bins, shop. Put "shop" first.
      controller.moveItem('shop', 'todo', 0);
      expect(controller.rootsIn('todo', manualOrder: true).map((i) => i.id), [
        'shop',
        'bins',
      ]);
      expect(controller.itemById('shop')!.pos.compareTo('a'), lessThan(0));
    });

    test('a task turned back from a subtask drops its repeat locally', () {
      controller.patchItem('glass', {
        'recurrence': {'freq': 'daily', 'interval': 1},
      });
      expect(controller.itemById('glass')!.recurrence, isNull);
      controller.patchItem('glass', {'parent_id': null});
      expect(controller.itemById('glass')!.parentId, isNull);
      expect(controller.rootsIn('todo').map((i) => i.id), contains('glass'));
    });
  });

  group('the list\'s own fields', () {
    test('a value shows at once and one patch sends it', () async {
      controller.patchItem('shop', {
        'custom': {'cost': 12, 'area': 'home'},
      });
      expect(controller.itemById('shop')!.custom, {'cost': 12, 'area': 'home'});
      await controller.flush();
      expect(repository.items['shop']!.custom, {'cost': 12, 'area': 'home'});
    });

    test(
      'changes to different fields before the first is sent both go',
      () async {
        repository.failUpserts = true;
        controller.patchItem('shop', {
          'custom': {'cost': 12},
        });
        controller.patchItem('shop', {
          'custom': {'area': 'work'},
        });
        await controller.flush();
        expect(controller.isOffline, isTrue);
        repository.failUpserts = false;
        await controller.flush();
        expect(repository.items['shop']!.custom, {'cost': 12, 'area': 'work'});
      },
    );

    test('null clears one value and only that one', () async {
      controller.patchItem('shop', {
        'custom': {'cost': 12, 'area': 'home'},
      });
      await controller.flush();
      controller.patchItem('shop', {
        'custom': {'cost': null},
      });
      expect(controller.itemById('shop')!.custom, {'area': 'home'});
      await controller.flush();
      expect(repository.items['shop']!.custom, {'area': 'home'});
    });

    test('a field changed while the first send was on its way stays', () async {
      controller.patchItem('shop', {
        'custom': {'cost': 1},
      });
      final sending = controller.flush();
      controller.patchItem('shop', {
        'custom': {'cost': 2, 'area': 'home'},
      });
      await sending;
      await controller.flush();
      expect(repository.items['shop']!.custom, {'cost': 2, 'area': 'home'});
      expect(controller.hasPending, isFalse);
    });

    test('mergeTaskPatch merges the values and keeps the rest', () {
      final merged = mergeTaskPatch(
        {
          'title': 'A',
          'custom': {'cost': 1, 'area': 'home'},
        },
        {
          'priority': 2,
          'custom': {'cost': null},
        },
      );
      expect(merged['title'], 'A');
      expect(merged['priority'], 2);
      expect(merged['custom'], {'cost': null, 'area': 'home'});
      expect(mergeTaskPatch(null, {'a': 1}), {'a': 1});
    });

    test('removeSentFromTaskPatch leaves what changed since', () {
      final pending = <String, Object?>{
        'title': 'B',
        'assignees': ['x'],
        'custom': {'cost': 2, 'area': 'home'},
      };
      removeSentFromTaskPatch(pending, {
        'title': 'A',
        'assignees': ['x'],
        'custom': {'cost': 1, 'area': 'home'},
      });
      expect(pending['title'], 'B');
      expect(pending.containsKey('assignees'), isFalse);
      expect(pending['custom'], {'cost': 2});
    });
  });

  group('repeat', () {
    test('a new task made with a date and a rule sends both', () async {
      final created = controller.createItem(
        'Water the plants',
        dueAt: DateTime(2026, 10, 21, 23, 59),
        recurrence: TaskRecurrence.here(TaskRepeatUnit.weekly),
      );
      expect(created.recurrence!.unit, TaskRepeatUnit.weekly);
      await controller.flush();
      final sent = repository.upserts.last;
      expect((sent['recurrence']! as Map)['freq'], 'weekly');
      expect(
        repository.items[created.id]!.recurrence!.unit,
        TaskRepeatUnit.weekly,
      );
    });

    test('no date, no repeat', () {
      final created = controller.createItem(
        'Whenever',
        recurrence: TaskRecurrence.here(TaskRepeatUnit.daily),
      );
      expect(created.recurrence, isNull);
    });

    test('the rule in a patch is shown at once', () {
      controller.patchItem('bins', {
        'recurrence': TaskRecurrence.here(
          TaskRepeatUnit.monthly,
          interval: 2,
        ).toJson(),
      });
      expect(controller.itemById('bins')!.recurrence!.label, 'Every 2 months');
      controller.patchItem('bins', {'recurrence': null});
      expect(controller.itemById('bins')!.recurrence, isNull);
    });

    test('the labels', () {
      expect(
        const TaskRecurrence(unit: TaskRepeatUnit.daily).label,
        'Every day',
      );
      expect(
        const TaskRecurrence(unit: TaskRepeatUnit.yearly).label,
        'Every year',
      );
      expect(
        const TaskRecurrence(unit: TaskRepeatUnit.daily, interval: 3).label,
        'Every 3 days',
      );
    });
  });

  group('calendar', () {
    test('tasks are put on the day they are due', () {
      final byDay = controller.dueByDay();
      expect(byDay.keys, [DateTime(2026, 10, 20)]);
      expect(controller.itemsDueOn(DateTime(2026, 10, 20)).single.id, 'bins');
      expect(controller.itemsDueOn(DateTime(2026, 10, 21)), isEmpty);
    });

    test('the tasks with no date are listed apart, and filters apply', () {
      expect(controller.undated.map((i) => i.id), contains('shop'));
      expect(controller.undated.map((i) => i.id), isNot(contains('bins')));
      controller.setFilter(TaskFilter.mine);
      expect(controller.undated.map((i) => i.id), ['shop', 'mop']);
      expect(controller.dueByDay(), isEmpty);
    });
  });

  group('kept on the device', () {
    test('fields, subtasks and repeats survive closing the app', () async {
      repository.failUpserts = true;
      controller.createItem('Cans', parentId: 'bins');
      controller.patchItem('shop', {
        'custom': {'cost': 7},
      });
      controller.patchItem('shop', {
        'custom': {'who': 'you'},
      });
      controller.patchItem('bins', {
        'recurrence': {'freq': 'daily', 'interval': 1},
      });
      await controller.flush();
      expect(controller.isOffline, isTrue);
      final kept = await store.load('me', 'list-1');
      expect(kept!.patches['shop']!['custom'], {'cost': 7, 'who': 'you'});
      expect(kept.patches['bins']!['recurrence'], {
        'freq': 'daily',
        'interval': 1,
      });
      expect(
        kept.patches.values.any((patch) => patch['parent_id'] == 'bins'),
        isTrue,
      );

      // Another run: the draft goes back on top of the server's list and is
      // sent.
      repository.failUpserts = false;
      final reopened = TaskListController(
        repository: repository,
        currentUserId: 'me',
        newId: () => 'new-${ids++}',
        store: store,
        clock: () => now,
        retryAfter: const Duration(milliseconds: 10),
      )..load(await repository.getList('list-1'), draft: kept);
      addTearDown(reopened.dispose);
      expect(reopened.itemById('shop')!.custom, {'cost': 7, 'who': 'you'});
      expect(reopened.subtasksOf('bins').any((i) => i.title == 'Cans'), isTrue);
      await reopened.flush();
      expect(repository.items['shop']!.custom, {'cost': 7, 'who': 'you'});
      expect(repository.items['bins']!.recurrence!.unit, TaskRepeatUnit.daily);
    });

    test('the background sweep sends the new fields as they are', () async {
      await store.save(
        const TaskListDraft(
          userId: 'me',
          listId: 'list-1',
          patches: {
            'shop': {
              'custom': {'cost': 9},
              'parent_id': null,
            },
          },
        ),
      );
      final waiting = await TaskPatchSync(
        store: store,
        repository: repository,
        userId: 'me',
        isOpen: (_) => false,
      ).sweep();
      expect(waiting, 0);
      expect(repository.items['shop']!.custom, {'cost': 9});
      expect(repository.upserts.last['custom'], {'cost': 9});
    });
  });
}
