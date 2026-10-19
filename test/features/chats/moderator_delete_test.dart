import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/profile.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

ChatMessage _message(
  String id,
  String body, {
  required int minute,
  String senderId = 'user-2',
  String? webhookName,
  DateTime? recalledAt,
  String? recalledBy,
  MessageType type = MessageType.text,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: body,
    createdAt: DateTime.utc(2026, 10, 14, 9, minute),
    recalledAt: recalledAt,
    recalledBy: recalledBy,
    webhookId: webhookName == null ? null : 'webhook-1',
    webhookName: webhookName,
    webhookAvatarUrl: webhookName == null ? null : 'https://example.com/ci.png',
  );
}

chat_fakes.FakeChatsRepository _channel(List<ChatMessage> messages) {
  return chat_fakes.FakeChatsRepository()
    ..conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.channel,
        unreadCount: 0,
        title: 'general',
        circleId: 'circle-1',
      ),
    ]
    ..messages = messages;
}

void main() {
  test('recalled_by tells a moderator deletion from the sender\'s own', () {
    final json = {
      'id': 'm1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-2',
      'type': 'text',
      'body': 'Spam',
      'created_at': '2026-10-14T09:00:00Z',
      'recalled_at': '2026-10-14T09:05:00Z',
      'recalled_by': 'user-1',
    };
    final byModerator = ChatMessage.fromJson(json);
    expect(byModerator.recalledBy, 'user-1');
    expect(byModerator.isDeletedByModerator, isTrue);
    expect(byModerator.deletedLabel, 'Message deleted by a moderator');

    final bySender = ChatMessage.fromJson({...json, 'recalled_by': 'user-2'});
    expect(bySender.isDeletedByModerator, isFalse);
    expect(bySender.deletedLabel, 'Message deleted');
    // Messages deleted before recalled_by existed read as the sender's own.
    final legacy = ChatMessage.fromJson({...json, 'recalled_by': null});
    expect(legacy.deletedLabel, 'Message deleted');
    expect(
      ChatMessage.fromJson({...json, 'recalled_at': null}).isDeletedByModerator,
      isFalse,
    );
  });

  testWidgets('moderators delete others\' messages after confirming', (
    tester,
  ) async {
    final chats = _channel([
      _message('m1', 'Buy cheap stuff', minute: 0),
      _message('m2', 'My note', minute: 1, senderId: 'user-1'),
    ])..canModerateMessagesValue = true;
    await tester.pumpWidget(_app(chats));
    await tester.pump();

    await tester.longPress(find.text('Buy cheap stuff'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    // The menu scrolls on a short screen.
    await tester.ensureVisible(
      find.byKey(const ValueKey('message-moderator-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-moderator-delete')));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete this message for everyone? This cannot be undone.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chats.recalledMessageIds, isEmpty);

    await tester.longPress(find.text('Buy cheap stuff'));
    await tester.pumpAndSettle();
    // The menu scrolls on a short screen.
    await tester.ensureVisible(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-delete-confirm')));
    await tester.pumpAndSettle();
    expect(chats.recalledMessageIds, ['m1']);

    // Their own messages keep the plain Delete, without a confirmation.
    await tester.longPress(find.text('My note'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('message-moderator-delete')),
      findsNothing,
    );
    // The menu scrolls on a short screen.
    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(chats.recalledMessageIds, ['m1', 'm2']);
  });

  testWidgets('members without moderation cannot delete others\' messages', (
    tester,
  ) async {
    final chats = _channel([
      _message('m1', 'Hello there', minute: 0),
      _message('m2', 'Deploy done', minute: 1, webhookName: 'CI'),
    ]);
    await tester.pumpWidget(_app(chats));
    await tester.pump();

    await tester.longPress(find.text('Hello there'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('message-moderator-delete')),
      findsNothing,
    );
    expect(find.text('Delete'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Someone else's webhook.
    await tester.longPress(find.text('Deploy done'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('message-moderator-delete')),
      findsNothing,
    );
  });

  testWidgets('a webhook\'s creator deletes its messages', (tester) async {
    final chats = _channel([
      _message(
        'm1',
        'Deploy done',
        minute: 0,
        senderId: 'user-1',
        webhookName: 'CI',
      ),
    ]);
    await tester.pumpWidget(_app(chats));
    await tester.pump();

    await tester.longPress(find.text('Deploy done'));
    await tester.pumpAndSettle();
    // The menu scrolls on a short screen.
    await tester.ensureVisible(
      find.byKey(const ValueKey('message-moderator-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-moderator-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-delete-confirm')));
    await tester.pumpAndSettle();
    expect(chats.recalledMessageIds, ['m1']);
  });

  testWidgets('says when a moderator deleted a message', (tester) async {
    final deletedAt = DateTime.utc(2026, 10, 14, 10);
    final chats = _channel([
      _message(
        'm1',
        'Spam',
        minute: 0,
        recalledAt: deletedAt,
        recalledBy: 'user-1',
      ),
      _message(
        'm2',
        'Oops',
        minute: 1,
        recalledAt: deletedAt,
        recalledBy: 'user-2',
      ),
    ]);
    await tester.pumpWidget(_app(chats));
    await tester.pump();

    expect(find.text('Message deleted by a moderator'), findsOneWidget);
    expect(find.text('Message deleted'), findsOneWidget);
    expect(find.text('Spam'), findsNothing);
  });

  testWidgets('pinned webhook messages show the webhook', (tester) async {
    final chats = _channel(const [])
      ..pinnedMessages = [
        PinnedMessage(
          message: _message('m1', 'Deploy done', minute: 0, webhookName: 'CI'),
          sender: Profile(
            id: 'user-2',
            username: 'grace',
            displayName: 'Grace Hopper',
            bio: '',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          pinnedAt: DateTime.utc(2026, 10, 14, 9, 5),
        ),
      ];
    await tester.pumpWidget(
      _wrap(
        chats,
        Scaffold(
          body: PinnedMessagesSheet(
            conversationId: 'conversation-1',
            canManagePins: false,
            onUnpin: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CI'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-bot-tag')), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNothing);
    // The avatar image cannot load in tests: the initials stay.
    expect(find.text('C'), findsOneWidget);
  });

  test('audit log reads message deletions', () {
    final entry = CircleAuditEntry(
      id: 'a',
      circleId: 'circle-1',
      action: 'message_delete',
      targetType: 'message',
      targetLabel: 'Grace',
      changes: const {
        'channel_id': 'channel-1',
        'channel_name': 'general',
        'author_id': 'user-2',
      },
      createdAt: DateTime.utc(2026, 10, 14),
      actor: const CircleAuditActor(
        id: 'user-1',
        username: 'ada',
        displayName: 'Ada',
      ),
    );
    expect(
      circleAuditSummary(entry, null).toPlainText(),
      'Ada deleted a message by Grace in #general',
    );
    expect(circleAuditDetails(entry), isEmpty);
    expect(circleAuditIcon('message_delete'), Icons.delete_outline);
    expect(
      CircleAuditActionGroup.of('message_delete'),
      CircleAuditActionGroup.message,
    );
    expect(CircleAuditActionGroup.message.label, 'Messages');
  });
}

Widget _wrap(chat_fakes.FakeChatsRepository chats, Widget home) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
      onlineUserIdsProvider.overrideWith(
        (ref) => const Stream<Set<String>>.empty(),
      ),
      authRepositoryProvider.overrideWithValue(
        chat_fakes.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(home: home),
  );
}

Widget _app(chat_fakes.FakeChatsRepository chats) {
  return _wrap(chats, const ChatThreadScreen(conversationId: 'conversation-1'));
}
