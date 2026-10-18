// The group read list ("N read" under the newest message, the list sheet and
// "Remind unread"), the read receipts switch in Privacy & Safety and the
// "Reminder" card in Notifications, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/read_status/read_reminder_notices.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/chats/read_status/read_status_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The group "Weekend Hiking" with the user's announcement as the newest
/// message; Bart and Grace have read it, three others have not, one turned
/// receipts off.
void readStatusWorld(PhoneWorld world, {bool reminded = false}) {
  world.chats
    ..messages = [
      phoneMessage(
        'g0',
        bart,
        'Who is bringing the stove on Saturday?',
        minutesAgo: 50,
        conversationId: 'group-1',
      ),
      phoneMessage(
        'g1',
        me,
        'Meet at the north lot at 7:30. Bring layers and water, please.',
        minutesAgo: 20,
        conversationId: 'group-1',
      ),
    ]
    ..readMarkers = [
      const ConversationReadMarker(userId: 'user-1', lastReadMessageId: 'g1'),
      const ConversationReadMarker(userId: 'user-2', lastReadMessageId: 'g1'),
      const ConversationReadMarker(userId: 'user-3', lastReadMessageId: 'g1'),
      for (final profile in extraMembers)
        ConversationReadMarker(userId: profile.id, lastReadMessageId: null),
    ];
  final others = [bart, grace, linus, ...extraMembers];
  final repository = FakeReadStatusRepository({
    'g1': [
      for (final (index, profile) in others.indexed)
        member(
          profile.id,
          profile.displayName,
          index < 2
              ? ReadState.read
              : index == others.length - 1
              ? ReadState.unknown
              : ReadState.unread,
          avatarUrl: profile.avatarUrl,
        ),
    ],
  });
  if (reminded) {
    repository.reminded.add('g1');
  }
  world.extraOverrides = [
    readStatusOverride(repository),
    readReceiptsOverride(FakeReadReceiptsRepository()),
  ];
}

Future<void> _openGroup(
  WidgetTester tester,
  PhoneWorld world, {
  bool openSheet = false,
  bool reminded = false,
}) async {
  readStatusWorld(world, reminded: reminded);
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  if (openSheet) {
    await tester.tap(find.byKey(const ValueKey('group-read-count')));
    await settle(tester);
  }
}

Future<void> _openPrivacy(WidgetTester tester, PhoneWorld world) async {
  readStatusWorld(world);
  await world.open(tester, '/me');
  await scrollIntoView(tester, find.byKey(const ValueKey('read-receipts-row')));
}

Future<void> _openCard(WidgetTester tester, PhoneWorld world) async {
  readStatusWorld(world);
  world.extraOverrides = [
    ...world.extraOverrides,
    readReminderNoticesRepositoryProvider.overrideWithValue(
      FakeReadReminderNoticesRepository([
        ReadReminderNotice(
          id: 'n1',
          messageId: 'g1',
          conversationId: 'group-1',
          senderName: bart.displayName,
          senderAvatarUrl: null,
          body:
              'Meet at the north lot at 7:30. Bring layers and water, please.',
          type: MessageType.text,
          createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
        ),
      ]),
    ),
  ];
  await world.open(tester, '/notifications');
  final chip = find.byKey(const ValueKey('inbox-filter-reminders'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

final readStatusA11yScreens = <A11yScreen>[
  A11yScreen('group-read-count', _openGroup),
  A11yScreen(
    'read-status-sheet',
    (tester, world) => _openGroup(tester, world, openSheet: true),
  ),
  A11yScreen(
    'read-status-sheet-reminded',
    (tester, world) =>
        _openGroup(tester, world, openSheet: true, reminded: true),
  ),
  A11yScreen(
    'read-status-sheet-desktop',
    (tester, world) => _openGroup(tester, world, openSheet: true),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('privacy-read-receipts', _openPrivacy),
  A11yScreen('notifications-read-reminder', _openCard),
];
