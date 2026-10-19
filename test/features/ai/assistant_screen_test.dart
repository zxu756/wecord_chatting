import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/extract_actions_repository.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/models/profile.dart';

import '../chats/events/chat_events_test.dart' show FakeChatEventsRepository;
import '../workspace/workspace_fakes.dart';
import 'ai_chat_app.dart';
import 'ai_fakes.dart';

/// The assistant and "Extract to-dos" in the real chat page: the AI's answers
/// carry their mark, the menus offer the features, and picking messages then
/// "Extract to-dos" opens the review.
class _Extract implements ExtractActionsRepository {
  final calls = <List<String>>[];

  @override
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  }) async {
    calls.add(messageIds);
    return const ExtractedActions(
      messageCount: 2,
      items: [ExtractedAction(title: 'Bring snacks')],
    );
  }
}

class _Assistant implements AssistantRepository {
  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async =>
      messageId == 'question'
      ? const AssistantJobStatus(status: 'skipped', reason: 'group_off')
      : null;

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async => true;

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {}
}

ChatMessage _aiAnswer() => ChatMessage(
  id: 'answer',
  conversationId: 'conversation-1',
  senderId: 'wecord-ai',
  type: MessageType.text,
  body: '- Meet at 7\n- Ben brings snacks',
  createdAt: DateTime.now(),
  aiReply: const MessageAiReply(
    kind: AiReplyKind.summary,
    requesterId: 'user-1',
    requesterName: 'Ana',
  ),
  sender: Profile(
    id: 'wecord-ai',
    username: 'wecord_ai',
    displayName: 'WeCord AI',
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
);

void main() {
  late _Extract extract;
  late FakeListsRepository lists;

  AiChatHarness harness() {
    extract = _Extract();
    lists = FakeListsRepository();
    return AiChatHarness(
      FakeAiRepository(),
      type: ConversationType.group,
      messages: [
        AiChatHarness.message('message-1', 'user-2', 'Meet at 7?', 1),
        AiChatHarness.message('message-2', 'user-1', 'I can make it', 2),
        _aiAnswer(),
        ChatMessage(
          id: 'question',
          conversationId: 'conversation-1',
          senderId: 'user-1',
          type: MessageType.text,
          body: '@WeCord AI /20 anything else?',
          createdAt: DateTime.now(),
        ),
      ],
      extraOverrides: [
        extractActionsRepositoryProvider.overrideWithValue(extract),
        assistantRepositoryProvider.overrideWithValue(_Assistant()),
        listsRepositoryProvider.overrideWithValue(lists),
        chatEventsRepositoryProvider.overrideWithValue(
          FakeChatEventsRepository([]),
        ),
        conversationMembersProvider(
          'conversation-1',
        ).overrideWith((ref) async => const []),
      ],
    );
  }

  testWidgets(
    'an AI answer is marked, and your question says why it got none',
    (tester) async {
      await tester.pumpWidget(harness().build());
      await tester.pumpAndSettle();
      expect(find.text('AI-generated · asked by Ana'), findsOneWidget);
      expect(find.text('WeCord AI'), findsWidgets);
      expect(
        find.text('The group owner turned off WeCord AI here.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the message menu offers Ask WeCord AI', (tester) async {
    await tester.pumpWidget(harness().build());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Meet at 7?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-ask-ai')), findsOneWidget);
    // The AI's own answers are not asked about again.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('- Meet at 7\n- Ben brings snacks'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-ask-ai')), findsNothing);
  });

  testWidgets('selecting messages then Extract to-dos opens the review', (
    tester,
  ) async {
    await tester.pumpWidget(harness().build());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Meet at 7?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I can make it'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('selection-extract-actions')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('selection-extract-actions')));
    await tester.pumpAndSettle();
    expect(extract.calls.single, ['message-1', 'message-2']);
    expect(find.text('Bring snacks'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    expect(lists.upserts.single['title'], 'Bring snacks');
    // Done: back to the chat, out of selection mode.
    expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
    expect(find.text('Task created.'), findsOneWidget);
  });

  testWidgets('the composer menu has Ask WeCord AI', (tester) async {
    await tester.pumpWidget(harness().build());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-ask-ai-entry')), findsOneWidget);
  });
}
