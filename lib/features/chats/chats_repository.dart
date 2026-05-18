import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/chat_status.dart';
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

  Future<List<ConversationReadMarker>> listReadMarkers(String conversationId);

  Future<String> getOrCreateDirectConversation(String otherUserId);

  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  });

  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  });

  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  });

  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  });

  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  });

  Future<String> createImageUrl(ImageAttachment attachment);

  Future<void> recallMessage({required String messageId});

  Future<void> editMessage({required String messageId, required String body});

  Future<void> markConversationRead(String conversationId);

  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  );

  List<ChatMessage> searchMessages(List<ChatMessage> messages, String query);

  Stream<void> conversationChanges();

  Stream<void> messageChanges(String conversationId);

  Stream<void> threadChanges(String conversationId);

  Stream<ConversationActivity> conversationActivity(String conversationId);

  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  });
}

abstract interface class ChatsDataSource {
  Future<List<Map<String, dynamic>>> listConversationSummaries();

  Future<List<Map<String, dynamic>>> listMessages(String conversationId);

  Future<List<Map<String, dynamic>>> listReadMarkers(String conversationId);

  Future<String?> latestMessageId(String conversationId);

  Future<void> insertMessage(Map<String, dynamic> values);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  });

  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Stream<void> conversationChanges();

  Stream<void> messageChanges(String conversationId);

  Stream<void> threadChanges(String conversationId);

  Stream<ConversationActivity> conversationActivity({
    required String conversationId,
    required String currentUserId,
  });

  Future<void> sendTyping({
    required String conversationId,
    required String currentUserId,
    required bool isTyping,
  });
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
    String Function()? storagePathSeed,
    Duration storageOperationTimeout = const Duration(seconds: 30),
  }) : _currentUserId = currentUserId,
       _storagePathSeed = storagePathSeed,
       _storageOperationTimeout = storageOperationTimeout;

  final ChatsDataSource _dataSource;
  final String? Function() _currentUserId;
  final String Function()? _storagePathSeed;
  final Duration _storageOperationTimeout;

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
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async {
    final rows = await _dataSource.listReadMarkers(conversationId);
    return rows.map(ConversationReadMarker.fromJson).toList(growable: false);
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
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  }) async {
    final values = {
      'conversation_id': conversationId,
      'sender_id': _requireCurrentUserId(),
      'type': MessageType.text.toJson(),
      'body': body.trim(),
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (replyPreview != null) 'reply_preview': replyPreview.toJson(),
    };
    await _dataSource.insertMessage(values);
  }

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {
    final path =
        '$conversationId/${_nextStoragePathSeed()}-${_safeFileName(image.fileName)}';
    const bucket = 'chat-images';
    await _withStorageTimeout(
      _dataSource.uploadBinary(
        bucket: bucket,
        path: path,
        bytes: image.bytes,
        mimeType: image.mimeType,
      ),
    );
    final attachment = ImageAttachment(
      bucket: bucket,
      path: path,
      mimeType: image.mimeType,
      size: image.bytes.length,
      width: image.width,
      height: image.height,
    );
    await _dataSource.insertMessage({
      'conversation_id': conversationId,
      'sender_id': _requireCurrentUserId(),
      'type': MessageType.image.toJson(),
      'body': '',
      'attachment': attachment.toJson(),
    });
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    return _withStorageTimeout(
      _dataSource.createSignedUrl(
        bucket: attachment.bucket,
        path: attachment.path,
        expiresIn: const Duration(hours: 1),
      ),
    );
  }

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) async {
    final conversationId = await _dataSource.rpc('create_group_conversation', {
      'group_title': title.trim(),
      'member_ids': memberIds,
    });
    return conversationId as String;
  }

  @override
  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  }) async {
    await _dataSource.rpc('rename_group_conversation', {
      'target_conversation_id': conversationId,
      'group_title': title.trim(),
    });
  }

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) async {
    await _dataSource.rpc('add_group_members', {
      'target_conversation_id': conversationId,
      'member_ids': memberIds,
    });
  }

  @override
  Future<void> recallMessage({required String messageId}) async {
    await _dataSource.rpc('recall_message', {'target_message_id': messageId});
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {
    await _dataSource.rpc('edit_message', {
      'target_message_id': messageId,
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
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return _searchConversations(conversations, query);
  }

  @override
  List<ChatMessage> searchMessages(List<ChatMessage> messages, String query) {
    return _searchMessages(messages, query);
  }

  @override
  Stream<void> conversationChanges() => _dataSource.conversationChanges();

  @override
  Stream<void> messageChanges(String conversationId) {
    return _dataSource.messageChanges(conversationId);
  }

  @override
  Stream<void> threadChanges(String conversationId) {
    return _dataSource.threadChanges(conversationId);
  }

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    return _dataSource.conversationActivity(
      conversationId: conversationId,
      currentUserId: _requireCurrentUserId(),
    );
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    await _dataSource.sendTyping(
      conversationId: conversationId,
      currentUserId: _requireCurrentUserId(),
      isTyping: isTyping,
    );
  }

  String _requireCurrentUserId() {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('A signed-in user is required for chats.');
    }
    return userId;
  }

  String _nextStoragePathSeed() {
    return _storagePathSeed?.call() ??
        DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  }

  Future<T> _withStorageTimeout<T>(Future<T> operation) {
    return operation.timeout(
      _storageOperationTimeout,
      onTimeout: () {
        throw TimeoutException(
          'Image storage request timed out',
          _storageOperationTimeout,
        );
      },
    );
  }

  String _safeFileName(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final sanitized = normalized
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'image.jpg' : sanitized;
  }
}

