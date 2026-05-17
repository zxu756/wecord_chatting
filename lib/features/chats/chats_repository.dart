import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  try {
    return SupabaseChatsRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const _UninitializedChatsRepository();
  }
});

abstract interface class ChatsRepository {
  Future<List<ConversationSummary>> listConversations();

  Future<List<ChatMessage>> listMessages(String conversationId);

  Future<String> getOrCreateDirectConversation(String otherUserId);

  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
  });

  Future<void> markConversationRead(String conversationId);

  Stream<void> conversationChanges();

  Stream<void> messageChanges(String conversationId);
}

abstract interface class ChatsDataSource {
  Future<List<Map<String, dynamic>>> listConversationSummaries();

  Future<List<Map<String, dynamic>>> listMessages(String conversationId);

  Future<String?> latestMessageId(String conversationId);

  Future<void> insertMessage(Map<String, dynamic> values);

  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Stream<void> conversationChanges();

  Stream<void> messageChanges(String conversationId);
}

class SupabaseChatsRepository implements ChatsRepository {
  SupabaseChatsRepository(SupabaseClient client)
    : this.withDataSource(
        SupabaseChatsDataSource(client),
        currentUserId: () => client.auth.currentUser?.id,
      );

  const SupabaseChatsRepository.withDataSource(
    this._dataSource, {
    required String? Function() currentUserId,
  }) : _currentUserId = currentUserId;

  final ChatsDataSource _dataSource;
  final String? Function() _currentUserId;

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final rows = await _dataSource.listConversationSummaries();
    return rows.map(ConversationSummary.fromJson).toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final rows = await _dataSource.listMessages(conversationId);
    return rows.map(ChatMessage.fromJson).toList(growable: false);
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async {
    final conversationId = await _dataSource.rpc(
      'get_or_create_direct_conversation',
      {'other_user_id': otherUserId},
    );
    return conversationId as String;
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
  }) async {
    await _dataSource.insertMessage({
      'conversation_id': conversationId,
      'sender_id': _requireCurrentUserId(),
      'type': MessageType.text.toJson(),
      'body': body.trim(),
    });
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    await _dataSource.rpc('mark_conversation_read', {
      'target_conversation_id': conversationId,
      'target_message_id': await _dataSource.latestMessageId(conversationId),
    });
  }

  @override
  Stream<void> conversationChanges() => _dataSource.conversationChanges();

  @override
  Stream<void> messageChanges(String conversationId) {
    return _dataSource.messageChanges(conversationId);
  }

  String _requireCurrentUserId() {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('A signed-in user is required for chats.');
    }
    return userId;
  }
}

class SupabaseChatsDataSource implements ChatsDataSource {
  const SupabaseChatsDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> listConversationSummaries() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_conversation_summaries',
    );
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<String?> latestMessageId(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(1);
    final castRows = rows.cast<Map<String, dynamic>>();
    if (castRows.isEmpty) {
      return null;
    }
    return castRows.single['id'] as String;
  }

  @override
  Future<void> insertMessage(Map<String, dynamic> values) async {
    await _client.from('messages').insert(values);
  }

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    return _client.rpc<Object?>(functionName, params: params);
  }

  @override
  Stream<void> conversationChanges() {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        channel = _client
            .channel('conversation-list-changes')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'conversations',
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              callback: emit,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'conversation_members',
              callback: emit,
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<void> messageChanges(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        channel = _client
            .channel('message-changes-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: emit,
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

class _UninitializedChatsRepository implements ChatsRepository {
  const _UninitializedChatsRepository();

  @override
  Future<List<ConversationSummary>> listConversations() async {
    return const [];
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) {
    throw StateError('Supabase must be initialized before opening chats.');
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
  }) {
    throw StateError('Supabase must be initialized before sending messages.');
  }

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();
}
