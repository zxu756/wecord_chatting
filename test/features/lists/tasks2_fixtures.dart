import 'package:wecord/features/lists/list_models.dart';

import '../workspace/workspace_world.dart';

const tasks2Fields = [
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

/// The launch list with fields and two subtasks under "Write the launch
/// copy" (one done).
/// The launch list with fields and two subtasks under "Write the launch
/// copy" (one done); "Plan the schedule" has values.
void withTasks2(WorkspaceWorld world) {
  world.lists.lists['list-launch'] = world.lists.lists['list-launch']!.copyWith(
    fieldDefs: tasks2Fields,
  );
  world.lists.items['sub-1'] = TaskItem(
    id: 'sub-1',
    listId: 'list-launch',
    title: 'Draft the headline',
    status: 'todo',
    pos: 'a',
    parentId: 'item-copy',
    createdAt: DateTime(2026, 10, 4),
  );
  world.lists.items['sub-2'] = TaskItem(
    id: 'sub-2',
    listId: 'list-launch',
    title: 'Pick the photo',
    status: 'done',
    pos: 'b',
    parentId: 'item-copy',
    completedAt: DateTime(2026, 10, 5),
    createdAt: DateTime(2026, 10, 4),
  );
  world.lists.items['item-plan'] = world.lists.items['item-plan']!.copyWith(
    custom: {'cost': 40, 'area': 'work', 'who': 'user-3'},
  );
  world.lists.items['item-copy'] = world.lists.items['item-copy']!.copyWith(
    custom: {'site': 'https://example.com/launch', 'area': 'home'},
    recurrence: const TaskRecurrence(unit: TaskRepeatUnit.weekly, interval: 2),
  );
}
