// AI guard 2.0 and link safety, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the guard's
// settings with what else it checks, the Review queue with a held picture, a
// poll and the flagged events and tasks, the warning page for a risky link
// (with the AI's answer), and the hint under a stranger's message in a group.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/circles/guard2/review_media.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/safety/link_check_repository.dart';
import 'package:wecord/features/safety/link_risk.dart';
import 'package:wecord/features/safety/link_warning_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/circles/ai_guard_fakes.dart';
import '../features/circles/guard2_fakes.dart';
import '../features/safety/link_safety_test.dart' show FakeLinkCheck;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The fakes behind the guard's settings and the Review queue.
List<Override> guard2A11yOverrides() {
  final rpc = FakeGuardRpc()
    ..results['get_circle_ai_guard'] = guardJson(enabled: true)
    ..results['count_message_reviews'] = 2
    ..results['list_message_reviews'] = [
      reviewJson(
        id: 'message-1',
        body: '',
        verdict: 'sexual',
        reason: 'Nudity',
      ),
      reviewJson(
        id: 'message-2',
        state: 'flagged',
        body: 'Where should the prizes go?',
        reason: 'Pushes pills',
      ),
    ]
    ..results['list_message_review_media'] = [
      {
        'message_id': 'message-1',
        'type': 'image',
        'media': {
          'bucket': 'chat-images',
          'path': 'c/p.png',
          'mime_type': 'image/png',
        },
      },
      {
        'message_id': 'message-2',
        'type': 'poll',
        'media': {
          'options': ['Cash', 'Pills at pills.example'],
        },
      },
    ];
  final guard2 = FakeGuard2Rpc()
    ..results['get_circle_ai_guard_scope'] = scopeJson(
      images: true,
      vision: true,
    )
    ..results['count_guard_item_reviews'] = 2
    ..results['list_guard_item_reviews'] = [
      itemJson(),
      itemJson(
        id: 'item-2',
        type: 'task_item',
        title: 'Send me your password',
        detail: 'Quick favour',
        reason: 'Asks for a password',
      ),
    ];
  return [
    circleAiGuardRepositoryProvider.overrideWithValue(
      CircleAiGuardRepository(rpc),
    ),
    guard2RepositoryProvider.overrideWithValue(Guard2Repository(guard2.call)),
    reviewImageUrlProvider.overrideWith(
      (ref, file) async => 'https://example.test/${file.path}',
    ),
    pendingJoinRequestsProvider.overrideWith((ref, circleId) async => const []),
    joinRequestCountProvider.overrideWith((ref, circleId) async => 0),
  ];
}

Future<void> _fromMenu(
  WidgetTester tester,
  PhoneWorld world,
  String item,
) async {
  world.extraOverrides = guard2A11yOverrides();
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

/// The warning page, opened over the chat list the way a tapped link opens
/// it. With the AI's answer showing when [asked].
Future<void> _warning(
  WidgetTester tester,
  PhoneWorld world, {
  bool asked = false,
}) async {
  world.extraOverrides = [
    linkCheckRepositoryProvider.overrideWithValue(
      FakeLinkCheck()
        ..result = const LinkCheckResult(
          verdict: LinkVerdict.suspicious,
          reason: 'Imitates PayPal and pushes you to log in.',
        ),
    ),
    aiAvailableProvider.overrideWith((ref, circleId) => true),
  ];
  await world.open(tester, ChatsScreen.path);
  await settle(tester);
  const url = 'https://paypal-login.example/verify?id=1';
  showLinkWarning(
    tester.element(find.byType(Scaffold).first),
    uri: Uri.parse(url),
    risk: assessLink(url),
    redirectHost: 'secure-paypal-check.top',
  );
  await settle(tester);
  expect(find.byType(LinkWarningScreen), findsOneWidget);
  if (asked) {
    final button = find.byKey(const ValueKey('link-warning-ask-ai'));
    await tester.ensureVisible(button);
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
  }
}

/// A stranger in a group asks for money and for a code.
Future<void> _scamHint(WidgetTester tester, PhoneWorld world) async {
  final stranger = extraMembers.first;
  world.extraOverrides = [
    chatConversationSummaryProvider.overrideWith(
      (ref, id) async => const ConversationSummary(
        id: 'group-1',
        type: ConversationType.group,
        unreadCount: 0,
      ),
    ),
  ];
  world.chats.messages = [
    phoneMessage(
      's1',
      bart,
      'Welcome to the group!',
      minutesAgo: 30,
      conversationId: 'group-1',
    ),
    phoneMessage(
      's2',
      stranger,
      'Congrats, you won! Send me the money for the fee and read me the verification code.',
      minutesAgo: 3,
      conversationId: 'group-1',
    ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: const ChatThreadRouteExtra(
      title: 'Weekend plans',
      type: ConversationType.group,
    ),
  );
  await settle(tester);
  expect(find.byKey(const ValueKey('scam-hint')), findsOneWidget);
}

final guard2A11yScreens = <A11yScreen>[
  A11yScreen(
    'guard2-settings',
    (tester, world) => _fromMenu(tester, world, 'AI guard'),
  ),
  A11yScreen(
    'desktop-guard2-settings',
    (tester, world) => _fromMenu(tester, world, 'AI guard'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'guard2-review',
    (tester, world) => _fromMenu(tester, world, 'Review'),
  ),
  A11yScreen(
    'desktop-guard2-review',
    (tester, world) => _fromMenu(tester, world, 'Review'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('link-warning', _warning),
  A11yScreen(
    'link-warning-ai',
    (tester, world) => _warning(tester, world, asked: true),
  ),
  A11yScreen(
    'desktop-link-warning',
    _warning,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('scam-hint', _scamHint),
];
