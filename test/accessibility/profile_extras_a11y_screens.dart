// Status bubbles, birthdays, mutuals and add sources, and support links, for
// the accessibility guard (guidelines_test.dart) and the accessibility
// screenshot tool: the friends row with bubbles, the profile card with its
// numbers in common and support links, the birthday and support link
// editors, the "Leaving WeCord" notice, the status audience, and the
// birthday and request cards in Notifications.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';

import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _links = [
  SupportLink(url: 'https://afdian.net/a/bart', label: 'Bart on 爱发电'),
  SupportLink(url: 'https://ko-fi.com/bart'),
];

List<Override> _extras() => [
  friendStatusesProvider.overrideWith(
    (ref) async => const {
      'user-2': FriendStatus(
        userId: 'user-2',
        emoji: '📚',
        text: 'Studying for the exam tomorrow',
      ),
      'user-3': FriendStatus(userId: 'user-3', emoji: '🎧'),
    },
  ),
  profileInsightsProvider('user-2').overrideWith(
    (ref) async => const ProfileInsights(
      mutuals: Mutuals(
        friendCount: 3,
        groupCount: 2,
        circleCount: 1,
        groups: [
          MutualItem(id: 'g1', title: 'Weekend climbers'),
          MutualItem(id: 'g2', title: 'Study group'),
        ],
      ),
      source: FriendSource.group,
      birthday: ProfileBirthday(month: 10, day: 18),
      links: _links,
    ),
  ),
  myProfileExtrasProvider.overrideWith(
    (ref) async => const MyProfileExtras(
      birthday: MyBirthday(
        birthday: ProfileBirthday(month: 10, day: 18),
        reminders: true,
      ),
      statusVisibility: StatusVisibility.friends,
      links: _links,
    ),
  ),
  birthdaysTodayProvider.overrideWith(
    (ref) async => const [
      BirthdayFriend(userId: 'user-2', username: 'bart', displayName: 'Bart'),
    ],
  ),
  mutualFriendCountProvider.overrideWith((ref, userId) async => 3),
];

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location,
) async {
  world.extraOverrides = _extras();
  await world.open(tester, location);
  await settle(tester);
}

Future<void> _openSettingsRow(
  WidgetTester tester,
  PhoneWorld world,
  String rowKey,
) async {
  await _open(tester, world, '/me');
  final row = find.byKey(ValueKey(rowKey));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(row);
  await settle(tester);
  await tester.tap(row);
  await settle(tester);
}

Future<void> _openProfileInsights(WidgetTester tester, PhoneWorld world) async {
  await _open(tester, world, '/profile/user-2');
  final card = find.byKey(const ValueKey('profile-support-links'));
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

final profileExtrasA11yScreens = <A11yScreen>[
  A11yScreen('home-status-bubbles', (tester, world) async {
    await _open(tester, world, '/home');
    // The friends row, scrolled to the friends with a bubble.
    await tester.drag(
      find.byKey(const ValueKey('phone-friends-row')),
      const Offset(-420, 0),
    );
    await settle(tester);
  }),
  A11yScreen('profile-in-common-and-support', _openProfileInsights),
  A11yScreen('profile-leaving-wecord', (tester, world) async {
    await _open(tester, world, '/profile/user-2');
    final link = find.byKey(const ValueKey('support-link-0'));
    await tester.scrollUntilVisible(
      link,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(link);
    await settle(tester);
    await tester.tap(link);
    await settle(tester);
  }),
  A11yScreen('settings-birthday-editor', (tester, world) async {
    await _openSettingsRow(tester, world, 'settings-birthday');
  }),
  A11yScreen('settings-support-links-editor', (tester, world) async {
    await _openSettingsRow(tester, world, 'settings-support-links');
  }),
  A11yScreen('notifications-birthday-and-request', (tester, world) async {
    await _open(tester, world, '/notifications');
  }),
  A11yScreen(
    'desktop-profile-in-common-and-support',
    _openProfileInsights,
    viewport: desktopViewport,
    desktop: true,
  ),
];
