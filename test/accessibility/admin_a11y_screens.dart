// The admin console screens, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the report
// queue, a report of each kind, the action dialogs, the audit log, Settings
// with the admin row and a suspended circle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circles_repository.dart';

import '../features/admin/admin_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A backend with a few reports of each kind and some audit entries.
FakeAdminBackend adminShowcaseBackend({String role = 'owner'}) {
  final backend = FakeAdminBackend(role: role)
    ..reports = [
      adminReportJson(
        'r-user',
        kind: 'user',
        reason: 'harassment',
        details: 'Keeps sending me insults after I blocked them elsewhere.',
        title: 'Eve Adams (@eve)',
        createdAt: '2026-10-20T11:30:00Z',
      ),
      adminReportJson(
        'r-circle',
        kind: 'circle',
        title: 'Free Gift Cards',
        createdAt: '2026-10-20T10:00:00Z',
      ),
      adminReportJson(
        'r-post',
        kind: 'post',
        title: 'buy my pills, DM me for prices and delivery options',
        repeat: 3,
        reason: 'unsafe_content',
        createdAt: '2026-10-20T09:00:00Z',
      ),
      adminReportJson(
        'r-spam',
        kind: 'post',
        title: 'Check out my new crypto coin',
        createdAt: '2026-10-19T09:00:00Z',
      ),
    ]
    ..audit = [
      adminAuditJson('a1', 'suspend_user', reason: 'Harassment after warning'),
      adminAuditJson(
        'a2',
        'disable_circle',
        title: 'Free Gift Cards',
        reason: 'Scam listing',
        extra: {'mode': 'delist'},
      ),
      adminAuditJson(
        'a3',
        'delete_circle_post',
        title: 'buy my pills',
        reason: 'Illegal goods',
      ),
      adminAuditJson(
        'a4',
        'resolve_report',
        title: '',
        reason: '',
        extra: {'resolution': 'no_violation'},
      ),
    ];
  backend.details['r-post'] = adminDetailJson(
    'r-post',
    kind: 'post',
    repeat: 3,
    history: [
      {
        'id': 'r-old',
        'kind': 'post',
        'reason': 'spam',
        'status': 'dismissed',
        'resolution': 'no_violation',
        'created_at': '2026-10-10T00:00:00Z',
      },
    ],
    actions: [adminAuditJson('a1', 'suspend_user')],
  );
  backend.details['r-circle'] = adminDetailJson('r-circle', kind: 'circle');
  backend.details['r-user'] = adminDetailJson('r-user', kind: 'user');
  return backend;
}

Future<void> _openConsole(WidgetTester tester, PhoneWorld world) async {
  world.extraOverrides = adminShowcaseBackend().callOverrides;
  await world.open(tester, '/admin');
}

Future<void> _openReport(
  WidgetTester tester,
  PhoneWorld world,
  String id,
) async {
  await _openConsole(tester, world);
  await tester.tap(find.byKey(ValueKey('admin-report-$id')));
  await settle(tester);
}

Future<void> _tapAction(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    action,
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('admin-report-detail')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await settle(tester);
  await tester.tap(action);
  await settle(tester);
}

final adminA11yScreens = <A11yScreen>[
  A11yScreen('admin-console', _openConsole),
  A11yScreen('admin-console-handled', (tester, world) async {
    final backend = adminShowcaseBackend()
      ..reports = [
        adminReportJson(
          'r-done',
          kind: 'post',
          status: 'dismissed',
          title: 'old post',
          resolution: 'no_violation',
          handledBy: 'mia',
        ),
        adminReportJson(
          'r-done2',
          kind: 'circle',
          status: 'reviewed',
          title: 'Free Gift Cards',
          resolution: 'circle_delisted',
          handledBy: 'mia',
        ),
      ];
    world.extraOverrides = backend.callOverrides;
    await world.open(tester, '/admin');
    await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    await settle(tester);
  }),
  A11yScreen('admin-audit-log', (tester, world) async {
    await _openConsole(tester, world);
    await tester.tap(find.byKey(const ValueKey('admin-tab-audit')));
    await settle(tester);
  }),
  A11yScreen('admin-report-post', (tester, world) async {
    await _openReport(tester, world, 'r-post');
  }),
  A11yScreen('admin-report-circle', (tester, world) async {
    await _openReport(tester, world, 'r-circle');
  }),
  A11yScreen('admin-report-user', (tester, world) async {
    await _openReport(tester, world, 'r-user');
  }),
  A11yScreen('admin-suspend-dialog', (tester, world) async {
    await _openReport(tester, world, 'r-user');
    await _tapAction(tester, 'admin-action-suspend-person');
  }),
  A11yScreen('admin-suspend-confirm', (tester, world) async {
    await _openReport(tester, world, 'r-user');
    await _tapAction(tester, 'admin-action-suspend-person');
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason-field')),
      'Harassment after a warning',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
    await settle(tester);
  }),
  A11yScreen('admin-circle-suspended', (tester, world) async {
    final backend = adminShowcaseBackend()
      ..takedowns = [
        {'circle_id': 'circle-1', 'mode': 'suspend'},
      ];
    world.extraOverrides = backend.callOverrides;
    world.circles.detailError = const CircleMembershipLostException('circle-1');
    await world.open(tester, '/circles/circle-1');
  }),
  A11yScreen('settings-admin-row', (tester, world) async {
    world.extraOverrides = adminShowcaseBackend().callOverrides;
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-admin-console')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
];
