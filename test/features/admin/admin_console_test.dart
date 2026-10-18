import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_report_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'admin_fakes.dart';

final _now = DateTime.utc(2026, 10, 20, 12);

Future<void> _open(
  WidgetTester tester,
  FakeAdminBackend backend, {
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: backend.overrides,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: home ?? AdminConsoleScreen(now: () => _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Types the reason of an action's first step.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('admin-reason-field')),
    text,
  );
  await tester.pump();
}

FakeAdminBackend _backend({String? role = 'moderator'}) {
  final backend = FakeAdminBackend(role: role)
    ..reports = [
      adminReportJson(
        'r-user',
        kind: 'user',
        reason: 'harassment',
        details: 'Keeps insulting me',
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
        title: 'buy my pills',
        repeat: 3,
        createdAt: '2026-10-20T09:00:00Z',
      ),
      adminReportJson(
        'r-done',
        kind: 'post',
        status: 'dismissed',
        title: 'old post',
        resolution: 'no_violation',
        handledBy: 'mia',
        createdAt: '2026-10-19T09:00:00Z',
      ),
    ];
  for (final kind in ['user', 'circle', 'post']) {
    backend.details['r-$kind'] = adminDetailJson(
      'r-$kind',
      kind: kind,
      repeat: kind == 'post' ? 3 : 1,
    );
  }
  return backend;
}

void main() {
  testWidgets('a normal user sees an empty page and no report is asked for', (
    tester,
  ) async {
    final backend = _backend(role: null);
    await _open(tester, backend);
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-report-list')), findsNothing);
    expect(backend.calls('admin_list_reports'), isEmpty);
  });

  testWidgets('the queue lists open reports and filters by kind and status', (
    tester,
  ) async {
    final backend = _backend();
    await _open(tester, backend);

    expect(find.text('Admin console'), findsOneWidget);
    expect(find.text('Moderator'), findsOneWidget);
    expect(find.text('Eve Adams (@eve)'), findsOneWidget);
    expect(find.text('Free Gift Cards'), findsOneWidget);
    expect(find.text('buy my pills'), findsOneWidget);
    expect(find.text('old post'), findsNothing);
    expect(find.text('Keeps insulting me'), findsOneWidget);
    // Three open reports about the post.
    expect(find.text('3'), findsOneWidget);
    expect(backend.calls('admin_list_reports').first['status_filter'], 'open');

    await tester.tap(find.byKey(const ValueKey('admin-kind-circle')));
    await tester.pumpAndSettle();
    expect(backend.calls('admin_list_reports').last['kind_filter'], 'circle');
    expect(find.text('Free Gift Cards'), findsOneWidget);
    expect(find.text('buy my pills'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('admin-kind-all')));
    await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    await tester.pumpAndSettle();
    expect(
      backend.calls('admin_list_reports').last['status_filter'],
      'handled',
    );
    expect(backend.calls('admin_list_reports').last['kind_filter'], isNull);
    expect(find.text('old post'), findsOneWidget);
    expect(find.text('No violation by @mia'), findsOneWidget);
  });

  testWidgets('an empty queue says so', (tester) async {
    final backend = _backend()..reports = [];
    await _open(tester, backend);
    expect(find.text('No open reports.'), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final backend = _backend()..failReports = true;
    await _open(tester, backend);
    expect(find.text('Could not load the reports.'), findsOneWidget);
    backend.failReports = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Eve Adams (@eve)'), findsOneWidget);
  });

  testWidgets('the audit log tab lists what admins did', (tester) async {
    final backend = _backend()
      ..audit = [
        adminAuditJson('a1', 'suspend_user'),
        adminAuditJson(
          'a2',
          'disable_circle',
          title: 'Free Gift Cards',
          reason: 'scam',
          extra: {'mode': 'delist'},
        ),
      ];
    await _open(tester, backend);
    await tester.tap(find.byKey(const ValueKey('admin-tab-audit')));
    await tester.pumpAndSettle();
    expect(find.text('@mia suspended @eve'), findsOneWidget);
    expect(
      find.text('@mia delisted the circle Free Gift Cards'),
      findsOneWidget,
    );
    expect(find.text('scam'), findsOneWidget);
    expect(find.text('harassment'), findsOneWidget);
  });

  group('a post report', () {
    testWidgets('shows the copy, the person, the history and the actions', (
      tester,
    ) async {
      final backend = _backend();
      backend.details['r-post'] = adminDetailJson(
        'r-post',
        kind: 'post',
        repeat: 3,
        history: [
          {
            'id': 'r-old',
            'kind': 'post',
            'reason': 'other',
            'status': 'dismissed',
            'resolution': 'no_violation',
            'created_at': '2026-10-10T00:00:00Z',
          },
        ],
        actions: [adminAuditJson('a1', 'suspend_user')],
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();

      expect(find.text('What was reported'), findsOneWidget);
      expect(find.text('buy my pills, DM me'), findsOneWidget);
      expect(find.text('Selling pills in a circle post'), findsOneWidget);
      expect(find.text('Pixel Painters'), findsOneWidget);
      expect(find.text('Eve Adams (@eve)'), findsNWidgets(2));
      expect(find.text('3 in all, 2 open'), findsOneWidget);
      expect(find.text('Other report, no violation'), findsOneWidget);
      expect(find.text('@mia suspended @eve'), findsOneWidget);
      expect(find.text('4 filed, 1 dismissed'), findsOneWidget);
      for (final key in [
        'admin-action-dismiss',
        'admin-action-handled',
        'admin-action-delete-post',
        'admin-action-suspend-person',
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('Suspend author'), findsOneWidget);
    });

    testWidgets('deleting the post asks for a reason, then asks again', (
      tester,
    ) async {
      final backend = _backend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      final delete = find.byKey(const ValueKey('admin-action-delete-post'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();

      // Step one: a reason is needed.
      expect(find.text('Delete this post?'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('admin-reason-confirm'));
      expect(tester.widget<WeCordButton>(confirm).onPressed, isNull);
      await _type(tester, 'selling drugs');
      await tester.pump();
      expect(tester.widget<WeCordButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      // Step two: nothing has happened yet.
      expect(backend.calls('admin_delete_circle_post'), isEmpty);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tester.tap(find.text('Delete post').last);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_delete_circle_post').single, {
        'target_post_id': 'subject-r-post',
        'reason': 'selling drugs',
        'report_id': 'r-post',
      });
      expect(find.text('The post was deleted.'), findsOneWidget);
    });

    testWidgets('backing out at the second step does nothing', (tester) async {
      final backend = _backend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      final delete = find.byKey(const ValueKey('admin-action-delete-post'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await _type(tester, 'x');
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_delete_circle_post'), isEmpty);
    });

    testWidgets('suspending the author goes through the admin function', (
      tester,
    ) async {
      final backend = _backend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      final suspend = find.byKey(const ValueKey('admin-action-suspend-person'));
      await tester.ensureVisible(suspend);
      await tester.tap(suspend);
      await tester.pumpAndSettle();

      expect(find.text('Suspend Eve Adams?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-length-day')));
      await _type(tester, 'spam');
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      expect(backend.functionCalls, isEmpty);
      await tester.tap(find.text('Suspend').last);
      await tester.pumpAndSettle();

      final (name, body) = backend.functionCalls.single;
      expect(name, 'admin');
      expect(body['action'], 'suspend_user');
      expect(body['user_id'], 'user-eve');
      expect(body['reason'], 'spam');
      expect(body['report_id'], 'r-post');
      expect(
        DateTime.parse(body['until'] as String).isAfter(DateTime.now()),
        isTrue,
      );
      expect(find.text('Eve Adams was suspended.'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown', (tester) async {
      final backend = _backend()
        ..functionError = const FunctionException(
          status: 403,
          details: {
            'error': 'forbidden',
            'message': 'Admins cannot be suspended',
          },
        );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      final suspend = find.byKey(const ValueKey('admin-action-suspend-person'));
      await tester.ensureVisible(suspend);
      await tester.tap(suspend);
      await tester.pumpAndSettle();
      await _type(tester, 'spam');
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend').last);
      await tester.pumpAndSettle();
      expect(find.text('Admins cannot be suspended'), findsOneWidget);
    });

    testWidgets('closing without a sanction sends the status', (tester) async {
      final backend = _backend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      final dismiss = find.byKey(const ValueKey('admin-action-dismiss'));
      await tester.ensureVisible(dismiss);
      await tester.tap(dismiss);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_resolve_report').single, {
        'target_report_id': 'r-post',
        'new_status': 'dismissed',
        'resolution': 'no_violation',
        'note': '',
      });
      expect(find.text('Report dismissed.'), findsOneWidget);
    });

    testWidgets('a picture is fetched only on request', (tester) async {
      final backend = _backend();
      backend.details['r-post'] = adminDetailJson(
        'r-post',
        snapshot: {
          'kind': 'post',
          'title': 'pic',
          'body': '',
          'author_username': 'eve',
          'author_display_name': 'Eve',
          'circle_name': 'Pixel Painters',
          'attachment': {'bucket': 'chat-media', 'path': 'c/a.png'},
        },
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      expect(backend.functionCalls, isEmpty);
      final show = find.byKey(const ValueKey('admin-show-picture'));
      await tester.ensureVisible(show);
      await tester.tap(show);
      await tester.pump();
      await tester.pump();
      expect(backend.functionCalls.single.$2, {
        'action': 'attachment_url',
        'report_id': 'r-post',
      });
      expect(
        find.byKey(const ValueKey('admin-report-picture')),
        findsOneWidget,
      );
    });
  });

  group('a circle report', () {
    testWidgets(
      'offers delist (not red) and suspend (red), both with a reason',
      (tester) async {
        final backend = _backend();
        await _open(tester, backend);
        await tester.tap(find.byKey(const ValueKey('admin-report-r-circle')));
        await tester.pumpAndSettle();
        expect(find.text('Free Gift Cards'), findsWidgets);
        expect(find.text('Click the link for free gift cards'), findsOneWidget);
        expect(find.text('Suspend owner'), findsOneWidget);

        // Delist: one step, a reason.
        final delist = find.byKey(const ValueKey('admin-action-delist'));
        await tester.ensureVisible(delist);
        await tester.tap(delist);
        await tester.pumpAndSettle();
        await _type(tester, 'misleading');
        await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
        await tester.pumpAndSettle();
        expect(backend.calls('admin_disable_circle').single, {
          'target_circle_id': 'subject-r-circle',
          'mode': 'delist',
          'reason': 'misleading',
          'report_id': 'r-circle',
        });
      },
    );

    testWidgets('suspending a circle asks twice', (tester) async {
      final backend = _backend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-circle')));
      await tester.pumpAndSettle();
      final suspend = find.byKey(const ValueKey('admin-action-suspend-circle'));
      await tester.ensureVisible(suspend);
      await tester.tap(suspend);
      await tester.pumpAndSettle();
      await _type(tester, 'illegal');
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_disable_circle'), isEmpty);
      expect(find.text('Its members lose access right away.'), findsOneWidget);
      await tester.tap(find.text('Suspend circle').last);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_disable_circle').single['mode'], 'suspend');
    });

    testWidgets('a circle that is down can be restored', (tester) async {
      final backend = _backend();
      backend.details['r-circle'] = adminDetailJson(
        'r-circle',
        kind: 'circle',
        subject: {
          'type': 'circle',
          'name': 'Free Gift Cards',
          'disabled_mode': 'delist',
        },
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-circle')));
      await tester.pumpAndSettle();
      expect(find.text('Circle delisted'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-action-delist')), findsNothing);
      final restore = find.byKey(const ValueKey('admin-action-restore-circle'));
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      // A note is optional when restoring.
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_enable_circle').single, {
        'target_circle_id': 'subject-r-circle',
        'reason': '',
      });
    });
  });

  group('a person report', () {
    testWidgets('a suspended person can have it lifted', (tester) async {
      final backend = _backend();
      backend.details['r-user'] = adminDetailJson(
        'r-user',
        kind: 'user',
        responsible: adminPersonJson(suspended: true),
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-user')));
      await tester.pumpAndSettle();
      expect(find.text('Eve Adams suspended for good'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-action-suspend-person')),
        findsNothing,
      );
      final lift = find.byKey(const ValueKey('admin-action-lift'));
      await tester.ensureVisible(lift);
      await tester.tap(lift);
      await tester.pumpAndSettle();
      await _type(tester, 'appeal accepted');
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await tester.pumpAndSettle();
      final (_, body) = backend.functionCalls.single;
      expect(body, {
        'action': 'unsuspend_user',
        'user_id': 'user-eve',
        'reason': 'appeal accepted',
      });
    });

    testWidgets('an admin cannot be suspended from here', (tester) async {
      final backend = _backend();
      backend.details['r-user'] = adminDetailJson(
        'r-user',
        kind: 'user',
        responsible: adminPersonJson(admin: true),
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-user')));
      await tester.pumpAndSettle();
      expect(find.text('Eve Adams is an admin'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-action-suspend-person')),
        findsNothing,
      );
    });

    testWidgets('support staff can only close reports', (tester) async {
      final backend = _backend(role: 'support');
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-report-r-post')));
      await tester.pumpAndSettle();
      for (final key in [
        'admin-action-delete-post',
        'admin-action-suspend-person',
        'admin-action-delist',
        'admin-action-suspend-circle',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      final dismiss = find.byKey(const ValueKey('admin-action-dismiss'));
      await tester.ensureVisible(dismiss);
      expect(dismiss, findsOneWidget);
    });

    testWidgets(
      'a closed report shows who handled it and has no close buttons',
      (tester) async {
        final backend = _backend(role: 'support');
        backend.details['r-done'] = adminDetailJson(
          'r-done',
          status: 'dismissed',
        );
        await _open(
          tester,
          backend,
          home: AdminReportScreen(reportId: 'r-done', now: () => _now),
        );
        expect(find.text('This report is closed.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin-action-dismiss')),
          findsNothing,
        );
      },
    );
  });
}
