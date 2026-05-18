import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
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

  test('listReadMarkers maps conversation member read state', () async {
    final dataSource = FakeChatsDataSource()
      ..readMarkerRows = [
        {'user_id': 'user-1', 'last_read_message_id': 'message-1'},
        {'user_id': 'user-2', 'last_read_message_id': null},
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final markers = await repository.listReadMarkers('conversation-1');

    expect(markers, hasLength(2));
    expect(markers.first.userId, 'user-1');
    expect(markers.first.lastReadMessageId, 'message-1');
    expect(markers.last.userId, 'user-2');
    expect(markers.last.lastReadMessageId, isNull);
    expect(dataSource.listReadMarkerCalls, ['conversation-1']);
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
    'sendImageMessage uploads image bytes and inserts image message',
    () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        storagePathSeed: () => 'seed-1',
      );

      await repository.sendImageMessage(
        conversationId: 'conversation-1',
        image: ChatImageUpload(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'My Photo.JPG',
          mimeType: 'image/jpeg',
          width: 640,
          height: 480,
        ),
      );

      expect(dataSource.uploadedImages, [
        UploadedImage(
          bucket: 'chat-images',
          path: 'conversation-1/seed-1-my-photo.jpg',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/jpeg',
        ),
      ]);
      expect(dataSource.insertedMessages, [
        {
          'conversation_id': 'conversation-1',
          'sender_id': 'user-1',
          'type': 'image',
          'body': '',
          'attachment': {
            'kind': 'image',
            'bucket': 'chat-images',
            'path': 'conversation-1/seed-1-my-photo.jpg',
            'mime_type': 'image/jpeg',
            'size': 3,
            'width': 640,
            'height': 480,
          },
        },
      ]);
    },
  );

  test('sendImageMessage times out stalled image uploads', () async {
    final dataSource = FakeChatsDataSource()
      ..uploadCompleter = Completer<void>();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
      storageOperationTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      repository.sendImageMessage(
        conversationId: 'conversation-1',
        image: ChatImageUpload(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'Photo.PNG',
          mimeType: 'image/png',
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(dataSource.insertedMessages, isEmpty);
  });

  test('createImageUrl delegates to private storage signed urls', () async {
    final dataSource = FakeChatsDataSource()
      ..signedUrlResult = 'https://signed.example.test/photo.jpg';
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final url = await repository.createImageUrl(
      const ImageAttachment(
        bucket: 'chat-images',
        path: 'conversation-1/seed-1-photo.jpg',
        mimeType: 'image/jpeg',
        size: 3,
      ),
    );

    expect(url, 'https://signed.example.test/photo.jpg');
    expect(dataSource.signedUrlCalls, [
      const SignedUrlCall(
        bucket: 'chat-images',
        path: 'conversation-1/seed-1-photo.jpg',
        expiresIn: Duration(hours: 1),
      ),
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

  test(
    'recallMessage calls the recall RPC with the target message id',
    () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await repository.recallMessage(messageId: 'message-1');

      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'recall_message',
          params: {'target_message_id': 'message-1'},
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

  test('threadChanges emits when thread data invalidates', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final events = <void>[];
    final subscription = repository
        .threadChanges('conversation-1')
        .listen(events.add);
    addTearDown(subscription.cancel);

    dataSource.emitThreadChange('conversation-1');
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(dataSource.threadChangeConversationIds, ['conversation-1']);
  });

  test('conversationActivity delegates with current user id', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final events = <ConversationActivity>[];
    final subscription = repository
        .conversationActivity('conversation-1')
        .listen(events.add);
    addTearDown(subscription.cancel);

    dataSource.emitActivity(
      const ConversationActivity(onlineUserIds: {'user-2'}),
    );
    await pumpEventQueue();

    expect(events.single.onlineUserIds, {'user-2'});
    expect(dataSource.activityCalls, [
      const ActivityCall(
        conversationId: 'conversation-1',
        currentUserId: 'user-1',
      ),
    ]);
  });

  test('setTyping delegates with current user id', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.setTyping(
      conversationId: 'conversation-1',
      isTyping: true,
    );

    expect(dataSource.typingCalls, [
      const TypingCall(
        conversationId: 'conversation-1',
        currentUserId: 'user-1',
        isTyping: true,
      ),
    ]);
  });
}

class FakeChatsDataSource implements ChatsDataSource {
  var conversationRows = <Map<String, dynamic>>[];
  var messageRows = <Map<String, dynamic>>[];
  var readMarkerRows = <Map<String, dynamic>>[];
  var rpcResult = 'conversation-1';
  String? latestMessageResult;
  String signedUrlResult = 'https://signed.example.test/default.jpg';
  var listCalls = 0;
  Completer<void>? uploadCompleter;
  final listMessageCalls = <String>[];
  final listReadMarkerCalls = <String>[];
  final latestMessageCalls = <String>[];
  final insertedMessages = <Map<String, dynamic>>[];
  final uploadedImages = <UploadedImage>[];
  final signedUrlCalls = <SignedUrlCall>[];
  final rpcCalls = <RpcCall>[];
  final activityCalls = <ActivityCall>[];
  final typingCalls = <TypingCall>[];
  final _changes = StreamController<void>.broadcast();
  final _messageChanges = <String, StreamController<void>>{};
  final _threadChanges = <String, StreamController<void>>{};
  final _activityChanges = StreamController<ConversationActivity>.broadcast();
  final messageChangeConversationIds = <String>[];
  final threadChangeConversationIds = <String>[];

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
  Future<List<Map<String, dynamic>>> listReadMarkers(
    String conversationId,
  ) async {
    listReadMarkerCalls.add(conversationId);
    return readMarkerRows;
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
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final completer = uploadCompleter;
    if (completer != null) {
      await completer.future;
      return;
    }
    uploadedImages.add(
      UploadedImage(
        bucket: bucket,
        path: path,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async {
    signedUrlCalls.add(
      SignedUrlCall(bucket: bucket, path: path, expiresIn: expiresIn),
    );
    return signedUrlResult;
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

  @override
  Stream<void> threadChanges(String conversationId) {
    threadChangeConversationIds.add(conversationId);
    return _threadChanges
        .putIfAbsent(conversationId, () => StreamController<void>.broadcast())
        .stream;
  }

  @override
  Stream<ConversationActivity> conversationActivity({
    required String conversationId,
    required String currentUserId,
  }) {
    activityCalls.add(
      ActivityCall(
        conversationId: conversationId,
        currentUserId: currentUserId,
      ),
    );
    return _activityChanges.stream;
  }

  @override
  Future<void> sendTyping({
    required String conversationId,
    required String currentUserId,
    required bool isTyping,
  }) async {
    typingCalls.add(
      TypingCall(
        conversationId: conversationId,
        currentUserId: currentUserId,
        isTyping: isTyping,
      ),
    );
  }

  void emitConversationChange() {
    _changes.add(null);
  }

  void emitMessageChange(String conversationId) {
    _messageChanges[conversationId]?.add(null);
  }

  void emitThreadChange(String conversationId) {
    _threadChanges[conversationId]?.add(null);
  }

  void emitActivity(ConversationActivity activity) {
    _activityChanges.add(activity);
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

class UploadedImage {
  const UploadedImage({
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.mimeType,
  });

  final String bucket;
  final String path;
  final Uint8List bytes;
  final String mimeType;

  @override
  bool operator ==(Object other) {
    return other is UploadedImage &&
        other.bucket == bucket &&
        other.path == path &&
        _listsEqual(other.bytes, bytes) &&
        other.mimeType == mimeType;
  }

  @override
  int get hashCode =>
      Object.hash(bucket, path, Object.hashAll(bytes), mimeType);
}

class SignedUrlCall {
  const SignedUrlCall({
    required this.bucket,
    required this.path,
    required this.expiresIn,
  });

  final String bucket;
  final String path;
  final Duration expiresIn;

  @override
  bool operator ==(Object other) {
    return other is SignedUrlCall &&
        other.bucket == bucket &&
        other.path == path &&
        other.expiresIn == expiresIn;
  }

  @override
  int get hashCode => Object.hash(bucket, path, expiresIn);
}

class ActivityCall {
  const ActivityCall({
    required this.conversationId,
    required this.currentUserId,
  });

  final String conversationId;
  final String currentUserId;

  @override
  bool operator ==(Object other) {
    return other is ActivityCall &&
        other.conversationId == conversationId &&
        other.currentUserId == currentUserId;
  }

  @override
  int get hashCode => Object.hash(conversationId, currentUserId);
}

class TypingCall {
  const TypingCall({
    required this.conversationId,
    required this.currentUserId,
    required this.isTyping,
  });

  final String conversationId;
  final String currentUserId;
  final bool isTyping;

  @override
  bool operator ==(Object other) {
    return other is TypingCall &&
        other.conversationId == conversationId &&
        other.currentUserId == currentUserId &&
        other.isTyping == isTyping;
  }

  @override
  int get hashCode => Object.hash(conversationId, currentUserId, isTyping);
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

bool _listsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
