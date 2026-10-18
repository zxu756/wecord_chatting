// Circle insights, for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool: circle settings → Insights with a busy
// circle, with a small one (every number hidden), and on a desktop window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

import '../features/circles/insights_fakes.dart';
import '../features/circles/join_requests_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The fakes behind the Insights page. [small] is a circle under 5 members.
List<Override> insightsOverrides({bool small = false}) {
  final rpc = JoinRpc()
    ..answer('get_circle_insights', insightsJson(small: small))
    ..answer('get_circle_join_settings', {
      'join_mode': 'open',
      'questions': [],
    });
  return [circleRpcProvider.overrideWithValue(rpc.call)];
}

Future<void> _openInsights(
  WidgetTester tester,
  PhoneWorld world, {
  bool small = false,
}) async {
  world.extraOverrides = insightsOverrides(small: small);
  await world.open(tester, '/circles/circle-1');
  await settle(tester);
  await tester.tap(find.byTooltip('Circle menu'));
  await settle(tester);
  final entry = find.text('Circle settings').last;
  await tester.ensureVisible(entry);
  await settle(tester);
  await tester.tap(entry);
  await settle(tester);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('circle-settings-insights')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey('circle-settings-insights')),
  );
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('circle-settings-insights')));
  await settle(tester);
}

final insightsA11yScreens = <A11yScreen>[
  A11yScreen('insights-page', _openInsights),
  A11yScreen(
    'insights-small-circle',
    (tester, world) => _openInsights(tester, world, small: true),
  ),
  A11yScreen(
    'desktop-insights-page',
    _openInsights,
    viewport: desktopViewport,
    desktop: true,
  ),
];
