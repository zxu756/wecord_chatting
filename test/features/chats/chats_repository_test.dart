import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

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
      final repository = SupabaseChatsRepository.withDataSource(dataSource);

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
      final repository = SupabaseChatsRepository.withDataSource(dataSource);

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
    final repository = SupabaseChatsRepository.withDataSource(dataSource);
    final events = <void>[];
    final subscription = repository.conversationChanges().listen(events.add);
    addTearDown(subscription.cancel);

    dataSource.emitConversationChange();
    await pumpEventQueue();

    expect(events, hasLength(1));
  });
}

class FakeChatsDataSource implements ChatsDataSource {
  var conversationRows = <Map<String, dynamic>>[];
  var rpcResult = 'conversation-1';
  var listCalls = 0;
  final rpcCalls = <RpcCall>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<Map<String, dynamic>>> listConversationSummaries() async {
    listCalls += 1;
    return conversationRows;
  }

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add(RpcCall(functionName: functionName, params: params));
    return rpcResult;
  }

  @override
  Stream<void> conversationChanges() => _changes.stream;

  void emitConversationChange() {
    _changes.add(null);
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
