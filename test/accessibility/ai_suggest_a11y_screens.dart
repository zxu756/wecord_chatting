// "Help me reply" (F6), for the accessibility guard (guidelines_test.dart) and
// the accessibility screenshot tool: the AI menu of the message box with the
// new row, the sheet asking what to say, three suggested replies (one of them
// long), nothing to reply to, and the refusals (a locked chat, the limit).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/ai/ai_fakes.dart';
import '../features/ai/draft_reply_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

FakeDraftReplyRepository _replies() =>
    FakeDraftReplyRepository()
      ..replies = const [
        'Sounds good, Friday at 8:30 works for me.',
        'Yes, 8:30 at the north lot is fine with me. Thanks for organizing the '
            'whole trip, and I can bring the extra headlamps and a thermos of '
            'tea for everyone if that helps.',
        'Could we make it 9 instead? The earlier train is hard for me.',
      ];

Future<void> _openGroup(
  WidgetTester tester,
  PhoneWorld world,
  FakeDraftReplyRepository replies,
) async {
  world.extraOverrides = [
    aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
    draftReplyRepositoryProvider.overrideWithValue(replies),
  ];
  world.chats.messages = [
    phoneMessage(
      'g1',
      bart,
      'Trailhead is at the north lot. Can someone book the 9am train on Friday?',
      minutesAgo: 40,
      conversationId: 'group-1',
    ),
    phoneMessage(
      'g2',
      grace,
      'I will bring snacks. Everybody please pack a headlamp and water.',
      minutesAgo: 38,
      conversationId: 'group-1',
    ),
    phoneMessage(
      'g3',
      bart,
      'Is 8:30 at the north lot OK for everyone?',
      minutesAgo: 1,
      conversationId: 'group-1',
    ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  await settle(tester);
}

/// The sheet, opened from the "+" menu (an empty box on a phone).
Future<void> _openSheet(
  WidgetTester tester,
  PhoneWorld world,
  FakeDraftReplyRepository replies, {
  bool desktop = false,
}) async {
  await _openGroup(tester, world, replies);
  if (desktop) {
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
  } else {
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    // The menu is long: the entry is at its end.
    await tester.ensureVisible(
      find.byKey(const ValueKey('composer-draft-reply-entry')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-draft-reply-entry')));
  }
  await settle(tester);
}

Future<void> _suggest(
  WidgetTester tester,
  PhoneWorld world,
  FakeDraftReplyRepository replies, {
  bool desktop = false,
}) async {
  await _openSheet(tester, world, replies, desktop: desktop);
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('draft-reply-intent')),
      matching: find.byType(EditableText),
    ),
    'say yes, and offer to bring the headlamps',
  );
  await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
  await settle(tester);
}

final aiSuggestA11yScreens = <A11yScreen>[
  A11yScreen('ai-suggest-menu', (tester, world) async {
    await _openGroup(tester, world, _replies());
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'yes see you there',
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
    await settle(tester);
  }),
  A11yScreen('ai-suggest-sheet', (tester, world) async {
    await _openSheet(tester, world, _replies());
  }),
  A11yScreen(
    'ai-suggest-sheet-desktop',
    (tester, world) async {
      await _openSheet(tester, world, _replies(), desktop: true);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('ai-suggest-result', (tester, world) async {
    await _suggest(tester, world, _replies());
  }),
  A11yScreen(
    'ai-suggest-result-desktop',
    (tester, world) async {
      await _suggest(tester, world, _replies(), desktop: true);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('ai-suggest-nothing', (tester, world) async {
    await _suggest(tester, world, _replies()..replies = const []);
  }),
  A11yScreen('ai-suggest-locked', (tester, world) async {
    await _suggest(
      tester,
      world,
      _replies()..error = const AiChatLockedException(),
    );
  }),
  A11yScreen('ai-suggest-limit', (tester, world) async {
    await _suggest(
      tester,
      world,
      _replies()..error = const AiLimitReachedException(limit: 50, used: 50),
    );
  }),
];
