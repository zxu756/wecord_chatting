import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'admin_fakes.dart';

final _now = DateTime.utc(2026, 10, 20, 12);

FakeAdminBackend _backend({String role = 'moderator'}) {
  final backend = FakeAdminBackend(role: role)
    ..reports = [
      adminReportJson(
        'r-user',
        kind: 'user',
        title: 'Eve Adams (@eve)',
        createdAt: '2026-10-20T11:30:00Z',
      ),
      adminReportJson(
        'r-msg',
        kind: 'message',
        reason: 'harassment',
        title: 'send me your password or else',
        createdAt: '2026-10-20T11:00:00Z',
      ),
      adminReportJson(
        'r-msg-done',
        kind: 'message',
        status: 'reviewed',
        resolution: 'message_deleted',
        title: 'older insult',
        handledBy: 'mia',
        createdAt: '2026-10-19T11:00:00Z',
      ),
    ];
  backend.details['r-msg'] = adminDetailJson('r-msg', kind: 'message');
  backend.details['r-msg-done'] = adminDetailJson(
    'r-msg-done',
    kind: 'message',
    status: 'reviewed',
  );
  return backend;
}

Future<void> _open(WidgetTester tester, FakeAdminBackend backend) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: backend.overrides,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: AdminConsoleScreen(now: () => _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMessages(
  WidgetTester tester,
  FakeAdminBackend backend,
) async {
  await _open(tester, backend);
  await tester.tap(find.byKey(const ValueKey('admin-kind-message')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('admin-report-r-msg')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  test('message is a kind of report with a label', () {
    expect(ReportKind.parse('message'), ReportKind.message);
    expect(ReportKind.message.label, 'Messages');
    expect(
      ReportResolution.parse('message_deleted'),
      ReportResolution.messageDeleted,
    );
    expect(ReportResolution.messageDeleted.label, 'Message deleted');
  });

  testWidgets('the Messages tab lists only the reports of messages', (
    tester,
  ) async {
    final backend = _backend();
    await _open(tester, backend);

    // The mixed queue is the old one.
    expect(find.text('Eve Adams (@eve)'), findsOneWidget);
    expect(find.text('send me your password or else'), findsNothing);
    expect(backend.calls('admin_list_message_reports'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('admin-kind-message')));
    await tester.pumpAndSettle();
    expect(
      backend.calls('admin_list_message_reports').single['status_filter'],
      'open',
    );
    expect(find.text('send me your password or else'), findsOneWidget);
    expect(find.text('Eve Adams (@eve)'), findsNothing);
    expect(find.text('older insult'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    await tester.pumpAndSettle();
    expect(
      backend.calls('admin_list_message_reports').last['status_filter'],
      'handled',
    );
    expect(find.text('older insult'), findsOneWidget);
    expect(find.text('Message deleted by @mia'), findsOneWidget);
  });

  testWidgets('a message report shows the copy, the context and the sender', (
    tester,
  ) async {
    final backend = _backend();
    await _openMessages(tester, backend);

    expect(backend.calls('admin_get_message_report').single, {
      'target_report_id': 'r-msg',
    });
    expect(backend.calls('admin_get_report'), isEmpty);
    expect(find.text('What was reported'), findsOneWidget);
    expect(find.text('Eve Adams (@eve)'), findsWidgets);
    expect(find.text('Group Weekend hikers'), findsOneWidget);
    expect(find.text('send me your password or else'), findsWidgets);
    expect(find.text('Photo · screenshot.jpg'), findsOneWidget);
    expect(find.text('Messages around it'), findsOneWidget);
    expect(find.text('Dee: who has the tickets?'), findsOneWidget);
    expect(find.text('Dee: please stop'), findsOneWidget);
    expect(find.text('Message is live'), findsOneWidget);
    // Dismiss, delete and suspend; "Mark as handled" is for the others.
    for (final key in [
      'admin-action-dismiss',
      'admin-action-delete-message',
      'admin-action-suspend-person',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('admin-action-handled')), findsNothing);
    expect(find.text('Suspend sender'), findsOneWidget);
  });

  testWidgets('"No violation" dismisses the report', (tester) async {
    final backend = _backend();
    await _openMessages(tester, backend);
    await _tap(tester, 'admin-action-dismiss');
    expect(backend.calls('admin_resolve_message_report').single, {
      'target_report_id': 'r-msg',
      'action': 'dismiss',
      'note': '',
    });
    expect(backend.calls('admin_resolve_report'), isEmpty);
    expect(find.text('Report dismissed.'), findsOneWidget);
  });

  testWidgets('deleting the message asks for a reason, then asks again', (
    tester,
  ) async {
    final backend = _backend();
    await _openMessages(tester, backend);
    await _tap(tester, 'admin-action-delete-message');

    expect(find.text('Delete this message?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason-field')),
      'a threat',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
    await tester.pumpAndSettle();
    expect(backend.calls('admin_resolve_message_report'), isEmpty);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    await tester.tap(find.text('Delete message').last);
    await tester.pumpAndSettle();

    expect(backend.calls('admin_resolve_message_report').single, {
      'target_report_id': 'r-msg',
      'action': 'delete_message',
      'note': 'a threat',
    });
    expect(find.text('The message was deleted.'), findsOneWidget);
  });

  testWidgets('suspending the sender suspends first, then closes the report', (
    tester,
  ) async {
    final backend = _backend();
    await _openMessages(tester, backend);
    await _tap(tester, 'admin-action-suspend-person');

    await tester.enterText(
      find.byKey(const ValueKey('admin-reason-field')),
      'threats',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend').last);
    await tester.pumpAndSettle();

    final (name, body) = backend.functionCalls.single;
    expect(name, 'admin');
    expect(body['action'], 'suspend_user');
    expect(body['user_id'], 'user-eve');
    // The suspension does not know message reports; the report is closed
    // by its own function afterwards.
    expect(body['report_id'], isNull);
    expect(backend.calls('admin_resolve_message_report').single, {
      'target_report_id': 'r-msg',
      'action': 'suspend',
      'note': 'threats',
    });
    expect(find.text('Eve Adams was suspended.'), findsOneWidget);
  });

  testWidgets('support staff can only dismiss', (tester) async {
    final backend = _backend(role: 'support');
    await _openMessages(tester, backend);
    await tester.ensureVisible(
      find.byKey(const ValueKey('admin-action-dismiss')),
    );
    expect(find.byKey(const ValueKey('admin-action-dismiss')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-action-delete-message')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('admin-action-suspend-person')),
      findsNothing,
    );
  });

  testWidgets('a handled report with its copy cleared says so', (tester) async {
    final backend = _backend();
    backend.details['r-msg'] = adminDetailJson(
      'r-msg',
      kind: 'message',
      snapshot: {},
      subject: {'type': 'message', 'deleted': true, 'missing': true},
    );
    await _openMessages(tester, backend);
    expect(
      find.text('There is no copy: what was reported no longer exists.'),
      findsOneWidget,
    );
  });
}
