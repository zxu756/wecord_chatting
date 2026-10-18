import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../circles/ai_guard_fakes.dart';
import 'report_fakes.dart';

DateTime _now() => DateTime.utc(2026, 10, 20, 12);

Future<void> _open(
  WidgetTester tester, {
  required FakeReportRpc reports,
  FakeGuardRpc? guard,
}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final guardRpc = guard ?? FakeGuardRpc();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...reports.overrides,
        circleAiGuardRepositoryProvider.overrideWithValue(
          CircleAiGuardRepository(guardRpc),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: CircleReviewScreen(circleId: 'circle-1', now: _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  FakeReportRpc reportsWith(List<Map<String, dynamic>> list) => FakeReportRpc()
    ..results['list_circle_message_reports'] = list
    ..results['resolve_message_report'] = {'status': 'actioned'};

  testWidgets('user reports come first, with a red count', (tester) async {
    final guard = FakeGuardRpc()
      ..results['list_message_reviews'] = [reviewJson()]
      ..results['count_message_reviews'] = 3;
    await _open(
      tester,
      reports: reportsWith([
        circleReportJson(),
        circleReportJson(id: 'report-2', body: 'second one'),
      ]),
      guard: guard,
    );

    expect(find.text('User reports'), findsOneWidget);
    expect(find.text('Held or flagged by the AI guard'), findsOneWidget);
    // Two reports, one held message.
    final badges = tester.widgetList<CountBadge>(find.byType(CountBadge));
    expect(badges.map((badge) => badge.count), [2, 1]);
    expect(badges.every((badge) => badge.tone == BadgeTone.mention), isTrue);
    expect(
      tester.getTopLeft(find.text('User reports')).dy,
      lessThan(
        tester.getTopLeft(find.text('Held or flagged by the AI guard')).dy,
      ),
    );
    expect(find.text('Win cheap pills at pills.example'), findsOneWidget);
    expect(find.text('second one'), findsOneWidget);
    expect(find.text('Cheap pills at pills.example'), findsOneWidget);
  });

  testWidgets('a report shows who, why, where and when', (tester) async {
    await _open(
      tester,
      reports: reportsWith([
        circleReportJson(
          reason: 'harassment',
          details: 'sent it to me twice',
          repeat: 3,
        ),
      ]),
    );

    expect(find.text('Eve'), findsOneWidget);
    expect(find.text('#general · 30m ago'), findsOneWidget);
    expect(find.text('Harassment'), findsOneWidget);
    expect(find.text('Reported by Dee and 2 others'), findsOneWidget);
    expect(find.text('“sent it to me twice”'), findsOneWidget);
  });

  testWidgets('a single report names its reporter', (tester) async {
    await _open(tester, reports: reportsWith([circleReportJson()]));
    expect(find.text('Reported by Dee'), findsOneWidget);
    // Nothing from the AI guard: no second heading.
    expect(find.text('Held or flagged by the AI guard'), findsNothing);
  });

  testWidgets('the context is folded until asked for', (tester) async {
    await _open(tester, reports: reportsWith([circleReportJson()]));

    expect(find.byKey(const ValueKey('report-context')), findsNothing);
    expect(find.text('Show context (2)'), findsOneWidget);
    await _tap(tester, 'report-toggle-context');
    expect(find.byKey(const ValueKey('report-context')), findsOneWidget);
    expect(
      find.text('Ada: anyone selling anything?', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Bart: please stop', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-context-reported')),
      findsOneWidget,
    );
    await _tap(tester, 'report-toggle-context');
    expect(find.byKey(const ValueKey('report-context')), findsNothing);
  });

  testWidgets('a report without context has no toggle', (tester) async {
    await _open(
      tester,
      reports: reportsWith([circleReportJson(withContext: false)]),
    );
    expect(find.byKey(const ValueKey('report-toggle-context')), findsNothing);
  });

  testWidgets('an attachment is named, never shown', (tester) async {
    await _open(
      tester,
      reports: reportsWith([
        circleReportJson(
          body: '',
          attachment: {'kind': 'view_once', 'view_once': true},
        ),
      ]),
    );
    expect(find.text('View-once photo or video (not kept)'), findsOneWidget);
  });

  testWidgets('Dismiss closes the report and refreshes the queue', (
    tester,
  ) async {
    final reports = reportsWith([circleReportJson()]);
    await _open(tester, reports: reports);
    reports.results['list_circle_message_reports'] = [];

    await _tap(tester, 'report-dismiss');

    expect(reports.callsOf('resolve_message_report').single, {
      'target_report_id': 'report-1',
      'action': 'dismiss',
    });
    expect(find.text('Report dismissed.'), findsOneWidget);
    expect(reports.callsOf('list_circle_message_reports'), hasLength(2));
    expect(find.text('User reports'), findsNothing);
    expect(find.text('Nothing to review'), findsOneWidget);
  });

  testWidgets('Delete message asks first, then deletes', (tester) async {
    final reports = reportsWith([circleReportJson()]);
    await _open(tester, reports: reports);

    await _tap(tester, 'report-delete');
    expect(find.text('Delete this message?'), findsOneWidget);
    expect(reports.callsOf('resolve_message_report'), isEmpty);
    await tester.tap(find.text('Delete message').last);
    await tester.pumpAndSettle();

    expect(
      reports.callsOf('resolve_message_report').single['action'],
      'delete_message',
    );
    expect(find.text('Message deleted.'), findsOneWidget);
  });

  testWidgets('a deleted message cannot be deleted again', (tester) async {
    await _open(
      tester,
      reports: reportsWith([circleReportJson(available: false)]),
    );
    expect(find.byKey(const ValueKey('report-delete')), findsNothing);
    expect(find.byKey(const ValueKey('report-dismiss')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-ban')), findsOneWidget);
  });

  testWidgets('Time out offers lengths and sends the chosen one', (
    tester,
  ) async {
    final reports = reportsWith([circleReportJson()]);
    await _open(tester, reports: reports);

    await _tap(tester, 'report-timeout');
    expect(find.text('Time out Eve'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('1 week'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-timeout-24h')));
    await tester.pumpAndSettle();

    expect(reports.callsOf('resolve_message_report').single, {
      'target_report_id': 'report-1',
      'action': 'timeout',
      'duration_seconds': 86400,
    });
    expect(find.text('Eve was timed out.'), findsOneWidget);
  });

  testWidgets('Ban asks first', (tester) async {
    final reports = reportsWith([circleReportJson()]);
    await _open(tester, reports: reports);

    await _tap(tester, 'report-ban');
    expect(find.text('Ban Eve?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(reports.callsOf('resolve_message_report'), isEmpty);

    await _tap(tester, 'report-ban');
    await tester.tap(find.text('Ban').last);
    await tester.pumpAndSettle();
    expect(reports.callsOf('resolve_message_report').single['action'], 'ban');
    expect(find.text('Eve was banned.'), findsOneWidget);
  });

  testWidgets('a moderator who may not ban is told so', (tester) async {
    final reports = reportsWith([circleReportJson()])
      ..failing['resolve_message_report'] = postgrestError('42501');
    await _open(tester, reports: reports);

    await _tap(tester, 'report-ban');
    await tester.tap(find.text('Ban').last);
    await tester.pumpAndSettle();

    expect(find.text("You don't have permission to do that."), findsOneWidget);
    // The report is still there to be handled another way.
    expect(find.byKey(const ValueKey('report-dismiss')), findsOneWidget);
  });

  testWidgets('reports that cannot be read leave the AI guard queue alone', (
    tester,
  ) async {
    final reports = FakeReportRpc()
      ..failing['list_circle_message_reports'] = postgrestError('42501');
    final guard = FakeGuardRpc()
      ..results['list_message_reviews'] = [reviewJson()];
    await _open(tester, reports: reports, guard: guard);

    expect(find.text('User reports'), findsNothing);
    expect(find.text('Cheap pills at pills.example'), findsOneWidget);
  });

  testWidgets('with nothing in either queue it says so', (tester) async {
    final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
    await _open(tester, reports: reportsWith([]), guard: guard);
    expect(find.text('Nothing to review'), findsOneWidget);
  });

  testWidgets('reads in Chinese', (tester) async {
    AppStrings.isChinese = true;
    await _open(tester, reports: reportsWith([circleReportJson()]));
    expect(find.text('用户举报'), findsOneWidget);
    expect(find.text('Dee 举报'), findsOneWidget);
    expect(find.text('忽略举报'), findsOneWidget);
  });
}
