// The quiet hours screens, for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/notifications/quiet_hours_screen.dart';

import '../features/notifications/quiet_hours_fakes.dart';
import '../features/moments/moments_fakes.dart' show FakeFriendTagsRepository;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

// Tuesday 23:30 on the clock of the device: inside the window.
final _night = DateTime(2026, 10, 20, 23, 30);

Future<void> _screen(
  WidgetTester tester,
  PhoneWorld world, {
  bool enabled = true,
}) async {
  world.extraOverrides = quietHoursOverrides(
    repository: quietHoursServer(enabled: enabled),
    now: _night,
  );
  await pumpStandalone(tester, world, const QuietHoursScreen());
}

final quietHoursA11yScreens = <A11yScreen>[
  A11yScreen(
    'quiet-hours-off',
    (tester, world) => _screen(tester, world, enabled: false),
  ),
  A11yScreen('quiet-hours-on', _screen),
  A11yScreen('quiet-hours-contacts', (tester, world) async {
    await _screen(tester, world);
    final row = find.byKey(const ValueKey('quiet-hours-contacts'));
    await tester.dragUntilVisible(
      row,
      find.byKey(const ValueKey('settings-page-list')),
      const Offset(0, -150),
    );
    await tester.ensureVisible(row);
    await tester.tap(row);
    await settle(tester);
  }),
  A11yScreen(
    'quiet-hours-on-desktop',
    _screen,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('friend-profile-important-contact', (tester, world) async {
    world.extraOverrides = [
      ...quietHoursOverrides(
        repository: quietHoursServer(contacts: {'user-2'}),
        now: _night,
      ),
      friendTagsRepositoryProvider.overrideWithValue(
        FakeFriendTagsRepository(),
      ),
    ];
    await world.open(tester, '/profile/user-2');
  }),
  A11yScreen('home-with-quiet-moon', (tester, world) async {
    world.extraOverrides = quietHoursOverrides(
      repository: quietHoursServer(),
      now: _night,
    );
    await world.open(tester, '/home');
  }),
];
