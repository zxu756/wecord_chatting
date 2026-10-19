// Task lists 2.0 (D7: a list's own fields, subtasks, repeating tasks and the
// calendar view), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_page.dart';

import '../features/lists/tasks2_fixtures.dart';
import '../features/workspace/workspace_world.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A narrow phone, 360 wide, where rows and chips have the least room.
const narrowTasksPhone = PhoneViewport(
  name: '360x740',
  size: Size(360, 740),
  devicePixelRatio: 3,
  topInset: 24,
  bottomInset: 0,
);

/// Tasks with a date this month, so the calendar has dots wherever the test
/// runs.
void _datedThisMonth(WorkspaceWorld workspace) {
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, d, 23, 59);
  final items = workspace.lists.items;
  items['item-copy'] = items['item-copy']!.copyWith(dueAt: day(3));
  items['item-design'] = items['item-design']!.copyWith(dueAt: day(12));
  items['item-qa'] = items['item-qa']!.copyWith(dueAt: day(12));
  items['item-plan'] = items['item-plan']!.copyWith(dueAt: day(18));
}

Future<WorkspaceWorld> _open(
  WidgetTester tester,
  PhoneWorld world, {
  TaskListView view = TaskListView.list,
  bool dated = false,
}) async {
  final workspace = WorkspaceWorld(world: world);
  withTasks2(workspace);
  workspace.lists.lists['list-launch'] = workspace.lists.lists['list-launch']!
      .copyWith(defaultView: view);
  if (dated) {
    _datedThisMonth(workspace);
  }
  workspace.install();
  await pumpStandalone(
    tester,
    world,
    TaskListPage(
      listId: 'list-launch',
      conversationId: WorkspaceWorld.conversationId,
      onBack: () {},
    ),
  );
  await settle(tester);
  return workspace;
}

Future<void> _chooseView(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('view-menu')));
  await settle(tester);
  await tester.tap(find.text(label).last);
}

final tasks2A11yScreens = <A11yScreen>[
  A11yScreen('tasks2-list', (tester, world) => _open(tester, world)),
  A11yScreen(
    'tasks2-list-narrow',
    (tester, world) => _open(tester, world),
    viewport: narrowTasksPhone,
  ),
  A11yScreen(
    'tasks2-board',
    (tester, world) => _open(tester, world, view: TaskListView.board),
  ),
  A11yScreen('tasks2-calendar', (tester, world) async {
    await _open(tester, world, dated: true);
    await _chooseView(tester, 'Calendar view');
  }),
  A11yScreen('tasks2-calendar-narrow', (tester, world) async {
    await _open(tester, world, dated: true);
    await _chooseView(tester, 'Calendar view');
  }, viewport: narrowTasksPhone),
  A11yScreen('tasks2-task-sheet', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.text('Write the launch copy'));
  }),
  A11yScreen('tasks2-task-sheet-narrow', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.text('Write the launch copy'));
  }, viewport: narrowTasksPhone),
  A11yScreen('tasks2-subtask-sheet', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.text('Draft the headline'));
  }),
  A11yScreen('tasks2-repeat-sheet', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.text('Write the launch copy'));
    await settle(tester);
    await tester.tap(find.text('Every 2 weeks'));
  }),
  A11yScreen('tasks2-fields-editor', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Custom fields'));
  }),
  A11yScreen('tasks2-fields-editor-narrow', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Custom fields'));
  }, viewport: narrowTasksPhone),
  A11yScreen('tasks2-field-choice', (tester, world) async {
    await _open(tester, world);
    await tester.tap(find.text('Write the launch copy'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('task-field-area')));
  }),
];
