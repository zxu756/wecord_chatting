import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/workflows/workflow_editor_page.dart';
import 'package:wecord/features/workflows/workflow_list_page.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/features/workflows/workflow_runs_page.dart';
import 'package:wecord/features/workflows/workflow_summary.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'workflow_fakes.dart';

const circle = WorkflowScope.circle('circle-1');
const groupScope = WorkflowScope.group('group-1');

Widget host(FakeWorkflowRepository repository, Widget page) {
  return ProviderScope(
    retry: (count, error) => null,
    overrides: workflowOverrides(repository),
    child: MaterialApp(theme: WeCordTheme.light(), home: page),
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pick(WidgetTester tester, String key, String option) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
  await tester.tap(find.text(option).last);
  await settle(tester);
}

void main() {
  group('models', () {
    test('a workflow reads the server', () {
      final workflow = Workflow.fromJson({
        'id': 'w1',
        'circle_id': 'c1',
        'conversation_id': null,
        'name': 'Welcome',
        'trigger': {'kind': 'member_joined', 'config': {}},
        'actions': [
          {'type': 'send_message', 'channel_id': 'ch', 'text': 'Hi'},
          {'type': 'nonsense'},
        ],
        'enabled': false,
        'paused_reason': 'creator_lost_permission',
        'created_by': {'id': 'u1', 'name': 'Ada'},
        'created_by_me': true,
        'next_run_at': null,
        'last_run_at': '2026-10-27T01:00:00Z',
        'runs_today': 3,
        'last_status': 'failed',
      })!;
      expect(workflow.actions.length, 1, reason: 'unknown steps are dropped');
      expect(workflow.actions.single.text, 'Hi');
      expect(workflow.pausedReason, WorkflowPauseReason.creatorLostPermission);
      expect(workflow.needsAttention, isTrue);
      expect(workflow.creatorName, 'Ada');
      expect(workflow.lastRunAt, isNotNull);
      expect(workflow.runsToday, 3);
    });

    test('a workflow with an unknown trigger is left out of the list', () {
      final list = WorkflowList.fromJson({
        'can_manage': true,
        'limits': {'max_per_circle': 7},
        'workflows': [
          {
            'id': 'w1',
            'name': 'x',
            'trigger': {'kind': 'telepathy', 'config': {}},
            'actions': [],
            'enabled': true,
          },
          {
            'id': 'w2',
            'name': 'y',
            'trigger': {
              'kind': 'schedule',
              'config': {'time': '08:30'},
            },
            'actions': [],
            'enabled': true,
          },
        ],
      });
      expect(list.workflows.map((w) => w.id), ['w2']);
      expect(list.limits.maxPerCircle, 7);
      expect(list.limits.maxPerGroup, 5);
    });

    test('a manual pause is not something that needs attention', () {
      final workflow = sampleWorkflow(
        'w',
        'n',
        enabled: false,
        pausedReason: WorkflowPauseReason.manual,
      );
      expect(workflow.needsAttention, isFalse);
    });

    test('the server refusals become messages', () {
      WorkflowFailureKind kind(String message, [String? code]) =>
          WorkflowException.fromPostgrest(
            PostgrestException(message: message, code: code),
          ).kind;
      expect(kind('workflow_limit_reached'), WorkflowFailureKind.limitReached);
      expect(kind('workflow_form_invalid'), WorkflowFailureKind.formInvalid);
      expect(kind('workflow_role_invalid'), WorkflowFailureKind.roleInvalid);
      expect(kind('workflow_not_found'), WorkflowFailureKind.gone);
      expect(kind('nope', '42501'), WorkflowFailureKind.notAllowed);
      expect(kind('boom'), WorkflowFailureKind.other);
      for (final k in WorkflowFailureKind.values) {
        expect(WorkflowException(k).message, isNotEmpty);
      }
    });

    test('a run explains why it was skipped and which step was held back', () {
      final run = WorkflowRun.fromJson({
        'id': 'r1',
        'status': 'succeeded',
        'results': [
          {'action': 'send_message', 'status': 'ok'},
          {'action': 'send_dm', 'status': 'skipped', 'detail': 'not_friends'},
        ],
        'created_at': '2026-10-27T01:00:00Z',
        'actor': {'id': 'u2', 'name': 'Bo'},
      });
      expect(run.steps.length, 2);
      expect(run.steps.last.kind, WorkflowActionKind.sendDm);
      expect(run.actorName, 'Bo');
      expect(workflowStepDetail('not_friends'), contains('friends'));
      final skipped = WorkflowRun.fromJson({
        'id': 'r2',
        'status': 'skipped',
        'skip_reason': 'daily_limit',
        'created_at': '2026-10-27T01:00:00Z',
      });
      expect(skipped.reasonLabel, contains('limit'));
    });

    test('the unknown names do not break the summaries', () {
      final action = WorkflowAction.fromJson({
        'type': 'add_role',
        'role_id': 'role-9',
      })!;
      expect(
        workflowActionSummary(action, sampleWorkflowOptions()),
        'Give a role',
      );
      expect(WorkflowAction.fromJson({'type': 'x'}), isNull);
      expect(WorkflowTrigger.fromJson('x'), isNull);
    });
  });

  group('list', () {
    testWidgets('lists the workflows with what starts them and their state', (
      tester,
    ) async {
      tall(tester);
      final repository = FakeWorkflowRepository(
        workflows: [
          sampleWorkflow('w1', 'Welcome'),
          sampleWorkflow(
            'w2',
            'Friday form',
            trigger: const WorkflowTrigger(WorkflowTriggerKind.schedule, {
              'recurrence': 'weekly',
              'day': 5,
              'time': '17:00',
              'zone': 'UTC',
            }),
            enabled: false,
            pausedReason: WorkflowPauseReason.creatorLostPermission,
          ),
          sampleWorkflow(
            'w3',
            'Thanks',
            trigger: const WorkflowTrigger(WorkflowTriggerKind.reaction, {
              'emoji': '👍',
              'channel_id': 'ch-2',
            }),
            lastStatus: 'failed',
          ),
        ],
      );
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: circle)),
      );
      await settle(tester);

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.textContaining('When someone joins'), findsOneWidget);
      expect(find.textContaining('Every Friday'), findsOneWidget);
      expect(find.textContaining('17:00'), findsOneWidget);
      expect(
        find.textContaining('the person who made it can no longer manage'),
        findsOneWidget,
      );
      expect(find.textContaining('reacts with 👍 in general'), findsOneWidget);
      expect(find.textContaining('The last run failed'), findsOneWidget);
    });

    testWidgets('an empty place invites the first workflow', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: groupScope)),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('workflow-empty')), findsOneWidget);
      expect(find.textContaining('Up to 5 workflows'), findsOneWidget);
    });

    testWidgets('the switch pauses and resumes', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository(
        workflows: [sampleWorkflow('w1', 'Welcome')],
      );
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: circle)),
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('workflow-switch-w1')));
      await settle(tester);
      expect(repository.calls, contains('pause'));
      expect(repository.items.single.enabled, isFalse);
      expect(find.textContaining('Paused'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workflow-switch-w1')));
      await settle(tester);
      expect(repository.calls, contains('resume'));
      expect(find.textContaining('Running'), findsOneWidget);
    });

    testWidgets('someone who cannot manage sees why', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository(canManage: false);
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: circle)),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('workflow-list-error')), findsOneWidget);
      expect(find.text("You can't manage workflows here."), findsOneWidget);
      expect(find.byKey(const ValueKey('workflow-add')), findsNothing);
    });

    testWidgets('the plus opens an empty editor', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: circle)),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('workflow-add')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('workflow-editor-page')),
        findsOneWidget,
      );
    });
  });

  group('editor', () {
    testWidgets('saves a welcome workflow of a circle', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowEditorPage(scope: circle)),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('workflow-name-field')),
        'Welcome',
      );
      await tester.enterText(
        find.byKey(const ValueKey('workflow-action-0-text')),
        'Hi {member}',
      );
      await tester.tap(find.byKey(const ValueKey('workflow-save')));
      await settle(tester);

      final saved = repository.lastSave!;
      expect(saved.id, isNull);
      expect(saved.name, 'Welcome');
      expect(saved.enabled, isTrue);
      expect(saved.trigger.kind, WorkflowTriggerKind.memberJoined);
      expect(saved.actions.single.kind, WorkflowActionKind.sendMessage);
      expect(saved.actions.single.text, 'Hi {member}');
      expect(
        saved.actions.single.channelId,
        'ch-1',
        reason: 'a circle step with no channel picked uses the first one',
      );
    });

    testWidgets('a keyword trigger and a second step', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowEditorPage(scope: circle)),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('workflow-name-field')),
        'Refunds',
      );
      await pick(tester, 'workflow-trigger-kind', 'A message has a keyword');
      await tester.enterText(
        find.byKey(const ValueKey('workflow-words-field')),
        'refund, price，  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('workflow-action-0-text')),
        'We will help',
      );
      await tester.tap(find.byKey(const ValueKey('workflow-add-action')));
      await settle(tester);
      await pick(tester, 'workflow-action-1-kind', 'Create a task');
      await tester.tap(
        find.byKey(const ValueKey('workflow-action-1-from-message')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('workflow-save')));
      await settle(tester);

      final saved = repository.lastSave!;
      expect(saved.trigger.kind, WorkflowTriggerKind.keyword);
      expect(saved.trigger.words, ['refund', 'price']);
      expect(saved.actions.length, 2);
      expect(
        saved.actions[0].channelId,
        isNull,
        reason: 'a keyword may answer where it happened',
      );
      expect(saved.actions[1].kind, WorkflowActionKind.createTask);
      expect(saved.actions[1].fromMessage, isTrue);
    });

    testWidgets('a group has no channels or roles to pick', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowEditorPage(scope: groupScope)),
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey('workflow-action-0-channel')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('workflow-action-0-kind')));
      await settle(tester);
      expect(find.text('Give a role'), findsNothing);
      expect(find.text('Send a form'), findsOneWidget);
    });

    testWidgets('the server refusal is shown and nothing closes', (
      tester,
    ) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowEditorPage(scope: circle)),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('workflow-save')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('workflow-editor-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workflow-editor-page')),
        findsOneWidget,
      );
    });

    testWidgets('a schedule builds the weekday, time and zone', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository();
      await tester.pumpWidget(
        host(repository, const WorkflowEditorPage(scope: groupScope)),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('workflow-name-field')),
        'Friday',
      );
      await pick(tester, 'workflow-trigger-kind', 'On a schedule');
      await pick(tester, 'workflow-trigger-day', 'Friday');
      await tester.enterText(
        find.byKey(const ValueKey('workflow-action-0-text')),
        'Weekly report is due',
      );
      await tester.tap(find.byKey(const ValueKey('workflow-save')));
      await settle(tester);

      final trigger = repository.lastSave!.trigger;
      expect(trigger.kind, WorkflowTriggerKind.schedule);
      expect(trigger.recurrence, 'weekly');
      expect(trigger.day, 5);
      expect(trigger.time, '09:00');
      expect(trigger.zone, isNotEmpty);
    });

    testWidgets('editing keeps the id, and a workflow can be deleted', (
      tester,
    ) async {
      tall(tester);
      final repository = FakeWorkflowRepository(
        workflows: [sampleWorkflow('w1', 'Welcome')],
      );
      final workflow = repository.items.single;
      await tester.pumpWidget(
        host(repository, WorkflowEditorPage(scope: circle, workflow: workflow)),
      );
      await settle(tester);
      expect(find.text('Welcome'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('workflow-name-field')),
        'Welcome 2',
      );
      await tester.tap(find.byKey(const ValueKey('workflow-save')));
      await settle(tester);
      expect(repository.lastSave!.id, 'w1');
      expect(repository.items.single.name, 'Welcome 2');
    });

    testWidgets('delete asks first', (tester) async {
      tall(tester);
      final repository = FakeWorkflowRepository(
        workflows: [sampleWorkflow('w1', 'Welcome')],
      );
      await tester.pumpWidget(
        host(
          repository,
          WorkflowEditorPage(scope: circle, workflow: repository.items.single),
        ),
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('workflow-delete')));
      await tester.tap(find.byKey(const ValueKey('workflow-delete')));
      await settle(tester);
      expect(find.text('Delete this workflow?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(repository.items, isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('workflow-delete')));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(repository.items, isEmpty);
    });
  });

  group('run log', () {
    testWidgets('shows each run with its reasons', (tester) async {
      tall(tester);
      final workflow = sampleWorkflow(
        'w1',
        'Welcome',
        enabled: false,
        pausedReason: WorkflowPauseReason.failures,
      );
      final repository = FakeWorkflowRepository(workflows: [workflow]);
      final now = DateTime.now();
      repository.runsById['w1'] = [
        WorkflowRun(
          id: 'r1',
          status: 'succeeded',
          createdAt: now,
          actorName: 'Bo',
          steps: const [
            WorkflowStep(action: 'send_message', status: 'ok'),
            WorkflowStep(
              action: 'send_dm',
              status: 'skipped',
              detail: 'not_friends',
            ),
          ],
        ),
        WorkflowRun(
          id: 'r2',
          status: 'failed',
          createdAt: now.subtract(const Duration(hours: 1)),
          steps: const [
            WorkflowStep(action: 'add_role', status: 'failed', detail: 'boom'),
          ],
        ),
        WorkflowRun(
          id: 'r3',
          status: 'skipped',
          skipReason: 'daily_limit',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ];
      await tester.pumpWidget(
        host(repository, WorkflowRunsPage(workflow: workflow)),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('workflow-run-r1')), findsOneWidget);
      expect(
        find.textContaining('Direct messages only go to friends'),
        findsOneWidget,
      );
      expect(find.textContaining('This step did not finish'), findsNothing);
      expect(find.textContaining('after it failed 5 times'), findsOneWidget);
      expect(find.textContaining('daily limit'), findsOneWidget);
      // The server's own error text never reaches the screen.
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('a workflow that has not run says so', (tester) async {
      tall(tester);
      final workflow = sampleWorkflow('w1', 'Welcome');
      final repository = FakeWorkflowRepository(workflows: [workflow]);
      await tester.pumpWidget(
        host(repository, WorkflowRunsPage(workflow: workflow)),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('workflow-runs-empty')), findsOneWidget);
    });
  });

  group('Chinese', () {
    testWidgets('the list reads in Chinese', (tester) async {
      tall(tester);
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      final repository = FakeWorkflowRepository(
        workflows: [sampleWorkflow('w1', 'Welcome')],
      );
      await tester.pumpWidget(
        host(repository, const WorkflowListPage(scope: circle)),
      );
      await settle(tester);
      expect(find.text('工作流'), findsOneWidget);
      expect(find.textContaining('有人加入时'), findsOneWidget);
    });
  });
}
