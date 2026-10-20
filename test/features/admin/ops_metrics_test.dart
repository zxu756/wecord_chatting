import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/admin/admin_alerts_models.dart';
import 'package:wecord/features/admin/admin_audit_view.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_stats_models.dart';
import 'package:wecord/features/announcements/announcement_card.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../announcements/announcement_fakes.dart';
import 'ops_metrics_fakes.dart';

Future<void> _open(
  WidgetTester tester,
  FakeMetricsBackend backend, {
  String tab = 'stats',
  Size size = const Size(900, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noProviderRetry,
      overrides: backend.overrides,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AdminConsoleScreen(now: () => DateTime.utc(2026, 10, 20, 10)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final chip = find.byKey(ValueKey('admin-tab-$tab'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the numbers', () {
    test('a day, the totals of a range and the retention table', () {
      final metrics = OpsMetrics.fromJson(opsMetricsJson());
      expect(metrics.days, hasLength(10));
      expect(metrics.latest!.day, DateTime.parse('2026-10-20'));
      expect(metrics.wau, 31);
      expect(metrics.mau, 58);
      expect(metrics.totalNewUsers, 12);
      expect(metrics.totalMessages, 4000);
      expect(metrics.totalVoiceMinutes, 450);
      expect(metrics.totalPushSent, 900);
      expect(metrics.totalPushFailed, 30);
      expect(metrics.totalPushGone, 10);
      expect(metrics.storageBytes, 1500 * 1024 * 1024);
      expect(metrics.totalStorageAdded, 12 * 1024 * 1024);
      // Newest cohort first, only the days with somebody new.
      expect(metrics.cohorts.map((d) => d.day.day), [18, 15]);
      expect(metrics.cohorts.last.d1Retained, 4);
      expect(metrics.cohorts.first.d1Retained, isNull);
    });

    test('messages and features add up over the range, biggest first', () {
      final metrics = OpsMetrics.fromJson(opsMetricsJson());
      final types = metrics.messagesByType;
      expect(types.first.key, 'text');
      expect(types.first.value, 3400);
      expect(types.map((e) => e.key), ['text', 'image', 'voice']);
      expect(metrics.featureCounts.first.key, 'moments');
      expect(metrics.featureCounts.first.value, 90);
    });

    test('a version is crash-free by the share of people who crashed', () {
      final metrics = OpsMetrics.fromJson(opsMetricsJson());
      expect(metrics.versions.first.crashFree, closeTo(0.85, 0.0001));
      expect(metrics.versions[1].crashFree, 1);
      expect(
        const OpsVersion(
          appVersion: '1',
          platform: 'web',
          activeUsers: 0,
          crashUsers: 0,
          crashReports: 0,
        ).crashFree,
        1,
      );
    });

    test('a damaged answer reads as an empty one', () {
      final metrics = OpsMetrics.fromJson({'days': 'x', 'versions': 3});
      expect(metrics.days, isEmpty);
      expect(metrics.versions, isEmpty);
      expect(metrics.latest, isNull);
      expect(metrics.storageBytes, isNull);
      expect(OpsDay.fromJson(const {}).activeUsers, 0);
    });

    test('numbers, percents and sizes read well', () {
      expect(opsNumber(0), '0');
      expect(opsNumber(999), '999');
      expect(opsNumber(1234), '1,234');
      expect(opsNumber(1234567), '1,234,567');
      expect(opsPercent(1, 4), '25%');
      expect(opsPercent(null, 4), '–');
      expect(opsPercent(1, 0), '–');
      expect(opsBytes(512), '512 B');
      expect(opsBytes(1536), '1.5 KB');
      expect(opsBytes(1500 * 1024 * 1024), '1.5 GB');
    });
  });

  group('the checks', () {
    test('the heartbeat tells whether the checks are still running', () {
      OpsChecks at(String? beat) =>
          OpsChecks.fromJson(opsChecksJson(heartbeat: beat));
      expect(at('2026-10-20T09:58:00Z').stale, isFalse);
      expect(at('2026-10-20T09:58:00Z').minutesSinceHeartbeat, 2);
      expect(at('2026-10-20T09:40:00Z').stale, isTrue);
      expect(at(null).stale, isTrue);
      expect(at(null).minutesSinceHeartbeat, isNull);
    });

    test('each check says what it looked at and what it found', () {
      final checks = OpsChecks.fromJson(opsChecksJson()).checks;
      String summary(String key) =>
          checks.firstWhere((check) => check.key == key).summary;
      expect(summary('cron_dispatch'), 'Last good run 13 min ago');
      expect(summary('push_failures'), '3 of 90 pushes failed in an hour');
      expect(summary('error_spike'), '41 reports in the last hour');
      expect(summary('edge_wakes'), 'Cannot be checked right now.');
      expect(summary('version_health'), '1.4.2: 3 of 20 people crashed');
      expect(
        checks.firstWhere((c) => c.key == 'cron_dispatch').label,
        'Scheduled tasks',
      );
      expect(OpsCheckStatus.parse('nonsense'), OpsCheckStatus.unknown);
    });

    test('an alert reads in the language of the app, or the other one', () {
      final alert = OpsAlert.fromJson(opsAlertJson('a1'));
      expect(alert.title(chinese: false), 'Scheduled tasks have stopped');
      expect(alert.title(chinese: true), '定时任务停了');
      final englishOnly = OpsAlert.fromJson(
        opsAlertJson('a2', titleZh: '', bodyZh: ''),
      );
      expect(englishOnly.title(chinese: true), 'Scheduled tasks have stopped');
      expect(alert.isOpen, isTrue);
      expect(alert.isFailure, isTrue);
      expect(alert.isEvent, isFalse);
    });

    test('an error group drops its kind from the label', () {
      final group = OpsErrorGroup.fromJson(opsErrorGroupJson('x'));
      expect(group.what, startsWith('Bad state: No element N'));
      expect(group.what, isNot(contains('flutter_error')));
      expect(group.occurrencesText, '38');
    });
  });

  group('the Stats tab', () {
    testWidgets('shows the people, the retention, the usage and the versions', (
      tester,
    ) async {
      final backend = FakeMetricsBackend();
      await _open(tester, backend);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin-stats-today')),
          matching: find.text('14'),
        ),
        findsOneWidget,
      );
      expect(find.text('Active today'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('58'), findsOneWidget);
      expect(find.text('12'), findsWidgets);

      // The retention table: the newest cohort first, empty cells as dashes.
      expect(find.byKey(const ValueKey('admin-stats-cohort-10/18')), findsOne);
      expect(find.byKey(const ValueKey('admin-stats-cohort-10/15')), findsOne);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin-stats-cohort-10/15')),
          matching: find.text('50%'),
        ),
        findsOneWidget,
      );

      // Messages by type and the use of features.
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('3,400'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);

      // The health numbers.
      expect(find.text('Storage in use'), findsOneWidget);
      expect(find.text('1.5 GB'), findsOneWidget);

      // The versions: the share of people without a crash.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('admin-stats-version-1.4.2-ios')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('1.4.2 on iOS'), findsOneWidget);
      expect(find.text('85% crash-free'), findsOneWidget);
      expect(find.text('100% crash-free'), findsOneWidget);
    });

    testWidgets('a range asks for that many days', (tester) async {
      final backend = FakeMetricsBackend();
      await _open(tester, backend);
      expect(backend.calls('admin_ops_metrics').single['range_days'], 30);
      await tester.tap(find.byKey(const ValueKey('admin-stats-range-90')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_ops_metrics').last['range_days'], 90);
      await tester.tap(find.byKey(const ValueKey('admin-stats-range-7')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_ops_metrics').last['range_days'], 7);
    });

    testWidgets('a young app shows empty tables, not errors', (tester) async {
      final backend = FakeMetricsBackend()
        ..metrics = {
          'days': <Object>[],
          'versions': <Object>[],
          'summary': {'wau': 0, 'mau': 0},
        };
      await _open(tester, backend);
      expect(find.text('Nobody new yet in this range.'), findsOneWidget);
      expect(find.text('No messages in this range.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('No version has reported yet.'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('No version has reported yet.'), findsOneWidget);
    });

    testWidgets('a failure shows the reason and Retry loads it again', (
      tester,
    ) async {
      final backend = FakeMetricsBackend();
      backend.failures['admin_ops_metrics'] = PostgrestException(
        message: 'Admin access required',
        code: '42501',
      );
      await _open(tester, backend);
      expect(find.text('Could not load the stats.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Active today'), findsOneWidget);
      expect(backend.calls('admin_ops_metrics'), hasLength(2));
    });

    testWidgets('support staff read it too', (tester) async {
      final backend = FakeMetricsBackend(role: 'support');
      await _open(tester, backend);
      expect(find.text('Active today'), findsOneWidget);
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      final backend = FakeMetricsBackend();
      await _open(tester, backend);
      expect(find.text('今日活跃'), findsOneWidget);
      expect(find.text('本周活跃'), findsOneWidget);
      expect(find.text('留存'), findsOneWidget);
      expect(find.text('图片'), findsOneWidget);
      expect(find.text('朋友圈'), findsOneWidget);
    });

    testWidgets('fits a phone at the largest text size', (tester) async {
      final backend = FakeMetricsBackend();
      await _open(tester, backend, size: const Size(320, 700), textScale: 2);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('admin-stats-versions')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the Alerts tab', () {
    testWidgets('lists the checks and the open alerts', (tester) async {
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      expect(find.text('The checks ran 2 minutes ago.'), findsOneWidget);
      for (final key in [
        'cron_dispatch',
        'cron_failures',
        'edge_wakes',
        'push_failures',
        'error_spike',
        'ai_quota',
        'version_health',
        'new_errors',
      ]) {
        expect(find.byKey(ValueKey('admin-check-$key')), findsOneWidget);
      }
      expect(find.text('Failing'), findsWidgets);
      expect(find.text('Unknown'), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin-alert-a1')),
          matching: find.text('Scheduled tasks have stopped'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('admin-alert-a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-alert-a3')), findsOneWidget);
      expect(find.text('Seen by @mia'), findsOneWidget);
      expect(find.text('Reopened 1 times'), findsOneWidget);
      expect(find.text('New error'), findsOneWidget);
    });

    testWidgets('an owner can say "I have seen it" and close an alert', (
      tester,
    ) async {
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      final ack = find.byKey(const ValueKey('admin-alert-ack-a1'));
      await tester.ensureVisible(ack);
      await tester.pumpAndSettle();
      await tester.tap(ack);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_ack_ops_alert').single, {
        'target_alert_id': 'a1',
      });
      // Seen: the button goes away, the name shows.
      expect(find.byKey(const ValueKey('admin-alert-ack-a1')), findsNothing);
      expect(find.text('Seen by @root'), findsOneWidget);

      final close = find.byKey(const ValueKey('admin-alert-close-a1'));
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_resolve_ops_alert').single, {
        'target_alert_id': 'a1',
      });
      expect(find.byKey(const ValueKey('admin-alert-a1')), findsNothing);
    });

    testWidgets('an event is closed, not acknowledged', (tester) async {
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      expect(find.byKey(const ValueKey('admin-alert-ack-a3')), findsNothing);
      final close = find.byKey(const ValueKey('admin-alert-close-a3'));
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_resolve_ops_alert').single, {
        'target_alert_id': 'a3',
      });
    });

    testWidgets('support staff read but have no buttons', (tester) async {
      final backend = opsMetricsShowcase(role: 'support');
      await _open(tester, backend, tab: 'alerts');
      expect(find.byKey(const ValueKey('admin-alert-a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-alert-ack-a1')), findsNothing);
      expect(find.byKey(const ValueKey('admin-alert-close-a1')), findsNothing);
    });

    testWidgets('a failed close says why and keeps the alert', (tester) async {
      final backend = opsMetricsShowcase();
      backend.failures['admin_resolve_ops_alert'] = PostgrestException(
        message: 'Alert not found or already closed',
        code: 'P0002',
      );
      await _open(tester, backend, tab: 'alerts');
      final close = find.byKey(const ValueKey('admin-alert-close-a1'));
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-alert-a1')), findsOneWidget);
    });

    testWidgets('closed alerts say how they ended', (tester) async {
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-alerts-resolved')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-alerts-resolved')));
      await tester.pumpAndSettle();
      expect(
        backend.calls('admin_list_ops_alerts').last['status_filter'],
        'resolved',
      );
      expect(find.byKey(const ValueKey('admin-alert-c1')), findsOneWidget);
      expect(find.textContaining('recovered'), findsOneWidget);
      expect(find.textContaining('closed by @root'), findsOneWidget);
      // Nothing to do on a closed one.
      expect(find.byKey(const ValueKey('admin-alert-close-c1')), findsNothing);
    });

    testWidgets('nothing wrong shows a calm page', (tester) async {
      final backend = FakeMetricsBackend()
        ..checks = opsChecksJson(
          checks: [
            opsCheckJson('cron_dispatch', detail: {'minutes_since_success': 0}),
          ],
        );
      await _open(tester, backend, tab: 'alerts');
      expect(find.text('No open alerts.'), findsOneWidget);
      expect(find.text('No error reports in the last day.'), findsOneWidget);
    });

    testWidgets('a heartbeat that stopped is a warning of its own', (
      tester,
    ) async {
      final backend = FakeMetricsBackend()
        ..checks = opsChecksJson(heartbeat: '2026-10-20T09:00:00Z');
      await _open(tester, backend, tab: 'alerts');
      expect(
        find.textContaining('The checks have not run for 60 minutes'),
        findsOneWidget,
      );
      final never = FakeMetricsBackend()
        ..checks = opsChecksJson(heartbeat: null);
      await _open(tester, never, tab: 'alerts');
      expect(find.text('The checks have not run yet.'), findsOneWidget);
    });

    testWidgets('the error groups show kind, count, people and what is new', (
      tester,
    ) async {
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      final row = find.byKey(const ValueKey('admin-error-aaaaaaaa11111111'));
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.descendant(of: row, matching: find.text('flutter_error')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('New')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('38 times')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('5 people')),
        findsOneWidget,
      );
      expect(find.textContaining('1,204 times'), findsOneWidget);
      final call = backend.calls('admin_ops_error_groups').single;
      expect(call['hours'], 24);
    });

    testWidgets('reads in Chinese, with the alert in Chinese too', (
      tester,
    ) async {
      AppStrings.isChinese = true;
      final backend = opsMetricsShowcase();
      await _open(tester, backend, tab: 'alerts');
      expect(find.text('检查项'), findsOneWidget);
      expect(find.text('定时任务停了'), findsWidgets);
      expect(find.text('@mia 已知晓'), findsOneWidget);
      expect(find.text('我知道了'), findsWidgets);
      expect(find.text('未处理'), findsOneWidget);
    });

    testWidgets('fits a phone at the largest text size', (tester) async {
      final backend = opsMetricsShowcase();
      await _open(
        tester,
        backend,
        tab: 'alerts',
        size: const Size(320, 700),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('admin-alerts-errors')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the console', () {
    testWidgets('has seven tabs, the two new ones at the end', (tester) async {
      final backend = FakeMetricsBackend();
      await _open(tester, backend, tab: 'audit');
      for (final tab in [
        'reports',
        'audit',
        'flags',
        'notices',
        'feedback',
        'stats',
        'alerts',
      ]) {
        expect(find.byKey(ValueKey('admin-tab-$tab')), findsOneWidget);
      }
    });

    test('the audit log tells acknowledging and closing in words', () {
      AdminAuditEntry entry(String action) => AdminAuditEntry(
        id: 'e1',
        actor: 'mia',
        actorRole: AdminRole.moderator,
        action: action,
        targetType: 'config',
        targetId: 'a1',
        details: const {'title': 'Scheduled tasks have stopped'},
        createdAt: DateTime.utc(2026, 10, 20),
      );
      expect(
        adminAuditSummary(entry('ack_ops_alert')),
        '@mia acknowledged the alert “Scheduled tasks have stopped”',
      );
      expect(
        adminAuditSummary(entry('resolve_ops_alert')),
        '@mia closed the alert “Scheduled tasks have stopped”',
      );
    });
  });

  group('the alert card in Notifications', () {
    Future<void> pumpCard(WidgetTester tester, Announcement notice) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            announcementsRepositoryProvider.overrideWithValue(
              FakeAnnouncementsRepository([notice]),
            ),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(body: AnnouncementCard(announcement: notice)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an alert is a warning card from Monitoring', (tester) async {
      await pumpCard(
        tester,
        notice(
          'n1',
          kind: AnnouncementKind.opsAlert,
          titleEn: 'Scheduled tasks have stopped',
          titleZh: '定时任务停了',
        ),
      );
      expect(find.text('Monitoring'), findsOneWidget);
      expect(find.text('Alert'), findsOneWidget);
      expect(find.text('WeCord team'), findsNothing);
      expect(find.text('Official'), findsNothing);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    });

    testWidgets('a notice from the team looks as it did', (tester) async {
      await pumpCard(tester, notice('n2'));
      expect(find.text('WeCord team'), findsOneWidget);
      expect(find.text('Official'), findsOneWidget);
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    });

    test('the kind comes from the server', () {
      expect(AnnouncementKind.parse('ops_alert'), AnnouncementKind.opsAlert);
      expect(
        AnnouncementKind.parse('feedback_reply'),
        AnnouncementKind.feedbackReply,
      );
      expect(
        AnnouncementKind.parse('who knows'),
        AnnouncementKind.announcement,
      );
    });
  });

  test('the roles that may act are the ones that may sanction', () {
    expect(AdminRole.owner.canSanction, isTrue);
    expect(AdminRole.moderator.canSanction, isTrue);
    expect(AdminRole.support.canSanction, isFalse);
  });
}
