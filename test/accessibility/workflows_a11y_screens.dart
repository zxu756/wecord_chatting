// Workflow automation (D9), for the accessibility guard (guidelines_test.dart)
// and the screenshot tools: the list of a circle's and a group's workflows
// (running, paused by the system, failed last time, empty), the editor (new,
// a keyword workflow with two steps, a schedule, an edit with its run log and
// delete rows) and the run log, at large text, narrow and with Care mode on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/workflows/workflow_editor_page.dart';
import 'package:wecord/features/workflows/workflow_list_page.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/features/workflows/workflow_runs_page.dart';

import '../features/workflows/workflow_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _circle = WorkflowScope.circle('circle-1');
const _group = WorkflowScope.group('group-1');

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

FakeWorkflowRepository _sample({bool circle = true, bool empty = false}) {
  if (empty) {
    return FakeWorkflowRepository();
  }
  final scopeCircle = circle ? 'circle-1' : null;
  final scopeGroup = circle ? null : 'group-1';
  return FakeWorkflowRepository(
    workflows: [
      sampleWorkflow(
        'w1',
        'Welcome new members',
        circleId: scopeCircle,
        conversationId: scopeGroup,
        runsToday: 12,
        actions: [
          WorkflowAction(WorkflowActionKind.sendMessage, {
            if (circle) 'channel_id': 'ch-1',
            'text': 'Welcome, {member}! Read the rules first.',
          }),
          const WorkflowAction(WorkflowActionKind.sendDm, {
            'text': 'Say hi in #general when you are ready.',
          }),
          if (circle)
            const WorkflowAction(WorkflowActionKind.addRole, {
              'role_id': 'role-1',
            }),
        ],
      ),
      sampleWorkflow(
        'w2',
        'Friday report',
        circleId: scopeCircle,
        conversationId: scopeGroup,
        trigger: const WorkflowTrigger(WorkflowTriggerKind.schedule, {
          'recurrence': 'weekly',
          'day': 5,
          'time': '17:00',
          'zone': 'Asia/Shanghai',
        }),
        actions: [
          WorkflowAction(WorkflowActionKind.sendForm, {
            if (circle) 'channel_id': 'ch-2',
            'form_id': 'form-1',
            'date_in_title': true,
            'deadline_days': 7,
          }),
        ],
        enabled: false,
        pausedReason: WorkflowPauseReason.creatorLostPermission,
      ),
      sampleWorkflow(
        'w3',
        'Thank you for the thumbs up on a very long title that wraps around',
        circleId: scopeCircle,
        conversationId: scopeGroup,
        trigger: WorkflowTrigger(WorkflowTriggerKind.reaction, {
          'emoji': '👍',
          if (circle) 'channel_id': 'ch-2',
        }),
        lastStatus: 'failed',
      ),
      sampleWorkflow(
        'w4',
        'Refund questions',
        circleId: scopeCircle,
        conversationId: scopeGroup,
        trigger: const WorkflowTrigger(WorkflowTriggerKind.keyword, {
          'words': ['refund', 'price', 'invoice'],
        }),
        enabled: false,
        pausedReason: WorkflowPauseReason.manual,
      ),
    ],
  );
}

Future<void> _list(
  WidgetTester tester,
  PhoneWorld world, {
  bool circle = true,
  bool empty = false,
}) async {
  world.extraOverrides = [
    ...world.extraOverrides,
    ...workflowOverrides(_sample(circle: circle, empty: empty)),
  ];
  await pumpStandalone(
    tester,
    world,
    WorkflowListPage(scope: circle ? _circle : _group),
  );
  await settle(tester);
}

Future<void> _editor(
  WidgetTester tester,
  PhoneWorld world, {
  bool circle = true,
  String? edit,
  bool keyword = false,
  bool schedule = false,
}) async {
  final repository = _sample(circle: circle);
  world.extraOverrides = [
    ...world.extraOverrides,
    ...workflowOverrides(repository),
  ];
  Workflow? workflow;
  if (edit != null) {
    workflow = repository.items.firstWhere((w) => w.id == edit);
  }
  await pumpStandalone(
    tester,
    world,
    WorkflowEditorPage(scope: circle ? _circle : _group, workflow: workflow),
  );
  await settle(tester);
  if (keyword) {
    await tester.enterText(
      find.byKey(const ValueKey('workflow-name-field')),
      'Refund questions',
    );
    await tester.tap(find.byKey(const ValueKey('workflow-trigger-kind')));
    await settle(tester);
    await tester.tap(find.text('A message has a keyword').last);
    await settle(tester);
    await _reach(tester, 'workflow-words-field');
    await tester.enterText(
      find.byKey(const ValueKey('workflow-words-field')),
      'refund, price',
    );
    await _reach(tester, 'workflow-action-0-text');
    await tester.enterText(
      find.byKey(const ValueKey('workflow-action-0-text')),
      'A moderator will answer soon.',
    );
    await _reach(tester, 'workflow-add-action');
    await tester.tap(find.byKey(const ValueKey('workflow-add-action')));
    await settle(tester);
    await _reach(tester, 'workflow-action-1-kind');
    await tester.tap(find.byKey(const ValueKey('workflow-action-1-kind')));
    await settle(tester);
    await tester.tap(find.text('Create a task').last);
    await settle(tester);
    await _reach(tester, 'workflow-action-1-from-message');
    await tester.tap(
      find.byKey(const ValueKey('workflow-action-1-from-message')),
    );
    await settle(tester);
  }
  if (schedule) {
    await tester.enterText(
      find.byKey(const ValueKey('workflow-name-field')),
      'Friday report',
    );
    await tester.tap(find.byKey(const ValueKey('workflow-trigger-kind')));
    await settle(tester);
    await tester.tap(find.text('On a schedule').last);
    await settle(tester);
  }
}

