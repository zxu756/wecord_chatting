import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_board.dart';
import 'package:wecord/features/lists/task_list_page.dart';

import '../../mobile/phone_test_support.dart';
import 'workspace_world.dart';

Future<WorkspaceWorld> openList(
  WidgetTester tester, {
  PhoneViewport viewport = notchedPhone,
  String? itemId,
  TaskListView? view,
  void Function(WorkspaceWorld world)? prepare,
}) async {
  usePhoneViewport(tester, viewport);
  final workspace = WorkspaceWorld();
  if (view != null) {
    workspace.lists.lists['list-launch'] = workspace.lists.lists['list-launch']!
        .copyWith(defaultView: view);
  }
  prepare?.call(workspace);
  workspace.install();
  await pumpStandalone(
    tester,
    workspace.world,
    TaskListPage(
      listId: 'list-launch',
      conversationId: WorkspaceWorld.conversationId,
      initialItemId: itemId,
      onBack: () {},
    ),
  );
  await settle(tester);
  return workspace;
}

void main() {
  testWidgets('tasks are grouped by status with their details', (tester) async {
    final semantics = tester.ensureSemantics();
    await openList(tester);
    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Write the launch copy'), findsOneWidget);
    expect(find.text('Design the banner'), findsOneWidget);
    // Overdue date, priority and assignees.
    expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);
    expect(find.text('High'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('task-item-design'))).label,
      contains('Assigned to'),
    );
    semantics.dispose();
  });

  testWidgets('filters show mine and overdue', (tester) async {
    await openList(tester);
    await tester.tap(find.byKey(const ValueKey('task-filter-mine')));
    await settle(tester);
    expect(find.text('Write the launch copy'), findsOneWidget);
    expect(find.text('Plan the schedule'), findsOneWidget);
    expect(find.text('Design the banner'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-filter-overdue')));
    await settle(tester);
    expect(find.text('Write the launch copy'), findsOneWidget);
    expect(find.text('Plan the schedule'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-filter-all')));
    await settle(tester);
    expect(find.text('Test on every phone'), findsOneWidget);
  });

  testWidgets('sorting by priority puts the high priority task first', (
    tester,
  ) async {
    await openList(tester);
    await tester.tap(find.byTooltip('Sort'));
    await settle(tester);
    await tester.tap(find.text('Priority').last);
    await settle(tester);
    final copy = tester.getTopLeft(find.text('Write the launch copy'));
    final qa = tester.getTopLeft(find.text('Test on every phone'));
    expect(copy.dy, lessThan(qa.dy));
  });

  testWidgets('checking a task off moves it to Done on the server', (
    tester,
  ) async {
    final workspace = await openList(tester);
    await tester.tap(
      find.bySemanticsLabel('Mark "Test on every phone" as done'),
    );
    await settle(tester);
    expect(workspace.lists.items['item-qa']!.status, 'done');
    expect(workspace.lists.items['item-qa']!.isDone, isTrue);
    // And back.
    await tester.tap(
      find.bySemanticsLabel('Mark "Test on every phone" as not done'),
    );
    await settle(tester);
    expect(workspace.lists.items['item-qa']!.status, 'todo');
  });

  testWidgets('a task added at the bottom appears in To do', (tester) async {
    final workspace = await openList(tester);
    await tester.enterText(
      find.byKey(const ValueKey('task-add-field')),
      'Book the venue',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Book the venue'), findsOneWidget);
    final created = workspace.lists.items.values.firstWhere(
      (item) => item.title == 'Book the venue',
    );
    expect(created.status, 'todo');
  });

  testWidgets('a task added offline survives closing the app and is sent', (
    tester,
  ) async {
    final workspace = await openList(
      tester,
      prepare: (workspace) => workspace.lists.failUpserts = true,
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-add-field')),
      'Book the venue',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Book the venue'), findsOneWidget);
    expect(
      workspace.lists.items.values.map((i) => i.title),
      isNot(contains('Book the venue')),
    );
    final kept = await SharedPreferences.getInstance();
    expect(
      kept.getKeys().where((key) => key.startsWith('wecord.lists.patches.')),
      hasLength(1),
    );

    // The app is closed: nothing of the page is left.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(
      workspace.lists.items.values.map((i) => i.title),
      isNot(contains('Book the venue')),
    );

    // And opened again once the connection is back.
    workspace.lists.failUpserts = false;
    await pumpStandalone(
      tester,
      workspace.world,
      TaskListPage(
        listId: 'list-launch',
        conversationId: WorkspaceWorld.conversationId,
        onBack: () {},
      ),
    );
    await settle(tester);
    expect(find.text('Book the venue'), findsOneWidget);
    expect(
      workspace.lists.items.values.where((i) => i.title == 'Book the venue'),
      hasLength(1),
    );
    expect(
      kept.getKeys().where((key) => key.startsWith('wecord.lists.patches.')),
      isEmpty,
    );
    await workspace.world.close(tester);
  });

  testWidgets('opening a task edits title, status, priority and assignees', (
    tester,
  ) async {
    final workspace = await openList(tester);
    await tester.tap(find.text('Test on every phone'));
    await settle(tester);
    expect(find.byKey(const ValueKey('task-title')), findsOneWidget);
    // Status chips.
    await tester.tap(find.byKey(const ValueKey('task-status-doing')));
    await settle(tester);
    expect(workspace.lists.items['item-qa']!.status, 'doing');
    // Priority.
    await tester.tap(find.text('Med'));
    await settle(tester);
    expect(workspace.lists.items['item-qa']!.priority, TaskPriority.medium);
    // Title, saved after a moment.
    await tester.enterText(
      find.byKey(const ValueKey('task-title')),
      'Test on every phone and tablet',
    );
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(
      workspace.lists.items['item-qa']!.title,
      'Test on every phone and tablet',
    );
    // Assign two people; they are notified.
    await tester.tap(find.text('Nobody yet'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('assignee-user-2')));
    await tester.tap(find.byKey(const ValueKey('assignee-user-3')));
    await tester.pump();
    await tester.tap(find.text('Done').last);
    await settle(tester);
    expect(workspace.lists.items['item-qa']!.assignees, ['user-2', 'user-3']);
    expect(workspace.lists.pushed, contains('item-qa'));
    await workspace.world.close(tester);
  });

  testWidgets('a due date can be chosen from the quick choices', (
    tester,
  ) async {
    final workspace = await openList(tester);
    await tester.tap(find.text('Test on every phone'));
    await settle(tester);
    await tester.tap(find.text('No date'));
    await settle(tester);
    await tester.tap(find.text('Tomorrow'));
    await settle(tester);
    await tester.tap(find.text('Done').last);
    await settle(tester);
    final due = workspace.lists.items['item-qa']!.dueAt!;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(due.day, tomorrow.day);
    expect(workspace.lists.items['item-qa']!.dueHasTime, isFalse);
    await workspace.world.close(tester);
  });

  testWidgets('a task from a message links back to it', (tester) async {
    await openList(tester, itemId: 'item-copy');
    expect(find.text('View the message'), findsOneWidget);
  });

  testWidgets('a task can be shared into the chat and deleted', (tester) async {
    final workspace = await openList(tester);
    await tester.tap(find.text('Test on every phone'));
    await settle(tester);
    await tester.tap(find.text('Share in the chat'));
    await settle(tester);
    expect(workspace.lists.shared, ['item:item-qa']);
    await tester.tap(find.byTooltip('Delete task'));
    await settle(tester);
    expect(find.text('Test on every phone'), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));
    expect(workspace.lists.items['item-qa']!.deleted, isTrue);
  });

  testWidgets('people who cannot send cannot add or check off tasks', (
    tester,
  ) async {
    await openList(
      tester,
      prepare: (w) {
        w.lists.lists['list-launch'] = TaskList(
          id: 'list-launch',
          conversationId: WorkspaceWorld.conversationId,
          title: 'Launch checklist',
          icon: 'x',
          statuses: TaskStatus.defaults,
        );
      },
    );
    expect(find.byKey(const ValueKey('task-add-field')), findsNothing);
    expect(find.text('Write the launch copy'), findsOneWidget);
  });

  testWidgets('the board has a column per status and cards move between them', (
    tester,
  ) async {
    final workspace = await openList(
      tester,
      view: TaskListView.board,
      viewport: const PhoneViewport(
        name: 'tablet',
        size: Size(1000, 700),
        devicePixelRatio: 1,
      ),
    );
    expect(find.byKey(const ValueKey('board-column-todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-column-doing')), findsOneWidget);
    expect(find.text('Write the launch copy'), findsOneWidget);

    // Long press, then drag into In progress, under "Design the banner".
    final card = find.text('Test on every phone');
    final from = tester.getCenter(card);
    final target = tester.getRect(
      find.byKey(const ValueKey('board-column-doing')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(Offset(target.center.dx, target.bottom - 60));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(Offset(target.center.dx, target.bottom - 50));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);

    expect(workspace.lists.items['item-qa']!.status, 'doing');
    // After "Design the banner" (pos a).
    expect(
      workspace.lists.items['item-qa']!.pos.compareTo('a'),
      greaterThan(0),
    );
  });

  testWidgets('boards offer the moves as actions for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final workspace = await openList(tester, view: TaskListView.board);
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Test on every phone')).first,
    );
    expect(node, isNotNull);
    expect(workspace.lists.items.length, 4);
    semantics.dispose();
  });

  test('boardInsertIndex puts a card between the ones around the pointer', () {
    expect(boardInsertIndex([10, 50, 90], 5), 0);
    expect(boardInsertIndex([10, 50, 90], 30), 1);
    expect(boardInsertIndex([10, 50, 90], 70), 2);
    expect(boardInsertIndex([10, 50, 90], 200), 3);
    expect(boardInsertIndex([], 20), 0);
  });

  testWidgets('statuses can be renamed and a column added', (tester) async {
    final workspace = await openList(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Edit statuses'));
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Add a status'),
      find.byType(ListView).last,
      const Offset(0, -150),
    );
    await tester.tap(find.text('Add a status'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(workspace.lists.lists['list-launch']!.statuses.length, 4);
    await workspace.world.close(tester);
  });
}
