import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

ChatMessage _message(
  String id,
  String body, {
  required int minute,
  String senderId = 'user-1',
  String? webhookName,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.utc(2026, 10, 13, 9, minute),
    webhookId: webhookName == null ? null : 'webhook-1',
    webhookName: webhookName,
    webhookAvatarUrl: webhookName == null ? null : 'https://example.com/ci.png',
  );
}

void main() {
  test('webhook messages are nobody\'s own', () {
    final json = {
      'id': 'm1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Deploy finished',
      'created_at': '2026-10-13T09:00:00Z',
      'webhook_id': null,
      'webhook_name': 'CI',
      'webhook_avatar_url': 'https://example.com/ci.png',
    };
    final message = ChatMessage.fromJson(json);
    expect(message.isWebhook, isTrue, reason: 'even after the webhook is gone');
    expect(message.isSentBy('user-1'), isFalse);
    expect(message.authorKey, isNot('user-1'));
    final own = ChatMessage.fromJson({...json, 'webhook_name': null});
    expect(own.isSentBy('user-1'), isTrue);
    expect(own.isSentBy(null), isFalse);
    expect(
      ConversationSummary.fromJson({
        'id': 'c1',
        'type': 'channel',
        'unread_count': 1,
        'last_message_webhook_name': 'CI',
      }).lastMessageWebhookName,
      'CI',
    );
  });

  testWidgets('shows the webhook name and a BOT tag, not the creator', (
    tester,
  ) async {
    final chats = chat_fakes.FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.channel,
          unreadCount: 0,
          title: 'general',
          circleId: 'circle-1',
        ),
      ]
      ..messages = [
        _message('m1', 'My own note', minute: 0),
        _message('m2', '**Deploy** finished', minute: 1, webhookName: 'CI'),
        _message('m3', 'Tests passed', minute: 2, webhookName: 'CI'),
      ];
    await tester.pumpWidget(_app(chats));
    await tester.pump();

    expect(find.text('CI'), findsOneWidget, reason: 'grouped messages');
    expect(find.byKey(const ValueKey('message-bot-tag')), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    // Webhook messages carry the webhook's avatar, not the creator's.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ChatAvatar && widget.name == 'CI',
      ),
      findsOneWidget,
    );

    await tester.longPress(find.text('Tests passed'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  test('audit log reads webhook entries', () {
    CircleAuditEntry entry(String action, [Map<String, dynamic>? changes]) {
      return CircleAuditEntry(
        id: 'a',
        circleId: 'circle-1',
        action: action,
        targetType: 'webhook',
        targetLabel: 'CI',
        changes: changes ?? const {},
        createdAt: DateTime.utc(2026, 10, 14),
        actor: const CircleAuditActor(
          id: 'user-1',
          username: 'ada',
          displayName: 'Ada',
        ),
      );
    }

    String summary(CircleAuditEntry entry) =>
        circleAuditSummary(entry, null).toPlainText();

    expect(
      summary(entry('webhook_create', {'channel_name': 'general'})),
      'Ada created webhook CI in #general',
    );
    expect(
      summary(
        entry('webhook_update', {
          'name': {'old': 'Bot', 'new': 'CI'},
        }),
      ),
      'Ada renamed webhook Bot to CI',
    );
    expect(
      summary(entry('webhook_regenerate')),
      'Ada regenerated the URL of webhook CI',
    );
    expect(summary(entry('webhook_delete')), 'Ada deleted webhook CI');
    expect(circleAuditIcon('webhook_create'), Icons.smart_toy_outlined);
    expect(
      CircleAuditActionGroup.of('webhook_regenerate'),
      CircleAuditActionGroup.webhook,
    );
    expect(
      CircleAuditActionGroup.filters,
      contains(CircleAuditActionGroup.webhook),
    );
  });
}

Widget _app(chat_fakes.FakeChatsRepository chats) {
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
    child: const MaterialApp(
      home: ChatThreadScreen(conversationId: 'conversation-1'),
    ),
  );
}
