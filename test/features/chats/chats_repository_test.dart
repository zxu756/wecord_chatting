import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
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
            'last_message_sender_id': 'user-2',
            'last_message_at': '2026-05-18T04:30:00.000Z',
            'last_message_type': 'text',
            'unread_count': 3,
            'pinned_at': '2026-05-18T04:29:00.000Z',
            'muted_until': '2026-05-19T04:30:00.000Z',
            'is_muted': true,
            'is_marked_unread': false,
            'member_count': 2,
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
      expect(conversations.single.lastMessageSenderId, 'user-2');
      expect(conversations.single.lastMessageType, MessageType.text);
      expect(
        conversations.single.lastMessageAt,
        DateTime.utc(2026, 5, 18, 4, 30),
      );
      expect(conversations.single.unreadCount, 3);
      expect(conversations.single.pinnedAt, DateTime.utc(2026, 5, 18, 4, 29));
      expect(conversations.single.mutedUntil, DateTime.utc(2026, 5, 19, 4, 30));
      expect(conversations.single.isMuted, isTrue);
      expect(conversations.single.isMarkedUnread, isFalse);
      expect(conversations.single.memberCount, 2);
      expect(dataSource.listCalls, 1);
    },
  );

  test('listConversations maps image previews from summary rows', () async {
    final dataSource = FakeChatsDataSource()
      ..conversationRows = [
        {
          'id': 'conversation-1',
          'type': 'direct',
          'title': 'Ada Lovelace',
          'avatar_url': null,
          'last_message_body': '[Image]',
          'last_message_sender_id': 'user-2',
          'last_message_at': '2026-05-18T04:30:00.000Z',
          'last_message_type': 'image',
          'unread_count': 0,
          'pinned_at': null,
          'muted_until': null,
          'is_muted': false,
          'is_marked_unread': false,
          'member_count': 2,
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final conversations = await repository.listConversations();

    expect(conversations.single.lastMessageBody, '[Image]');
    expect(conversations.single.lastMessageType, MessageType.image);
  });

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

  test('forwardMessage calls the forwarding RPC', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.forwardMessage(
      sourceMessageId: 'message-1',
      targetConversationId: 'conversation-2',
    );

    expect(dataSource.rpcCalls.single.functionName, 'forward_message');
  });

  test('searchMessages maps global search rows', () async {
    final dataSource = FakeChatsDataSource()
      ..searchRows = [
        {
          'message_id': 'message-1',
          'conversation_id': 'conversation-1',
          'conversation_title': 'Launch Crew',
          'sender_id': 'user-2',
          'sender_name': 'Ada',
          'body': 'ship it',
          'type': 'text',
          'created_at': '2026-05-18T00:00:00Z',
          'rank': 0.9,
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final results = await repository.searchMessages(' ship ');

    expect(results.single.body, 'ship it');
    expect(results.single.conversationTitle, 'Launch Crew');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'search_messages',
        params: {'search_query': 'ship'},
      ),
    ]);
  });

  test('searchDiscovery maps grouped discovery rows', () async {
    final dataSource = FakeChatsDataSource()
      ..discoveryRows = [
        {
          'result_type': 'circle_channel',
          'id': 'channel-1',
          'title': 'photos',
          'subtitle': 'Close Friends',
          'conversation_id': 'conversation-2',
          'circle_id': 'circle-1',
          'channel_id': 'channel-1',
          'rank': 0.8,
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final results = await repository.searchDiscovery(' photos ');

    expect(results.single.type, DiscoveryResultType.circleChannel);
    expect(results.single.conversationId, 'conversation-2');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'search_discovery',
        params: {'search_query': 'photos'},
      ),
    ]);
  });

  test('createGroupConversation calls the group creation RPC', () async {
    final dataSource = FakeChatsDataSource()..rpcResult = 'conversation-3';
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final conversationId = await repository.createGroupConversation(
      title: '  Dream Team  ',
      memberIds: ['user-2', 'user-3'],
    );

    expect(conversationId, 'conversation-3');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'create_group_conversation',
        params: {
          'group_title': 'Dream Team',
          'member_ids': ['user-2', 'user-3'],
        },
      ),
    ]);
  });

  test('getGroupDetail loads group title and member profile rows', () async {
    final dataSource = FakeChatsDataSource()
      ..conversationRows = [
        {
          'id': 'conversation-1',
          'type': 'group',
          'title': 'Launch Crew',
          'avatar_url': null,
          'last_message_body': null,
          'last_message_sender_id': null,
          'last_message_at': null,
          'last_message_type': null,
          'unread_count': 0,
          'pinned_at': null,
          'muted_until': null,
          'is_muted': false,
          'is_marked_unread': false,
          'member_count': 2,
          'announcement': 'Ship it carefully',
          'announcement_updated_at': '2026-05-19T09:30:00.000Z',
          'announcement_updated_by': 'user-1',
        },
      ]
      ..groupMemberRows = [
        {
          'role': 'owner',
          'profile': {
            'id': 'user-1',
            'username': 'grace',
            'display_name': 'Grace Hopper',
            'avatar_url': null,
            'bio': '',
            'created_at': '2026-05-18T04:30:00.000Z',
            'updated_at': '2026-05-18T04:31:00.000Z',
          },
        },
        {
          'role': 'member',
          'profile': {
            'id': 'user-2',
            'username': 'ada',
            'display_name': 'Ada Lovelace',
            'avatar_url': null,
            'bio': '',
            'created_at': '2026-05-18T04:32:00.000Z',
            'updated_at': '2026-05-18T04:33:00.000Z',
          },
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final detail = await repository.getGroupDetail('conversation-1');

    expect(detail.conversationId, 'conversation-1');
    expect(detail.title, 'Launch Crew');
    expect(detail.announcement, 'Ship it carefully');
    expect(detail.announcementUpdatedAt, DateTime.utc(2026, 5, 19, 9, 30));
    expect(detail.announcementUpdatedBy, 'user-1');
    expect(detail.avatarUrl, isNull);
    expect(detail.currentUserRole, 'owner');
    expect(detail.members, hasLength(2));
    expect(detail.members.first, isA<GroupMember>());
    expect(detail.members.first.role, 'owner');
    expect(detail.members.first.profile.displayName, 'Grace Hopper');
    expect(detail.members.last.role, 'member');
    expect(detail.members.last.profile.username, 'ada');
    expect(dataSource.listCalls, 1);
    expect(dataSource.listGroupMemberCalls, ['conversation-1']);
  });

  test(
    'group member query requests contact aliases for profile display labels',
    () {
      final source = File(
        'lib/features/chats/chats_repository.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          'contact_alias:contact_aliases!contact_aliases_friend_id_fkey(alias)',
        ),
      );
    },
  );

  test('getGroupDetail maps embedded member contact aliases', () async {
    final dataSource = FakeChatsDataSource()
      ..groupMemberRows = [
        {
          'role': 'member',
          'profile': {
            'id': 'user-2',
            'username': 'ada',
            'display_name': 'Ada Lovelace',
            'contact_alias': [
              {'alias': 'Ada L.'},
            ],
            'avatar_url': null,
            'bio': '',
            'created_at': '2026-05-18T04:32:00.000Z',
            'updated_at': '2026-05-18T04:33:00.000Z',
          },
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final detail = await repository.getGroupDetail('conversation-1');

    expect(detail.members.single.profile.alias, 'Ada L.');
    expect(detail.members.single.profile.displayLabel, 'Ada L.');
  });

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

  test('sendTextMessage can include reply preview', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.sendTextMessage(
      conversationId: 'conversation-1',
      body: '  Replying  ',
      replyToMessageId: 'message-1',
      replyPreview: const ReplyPreview(
        messageId: 'message-1',
        senderName: 'Ada',
        body: 'Original',
        type: MessageType.text,
      ),
    );

    expect(dataSource.insertedMessages, [
      {
        'conversation_id': 'conversation-1',
        'sender_id': 'user-1',
        'type': 'text',
        'body': 'Replying',
        'reply_to_message_id': 'message-1',
        'reply_preview': {
          'message_id': 'message-1',
          'sender_name': 'Ada',
          'body': 'Original',
          'type': 'text',
        },
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

  test('sendVoiceMessage uploads audio and inserts a voice message', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
    );

    await repository.sendVoiceMessage(
      conversationId: 'conversation-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/mp4',
      durationMs: 4200,
    );

    expect(dataSource.uploadedImages, [
      UploadedImage(
        bucket: 'voice-messages',
        path: 'conversation-1/seed-1.m4a',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/mp4',
      ),
    ]);
    expect(dataSource.insertedMessages, [
      {
        'conversation_id': 'conversation-1',
        'sender_id': 'user-1',
        'type': 'voice',
        'body': '',
        'attachment': {
          'kind': 'voice',
          'bucket': 'voice-messages',
          'path': 'conversation-1/seed-1.m4a',
          'mime_type': 'audio/mp4',
          'size': 3,
          'duration_ms': 4200,
        },
      },
    ]);
  });

  test('sendVoiceMessage chooses storage extension from mime type', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
    );

    await repository.sendVoiceMessage(
      conversationId: 'conversation-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/wav',
      durationMs: 4200,
    );

    expect(dataSource.uploadedImages.single.path, 'conversation-1/seed-1.wav');
    expect(
      dataSource.insertedMessages.single['attachment'],
      containsPair('path', 'conversation-1/seed-1.wav'),
    );
  });

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

  test('conversation management methods call scoped RPCs', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.setConversationPinned(
      conversationId: 'conversation-1',
      pinned: true,
    );
    await repository.setConversationMuted(
      conversationId: 'conversation-1',
      muted: true,
    );
    await repository.markConversationUnread('conversation-1');
    await repository.hideConversation('conversation-1');

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'set_conversation_pinned',
        params: {'target_conversation_id': 'conversation-1', 'pinned': true},
      ),
      const RpcCall(
        functionName: 'set_conversation_muted',
        params: {'target_conversation_id': 'conversation-1', 'muted': true},
      ),
      const RpcCall(
        functionName: 'mark_conversation_unread',
        params: {'target_conversation_id': 'conversation-1'},
      ),
      const RpcCall(
        functionName: 'hide_conversation',
        params: {'target_conversation_id': 'conversation-1'},
      ),
    ]);
  });

  test('group management methods call scoped RPCs and storage', () async {
    final dataSource = FakeChatsDataSource()..signedUrlResult = 'signed-avatar';
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
    );

    final avatarPath = await repository.uploadGroupAvatar(
      conversationId: 'conversation-1',
      image: ChatImageUpload(
        bytes: Uint8List.fromList([9, 8]),
        fileName: 'Group.PNG',
        mimeType: 'image/png',
      ),
    );
    await repository.updateGroupProfile(
      conversationId: 'conversation-1',
      title: '  Launch Crew  ',
      avatarUrl: avatarPath,
      announcement: '  Bring snacks  ',
    );
    await repository.removeGroupMember(
      conversationId: 'conversation-1',
      memberId: 'user-2',
    );
    await repository.leaveGroupConversation('conversation-1');

    expect(avatarPath, 'group-avatars/conversation-1/seed-1-group.png');
    expect(dataSource.uploadedImages.single.bucket, 'group-avatars');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'update_group_profile',
        params: {
          'target_conversation_id': 'conversation-1',
          'group_title': 'Launch Crew',
          'avatar_url': 'group-avatars/conversation-1/seed-1-group.png',
          'announcement': 'Bring snacks',
        },
      ),
      const RpcCall(
        functionName: 'remove_group_member',
        params: {
          'target_conversation_id': 'conversation-1',
          'target_user_id': 'user-2',
        },
      ),
      const RpcCall(
        functionName: 'leave_group_conversation',
        params: {'target_conversation_id': 'conversation-1'},
      ),
    ]);
  });

  test('sendTextMessage can include mention metadata', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.sendTextMessage(
      conversationId: 'conversation-1',
      body: 'Hi @ada',
      mentions: const [
        MessageMention(userId: 'user-2', displayName: 'Ada', start: 3, end: 7),
      ],
    );

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'send_text_message',
        params: {
          'target_conversation_id': 'conversation-1',
          'body': 'Hi @ada',
          'reply_to_message_id': null,
          'reply_preview': null,
          'mentions': [
            {
              'user_id': 'user-2',
              'display_name': 'Ada',
              'start': 3,
              'end': 7,
              'kind': 'user',
            },
          ],
        },
      ),
    ]);
  });

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

  test('editMessage calls the edit RPC', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.editMessage(messageId: 'message-1', body: '  Fixed  ');

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'edit_message',
        params: {'target_message_id': 'message-1', 'body': 'Fixed'},
      ),
    ]);
  });

  test('searchConversations matches title or last message body', () {
    final repository = SupabaseChatsRepository.withDataSource(
      FakeChatsDataSource(),
      currentUserId: () => 'user-1',
    );
    final conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.direct,
        title: 'Ada Lovelace',
        lastMessageBody: 'See you soon',
        unreadCount: 0,
      ),
      const ConversationSummary(
        id: 'conversation-2',
        type: ConversationType.group,
        title: 'Planning',
        lastMessageBody: 'Bring the notes',
        unreadCount: 0,
      ),
    ];

    expect(repository.searchConversations(conversations, ' ada '), [
      conversations.first,
    ]);
    expect(repository.searchConversations(conversations, 'NOTES'), [
      conversations.last,
    ]);
    expect(repository.searchConversations(conversations, ' '), conversations);
  });

  test('searchConversations does not match deleted original text', () {
    final repository = SupabaseChatsRepository.withDataSource(
      FakeChatsDataSource(),
      currentUserId: () => 'user-1',
    );
    final conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.direct,
        title: 'Ada Lovelace',
        lastMessageBody: 'Message deleted',
        unreadCount: 0,
      ),
    ];

    expect(
      repository.searchConversations(conversations, 'secret draft'),
      isEmpty,
    );
  });

  test('searchMessages skips recalled messages entirely', () {
    final repository = SupabaseChatsRepository.withDataSource(
      FakeChatsDataSource(),
      currentUserId: () => 'user-1',
    );
    final messages = [
      ChatMessage(
        id: 'message-1',
        conversationId: 'conversation-1',
        senderId: 'user-1',
        type: MessageType.text,
        body: 'Visible body',
        createdAt: DateTime.utc(2026, 5, 18),
      ),
      ChatMessage(
        id: 'message-2',
        conversationId: 'conversation-1',
        senderId: 'user-2',
        type: MessageType.text,
        body: 'Plain reply',
        replyPreview: const ReplyPreview(
          messageId: 'message-1',
          senderName: 'Grace',
          body: 'Earlier context',
          type: MessageType.text,
        ),
        createdAt: DateTime.utc(2026, 5, 18, 0, 1),
      ),
      ChatMessage(
        id: 'message-3',
        conversationId: 'conversation-1',
        senderId: 'user-2',
        type: MessageType.text,
        body: 'Secret recalled body',
        replyPreview: const ReplyPreview(
          messageId: 'message-1',
          senderName: 'Grace',
          body: 'Earlier context',
          type: MessageType.text,
        ),
        recalledAt: DateTime.utc(2026, 5, 18, 1),
        createdAt: DateTime.utc(2026, 5, 18, 0, 2),
      ),
    ];

    expect(repository.searchThreadMessages(messages, 'visible'), [
      messages.first,
    ]);
    expect(repository.searchThreadMessages(messages, 'grace'), [messages[1]]);
    expect(repository.searchThreadMessages(messages, 'secret'), isEmpty);
    expect(repository.searchThreadMessages(messages, 'earlier'), [messages[1]]);
    expect(repository.searchThreadMessages(messages, ''), messages);
  });

  test('searchMessages hides previews for recalled parents in the thread', () {
    final repository = SupabaseChatsRepository.withDataSource(
      FakeChatsDataSource(),
      currentUserId: () => 'user-1',
    );
    final messages = [
      ChatMessage(
        id: 'message-1',
        conversationId: 'conversation-1',
        senderId: 'user-1',
        type: MessageType.text,
        body: 'Deleted project secret',
        recalledAt: DateTime.utc(2026, 5, 18, 1),
        createdAt: DateTime.utc(2026, 5, 18),
      ),
      ChatMessage(
        id: 'message-2',
        conversationId: 'conversation-1',
        senderId: 'user-2',
        type: MessageType.text,
        body: 'Acknowledged',
        replyToMessageId: 'message-1',
        replyPreview: const ReplyPreview(
          messageId: 'message-1',
          senderName: 'Ada',
          body: 'Deleted project secret',
          type: MessageType.text,
        ),
        createdAt: DateTime.utc(2026, 5, 18, 0, 1),
      ),
    ];

    expect(repository.searchThreadMessages(messages, 'project'), isEmpty);
    expect(repository.searchThreadMessages(messages, 'acknowledged'), [
      messages.last,
    ]);
  });

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
  var searchRows = <Map<String, dynamic>>[];
  var discoveryRows = <Map<String, dynamic>>[];
  var readMarkerRows = <Map<String, dynamic>>[];
  var groupMemberRows = <Map<String, dynamic>>[];
  var rpcResult = 'conversation-1';
  String? latestMessageResult;
  String signedUrlResult = 'https://signed.example.test/default.jpg';
  var listCalls = 0;
  Completer<void>? uploadCompleter;
  final listMessageCalls = <String>[];
  final listReadMarkerCalls = <String>[];
  final listGroupMemberCalls = <String>[];
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
  Future<List<Map<String, dynamic>>> listGroupMembers(
    String conversationId,
  ) async {
    listGroupMemberCalls.add(conversationId);
    return groupMemberRows;
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
    if (functionName == 'search_messages') {
      return searchRows;
    }
    if (functionName == 'search_discovery') {
      return discoveryRows;
    }
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
    final leftValue = entry.value;
    final rightValue = right[entry.key];
    if (leftValue is List && rightValue is List) {
      if (!_listsEqual(leftValue.cast<Object?>(), rightValue.cast<Object?>())) {
        return false;
      }
      continue;
    }
    if (leftValue is Map<String, dynamic> &&
        rightValue is Map<String, dynamic>) {
      if (!_mapsEqual(leftValue, rightValue)) {
        return false;
      }
      continue;
    }
    if (rightValue != leftValue) {
      return false;
    }
  }
  return true;
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftValue = left[index];
    final rightValue = right[index];
    if (leftValue is Map<String, dynamic> &&
        rightValue is Map<String, dynamic>) {
      if (!_mapsEqual(leftValue, rightValue)) {
        return false;
      }
      continue;
    }
    if (leftValue != rightValue) {
      return false;
    }
  }
  return true;
}
