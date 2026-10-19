import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_page.dart';

import '../../mobile/phone_test_support.dart';
import '../workspace/workspace_world.dart';
import 'tasks2_fixtures.dart';

Future<WorkspaceWorld> openList(
  WidgetTester tester, {
  PhoneViewport viewport = notchedPhone,
  TaskListView? view,
  void Function(WorkspaceWorld world)? prepare,
}) async {
  usePhoneViewport(tester, viewport);
  final workspace = WorkspaceWorld();
  if (view != null) {
    workspace.lists.lists['list-launch'] = workspace.lists.lists['list-launch']!
        .copyWith(defaultView: view);
  }
  withTasks2(workspace);
  prepare?.call(workspace);
  workspace.install();
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
  return workspace;
}

Future<void> chooseView(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('view-menu')));
  await settle(tester);
  await tester.tap(find.text(label).last);
  await settle(tester);
}

void main() {
  testWidgets('a list shows subtasks under their task, with their progress', (
    tester,
  ) async {
    await openList(tester);
    expect(find.text('Write the launch copy'), findsOneWidget);
    expect(find.text('Draft the headline'), findsOneWidget);
    expect(find.text('Pick the photo'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    // The subtask is indented under its task.
    expect(
      tester.getTopLeft(find.text('Draft the headline')).dx,
      greaterThan(tester.getTopLeft(find.text('Write the launch copy')).dx),
    );
    // And not a task of its own: "To do" counts the tasks, not the steps.
    await tester.tap(find.byKey(const ValueKey('task-filter-mine')));
    await settle(tester);
    expect(find.text('Write the launch copy'), findsOneWidget);
  });

  testWidgets('fields show on the row of a task that has values', (
    tester,
  ) async {
    await openList(tester);
    expect(find.text('Cost: 40'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Grace Brewster Murray Hopper'), findsOneWidget);
  });

  testWidgets('the board shows tasks, not subtasks, with their progress', (
    tester,
  ) async {
    await openList(tester, view: TaskListView.board);
    expect(find.text('Write the launch copy'), findsOneWidget);
    expect(find.text('Draft the headline'), findsNothing);
    expect(find.text('1/2'), findsOneWidget);
  });

  group('the task sheet', () {
    testWidgets('fills in a number, a choice, a link and a person', (
      tester,
    ) async {
      final workspace = await openList(tester);
      await tester.tap(find.text('Test on every phone'));
      await settle(tester);
      expect(find.byKey(const ValueKey('task-field-cost')), findsOneWidget);
      expect(find.text('Not set'), findsNWidgets(4));

      await tester.tap(find.byKey(const ValueKey('task-field-cost')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-field-input')),
        '12.5',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(workspace.lists.items['item-qa']!.custom['cost'], 12.5);
      expect(find.text('12.5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('task-field-area')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('field-choice-home')));
      await settle(tester);
      expect(workspace.lists.items['item-qa']!.custom['area'], 'home');

      await tester.tap(find.byKey(const ValueKey('task-field-who')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('field-choice-user-3')));
      await settle(tester);
      expect(workspace.lists.items['item-qa']!.custom['who'], 'user-3');

      // A choice can be taken back.
      await tester.tap(find.byKey(const ValueKey('task-field-area')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('field-choice-none')));
      await settle(tester);
      expect(
        workspace.lists.items['item-qa']!.custom.containsKey('area'),
        isFalse,
      );
      await workspace.world.close(tester);
    });

    testWidgets('a link needs an address; a bare domain gets https', (
      tester,
    ) async {
      final workspace = await openList(tester);
      await tester.tap(find.text('Test on every phone'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('task-field-site')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-field-input')),
        'not a link',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter a web address.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('task-field-input')),
        'example.com/plan',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
        workspace.lists.items['item-qa']!.custom['site'],
        'https://example.com/plan',
      );
      expect(find.text('example.com'), findsWidgets);
      await workspace.world.close(tester);
    });

    testWidgets('a number field refuses text', (tester) async {
      final workspace = await openList(tester);
      await tester.tap(find.text('Test on every phone'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('task-field-cost')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-field-input')),
        '1.2.3',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter a number.'), findsOneWidget);
      expect(
        workspace.lists.items['item-qa']!.custom.containsKey('cost'),
        isFalse,
      );
      await workspace.world.close(tester);
    });

    testWidgets('lists the subtasks, adds one and opens it', (tester) async {
      final workspace = await openList(tester);
      await tester.tap(find.text('Write the launch copy'));
      await settle(tester);
      expect(find.byKey(const ValueKey('task-subtasks')), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('subtask-add-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('subtask-add-field')),
        'Proofread',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      final added = workspace.lists.items.values.firstWhere(
        (item) => item.title == 'Proofread',
      );
      expect(added.parentId, 'item-copy');
      expect(find.text('1 of 3 done'), findsOneWidget);

      // A subtask is checked off from the sheet, and opens as a task.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('subtask-sub-1')),
          matching: find.bySemanticsLabel('Mark "Draft the headline" as done'),
        ),
      );
      await settle(tester);
      expect(workspace.lists.items['sub-1']!.isDone, isTrue);
      expect(find.text('2 of 3 done'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subtask-sub-1')));
      await settle(tester);
      expect(find.text('Subtask of Write the launch copy'), findsOneWidget);
      // It has no steps of its own, and cannot repeat.
      expect(find.byKey(const ValueKey('task-subtasks')), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('task-parent')));
      await settle(tester);
      expect(find.byKey(const ValueKey('task-subtasks')), findsOneWidget);
      await workspace.world.close(tester);
    });

    testWidgets('a task can be made to repeat, which gives it a date', (
      tester,
    ) async {
      final workspace = await openList(tester);
      await tester.tap(find.text('Test on every phone'));
      await settle(tester);
      expect(find.text('Does not repeat'), findsOneWidget);
      await tester.tap(find.text('Does not repeat'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-weekly')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeat-more')));
      await tester.pump();
      expect(find.text('2 weeks'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      final saved = workspace.lists.items['item-qa']!;
      expect(saved.recurrence!.unit, TaskRepeatUnit.weekly);
      expect(saved.recurrence!.interval, 2);
      expect(saved.dueAt, isNotNull);
      expect(find.text('Every 2 weeks'), findsOneWidget);

      // And to stop.
      await tester.tap(find.text('Every 2 weeks'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-never')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(workspace.lists.items['item-qa']!.recurrence, isNull);
      await workspace.world.close(tester);
    });

    testWidgets('clearing the date ends the repeat', (tester) async {
      final workspace = await openList(
        tester,
        prepare: (world) {
          world.lists.items['item-design'] = world.lists.items['item-design']!
              .copyWith(
                recurrence: const TaskRecurrence(unit: TaskRepeatUnit.daily),
              );
        },
      );
      await tester.tap(find.text('Design the banner'));
      await settle(tester);
      expect(find.text('Every day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-title')));
      await tester.pump();
      // The date row: open it and clear it.
      await tester.tap(find.text('Due'));
      await settle(tester);
      await tester.tap(find.text('No date').last);
      await settle(tester);
      expect(workspace.lists.items['item-design']!.dueAt, isNull);
      expect(workspace.lists.items['item-design']!.recurrence, isNull);
      await workspace.world.close(tester);
    });
  });

  group('custom fields', () {
    testWidgets('adds and saves a single-choice field', (tester) async {
      final workspace = await openList(
        tester,
        prepare: (world) {
          world.lists.lists['list-launch'] = world.lists.lists['list-launch']!
              .copyWith(fieldDefs: const []);
        },
      );
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Custom fields'));
      await settle(tester);
      await tester.tap(find.text('Add a field'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('field-name-field')),
        'Team',
      );
      await tester.pump();
      await tester.tap(find.text('Single choice'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('option-name-field-option')),
        'Design',
      );
      await tester.pump();
      await tester.tap(find.text('Add a choice'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('option-name-field-option-2')),
        'Build',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      final saved = workspace.lists.lists['list-launch']!.fieldDefs;
      expect(saved.length, 1);
      expect(saved.single.name, 'Team');
      expect(saved.single.type, TaskFieldType.select);
      expect(saved.single.options.map((o) => o.name), ['Design', 'Build']);
      await workspace.world.close(tester);
    });

    testWidgets('a field without a name cannot be saved', (tester) async {
      await openList(
        tester,
        prepare: (world) {
          world.lists.lists['list-launch'] = world.lists.lists['list-launch']!
              .copyWith(fieldDefs: const []);
        },
      );
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Custom fields'));
      await settle(tester);
      await tester.tap(find.text('Add a field'));
      await tester.pump();
      expect(
        find.text(
          'Give every field and choice a name, and every single-choice field at least one choice.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      // Still open.
      expect(find.text('Add a field'), findsOneWidget);
    });

    testWidgets('people who cannot edit the list do not see the menu entry', (
      tester,
    ) async {
      await openList(
        tester,
        prepare: (world) {
          world.lists.lists['list-launch'] = world.lists.lists['list-launch']!
              .copyWith(fieldDefs: tasks2Fields);
          world.lists.lists['list-launch'] = TaskList(
            id: 'list-launch',
            conversationId: WorkspaceWorld.conversationId,
            title: 'Launch checklist',
            icon: 'x',
            statuses: TaskStatus.defaults,
            fieldDefs: tasks2Fields,
          );
        },
      );
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      expect(find.text('Custom fields'), findsNothing);
    });
  });

  group('calendar view', () {
    final today = DateTime(2026, 10, 20, 12);

    void prepare(WorkspaceWorld world) {
      world.lists.items.clear();
      world.lists.items['due-a'] = TaskItem(
        id: 'due-a',
        listId: 'list-launch',
        title: 'Send the invoice',
        status: 'todo',
        pos: 'a',
        dueAt: DateTime(2026, 10, 22, 23, 59),
        assignees: const ['user-1'],
        createdAt: DateTime(2026, 10, 1),
      );
      world.lists.items['due-b'] = TaskItem(
        id: 'due-b',
        listId: 'list-launch',
        title: 'Renew the licence',
        status: 'todo',
        pos: 'b',
        dueAt: DateTime(2026, 10, 15, 23, 59),
        createdAt: DateTime(2026, 10, 1),
      );
      world.lists.items['due-c'] = TaskItem(
        id: 'due-c',
        listId: 'list-launch',
        title: 'Print the posters',
        status: 'done',
        pos: 'a',
        completedAt: DateTime(2026, 10, 3),
        dueAt: DateTime(2026, 10, 22, 9),
        dueHasTime: true,
        createdAt: DateTime(2026, 10, 1),
      );
      world.lists.items['open'] = TaskItem(
        id: 'open',
        listId: 'list-launch',
        title: 'Think about a name',
        status: 'todo',
        pos: 'c',
        createdAt: DateTime(2026, 10, 1),
      );
    }

    testWidgets('puts tasks on their day, with the undated ones apart', (
      tester,
    ) async {
      await withClock(Clock.fixed(today), () async {
        await openList(tester, prepare: prepare);
        await chooseView(tester, 'Calendar view');
        expect(find.byKey(const ValueKey('task-calendar')), findsOneWidget);
        expect(find.text('October 2026'), findsOneWidget);
        // Today, with nothing due.
        expect(find.text('No tasks due'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('task-day-2026-10-22')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('task-day-2026-10-22')));
        await settle(tester);
        expect(find.text('Send the invoice'), findsOneWidget);
        expect(find.text('Print the posters'), findsOneWidget);
        expect(find.text('Renew the licence'), findsNothing);

        // An overdue day reads as such to a screen reader.
        await tester.tap(find.byKey(const ValueKey('task-day-2026-10-15')));
        await settle(tester);
        expect(find.text('Renew the licence'), findsOneWidget);

        // The tasks without a date are listed below the days.
        await tester.dragUntilVisible(
          find.byKey(const ValueKey('task-calendar-undated')),
          find.byKey(const ValueKey('task-calendar')),
          const Offset(0, -200),
        );
        expect(find.text('No date (1)'), findsOneWidget);
        expect(find.text('Think about a name'), findsOneWidget);
      });
    });

    testWidgets('moves between months and back to today', (tester) async {
      await withClock(Clock.fixed(today), () async {
        await openList(tester, prepare: prepare);
        await chooseView(tester, 'Calendar view');
        await tester.tap(find.byKey(const ValueKey('task-calendar-next')));
        await settle(tester);
        expect(find.text('November 2026'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('task-calendar-today')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('task-calendar-today')));
        await settle(tester);
        expect(find.text('October 2026'), findsOneWidget);
      });
    });

    testWidgets('a task added for a day is due at the end of it', (
      tester,
    ) async {
      await withClock(Clock.fixed(today), () async {
        final workspace = await openList(tester, prepare: prepare);
        await chooseView(tester, 'Calendar view');
        await tester.tap(find.byKey(const ValueKey('task-day-2026-10-24')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('task-calendar-add-field')),
          'Call the printer',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
        expect(find.text('Call the printer'), findsOneWidget);
        final added = workspace.lists.items.values.firstWhere(
          (item) => item.title == 'Call the printer',
        );
        expect(added.dueAt!.year, 2026);
        expect(added.dueAt!.month, 10);
        expect(added.dueAt!.day, 24);
        expect(added.dueHasTime, isFalse);
      });
    });

    testWidgets('filters apply to the calendar', (tester) async {
      await withClock(Clock.fixed(today), () async {
        await openList(tester, prepare: prepare);
        await chooseView(tester, 'Calendar view');
        await tester.tap(find.byKey(const ValueKey('task-day-2026-10-22')));
        await settle(tester);
        expect(find.text('Send the invoice'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('task-filter-mine')));
        await settle(tester);
        expect(find.text('Send the invoice'), findsOneWidget);
        expect(find.text('Print the posters'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('task-filter-all')));
        await settle(tester);
        expect(find.text('Print the posters'), findsOneWidget);
      });
    });

    testWidgets('opens the task sheet from a day', (tester) async {
      await withClock(Clock.fixed(today), () async {
        await openList(tester, prepare: prepare);
        await chooseView(tester, 'Calendar view');
        await tester.tap(find.byKey(const ValueKey('task-day-2026-10-22')));
        await settle(tester);
        await tester.tap(find.text('Send the invoice'));
        await settle(tester);
        expect(find.byKey(const ValueKey('task-title')), findsOneWidget);
      });
    });

    testWidgets('people who cannot edit have no field to add on a day', (
      tester,
    ) async {
      await withClock(Clock.fixed(today), () async {
        await openList(
          tester,
          prepare: (world) {
            prepare(world);
            world.lists.lists['list-launch'] = TaskList(
              id: 'list-launch',
              conversationId: WorkspaceWorld.conversationId,
              title: 'Launch checklist',
              icon: 'x',
              statuses: TaskStatus.defaults,
            );
          },
        );
        await chooseView(tester, 'Calendar view');
        expect(
          find.byKey(const ValueKey('task-calendar-add-field')),
          findsNothing,
        );
      });
    });
  });

  testWidgets('the view menu switches between the three views', (tester) async {
    await openList(tester);
    expect(find.byKey(const ValueKey('task-calendar')), findsNothing);
    await chooseView(tester, 'Board view');
    expect(find.byKey(const ValueKey('board-column-todo')), findsOneWidget);
    await chooseView(tester, 'Calendar view');
    expect(find.byKey(const ValueKey('task-calendar')), findsOneWidget);
    await chooseView(tester, 'List view');
    expect(find.byKey(const ValueKey('task-add-field')), findsOneWidget);
  });
}
