// Privacy permissions 2.0 and new-login alerts, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the three
// new Privacy & Safety groups and their pickers, the group invitation and
// Security cards in Notifications, "Not me" and the password sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/privacy/privacy2_fakes.dart';
import '../features/privacy/privacy_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _world(PhoneWorld world) {
  world.extraOverrides = [...deviceOverrides(), ...privacy2Overrides()];
}

Future<void> _openPrivacy(WidgetTester tester, PhoneWorld world) async {
  _world(world);
  await world.open(tester, '/me');
  final row = find.byKey(const ValueKey('friend-request-from-row'));
  await scrollIntoView(tester, row);
}

Future<void> _openFilter(
  WidgetTester tester,
  PhoneWorld world,
  String filter,
) async {
  _world(world);
  await world.open(tester, '/notifications');
  final chip = find.byKey(ValueKey('inbox-filter-$filter'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

Future<void> _openDesktopPrivacy(WidgetTester tester, PhoneWorld world) async {
  _world(world);
  await world.open(tester, '/me');
  await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
  await settle(tester);
  final row = find.byKey(const ValueKey('friend-request-from-row'));
  await tester.ensureVisible(row);
  await settle(tester);
}

/// The screens, in the order of the flows.
final privacy2A11yScreens = <A11yScreen>[
  A11yScreen('privacy-permissions', _openPrivacy),
  A11yScreen('privacy-friend-request-picker', (tester, world) async {
    await _openPrivacy(tester, world);
    await tester.tap(find.byKey(const ValueKey('friend-request-from-row')));
    await settle(tester);
  }),
  A11yScreen('privacy-group-invite-picker', (tester, world) async {
    await _openPrivacy(tester, world);
    final row = find.byKey(const ValueKey('group-invite-from-row'));
    await tester.ensureVisible(row);
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
  }),
  A11yScreen('privacy-calls-picker', (tester, world) async {
    await _openPrivacy(tester, world);
    final row = find.byKey(const ValueKey('calls-from-row'));
    await tester.ensureVisible(row);
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
  }),
  A11yScreen('notifications-group-invitation', (tester, world) async {
    await _openFilter(tester, world, 'friends');
  }),
  A11yScreen('notifications-security', (tester, world) async {
    await _openFilter(tester, world, 'security');
  }),
  A11yScreen('security-not-me', (tester, world) async {
    await _openFilter(tester, world, 'security');
    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await settle(tester);
  }),
  A11yScreen('change-password-sheet', (tester, world) async {
    await _openFilter(tester, world, 'security');
    await tester.tap(find.byKey(const ValueKey('security-not-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('security-password-change')));
    await settle(tester);
  }),
  A11yScreen(
    'desktop-privacy-permissions',
    _openDesktopPrivacy,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-notifications-privacy2',
    (tester, world) async {
      _world(world);
      await world.open(tester, '/notifications');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
