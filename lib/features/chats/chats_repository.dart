import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/conversation.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  try {
    return SupabaseChatsRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const _UninitializedChatsRepository();
  }
});

abstract interface class ChatsRepository {
  Future<List<ConversationSummary>> listConversations();

  Future<String> getOrCreateDirectConversation(String otherUserId);

  Stream<void> conversationChanges();
}

abstract interface class ChatsDataSource {
  Future<List<Map<String, dynamic>>> listConversationSummaries();

  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Stream<void> conversationChanges();
}

class SupabaseChatsRepository implements ChatsRepository {
  SupabaseChatsRepository(SupabaseClient client)
    : this.withDataSource(SupabaseChatsDataSource(client));

  const SupabaseChatsRepository.withDataSource(this._dataSource);

  final ChatsDataSource _dataSource;

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final rows = await _dataSource.listConversationSummaries();
    return rows.map(ConversationSummary.fromJson).toList(growable: false);
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
  Stream<void> conversationChanges() => _dataSource.conversationChanges();
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
}

class _UninitializedChatsRepository implements ChatsRepository {
  const _UninitializedChatsRepository();

  @override
  Future<List<ConversationSummary>> listConversations() async {
    return const [];
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) {
    throw StateError('Supabase must be initialized before opening chats.');
  }

  @override
  Stream<void> conversationChanges() => const Stream.empty();
}