Future<void> _reach(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('workflow-enabled')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Future<void> _runs(WidgetTester tester, PhoneWorld world) async {
  final repository = _sample();
  final now = DateTime.now();
  repository.runsById['w1'] = [
    WorkflowRun(
      id: 'r1',
      status: 'succeeded',
      createdAt: now.subtract(const Duration(minutes: 3)),
      actorName: 'Grace',
      steps: const [
        WorkflowStep(action: 'send_message', status: 'ok'),
        WorkflowStep(action: 'send_dm', status: 'ok'),
        WorkflowStep(action: 'add_role', status: 'ok'),
      ],
    ),
    WorkflowRun(
      id: 'r2',
      status: 'succeeded',
      createdAt: now.subtract(const Duration(hours: 2)),
      actorName: 'Linus',
      steps: const [
        WorkflowStep(action: 'send_message', status: 'ok'),
        WorkflowStep(
          action: 'send_dm',
          status: 'skipped',
          detail: 'not_friends',
        ),
        WorkflowStep(action: 'add_role', status: 'skipped', detail: 'has_role'),
      ],
    ),
    WorkflowRun(
      id: 'r3',
      status: 'failed',
      createdAt: now.subtract(const Duration(hours: 5)),
      actorName: 'Mei',
      steps: const [
        WorkflowStep(action: 'send_message', status: 'failed', detail: 'x'),
      ],
    ),
    WorkflowRun(
      id: 'r4',
      status: 'skipped',
      skipReason: 'creator_lost_permission',
      createdAt: now.subtract(const Duration(days: 1)),
      actorName: 'Tomás',
    ),
    WorkflowRun(
      id: 'r5',
      status: 'skipped',
      skipReason: 'daily_limit',
      createdAt: now.subtract(const Duration(days: 2)),
    ),
  ];
  world.extraOverrides = [
    ...world.extraOverrides,
    ...workflowOverrides(repository),
  ];
  await pumpStandalone(
    tester,
    world,
    WorkflowRunsPage(workflow: repository.items.first),
  );
  await settle(tester);
}

final workflowsA11yScreens = <A11yScreen>[
  A11yScreen('workflows-list', (tester, world) => _list(tester, world)),
  A11yScreen(
    'workflows-list-large-text',
    (tester, world) => _list(tester, world),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'workflows-list-narrow',
    (tester, world) => _list(tester, world),
    viewport: smallPhone,
  ),
  A11yScreen(
    'workflows-list-group',
    (tester, world) => _list(tester, world, circle: false),
  ),
  A11yScreen(
    'workflows-list-empty',
    (tester, world) => _list(tester, world, empty: true),
  ),
  A11yScreen('workflows-list-care-mode', (tester, world) {
    _care(world);
    return _list(tester, world);
  }),
  A11yScreen('workflows-editor-new', (tester, world) => _editor(tester, world)),
  A11yScreen(
    'workflows-editor-keyword',
    (tester, world) => _editor(tester, world, keyword: true),
  ),
  A11yScreen(
    'workflows-editor-keyword-large-text',
    (tester, world) => _editor(tester, world, keyword: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'workflows-editor-keyword-narrow',
    (tester, world) => _editor(tester, world, keyword: true),
    viewport: smallPhone,
  ),
  A11yScreen(
    'workflows-editor-schedule',
    (tester, world) => _editor(tester, world, schedule: true),
  ),
  A11yScreen(
    'workflows-editor-schedule-narrow',
    (tester, world) => _editor(tester, world, schedule: true),
    viewport: smallPhone,
  ),
  A11yScreen(
    'workflows-editor-group',
    (tester, world) => _editor(tester, world, circle: false),
  ),
  A11yScreen('workflows-editor-edit', (tester, world) async {
    await _editor(tester, world, edit: 'w1');
    await _scrollToEnd(tester);
  }),
  A11yScreen('workflows-editor-edit-large-text', (tester, world) async {
    await _editor(tester, world, edit: 'w1');
    await _scrollToEnd(tester);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('workflows-editor-care-mode', (tester, world) {
    _care(world);
    return _editor(tester, world, edit: 'w2');
  }),
  A11yScreen('workflows-runs', _runs),
  A11yScreen(
    'workflows-runs-large-text',
    _runs,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('workflows-runs-narrow', _runs, viewport: smallPhone),
  A11yScreen(
    'desktop-workflows-list',
    (tester, world) => _list(tester, world),
    viewport: desktopViewport,
    desktop: true,
  ),
];
