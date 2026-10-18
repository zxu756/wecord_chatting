// The edit history sheet, for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/chats/edit_history/edit_history_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<void> _openEditedThread(
  WidgetTester tester,
  PhoneWorld world, {
  bool withHistory = true,
  bool openSheet = true,
}) async {
  final sent = DateTime.now().subtract(const Duration(hours: 2));
  world.chats.messages = [
    phoneMessage('m0', bart, 'Anyone up for lunch?', minutesAgo: 130),
    phoneMessage(
      'm1',
      me,
      'Lunch at 1pm, the new ramen place',
      minutesAgo: 120,
      editedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    ),
    phoneMessage('m2', bart, 'Sounds good', minutesAgo: 30),
  ];
  world.extraOverrides = [
    editHistoryOverride(
      FakeEditHistoryRepository({
        if (withHistory)
          'm1': [
            editVersion(
              2,
              'Lunch at noon at the ramen place',
              DateTime.now().subtract(const Duration(minutes: 90)),
            ),
            editVersion(1, 'Lunch today?', sent),
          ],
      }),
    ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  if (openSheet) {
    await tester.tap(find.byKey(const ValueKey('edited-marker')));
    await settle(tester);
  }
}

final editHistoryA11yScreens = <A11yScreen>[
  A11yScreen(
    'edited-message-thread',
    (tester, world) => _openEditedThread(tester, world, openSheet: false),
  ),
  A11yScreen('edit-history-sheet', _openEditedThread),
  A11yScreen(
    'edit-history-sheet-none-kept',
    (tester, world) => _openEditedThread(tester, world, withHistory: false),
  ),
  A11yScreen(
    'edit-history-sheet-desktop',
    _openEditedThread,
    viewport: desktopViewport,
    desktop: true,
  ),
];