class ChatImageUpload {
  ChatImageUpload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int? width;
  final int? height;
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
        .order('created_at', ascending: true)
        .order('id', ascending: true);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listReadMarkers(
    String conversationId,
  ) async {
    final rows = await _client
        .from('conversation_members')
        .select('user_id,last_read_message_id')
        .eq('conversation_id', conversationId);
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
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) {
    return _client.storage
        .from(bucket)
        .createSignedUrl(path, expiresIn.inSeconds);
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

  @override
  Stream<void> threadChanges(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        void emit(PostgresChangePayload payload) {
          controller.add(null);
        }

        channel = _client
            .channel('thread-changes-$conversationId')
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
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'conversation_members',
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

  @override
  Stream<ConversationActivity> conversationActivity({
    required String conversationId,
    required String currentUserId,
  }) {
    final typingUserIds = <String>{};
    final typingExpiryTimers = <String, Timer>{};
    late RealtimeChannel channel;
    late StreamController<ConversationActivity> controller;

    Set<String> onlineUserIds() {
      return {
        for (final state in channel.presenceState())
          if (state.key != currentUserId) state.key,
      };
    }

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add(
        ConversationActivity(
          onlineUserIds: onlineUserIds(),
          typingUserIds: {...typingUserIds},
        ),
      );
    }

    void expireTyping(String userId) {
      typingExpiryTimers.remove(userId)?.cancel();
      typingExpiryTimers[userId] = Timer(const Duration(seconds: 4), () {
        typingUserIds.remove(userId);
        emit();
      });
    }

    controller = StreamController<ConversationActivity>(
      onListen: () {
        channel = _client
            .channel(
              'chat-activity-$conversationId',
              opts: RealtimeChannelConfig(key: currentUserId),
            )
            .onPresenceSync((payload) {
              emit();
            })
            .onPresenceJoin((payload) {
              emit();
            })
            .onPresenceLeave((payload) {
              typingUserIds.remove(payload.key);
              typingExpiryTimers.remove(payload.key)?.cancel();
              emit();
            })
            .onBroadcast(
              event: 'typing',
              callback: (payload) {
                final userId = payload['user_id'] as String?;
                if (userId == null || userId == currentUserId) {
                  return;
                }
                final isTyping = payload['is_typing'] == true;
                if (isTyping) {
                  typingUserIds.add(userId);
                  expireTyping(userId);
                } else {
                  typingUserIds.remove(userId);
                  typingExpiryTimers.remove(userId)?.cancel();
                }
                emit();
              },
            )
            .subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.subscribed) {
                unawaited(
                  channel.track({
                    'user_id': currentUserId,
                    'online_at': DateTime.now().toUtc().toIso8601String(),
                  }),
                );
              }
            });
      },
      onCancel: () async {
        for (final timer in typingExpiryTimers.values) {
          timer.cancel();
        }
        typingExpiryTimers.clear();
        await channel.untrack();
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> sendTyping({
    required String conversationId,
    required String currentUserId,
    required bool isTyping,
  }) async {
    final channel = _client.channel('chat-activity-$conversationId');
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': currentUserId, 'is_typing': isTyping},
      );
    } finally {
      await _client.removeChannel(channel);
    }
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
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async {
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
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  }) {
    throw StateError('Supabase must be initialized before sending messages.');
  }

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) {
    throw StateError('Supabase must be initialized before sending images.');
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    throw StateError('Supabase must be initialized before loading images.');
  }

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) {
    throw StateError('Supabase must be initialized before creating groups.');
  }

  @override
  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  }) {
    throw StateError('Supabase must be initialized before renaming groups.');
  }

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) {
    throw StateError('Supabase must be initialized before adding members.');
  }

  @override
  Future<void> recallMessage({required String messageId}) {
    throw StateError('Supabase must be initialized before deleting messages.');
  }

  @override
  Future<void> editMessage({required String messageId, required String body}) {
    throw StateError('Supabase must be initialized before editing messages.');
  }

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return _searchConversations(conversations, query);
  }

  @override
  List<ChatMessage> searchMessages(List<ChatMessage> messages, String query) {
    return _searchMessages(messages, query);
  }

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();

  @override
  Stream<void> threadChanges(String conversationId) => const Stream.empty();

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    return const Stream.empty();
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) {
    throw StateError('Supabase must be initialized before sharing activity.');
  }
}

List<ConversationSummary> _searchConversations(
  List<ConversationSummary> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return conversations;
  }
  return conversations
      .where((conversation) {
        return _containsQuery(conversation.title, normalizedQuery) ||
            _containsQuery(conversation.lastMessageBody, normalizedQuery);
      })
      .toList(growable: false);
}

List<ChatMessage> _searchMessages(List<ChatMessage> messages, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return messages;
  }
  return messages
      .where((message) {
        if (message.recalledAt != null) {
          return false;
        }
        final preview = message.replyPreview;
        return _containsQuery(message.body, normalizedQuery) ||
            _containsQuery(preview?.body, normalizedQuery) ||
            _containsQuery(preview?.senderName, normalizedQuery);
      })
      .toList(growable: false);
}

bool _containsQuery(String? value, String query) {
  return value?.toLowerCase().contains(query) ?? false;
}
