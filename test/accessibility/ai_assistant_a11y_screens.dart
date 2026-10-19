// The WeCord AI assistant and "Extract to-dos", for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: a group chat with the
// assistant's answers, the Ask WeCord AI sheet, picking messages to extract
// to-dos from, the review sheet, and the group owner's switch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/extract_actions_repository.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/models/profile.dart';

import '../features/ai/ai_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

class _Extract implements ExtractActionsRepository {
  @override
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  }) async {
    final today = DateTime.now();
    return ExtractedActions(
      messageCount: messageIds.length,
      items: [
        ExtractedAction(
          title: 'Book the 9am train to the trailhead',
          assignees: [bart.id],
          due: DateTime(today.year, today.month, today.day + 2, 9),
          dueHasTime: true,
          sourceMessageId: messageIds.first,
        ),
        ExtractedAction(
          title: 'Hiking club dinner',
          due: DateTime(today.year, today.month, today.day + 3, 19),
          dueHasTime: true,
          kind: ExtractedKind.event,
        ),
        const ExtractedAction(title: 'Bring a headlamp and water'),
      ],
    );
  }
}

class _Assistant implements AssistantRepository {
  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async =>
      messageId == 'ai-question-2'
      ? const AssistantJobStatus(status: 'running')
      : messageId == 'ai-question-3'
      ? const AssistantJobStatus(status: 'skipped', reason: 'limit')
      : null;

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async => true;

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {}
}

/// The Wecord AI account as other members see it.
final _assistantProfile = Profile(
  id: 'wecord-ai',
  username: 'wecord_ai',
  displayName: 'WeCord AI',
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ChatMessage _answer(
  String id,
  String body,
  int minutesAgo,
  MessageAiReply reply,
  String replyTo,
) {
  return ChatMessage(
    id: id,
    conversationId: 'group-1',
    senderId: _assistantProfile.id,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    sender: _assistantProfile,
    replyToMessageId: replyTo,
    replyPreview: ReplyPreview(
      messageId: replyTo,
      senderName: me.displayName,
      body: '@WeCord AI …',
      type: MessageType.text,
    ),
    aiReply: reply,
  );
}

List<ChatMessage> _groupMessages() {
  ChatMessage mine(String id, String body, int minutesAgo) => phoneMessage(
    id,
    me,
    body,
    minutesAgo: minutesAgo,
    conversationId: 'group-1',
  );
  return [
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
    mine('ai-question-1', '@WeCord AI /20 list the to-dos', 30),
    _answer(
      'ai-answer-1',
      '- Book the 9am train on Friday (Bart)\n- Bring snacks (Grace)\n'
          '- Pack a headlamp and water',
      29,
      MessageAiReply(
        kind: AiReplyKind.todos,
        requesterId: me.id,
        requesterName: me.displayName,
        items: [
          {
            'title': 'Book the 9am train on Friday',
            'assignee': bart.id,
            'kind': 'task',
          },
          {'title': 'Bring snacks', 'assignee': grace.id, 'kind': 'task'},
          {'title': 'Pack a headlamp and water', 'kind': 'task'},
        ],
      ),
      'ai-question-1',
    ),
    mine('ai-question-2', '@WeCord AI summarize the plan', 2),
    mine('ai-question-3', '@WeCord AI /100 translate it all to French', 1),
    phoneMessage(
      'g3',
      bart,
      'Is 8:30 at the north lot OK for everyone?',
      minutesAgo: 0,
      conversationId: 'group-1',
    ),
  ];
}

Future<void> _openGroup(
  WidgetTester tester,
  PhoneWorld world, {
  List<ChatMessage>? messages,
}) async {
  world.extraOverrides = [
    aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
    extractActionsRepositoryProvider.overrideWithValue(_Extract()),
    assistantRepositoryProvider.overrideWithValue(_Assistant()),
  ];
  world.chats.messages = messages ?? _groupMessages();
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  // The status of the questions arrives.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await settle(tester);
}

Future<void> _selectTwo(WidgetTester tester, PhoneWorld world) async {
  await _openGroup(tester, world);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatThreadScreen)),
  );
  final messages = world.chats.messages;
  container.read(chatSelectionProvider('group-1').notifier)
    ..begin(messages[0])
    ..toggle(messages[1]);
  await settle(tester);
}

final aiAssistantA11yScreens = <A11yScreen>[
  A11yScreen('ai-assistant-thread', _openGroup),
  A11yScreen(
    'ai-assistant-thread-desktop',
    _openGroup,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('ai-assistant-ask-sheet', (tester, world) async {
    await _openGroup(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('composer-ask-ai-entry')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ask-ai-range-20')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ask-ai-question')),
        matching: find.byType(EditableText),
      ),
      'What did we decide about Friday?',
    );
    await settle(tester);
  }),
  A11yScreen('ai-assistant-ask-about-message', (tester, world) async {
    await _openGroup(tester, world);
    await tester.longPress(find.textContaining('Is 8:30 at the north lot'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('message-ask-ai')));
    await settle(tester);
  }),
  A11yScreen('extract-selection', _selectTwo),
  A11yScreen(
    'extract-selection-desktop',
    _selectTwo,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('extract-review-sheet', (tester, world) async {
    await _selectTwo(tester, world);
    await tester.tap(find.byKey(const ValueKey('selection-extract-actions')));
    await settle(tester);
  }),
  A11yScreen(
    'extract-review-sheet-desktop',
    (tester, world) async {
      await _selectTwo(tester, world);
      await tester.tap(find.byKey(const ValueKey('selection-extract-actions')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('ai-make-tasks-sheet', (tester, world) async {
    await _openGroup(tester, world);
    await tester.tap(find.byKey(const ValueKey('ai-reply-make-tasks')));
    await settle(tester);
  }),
  A11yScreen('ai-assistant-group-switch', (tester, world) async {
    await _openGroup(tester, world);
    await tester.tap(find.byTooltip(tr('Group details')));
    await settle(tester);
  }),
];
