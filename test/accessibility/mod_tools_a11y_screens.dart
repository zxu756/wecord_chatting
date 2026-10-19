// Moderator tools 2.0 and raid protection, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the member
// list with its filters and batch bar, a member's notes, the Review page with
// a lockdown banner and ban appeals, the raid protection page, the circle
// menu's Safety actions, and a ban with its appeal in Notifications.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

import '../features/circles/ai_guard_fakes.dart';
import '../features/circles/mod_tools_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The fakes behind the moderator tools. [lockdown] makes the circle report a
/// lockdown (and paused invites) with two ban appeals waiting.
List<Override> modToolsA11yOverrides({bool lockdown = false}) {
  final rpc = JoinRpc()
    ..answer('list_circle_members_for_moderation', [
      modMemberJson(
        id: 'm1',
        name: 'Nia Novak',
        username: 'nia',
        flagged: true,
        warnings: 2,
        messages: 14,
        total: 4,
      ),
      modMemberJson(
        id: 'm2',
        name: 'Omar Haddad',
        username: 'omar',
        joinedAt: DateTime.now()
            .subtract(const Duration(minutes: 20))
            .toUtc()
            .toIso8601String(),
        accountCreatedAt: DateTime.now()
            .subtract(const Duration(hours: 5))
            .toUtc()
            .toIso8601String(),
        messages: 0,
        total: 4,
      ),
      modMemberJson(
        id: 'm3',
        name: 'Priya Raman',
        username: 'priya',
        timedOutUntil: '2099-01-01T10:00:00Z',
        total: 4,
      ),
      modMemberJson(
        id: 'm4',
        name: 'Sam Senior',
        username: 'sam',
        canTimeout: false,
        canKick: false,
        canBan: false,
        total: 4,
      ),
    ])
    ..answer('list_circle_mod_notes', [
      modNoteJson(),
      modNoteJson(
        id: 'n2',
        kind: 'warning',
        body: 'Posted the same invite link in three channels.',
      ),
      modNoteJson(
        id: 'n3',
        body: 'Joined from the 25 Oct invite wave.',
        author: 'Sam',
        canDelete: false,
      ),
    ])
    ..answer(
      'get_circle_security',
      lockdown
          ? securityJson(
              lockdown: lockdownJson(),
              invitesPausedUntil: '2099-01-01T10:00:00Z',
              joinMode: 'apply',
              recentJoins: 24,
              recentNew: 9,
            )
          : securityJson(recentJoins: 3, recentNew: 1),
    )
    ..answer('count_ban_appeals', lockdown ? 2 : 0)
    ..answer('list_ban_appeals', [
      if (lockdown) ...[
        banAppealJson(),
        banAppealJson(
          id: 'a2',
          name: 'Fay Okafor',
          username: 'fay',
          message: 'My account was hacked, the spam was not me.',
          reason: null,
        ),
      ],
    ])
    ..answer('count_join_requests', 0)
    ..answer('list_join_requests', const <Object>[])
    ..answer('my_circle_bans', [
      myBanJson(),
      myBanJson(
        circleId: 'circle-2',
        name: 'Night Owls Gaming',
        expiresAt: '2099-01-01T10:00:00Z',
        appealStatus: 'denied',
        appealNote: 'Please wait until the ban ends.',
      ),
    ]);
  final guard = FakeGuardRpc()
    ..results['count_message_reviews'] = 0
    ..results['list_message_reviews'] = const <Object>[];
  return [
    circleRpcProvider.overrideWithValue(rpc.call),
    circleAiGuardRepositoryProvider.overrideWithValue(
      CircleAiGuardRepository(guard),
    ),
  ];
}

Future<void> _fromMenu(
  WidgetTester tester,
  PhoneWorld world,
  String item, {
  bool lockdown = false,
}) async {
  world.extraOverrides = modToolsA11yOverrides(lockdown: lockdown);
  await world.open(tester, '/circles/circle-1');
  await settle(tester);
  await tester.tap(find.byTooltip('Circle menu'));
  await settle(tester);
  final entry = find.text(item).last;
  await tester.ensureVisible(entry);
  await settle(tester);
  await tester.tap(entry);
  await settle(tester);
}

Future<void> _selecting(WidgetTester tester, PhoneWorld world) async {
  await _fromMenu(tester, world, 'Members');
  await tester.tap(find.byKey(const ValueKey('member-tools-select')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('member-tools-m1')));
  await tester.tap(find.byKey(const ValueKey('member-tools-m2')));
  await settle(tester);
}

Future<void> _filters(WidgetTester tester, PhoneWorld world) async {
  await _fromMenu(tester, world, 'Members');
  await tester.tap(find.byKey(const ValueKey('member-tools-filter')));
  await settle(tester);
}

Future<void> _notes(WidgetTester tester, PhoneWorld world) async {
  await _fromMenu(tester, world, 'Members');
  await tester.tap(find.byKey(const ValueKey('member-tools-m1')));
  await settle(tester);
}

Future<void> _raidSettings(WidgetTester tester, PhoneWorld world) async {
  await _fromMenu(tester, world, 'Circle settings');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('circle-settings-raid')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const ValueKey('circle-settings-raid')));
  await settle(tester);
}

Future<void> _notifications(WidgetTester tester, PhoneWorld world) async {
  world.extraOverrides = modToolsA11yOverrides();
  await world.open(tester, '/notifications');
  await settle(tester);
  final chip = find.byKey(const ValueKey('inbox-filter-circles'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

final modToolsA11yScreens = <A11yScreen>[
  A11yScreen(
    'mod-members',
    (tester, world) => _fromMenu(tester, world, 'Members'),
  ),
  A11yScreen(
    'desktop-mod-members',
    (tester, world) => _fromMenu(tester, world, 'Members'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('mod-members-selected', _selecting),
  A11yScreen('mod-members-filters', _filters),
  A11yScreen('mod-notes', _notes),
  A11yScreen(
    'desktop-mod-notes',
    _notes,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'mod-review-lockdown',
    (tester, world) => _fromMenu(tester, world, 'Review', lockdown: true),
  ),
  A11yScreen(
    'desktop-mod-review-lockdown',
    (tester, world) => _fromMenu(tester, world, 'Review', lockdown: true),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('mod-raid-settings', _raidSettings),
  A11yScreen(
    'desktop-mod-raid-settings',
    _raidSettings,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'mod-safety-actions',
    (tester, world) => _fromMenu(tester, world, 'Safety actions'),
  ),
  A11yScreen('mod-ban-notifications', _notifications),
];
