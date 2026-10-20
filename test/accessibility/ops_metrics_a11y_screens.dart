// Product stats (K2), monitoring and alerts (K3) and error reports 2.0 (K5),
// for the accessibility guard (guidelines_test.dart) and the accessibility
// screenshot tool: the admin console's Stats tab (people, coming back,
// messages, usage, health, versions) and Alerts tab (the checks, open and
// closed alerts, the error groups), and the alert card in Notifications.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';

import '../features/admin/ops_metrics_fakes.dart';
import '../features/announcements/announcement_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<void> _openConsoleTab(
  WidgetTester tester,
  PhoneWorld world,
  String tab, {
  String role = 'owner',
}) async {
  // (The console is opened by its route, so the times are counted back from
  // the real clock.)
  world.extraOverrides = opsMetricsShowcase(
    role: role,
    clock: DateTime.now(),
  ).callOverrides;
  await world.open(tester, '/admin');
  final chip = find.byKey(ValueKey('admin-tab-$tab'));
  // (The tabs scroll sideways on a phone.)
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await settle(tester);
}

final opsMetricsA11yScreens = <A11yScreen>[
  A11yScreen('admin-stats', (tester, world) async {
    await _openConsoleTab(tester, world, 'stats');
  }),
  A11yScreen('admin-stats-usage', (tester, world) async {
    await _openConsoleTab(tester, world, 'stats');
    await _scrollTo(tester, 'admin-stats-usage');
  }),
  A11yScreen('admin-stats-versions', (tester, world) async {
    await _openConsoleTab(tester, world, 'stats');
    await _scrollTo(tester, 'admin-stats-versions');
  }),
  A11yScreen('admin-alerts', (tester, world) async {
    await _openConsoleTab(tester, world, 'alerts');
  }),
  A11yScreen('admin-alerts-open', (tester, world) async {
    await _openConsoleTab(tester, world, 'alerts');
    await _scrollTo(tester, 'admin-alert-a1');
  }),
  A11yScreen('admin-alerts-closed', (tester, world) async {
    await _openConsoleTab(tester, world, 'alerts');
    await _scrollTo(tester, 'admin-alerts-resolved');
    await tester.tap(find.byKey(const ValueKey('admin-alerts-resolved')));
    await settle(tester);
  }),
  A11yScreen('admin-alerts-errors', (tester, world) async {
    await _openConsoleTab(tester, world, 'alerts');
    await _scrollTo(tester, 'admin-alerts-errors');
  }),
  A11yScreen('admin-alerts-support', (tester, world) async {
    await _openConsoleTab(tester, world, 'alerts', role: 'support');
    await _scrollTo(tester, 'admin-alert-a1');
  }),
  A11yScreen('inbox-ops-alert', (tester, world) async {
    world.extraOverrides = [
      announcementsRepositoryProvider.overrideWithValue(
        FakeAnnouncementsRepository([
          notice(
            'n1',
            kind: AnnouncementKind.opsAlert,
            titleEn: 'Scheduled tasks have stopped',
            titleZh: '定时任务停了',
            bodyEn:
                'The every-minute dispatcher (wecord-later-dispatch) has not '
                'finished a run for 13 minutes. Scheduled messages, reminders '
                'and pushes may not be going out.',
            bodyZh: '每分钟的调度任务（wecord-later-dispatch）已有 13 分钟没有成功运行，定时消息、提醒和推送可能发不出去。',
          ),
          notice(
            'n2',
            titleEn: 'New terms of service',
            titleZh: '新的服务条款',
            bodyEn:
                'We changed the terms. Read them in Settings, About WeCord.',
            read: true,
          ),
        ]),
      ),
    ];
    await world.open(tester, '/notifications');
  }),
  A11yScreen(
    'desktop-admin-stats',
    (tester, world) async {
      await _openConsoleTab(tester, world, 'stats');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-admin-alerts',
    (tester, world) async {
      await _openConsoleTab(tester, world, 'alerts');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
