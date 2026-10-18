import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/admin/admin_audit_view.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_repository.dart';

import 'admin_fakes.dart';

void main() {
  late FakeAdminBackend backend;
  late AdminRepository repository;

  setUp(() {
    backend = FakeAdminBackend();
    repository = AdminRepository(backend.rpc, backend.function);
  });

  test('the role is read from the server; anybody else has none', () async {
    expect(await repository.myRole(), AdminRole.moderator);
    backend.role = null;
    expect(await repository.myRole(), isNull);
    backend.role = 'something else';
    expect(await repository.myRole(), isNull);
  });

  test('only owners and moderators may sanction', () {
    expect(AdminRole.owner.canSanction, isTrue);
    expect(AdminRole.moderator.canSanction, isTrue);
    expect(AdminRole.support.canSanction, isFalse);
  });

  test('the queue asks for a kind, a status and a page', () async {
    backend.reports = [
      adminReportJson('r1', kind: 'user'),
      adminReportJson('r2', kind: 'post', title: 'buy my pills'),
    ];
    final posts = await repository.listReports(
      kind: ReportKind.post,
      before: DateTime.utc(2026, 10, 21),
      pageSize: 10,
    );
    expect([for (final report in posts) report.id], ['r2']);
    expect(backend.calls('admin_list_reports').single, {
      'kind_filter': 'post',
      'status_filter': 'open',
      'page_size': 10,
      'before_created_at': '2026-10-21T00:00:00.000Z',
    });
    final all = await repository.listReports(status: ReportQueueStatus.handled);
    expect(all, isEmpty);
    expect(backend.calls('admin_list_reports').last['kind_filter'], isNull);
    expect(
      backend.calls('admin_list_reports').last['status_filter'],
      'handled',
    );
  });

  test('a report row keeps what the queue shows', () {
    final report = AdminReport.fromJson(
      adminReportJson(
        'r1',
        kind: 'circle',
        reason: 'harassment',
        title: 'Free Gift Cards',
        repeat: 3,
        status: 'reviewed',
        resolution: 'circle_delisted',
        handledBy: 'mia',
      ),
    );
    expect(report.kind, ReportKind.circle);
    expect(report.title, 'Free Gift Cards');
    expect(report.reasonLabel, 'Harassment');
    expect(report.repeatCount, 3);
    expect(report.isOpen, isFalse);
    expect(report.resolution, ReportResolution.circleDelisted);
    expect(report.handledBy, 'mia');
    expect(report.reporterName, 'DEE');
  });

  test('a report detail reads its snapshot, subject and history', () {
    final detail = AdminReportDetail.fromJson(
      adminDetailJson(
        'r1',
        history: [
          {
            'id': 'r0',
            'kind': 'post',
            'reason': 'other',
            'status': 'dismissed',
            'resolution': 'no_violation',
            'created_at': '2026-10-01T00:00:00Z',
          },
        ],
        actions: [adminAuditJson('a1', 'suspend_user')],
        subject: {
          'type': 'post',
          'deleted': true,
          'circle_id': 'circle-9',
          'circle_disabled_mode': 'delist',
        },
      ),
    );
    expect(detail.snapshot['body'], 'buy my pills, DM me');
    expect(detail.postDeleted, isTrue);
    expect(detail.circleId, 'circle-9');
    expect(detail.circleMode, CircleTakedownMode.delist);
    expect(detail.responsible?.username, 'eve');
    expect(detail.responsible?.openReportsAgainst, 2);
    expect(detail.history.single.resolution, ReportResolution.noViolation);
    expect(detail.actions.single.action, 'suspend_user');
    expect(detail.reporterTotal, 4);
    expect(detail.reporterDismissed, 1);
  });

  test('closing a report sends its status and resolution', () async {
    await repository.resolveReport(
      reportId: 'r1',
      dismissed: true,
      resolution: ReportResolution.noViolation,
      note: ' fine ',
    );
    await repository.resolveReport(
      reportId: 'r2',
      dismissed: false,
      resolution: ReportResolution.other,
    );
    expect(backend.calls('admin_resolve_report').toList(), [
      {
        'target_report_id': 'r1',
        'new_status': 'dismissed',
        'resolution': 'no_violation',
        'note': 'fine',
      },
      {
        'target_report_id': 'r2',
        'new_status': 'reviewed',
        'resolution': 'other',
        'note': '',
      },
    ]);
  });

  test('banning goes through the admin function, not an RPC', () async {
    await repository.suspendUser(
      userId: 'user-eve',
      reason: ' harassment ',
      until: DateTime.utc(2026, 11, 1),
      reportId: 'r1',
    );
    await repository.unsuspendUser(userId: 'user-eve', reason: 'appeal');
    expect(
      [for (final (name, _) in backend.functionCalls) name],
      ['admin', 'admin'],
    );
    expect(
      [for (final (_, body) in backend.functionCalls) body],
      [
        {
          'action': 'suspend_user',
          'user_id': 'user-eve',
          'reason': 'harassment',
          'until': '2026-11-01T00:00:00.000Z',
          'report_id': 'r1',
        },
        {'action': 'unsuspend_user', 'user_id': 'user-eve', 'reason': 'appeal'},
      ],
    );
    expect(backend.calls('admin_suspend_user'), isEmpty);
  });

  test('circle and post actions call their RPCs', () async {
    await repository.disableCircle(
      circleId: 'c1',
      mode: CircleTakedownMode.suspend,
      reason: 'illegal',
      reportId: 'r1',
    );
    await repository.enableCircle(circleId: 'c1', reason: 'cleared');
    await repository.deletePost(postId: 'p1', reason: 'pills');
    expect(backend.calls('admin_disable_circle').single, {
      'target_circle_id': 'c1',
      'mode': 'suspend',
      'reason': 'illegal',
      'report_id': 'r1',
    });
    expect(backend.calls('admin_enable_circle').single, {
      'target_circle_id': 'c1',
      'reason': 'cleared',
    });
    expect(backend.calls('admin_delete_circle_post').single, {
      'target_post_id': 'p1',
      'reason': 'pills',
      'report_id': null,
    });
  });

  test('a suspended circle is listed for its members', () async {
    backend.takedowns = [
      {'circle_id': 'c1', 'mode': 'suspend'},
      {'circle_id': 'c2', 'mode': 'delist'},
      {'circle_id': 'c3', 'mode': 'nonsense'},
    ];
    final takedowns = await repository.myCircleTakedowns();
    expect(
      {for (final t in takedowns) t.circleId: t.mode},
      {'c1': CircleTakedownMode.suspend, 'c2': CircleTakedownMode.delist},
    );
  });

  test('the picture link comes from the function', () async {
    expect(
      await repository.attachmentUrl('r1'),
      'https://example.test/picture.png',
    );
  });

  test('audit entries read as sentences', () {
    String say(Map<String, dynamic> json) =>
        adminAuditSummary(AdminAuditEntry.fromJson(json));
    expect(say(adminAuditJson('a', 'suspend_user')), '@mia suspended @eve');
    expect(
      say(adminAuditJson('a', 'disable_circle', extra: {'mode': 'delist'})),
      '@mia delisted the circle @eve',
    );
    expect(
      say(adminAuditJson('a', 'disable_circle', extra: {'mode': 'suspend'})),
      '@mia suspended the circle @eve',
    );
    expect(
      say(
        adminAuditJson(
          'a',
          'resolve_report',
          extra: {'resolution': 'no_violation'},
        ),
      ),
      '@mia closed a report: No violation',
    );
    expect(
      say(adminAuditJson('a', 'delete_circle_post', title: 'pills')),
      '@mia deleted the post "pills"',
    );
  });
}
