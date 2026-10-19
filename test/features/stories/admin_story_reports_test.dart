import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../admin/admin_fakes.dart';
import 'stories_fakes.dart';

final _now = DateTime.utc(2026, 10, 24, 12);

/// The admin backend with the three calls for reports of dailies.
class StoryAdminBackend extends FakeAdminBackend {
  StoryAdminBackend({super.role});

  var storyReports = <Map<String, dynamic>>[];
  final storyDetails = <String, Map<String, dynamic>>{};

  @override
  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    switch (name) {
      case 'admin_list_story_reports':
        rpcCalls.add((name, params));
        final status = params['status_filter'] as String?;
        return [
          for (final report in storyReports)
            if (status == 'handled'
                ? report['status'] != 'open'
                : report['status'] == 'open')
              report,
        ];
      case 'admin_get_story_report':
        rpcCalls.add((name, params));
        return storyDetails[params['target_report_id']];
      case 'admin_resolve_story_report':
        rpcCalls.add((name, params));
        return {'status': 'reviewed'};
    }
    return super.rpc(name, params);
  }
}

Map<String, dynamic> _detail(
  String id, {
  bool live = true,
  bool deleted = false,
  String status = 'open',
}) {
  final base = adminDetailJson(id, kind: 'message', status: status);
  return {
    ...base,
    'report': {
      ...(base['report'] as Map<String, dynamic>),
      'kind': 'story',
      'title': 'Sunrise run',
      'snapshot': {
        'title': 'Sunrise run',
        'caption': 'Sunrise run, buy my pills',
        'media_kind': 'photo',
        'author_id': 'user-eve',
        'author_username': 'eve',
        'author_name': 'Eve Adams',
        'created_at': '2026-10-24T08:00:00Z',
        'thumb_path': 'user-eve/s-t.jpg',
      },
    },
    'subject': {
      'type': 'story',
      'id': 'subject-$id',
      'deleted': deleted,
      'missing': deleted,
      'live': live,
      'media_kind': 'photo',
      'thumb_path': 'user-eve/s-t.jpg',
    },
  };
}

StoryAdminBackend _backend({String role = 'moderator'}) {
  final backend = StoryAdminBackend(role: role)
    ..reports = [
      adminReportJson('r-user', kind: 'user', title: 'Eve Adams (@eve)'),
    ]
    ..storyReports = [
      adminReportJson('r-story', kind: 'story', title: 'Sunrise run'),
      adminReportJson(
        'r-story-done',
        kind: 'story',
        status: 'reviewed',
        resolution: 'story_deleted',
        title: 'Older daily',
        handledBy: 'mia',
      ),
    ];
  backend.storyDetails['r-story'] = _detail('r-story');
  backend.storyDetails['r-story-done'] = _detail(
    'r-story-done',
    live: false,
    deleted: true,
    status: 'reviewed',
  );
  return backend;
}

Future<void> _open(WidgetTester tester, StoryAdminBackend backend) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...backend.overrides,
        ...storiesOverrides(repository: FakeStoriesRepository()),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: AdminConsoleScreen(now: () => _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openStoryReport(
  WidgetTester tester,
  StoryAdminBackend backend,
) async {
  await _open(tester, backend);
  await tester.tap(find.byKey(const ValueKey('admin-kind-story')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('admin-report-r-story')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('a daily is a kind of report with a label', () {
    expect(ReportKind.parse('story'), ReportKind.story);
    expect(ReportKind.story.label, 'Dailies');
    expect(ReportKind.story.singular, 'Daily');
    expect(
      ReportResolution.parse('story_deleted'),
      ReportResolution.storyDeleted,
    );
    expect(ReportResolution.storyDeleted.label, 'Daily deleted');
  });

  testWidgets('the Dailies tab lists only the reports of dailies', (
    tester,
  ) async {
    final backend = _backend();
    await _open(tester, backend);
    expect(find.text('Eve Adams (@eve)'), findsOneWidget);
    expect(backend.calls('admin_list_story_reports'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('admin-kind-story')));
    await tester.pumpAndSettle();
    expect(
      backend.calls('admin_list_story_reports').single['status_filter'],
      'open',
    );
    expect(find.text('Sunrise run'), findsOneWidget);
    expect(find.text('Eve Adams (@eve)'), findsNothing);
    expect(find.text('Older daily'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    await tester.pumpAndSettle();
    expect(find.text('Older daily'), findsOneWidget);
  });

  testWidgets(
    'a report of a daily shows the copy, the picture and the author',
    (tester) async {
      final backend = _backend();
      await _openStoryReport(tester, backend);

      expect(backend.calls('admin_get_story_report').single, {
        'target_report_id': 'r-story',
      });
      expect(backend.calls('admin_get_report'), isEmpty);
      expect(find.text('What was reported'), findsOneWidget);
      expect(find.text('Eve Adams (@eve)'), findsWidgets);
      expect(find.text('Sunrise run, buy my pills'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-story-picture')), findsOneWidget);
      expect(find.text('Daily is live'), findsOneWidget);
      for (final key in [
        'admin-action-dismiss',
        'admin-action-delete-story',
        'admin-action-suspend-person',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      // "Mark as handled" belongs to the other kinds.
      expect(find.byKey(const ValueKey('admin-action-handled')), findsNothing);
      expect(find.text('Suspend author'), findsOneWidget);
    },
  );

  testWidgets('dismissing closes it as no violation', (tester) async {
    final backend = _backend();
    await _openStoryReport(tester, backend);
    await _tap(tester, 'admin-action-dismiss');

    expect(backend.calls('admin_resolve_story_report').single, {
      'target_report_id': 'r-story',
      'action': 'dismiss',
      'note': '',
    });
    expect(backend.calls('admin_resolve_report'), isEmpty);
  });

  testWidgets('deleting the daily asks for a reason and then to confirm', (
    tester,
  ) async {
    final backend = _backend();
    await _openStoryReport(tester, backend);
    await _tap(tester, 'admin-action-delete-story');

    expect(find.text('Delete this daily?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Selling pills');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('This cannot be undone.'), findsOneWidget);
    await tester.tap(find.text('Delete daily').last);
    await tester.pumpAndSettle();

    expect(backend.calls('admin_resolve_story_report').single, {
      'target_report_id': 'r-story',
      'action': 'delete_story',
      'note': 'Selling pills',
    });
  });

  testWidgets('support staff can dismiss but not sanction', (tester) async {
    final backend = _backend(role: 'support');
    await _openStoryReport(tester, backend);
    expect(find.byKey(const ValueKey('admin-action-dismiss')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-action-delete-story')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('admin-action-suspend-person')),
      findsNothing,
    );
  });

  testWidgets('a daily that has ended has nothing left to delete', (
    tester,
  ) async {
    final backend = _backend();
    await _open(tester, backend);
    await tester.tap(find.byKey(const ValueKey('admin-kind-story')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-report-r-story-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-story-picture')), findsNothing);
    expect(find.text('The daily has ended or was deleted.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-action-delete-story')),
      findsNothing,
    );
  });
}
