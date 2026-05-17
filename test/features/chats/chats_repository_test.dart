import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  test(
    'listConversations maps summary rows and preserves unread counts',
    () async {
      final dataSource = FakeChatsDataSource()
        ..conversationRows = [
          {
            'id': 'conversation-1',
            'type': 'direct',
            'title': 'Ada Lovelace',
            'avatar_url': null,
            'last_message_body': 'See you soon',
            'last_message_at': '2026-05-18T04:30:00.000Z',
            'unread_count': 3,
          },
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final conversations = await repository.listConversations();

      expect(conversations, hasLength(1));
      expect(conversations.single, isA<ConversationSummary>());
      expect(conversations.single.id, 'conversation-1');
      expect(conversations.single.type, ConversationType.direct);
      expect(conversations.single.title, 'Ada Lovelace');
      expect(conversations.single.lastMessageBody, 'See you soon');
      expect(
        conversations.single.lastMessageAt,
        DateTime.utc(2026, 5, 18, 4, 30),
      );
      expect(conversations.single.unreadCount, 3);
      expect(dataSource.listCalls, 1);
    },
  );

  test(
    'getOrCreateDirectConversation calls the direct conversation RPC',
    () async {
      final dataSource = FakeChatsDataSource()..rpcResult = 'conversation-2';
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final conversationId = await repository.getOrCreateDirectConversation(
        'user-2',
      );

      expect(conversationId, 'conversation-2');
      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'get_or_create_direct_conversation',
          params: {'other_user_id': 'user-2'},
        ),
      ]);
    },
  );

  test('conversationChanges emits when the data source invalidates', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final events = <void>[];
    final subscription = repository.conversationChanges().listen(events.add);
    addTearDown(subscription.cancel);

    dataSource.emitConversationChange();
    await pumpEventQueue();

    expect(events, hasLength(1));
  });

  test('listMessages maps message rows in chronological order', () async {
    final dataSource = FakeChatsDataSource()
      ..messageRows = [
        {
          'id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'type': 'text',
          'body': 'First',
          'attachment': null,
          'reply_to_message_id': null,
          'edited_at': null,
          'recalled_at': null,
          'created_at': '2026-05-18T04:30:00.000Z',
        },
        {
          'id': 'message-2',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-1',
          'type': 'text',
          'body': 'Second',
          'attachment': null,
          'reply_to_message_id': null,
          'edited_at': null,
          'recalled_at': null,
          'created_at': '2026-05-18T04:31:00.000Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final messages = await repository.listMessages('conversation-1');

    expect(messages.map((message) => message.body), ['First', 'Second']);
    expect(messages.first, isA<ChatMessage>());
    expect(dataSource.listMessageCalls, ['conversation-1']);
  });

  test('sendTextMessage trims text and inserts the current sender', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.sendTextMessage(
      conversationId: 'conversation-1',
      body: '  Hello Ada  ',
    );

    expect(dataSource.insertedMessages, [
      {
        'conversation_id': 'conversation-1',
        'sender_id': 'user-1',
        'type': 'text',
        'body': 'Hello Ada',
      },
    ]);
  });

  test(
    'markConversationRead calls the read RPC with latest message id',
    () async {
      final dataSource = FakeChatsDataSource()
        ..latestMessageResult = 'message-2';
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await repository.markConversationRead('conversation-1');

      expect(dataSource.latestMessageCalls, ['conversation-1']);
      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'mark_conversation_read',
          params: {
            'target_conversation_id': 'conversation-1',
            'target_message_id': 'message-2',
          },
        ),
      ]);
    },
  );

  test('messageChanges emits when matching messages invalidate', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final events = <void>[];
    final subscription = repository
        .messageChanges('conversation-1')
        .listen(events.add);
    addTearDown(subscription.cancel);

    dataSource.emitMessageChange('conversation-1');
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(dataSource.messageChangeConversationIds, ['conversation-1']);
  });
}

class FakeChatsDataSource implements ChatsDataSource {
  var conversationRows = <Map<String, dynamic>>[];
  var messageRows = <Map<String, dynamic>>[];
  var rpcResult = 'conversation-1';
  String? latestMessageResult;
  var listCalls = 0;
  final listMessageCalls = <String>[];
  final latestMessageCalls = <String>[];
  final insertedMessages = <Map<String, dynamic>>[];
  final rpcCalls = <RpcCall>[];
  final _changes = StreamController<void>.broadcast();
  final _messageChanges = <String, StreamController<void>>{};
  final messageChangeConversationIds = <String>[];

  @override
  Future<List<Map<String, dynamic>>> listConversationSummaries() async {
    listCalls += 1;
    return conversationRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(String conversationId) async {
    listMessageCalls.add(conversationId);
    return messageRows;
  }

  @override
  Future<String?> latestMessageId(String conversationId) async {
    latestMessageCalls.add(conversationId);
    return latestMessageResult;
  }

  @override
  Future<void> insertMessage(Map<String, dynamic> values) async {
    insertedMessages.add(values);
  }

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add(RpcCall(functionName: functionName, params: params));
    return rpcResult;
  }

  @override
  Stream<void> conversationChanges() => _changes.stream;

  @override
  Stream<void> messageChanges(String conversationId) {
    messageChangeConversationIds.add(conversationId);
    return _messageChanges
        .putIfAbsent(conversationId, () => StreamController<void>.broadcast())
        .stream;
  }

  void emitConversationChange() {
    _changes.add(null);
  }

  void emitMessageChange(String conversationId) {
    _messageChanges[conversationId]?.add(null);
  }
}

class RpcCall {
  const RpcCall({required this.functionName, required this.params});

  final String functionName;
  final Map<String, dynamic> params;

  @override
  bool operator ==(Object other) {
    return other is RpcCall &&
        other.functionName == functionName &&
        _mapsEqual(other.params, params);
  }

  @override
  int get hashCode => Object.hash(functionName, Object.hashAll(params.entries));
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
