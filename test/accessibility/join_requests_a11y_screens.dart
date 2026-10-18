// Circle join requests, for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool: the Review page with requests, Join
// mode in circle settings, the invite page asking questions and waiting, and
// the answers in Notifications.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

import '../features/circles/ai_guard_fakes.dart';
import '../features/circles/join_requests_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The fakes behind the join request screens. [pendingInvite] makes the
/// invite page (circle-4) show a request that is waiting.
List<Override> joinRequestsOverrides({bool pendingInvite = false}) {
  final rpc = JoinRpc()
    ..answer('count_join_requests', 3)
    ..answer('list_circle_invites_skipping_review', ['h7Kq2mPz'])
    ..answer('list_join_requests', [
      pendingRequestJson(),
      pendingRequestJson(
        id: 'req-2',
        name: 'Omar Haddad',
        username: 'omar',
        invitedBy: 'Bart the Bold',
        answers: const [],
      ),
      pendingRequestJson(
        id: 'req-3',
        name: 'Priya Raman',
        username: 'priya',
        answers: const [
          {
            'question_id': 'q1',
            'prompt': 'Why do you want to join?',
            'kind': 'text',
            'answer': 'Friends told me you share weekly palette challenges.',
          },
        ],
      ),
    ])
    ..answer('get_circle_join_settings', {
      'join_mode': 'apply',
      'questions': [
        questionJson(),
        questionJson(
          id: 'q2',
          kind: 'choice',
          prompt: 'How did you find us?',
          options: const ['A friend', 'Search', 'Social media'],
          required: false,
        ),
      ],
    })
    ..answer(
      'get_circle_join_state',
      joinStateJson(
        circleId: 'circle-4',
        request: pendingInvite ? requestInfoJson() : null,
      ),
    )
    ..answer('list_my_join_requests', [
      myRequestJson(id: 'r-approved', status: 'approved'),
      myRequestJson(
        id: 'r-denied',
        status: 'denied',
        circleName: 'Night Owls Gaming',
        note: 'Please introduce yourself in the invite message next time.',
      ),
      myRequestJson(id: 'r-pending', circleName: 'Trail Runners Sydney'),
    ]);
  final guard = FakeGuardRpc()
    ..results['count_message_reviews'] = 1
    ..results['list_message_reviews'] = [reviewJson()];
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
  String item,
) async {
  world.extraOverrides = joinRequestsOverrides();
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

Future<void> _openJoinMode(WidgetTester tester, PhoneWorld world) async {
  await _fromMenu(tester, world, 'Circle settings');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('circle-settings-join-mode')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const ValueKey('circle-settings-join-mode')));
  await settle(tester);
}

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  String location, {
  bool pendingInvite = false,
}) async {
  world.extraOverrides = joinRequestsOverrides(pendingInvite: pendingInvite);
  await world.open(tester, location);
  await settle(tester);
}

final joinRequestsA11yScreens = <A11yScreen>[
  A11yScreen(
    'join-requests-review',
    (tester, world) => _fromMenu(tester, world, 'Review'),
  ),
  A11yScreen(
    'desktop-join-requests-review',
    (tester, world) => _fromMenu(tester, world, 'Review'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'join-invite-sheet',
    (tester, world) => _fromMenu(tester, world, 'Invite friends'),
  ),
  A11yScreen(
    'desktop-join-invite-sheet',
    (tester, world) => _fromMenu(tester, world, 'Invite friends'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('join-mode-settings', _openJoinMode),
  A11yScreen(
    'desktop-join-mode-settings',
    _openJoinMode,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'join-invite-questions',
    (tester, world) => _open(tester, world, '/invite/h7Kq2mPz'),
  ),
  A11yScreen(
    'join-invite-pending',
    (tester, world) =>
        _open(tester, world, '/invite/h7Kq2mPz', pendingInvite: true),
  ),
  A11yScreen(
    'desktop-join-invite-questions',
    (tester, world) => _open(tester, world, '/invite/h7Kq2mPz'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('join-notifications', (tester, world) async {
    await _open(tester, world, '/notifications');
    final chip = find.byKey(const ValueKey('inbox-filter-circles'));
    await tester.ensureVisible(chip);
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
  }),
];
