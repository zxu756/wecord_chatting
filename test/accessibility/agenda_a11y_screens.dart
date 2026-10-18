// My agenda and its calendar subscription, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/agenda/agenda_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location, {
  FakeAgendaRepository? agenda,
  FakeCalendarFeedRepository? feed,
  InMemoryCalendarFeedTokenStore? tokens,
}) async {
  world.extraOverrides = agendaOverrides(
    agenda: agenda ?? FakeAgendaRepository(sampleAgenda()),
    feed: feed,
    tokens: tokens,
  );
  await world.open(tester, location);
  await settle(tester);
}

Future<void> _openSettings(
  WidgetTester tester,
  PhoneWorld world, {
  required FakeCalendarFeedRepository feed,
  InMemoryCalendarFeedTokenStore? tokens,
}) async {
  await _open(tester, world, '/agenda', feed: feed, tokens: tokens);
  await tester.tap(find.byKey(const ValueKey('agenda-calendar-settings')));
  await settle(tester);
}

final agendaA11yScreens = <A11yScreen>[
  A11yScreen('agenda-list', (tester, world) => _open(tester, world, '/agenda')),
  A11yScreen('agenda-month', (tester, world) async {
    await _open(tester, world, '/agenda');
    await tester.tap(find.byKey(const ValueKey('agenda-view-month')));
    await settle(tester);
  }),
  A11yScreen(
    'agenda-empty',
    (tester, world) =>
        _open(tester, world, '/agenda', agenda: FakeAgendaRepository()),
  ),
  A11yScreen(
    'agenda-calendar-subscription-new',
    (tester, world) =>
        _openSettings(tester, world, feed: FakeCalendarFeedRepository()),
  ),
  A11yScreen(
    'agenda-calendar-subscription-link',
    (tester, world) => _openSettings(
      tester,
      world,
      feed: FakeCalendarFeedRepository(
        enabled: true,
        lastUsedAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      tokens: InMemoryCalendarFeedTokenStore({'user-1': '7'.padLeft(48, 'a')}),
    ),
  ),
  A11yScreen(
    'desktop-agenda',
    (tester, world) => _open(tester, world, '/agenda'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-agenda-month',
    (tester, world) async {
      await _open(tester, world, '/agenda');
      await tester.tap(find.byKey(const ValueKey('agenda-view-month')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
