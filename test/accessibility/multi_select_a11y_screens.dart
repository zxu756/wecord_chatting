// Multi-select, merged forwards and contact cards, for the accessibility
// guard (guidelines_test.dart) and the accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/features/contact_cards/contact_cards_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/chats/merged_forward/merged_forward_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A direct chat with a chat history and two contact cards after the
/// usual messages.
Future<void> _openCards(
  WidgetTester tester,
  PhoneWorld world, {
  bool onlyHistory = false,
}) async {
  final merged = FakeMergedForwardRepository(
    bundles: {
      'history-1': ChatHistoryBundle.fromJson({
        'title': 'Climbing crew',
        'items': bundleItemJson(),
      }),
    },
  );
  world.extraOverrides = [
    mergedForwardRepositoryProvider.overrideWithValue(merged),
    contactCardsRepositoryProvider.overrideWithValue(
      FakeContactCardsRepository(),
    ),
  ];
  world.chats.messages = onlyHistory
      ? [
          chatHistoryMessage(
            senderId: bart.id,
            createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ]
      : [
          // The usual messages, without the one with a link: a link is a
          // control of its own, which this screen is not about.
          for (final message in richMessages())
            if (!message.body.contains('Also this')) message,
          chatHistoryMessage(
            senderId: bart.id,
            createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
          ),
          contactCardMessage(
            senderId: me.id,
            createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
            card: {
              'kind': 'contact_card',
              'card': 'user',
              'user_id': grace.id,
              'name': grace.displayName,
              'username': grace.username,
            },
          ),
          contactCardMessage(
            id: 'card-2',
            senderId: bart.id,
            createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
            card: {
              'kind': 'contact_card',
              'card': 'circle',
              'circle_id': 'circle-5',
              'name': 'Climbing',
              'member_count': 14,
              'invite_code': 'abcdefghij',
            },
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
  await settle(tester);
}

/// A direct chat in selection mode with two messages ticked.
Future<void> _openSelecting(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = richMessages();
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatThreadScreen)),
  );
  final controller = container.read(chatSelectionProvider('dm-1').notifier);
  final messages = world.chats.messages;
  controller
    ..begin(messages[1])
    ..toggle(messages[2]);
  await settle(tester);
}

final multiSelectA11yScreens = <A11yScreen>[
  A11yScreen('selection-mode', _openSelecting),
  A11yScreen(
    'selection-mode-desktop',
    _openSelecting,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('selection-merge-sheet', (tester, world) async {
    await _openSelecting(tester, world);
    await tester.tap(find.byKey(const ValueKey('selection-merge')));
    await settle(tester);
  }),
  A11yScreen('chat-history-and-contact-cards', _openCards),
  A11yScreen('chat-history-page', (tester, world) async {
    await _openCards(tester, world, onlyHistory: true);
    await tester.tap(find.byKey(const ValueKey('chat-history-card-history-1')));
    await settle(tester);
  }),
  A11yScreen('contact-card-picker', (tester, world) async {
    await _openCards(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-contact-card-entry')));
    await settle(tester);
  }),
];
