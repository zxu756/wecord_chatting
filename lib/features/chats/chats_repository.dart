import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/media_attachment.dart';
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

  Future<ConversationSummary?> getConversationSummary(String conversationId);

  Future<List<ChatMessage>> listMessages(String conversationId);

  Future<List<ConversationReadMarker>> listReadMarkers(String conversationId);

  Future<String> getOrCreateDirectConversation(String otherUserId);

  Future<GroupDetail> getGroupDetail(String conversationId);

  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  });

  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  });

  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  });

  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  });

  Future<List<MessageSearchResult>> searchMessages(String query);

  Future<List<DiscoveryResult>> searchDiscovery(String query);

  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  );

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

  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  });

  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  });

  Future<void> leaveGroupConversation(String conversationId);

  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  });

  Future<String> createImageUrl(ImageAttachment attachment);

  Future<String> createVoiceUrl(VoiceAttachment attachment);

  Future<void> recallMessage({required String messageId});

  Future<void> editMessage({required String messageId, required String body});

  Future<void> markConversationRead(String conversationId);

  Future<void> markConversationUnread(String conversationId);

  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  });

  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  });

  Future<void> hideConversation(String conversationId);

  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  );

  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  );

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

  Future<List<Map<String, dynamic>>> listGroupMembers(String conversationId);

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
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async {
    final conversations = await listConversations();
    for (final conversation in conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
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
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    final conversations = await listConversations();
    ConversationSummary? conversation;
    for (final item in conversations) {
      if (item.id == conversationId) {
        conversation = item;
        break;
      }
    }
    final memberRows = await _dataSource.listGroupMembers(conversationId);
    return GroupDetail(
      conversationId: conversationId,
      title: conversation?.title ?? conversationId,
      avatarUrl: conversation?.avatarUrl,
      announcement: conversation?.announcement ?? '',
      announcementUpdatedAt: conversation?.announcementUpdatedAt,
      announcementUpdatedBy: conversation?.announcementUpdatedBy,
      currentUserRole: _currentUserRole(memberRows),
      members: memberRows.map(_groupMemberFromJson).toList(growable: false),
    );
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {
    final trimmedBody = body.trim();
    if (mentions.isNotEmpty) {
      await _dataSource.rpc('send_text_message', {
        'target_conversation_id': conversationId,
        'body': trimmedBody,
        'reply_to_message_id': replyToMessageId,
        'reply_preview': replyPreview?.toJson(),
        'mentions': mentions.map((mention) => mention.toJson()).toList(),
      });
      return;
    }
    final values = {
      'conversation_id': conversationId,
      'sender_id': _requireCurrentUserId(),
      'type': MessageType.text.toJson(),
      'body': trimmedBody,
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
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {
    const bucket = 'voice-messages';
    final extension = _voiceStorageExtension(mimeType);
    final path = '$conversationId/${_nextStoragePathSeed()}.$extension';
    await _withStorageTimeout(
      _dataSource.uploadBinary(
        bucket: bucket,
        path: path,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
    final attachment = VoiceAttachment(
      bucket: bucket,
      path: path,
      mimeType: mimeType,
      size: bytes.length,
      durationMs: durationMs,
    );
    await _dataSource.insertMessage({
      'conversation_id': conversationId,
      'sender_id': _requireCurrentUserId(),
      'type': MessageType.voice.toJson(),
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
  Future<String> createVoiceUrl(VoiceAttachment attachment) {
    return _withStorageTimeout(
      _dataSource.createSignedUrl(
        bucket: attachment.bucket,
        path: attachment.path,
        expiresIn: const Duration(hours: 1),
      ),
    );
  }

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) async {
    await _dataSource.rpc('forward_message', {
      'source_message_id': sourceMessageId,
      'target_conversation_id': targetConversationId,
    });
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }
    final rows = await _dataSource.rpc('search_messages', {
      'search_query': trimmedQuery,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(MessageSearchResult.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }
    final rows = await _dataSource.rpc('search_discovery', {
      'search_query': trimmedQuery,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(DiscoveryResult.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) async {
    final rows = await _dataSource.rpc('list_conversation_media', {
      'target_conversation_id': conversationId,
    });
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ConversationMediaItem.fromJson)
        .toList(growable: false);
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
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) async {
    const bucket = 'group-avatars';
    final path =
        '$conversationId/${_nextStoragePathSeed()}-${_safeFileName(image.fileName)}';
    await _withStorageTimeout(
      _dataSource.uploadBinary(
        bucket: bucket,
        path: path,
        bytes: image.bytes,
        mimeType: image.mimeType,
      ),
    );
    return '$bucket/$path';
  }

  @override
  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  }) async {
    await _dataSource.rpc('update_group_profile', {
      'target_conversation_id': conversationId,
      'group_title': title.trim(),
      'avatar_url': avatarUrl,
      'announcement': announcement.trim(),
    });
  }

  @override
  Future<void> leaveGroupConversation(String conversationId) async {
    await _dataSource.rpc('leave_group_conversation', {
      'target_conversation_id': conversationId,
    });
  }

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  }) async {
    await _dataSource.rpc('remove_group_member', {
      'target_conversation_id': conversationId,
      'target_user_id': memberId,
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
  Future<void> markConversationUnread(String conversationId) async {
    await _dataSource.rpc('mark_conversation_unread', {
      'target_conversation_id': conversationId,
    });
  }

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {
    await _dataSource.rpc('set_conversation_pinned', {
      'target_conversation_id': conversationId,
      'pinned': pinned,
    });
  }

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {
    await _dataSource.rpc('set_conversation_muted', {
      'target_conversation_id': conversationId,
      'muted': muted,
    });
  }

  @override
  Future<void> hideConversation(String conversationId) async {
    await _dataSource.rpc('hide_conversation', {
      'target_conversation_id': conversationId,
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
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) {
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

  String _voiceStorageExtension(String mimeType) {
    switch (mimeType.toLowerCase().split(';').first.trim()) {
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/pcm':
      case 'audio/l16':
        return 'pcm';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/ogg':
        return 'ogg';
      case 'audio/webm':
        return 'webm';
      case 'audio/mp4':
      case 'audio/aac':
      default:
        return 'm4a';
    }
  }

  String? _currentUserRole(List<Map<String, dynamic>> memberRows) {
    final currentUserId = _currentUserId();
    if (currentUserId == null) {
      return null;
    }
    for (final row in memberRows) {
      final profile = row['profile'] as Map<String, dynamic>?;
      if (profile?['id'] == currentUserId) {
        return row['role'] as String?;
      }
    }
    return null;
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

class MessageSearchResult {
  const MessageSearchResult({
    required this.messageId,
    required this.conversationId,
    required this.conversationTitle,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.rank,
  });

  factory MessageSearchResult.fromJson(Map<String, dynamic> json) {
    return MessageSearchResult(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      conversationTitle:
          json['conversation_title'] as String? ?? 'Conversation',
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String? ?? 'Someone',
      body: json['body'] as String? ?? '',
      type: MessageType.fromJson(json['type'] as String? ?? 'text'),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      rank: (json['rank'] as num?)?.toDouble() ?? 0,
    );
  }

  final String messageId;
  final String conversationId;
  final String conversationTitle;
  final String senderId;
  final String senderName;
  final String body;
  final MessageType type;
  final DateTime createdAt;
  final double rank;
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
  Future<List<Map<String, dynamic>>> listGroupMembers(
    String conversationId,
  ) async {
    final rows = await _client
        .from('conversation_members')
        .select(
          'role,profile:profiles(id,username,display_name,avatar_url,bio,created_at,updated_at,contact_alias:contact_aliases!contact_aliases_friend_id_fkey(alias))',
        )
        .eq('conversation_id', conversationId)
        .order('joined_at', ascending: true);
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
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async {
    return null;
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
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    return GroupDetail(
      conversationId: conversationId,
      title: conversationId,
      members: const [],
    );
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
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
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) {
    throw StateError('Supabase must be initialized before sending audio.');
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    throw StateError('Supabase must be initialized before loading images.');
  }

  @override
  Future<String> createVoiceUrl(VoiceAttachment attachment) {
    throw StateError('Supabase must be initialized before loading audio.');
  }

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) {
    throw StateError(
      'Supabase must be initialized before forwarding messages.',
    );
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) {
    throw StateError('Supabase must be initialized before searching messages.');
  }

  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) {
    throw StateError('Supabase must be initialized before searching.');
  }

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) {
    throw StateError('Supabase must be initialized before browsing media.');
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
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) {
    throw StateError('Supabase must be initialized before uploading groups.');
  }

  @override
  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  }) {
    throw StateError('Supabase must be initialized before updating groups.');
  }

  @override
  Future<void> leaveGroupConversation(String conversationId) {
    throw StateError('Supabase must be initialized before leaving groups.');
  }

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  }) {
    throw StateError('Supabase must be initialized before removing members.');
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
  Future<void> markConversationUnread(String conversationId) async {}

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {}

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {}

  @override
  Future<void> hideConversation(String conversationId) async {}

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return _searchConversations(conversations, query);
  }

  @override
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) {
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
  final recalledMessageIds = {
    for (final message in messages)
      if (message.recalledAt != null) message.id,
  };
  return messages
      .where((message) {
        if (message.recalledAt != null) {
          return false;
        }
        final preview = message.replyPreview;
        final previewParentIsRecalled =
            message.replyToMessageId != null &&
            recalledMessageIds.contains(message.replyToMessageId);
        return _containsQuery(message.body, normalizedQuery) ||
            (!previewParentIsRecalled &&
                (_containsQuery(preview?.body, normalizedQuery) ||
                    _containsQuery(preview?.senderName, normalizedQuery)));
      })
      .toList(growable: false);
}

bool _containsQuery(String? value, String query) {
  return value?.toLowerCase().contains(query) ?? false;
}

GroupMember _groupMemberFromJson(Map<String, dynamic> row) {
  final profile = row['profile'] as Map<String, dynamic>;
  final alias = _embeddedContactAlias(profile);
  if (alias == null || profile['alias'] != null) {
    return GroupMember.fromJson(row);
  }
  return GroupMember.fromJson({
    ...row,
    'profile': {...profile, 'alias': alias},
  });
}

String? _embeddedContactAlias(Map<String, dynamic> profile) {
  final rawAlias = profile['contact_alias'] ?? profile['contact_aliases'];
  if (rawAlias is List && rawAlias.isNotEmpty) {
    final firstAlias = rawAlias.first;
    if (firstAlias is Map<String, dynamic>) {
      return firstAlias['alias'] as String?;
    }
  }
  if (rawAlias is Map<String, dynamic>) {
    return rawAlias['alias'] as String?;
  }
  return null;
}
