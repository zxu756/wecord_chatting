// The Notes and Lists screens, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_page.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';

import '../features/workspace/workspace_world.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<void> _panel(
  WidgetTester tester,
  PhoneWorld world, {
  WorkspaceTab tab = WorkspaceTab.notes,
  String? noteId,
}) async {
  WorkspaceWorld(world: world).install();
  await pumpStandalone(
    tester,
    world,
    WorkspacePanel(
      conversationId: WorkspaceWorld.conversationId,
      initialTab: tab,
      initialNoteId: noteId,
      pageMode: true,
      onClose: () {},
    ),
  );
}

Future<void> _list(
  WidgetTester tester,
  PhoneWorld world, {
  TaskListView view = TaskListView.list,
}) async {
  final workspace = WorkspaceWorld(world: world);
  workspace.lists.lists['list-launch'] = workspace.lists.lists['list-launch']!
      .copyWith(defaultView: view);
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
}

final workspaceA11yScreens = <A11yScreen>[
  A11yScreen('notes-index', (tester, world) => _panel(tester, world)),
  A11yScreen(
    'note-editor',
    (tester, world) => _panel(tester, world, noteId: 'note-plan'),
  ),
  A11yScreen(
    'lists-index',
    (tester, world) => _panel(tester, world, tab: WorkspaceTab.lists),
  ),
  A11yScreen('task-list', (tester, world) => _list(tester, world)),
  A11yScreen(
    'task-board',
    (tester, world) => _list(tester, world, view: TaskListView.board),
  ),
  A11yScreen('task-sheet', (tester, world) async {
    await _list(tester, world);
    await tester.tap(find.text('Design the banner'));
  }),
];
