import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  group('paged history', () {
    test('fetchMessageRows passes the cursor and page size through', () async {
      final dataSource = FakeChatsDataSource()
        ..messageRows = [
          {'id': 'message-1'},
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );
      final cursor = MessageCursor(
        DateTime.utc(2026, 5, 18),
        'message-9',
        timestamp: '2026-05-18T00:00:00.123456+00:00',
      );

      final rows = await repository.fetchMessageRows(
        'conversation-1',
        before: cursor,
        limit: 30,
      );

      expect(rows, hasLength(1));
      final call = dataSource.pageCalls.single;
      expect(call.conversationId, 'conversation-1');
      expect(call.before, cursor);
      expect(call.before!.queryTimestamp, '2026-05-18T00:00:00.123456+00:00');
      expect(call.after, isNull);
      expect(call.limit, 30);
    });

    test('fetchReactions maps rows by message and skips empty asks', () async {
      final dataSource = FakeChatsDataSource()
        ..reactionRows = [
          {
            'message_id': 'message-1',
            'reactions': [
              {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
            ],
          },
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      expect(await repository.fetchReactions('conversation-1', const []), {});
      expect(dataSource.reactionCalls, isEmpty);
      final reactions = await repository.fetchReactions('conversation-1', [
        'message-1',
        'message-2',
      ]);

      expect(reactions.keys, ['message-1']);
      expect(dataSource.reactionCalls.single, ['message-1', 'message-2']);
    });

    test('sendQueuedTextMessage sends its client id once', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['send_text_message'] = 'message-7';
      final sent = <String>[];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        onMessageSent: (id) async => sent.add(id),
      );

      final id = await repository.sendQueuedTextMessage(
        conversationId: 'conversation-1',
        clientId: '11111111-1111-4111-8111-111111111111',
        body: '  hello  ',
      );

      expect(id, 'message-7');
      expect(sent, ['message-7']);
      final call = dataSource.rpcCalls.single;
      expect(call.functionName, 'send_text_message');
      expect(call.params['client_id'], '11111111-1111-4111-8111-111111111111');
      expect(call.params['body'], 'hello');
      expect(call.params['mentions'], isEmpty);
    });

    test('sendQueuedTextMessage turns refusals into exceptions', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcErrors['send_text_message'] = const PostgrestException(
          message: 'Slowmode is enabled. Try again in 9 seconds.',
          code: 'P0001',
          details: 'slowmode_remaining_seconds=9',
        );
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await expectLater(
        repository.sendQueuedTextMessage(
          conversationId: 'conversation-1',
          clientId: '11111111-1111-4111-8111-111111111111',
          body: 'hello',
        ),
        throwsA(
          isA<SlowmodeException>().having(
            (error) => error.remainingSeconds,
            'remainingSeconds',
            9,
          ),
        ),
      );
    });

    group('sendQueuedMediaMessage', () {
      const attachment = {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'conversation-1/c-photo.jpg',
      };

      SupabaseChatsRepository repository(
        FakeChatsDataSource dataSource, {
        List<String>? notified,
      }) {
        return SupabaseChatsRepository.withDataSource(
          dataSource,
          currentUserId: () => 'user-1',
          onMessageSent: (id) async => notified?.add(id),
        );
      }

      test('stores the message with its client id and album id', () async {
        final dataSource = FakeChatsDataSource();
        final notified = <String>[];

        final id = await repository(dataSource, notified: notified)
            .sendQueuedMediaMessage(
              conversationId: 'conversation-1',
              clientId: 'client-1',
              type: MessageType.image,
              attachment: attachment,
              body: 'Look',
              attachmentGroupId: 'album-1',
            );

        expect(id, 'inserted-1');
        final row = dataSource.insertedMessages.single;
        expect(row['conversation_id'], 'conversation-1');
        expect(row['sender_id'], 'user-1');
        expect(row['type'], 'image');
        expect(row['body'], 'Look');
        expect(row['client_id'], 'client-1');
        expect(row['attachment_group_id'], 'album-1');
        expect(row['attachment'], attachment);
        expect(notified, ['inserted-1']);
      });

      test(
        'an album item sent with notify false sends no notification',
        () async {
          final dataSource = FakeChatsDataSource();
          final notified = <String>[];

          await repository(
            dataSource,
            notified: notified,
          ).sendQueuedMediaMessage(
            conversationId: 'conversation-1',
            clientId: 'client-2',
            type: MessageType.file,
            attachment: attachment,
            attachmentGroupId: 'album-1',
            notify: false,
          );

          expect(dataSource.insertedMessages, hasLength(1));
          expect(notified, isEmpty);
        },
      );

      test('a server without albums or client ids still takes it', () async {
        final dataSource = FakeChatsDataSource()
          ..insertErrors.addAll([
            const PostgrestException(
              message: "Could not find the 'attachment_group_id' column",
              code: 'PGRST204',
            ),
            const PostgrestException(
              message: "Could not find the 'client_id' column",
              code: 'PGRST204',
            ),
          ]);

        final id = await repository(dataSource).sendQueuedMediaMessage(
          conversationId: 'conversation-1',
          clientId: 'client-1',
          type: MessageType.image,
          attachment: attachment,
          attachmentGroupId: 'album-1',
        );

        expect(id, 'inserted-1');
        final row = dataSource.insertedMessages.single;
        expect(row.containsKey('attachment_group_id'), isFalse);
        expect(row.containsKey('client_id'), isFalse);
      });

      test('a message stored by an earlier try is not stored again', () async {
        final dataSource = FakeChatsDataSource()
          ..insertErrors.add(
            const PostgrestException(
              message:
                  'duplicate key value violates unique constraint '
                  '"messages_sender_client_id_key"',
              code: '23505',
            ),
          );

        final id = await repository(dataSource).sendQueuedMediaMessage(
          conversationId: 'conversation-1',
          clientId: 'client-1',
          type: MessageType.image,
          attachment: attachment,
        );

        expect(id, isNull);
        expect(dataSource.insertedMessages, isEmpty);
      });

      test('AutoMod dropping an item quietly gives its reason', () async {
        final dataSource = FakeChatsDataSource()
          ..insertReturnsNull = true
          ..autoModNotice = {'rule_name': 'Links', 'reason': 'No links here'};

        await expectLater(
          repository(dataSource).sendQueuedMediaMessage(
            conversationId: 'conversation-1',
            clientId: 'client-1',
            type: MessageType.image,
            attachment: attachment,
            attachmentGroupId: 'album-1',
          ),
          throwsA(
            isA<AutoModBlockedException>().having(
              (error) => error.reason,
              'reason',
              'No links here',
            ),
          ),
        );
        expect(dataSource.autoModNoticeCalls, ['conversation-1']);
      });

      test(
        'AutoMod and the circle rules refusing an item are told apart',
        () async {
          final dataSource = FakeChatsDataSource()
            ..insertErrors.addAll([
              const PostgrestException(
                message: 'AutoMod blocked this message',
                code: 'P0001',
                details: 'automod_block',
                hint: 'No links here',
              ),
              const PostgrestException(
                message: 'Accept the circle rules first',
                code: '42501',
                details: 'rules_not_accepted',
              ),
            ]);

          Future<void> send() => repository(dataSource).sendQueuedMediaMessage(
            conversationId: 'conversation-1',
            clientId: 'client-1',
            type: MessageType.image,
            attachment: attachment,
            attachmentGroupId: 'album-1',
          );
          await expectLater(send(), throwsA(isA<AutoModBlockedException>()));
          await expectLater(
            send(),
            throwsA(isA<CircleRulesNotAcceptedException>()),
          );
        },
      );

      test('a push can be asked for after the fact', () async {
        final notified = <String>[];
        await repository(
          FakeChatsDataSource(),
          notified: notified,
        ).notifyMessageSent('inserted-2');
        expect(notified, ['inserted-2']);
      });

      test('slowmode and the server stopping it are told apart', () async {
        final dataSource = FakeChatsDataSource()
          ..insertErrors.add(
            const PostgrestException(
              message: 'Slowmode is enabled. Try again in 9 seconds.',
              code: 'P0001',
              details: 'slowmode_remaining_seconds=9',
            ),
          );

        await expectLater(
          repository(dataSource).sendQueuedMediaMessage(
            conversationId: 'conversation-1',
            clientId: 'client-1',
            type: MessageType.image,
            attachment: attachment,
          ),
          throwsA(isA<SlowmodeException>()),
        );
      });
    });

    test('messageFromRow reads embedded aliases', () {
      final repository = SupabaseChatsRepository.withDataSource(
        FakeChatsDataSource(),
        currentUserId: () => 'user-1',
      );

      final message = repository.messageFromRow({
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'sender_id': 'user-2',
        'type': 'text',
        'body': 'Hi',
        'created_at': '2026-05-18T04:30:00.000Z',
        'client_id': '11111111-1111-4111-8111-111111111111',
        'sender': {
          'id': 'user-2',
          'username': 'grace',
          'display_name': 'Grace Hopper',
          'bio': '',
          'created_at': '2026-05-18T04:30:00.000Z',
          'updated_at': '2026-05-18T04:30:00.000Z',
          'contact_alias': [
            {'alias': 'Amazing Grace'},
          ],
        },
      });

      expect(message.clientId, '11111111-1111-4111-8111-111111111111');
      expect(message.sender?.alias, 'Amazing Grace');
    });
  });

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

  test('poll calls send the poll RPCs', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcResults['can_current_user_moderate_polls'] = true
      ..rpcResults['list_poll_voters'] = [
        {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada',
          'bio': '',
          'created_at': '2026-10-13T09:00:00Z',
          'updated_at': '2026-10-13T09:00:00Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.createPoll(
      conversationId: 'conversation-1',
      question: ' Lunch? ',
      options: [' Pizza', 'Sushi '],
      multi: true,
      durationHours: 24,
    );
    await repository.votePoll(messageId: 'poll-1', optionIds: ['o2']);
    await repository.endPoll(messageId: 'poll-1');
    expect(await repository.canModeratePolls('conversation-1'), isTrue);
    final voters = await repository.listPollVoters(
      messageId: 'poll-1',
      optionId: 'o2',
    );

    expect(voters.single.username, 'ada');
    expect(dataSource.rpcCalls.map((call) => call.functionName), [
      'create_poll',
      'vote_poll',
      'end_poll',
      // Asked together with the other permissions first; this fake server
      // does not know the function, so the single question follows.
      'get_conversation_capabilities',
      'can_current_user_moderate_polls',
      'list_poll_voters',
    ]);
    expect(dataSource.rpcCalls.first.params, {
      'target_conversation_id': 'conversation-1',
      'question': 'Lunch?',
      'options': ['Pizza', 'Sushi'],
      'multi': true,
      'duration_hours': 24,
    });
    expect(dataSource.rpcCalls[1].params, {
      'target_message_id': 'poll-1',
      'option_ids': ['o2'],
    });
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

  test('listConversationMedia maps scoped media rows', () async {
    final dataSource = FakeChatsDataSource()
      ..mediaRows = [
        {
          'message_id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'sender_name': 'Ada',
          'type': 'image',
          'body': '',
          'attachment': {
            'kind': 'image',
            'bucket': 'chat-media',
            'path': 'conversation-1/image.png',
            'mime_type': 'image/png',
            'size': 32,
          },
          'created_at': '2026-05-19T10:00:00.000Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final results = await repository.listConversationMedia('conversation-1');

    expect(results.single, isA<ConversationMediaItem>());
    expect(results.single.imageAttachment?.path, 'conversation-1/image.png');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'list_conversation_media',
        params: {'target_conversation_id': 'conversation-1'},
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

  test('getGroupDetail maps circle channel nicknames', () async {
    final dataSource = FakeChatsDataSource()
      ..groupMemberRows = [
        {
          'role': 'member',
          'circle_nickname': 'Countess',
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

    expect(detail.members.single.nickname, 'Countess');
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

  test('AutoMod refusals become AutoModBlockedException', () async {
    final dataSource = FakeChatsDataSource()
      ..insertReturnsNull = true
      ..autoModNotice = {'rule_name': 'Bad words', 'reason': 'Keep it clean'}
      ..rpcErrors['send_sticker'] = const PostgrestException(
        message: 'AutoMod blocked this message',
        code: 'P0001',
        details: 'automod_block',
        hint: '',
      );
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    // A quiet refusal: nothing inserted, and the notice says why.
    await expectLater(
      repository.sendTextMessage(conversationId: 'conversation-1', body: 'hm'),
      throwsA(
        isA<AutoModBlockedException>()
            .having((error) => error.reason, 'reason', 'Keep it clean')
            .having(
              (error) => error.toString(),
              'message',
              'AutoMod blocked your message: Keep it clean',
            ),
      ),
    );
    expect(dataSource.autoModNoticeCalls, ['conversation-1']);

    // Refused with an error on other paths.
    await expectLater(
      repository.sendSticker(
        conversationId: 'conversation-1',
        stickerId: 'sticker-1',
      ),
      throwsA(
        isA<AutoModBlockedException>()
            .having((error) => error.reason, 'reason', isNull)
            .having(
              (error) => error.toString(),
              'message',
              'AutoMod blocked your message.',
            ),
      ),
    );

    // Circles with onboarding refuse members who have not accepted the
    // rules.
    dataSource.rpcErrors['forward_message'] = const PostgrestException(
      message: 'Accept the circle rules before taking part',
      code: '42501',
      details: 'rules_not_accepted',
    );
    await expectLater(
      repository.forwardMessage(
        sourceMessageId: 'message-1',
        targetConversationId: 'conversation-1',
      ),
      throwsA(
        isA<CircleRulesNotAcceptedException>().having(
          (error) => error.toString(),
          'message',
          'Accept the circle rules to start chatting.',
        ),
      ),
    );

    // Without a notice, a missing id is not an error.
    dataSource.autoModNotice = null;
    await repository.sendTextMessage(
      conversationId: 'conversation-2',
      body: 'fine',
    );
  });

  test('stickers, polls and forwards read the AutoMod notice', () async {
    final dataSource = FakeChatsDataSource()
      ..autoModNotice = {'rule_name': 'Bad words', 'reason': 'Keep it clean'}
      ..rpcResults['send_sticker'] = null
      ..rpcResults['create_poll'] = null
      ..rpcResults['forward_message'] = null;
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final blocked = throwsA(
      isA<AutoModBlockedException>().having(
        (error) => error.reason,
        'reason',
        'Keep it clean',
      ),
    );

    await expectLater(
      repository.sendSticker(conversationId: 'c-1', stickerId: 'sticker-1'),
      blocked,
    );
    await expectLater(
      repository.createPoll(
        conversationId: 'c-2',
        question: 'Bad?',
        options: const ['Yes', 'No'],
        multi: false,
      ),
      blocked,
    );
    await expectLater(
      repository.forwardMessage(
        sourceMessageId: 'message-1',
        targetConversationId: 'c-3',
      ),
      blocked,
    );
    expect(dataSource.autoModNoticeCalls, ['c-1', 'c-2', 'c-3']);
  });

  test('sends map slowmode refusals to SlowmodeException', () async {
    final dataSource = FakeChatsDataSource()
      ..insertError = const PostgrestException(
        message: 'Slowmode is enabled. Try again in 7 seconds.',
        code: 'P0001',
        details: 'slowmode_remaining_seconds=7',
      )
      ..rpcErrors['forward_message'] = const PostgrestException(
        message: 'Slowmode is enabled. Try again in 42 seconds.',
        code: 'P0001',
      )
      ..rpcErrors['send_text_message'] = const PostgrestException(
        message: 'You do not have permission to send messages in this channel',
        code: '42501',
      );
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await expectLater(
      repository.sendTextMessage(conversationId: 'conversation-1', body: 'hi'),
      throwsA(
        isA<SlowmodeException>().having(
          (error) => error.remainingSeconds,
          'remainingSeconds',
          7,
        ),
      ),
    );
    await expectLater(
      repository.forwardMessage(
        sourceMessageId: 'message-1',
        targetConversationId: 'conversation-1',
      ),
      throwsA(
        isA<SlowmodeException>().having(
          (error) => error.remainingSeconds,
          'remainingSeconds',
          42,
        ),
      ),
    );
    // Other refusals stay as they are.
    await expectLater(
      repository.sendTextMessage(
        conversationId: 'conversation-1',
        body: 'hi @ada',
        mentions: const [
          MessageMention(
            userId: 'user-2',
            displayName: 'Ada',
            start: 3,
            end: 7,
          ),
        ],
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(
      SlowmodeException.fromPostgrest(
        const PostgrestException(message: 'Something else', code: 'P0001'),
      ),
      isNull,
    );
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

  test(
    'sendFileMessage uploads to chat-files and sends a file message',
    () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        storagePathSeed: () => 'seed-1',
      );

      await repository.sendFileMessage(
        conversationId: 'conversation-1',
        fileName: 'Trip Plan.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      await repository.sendFileMessage(
        conversationId: 'conversation-1',
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
        bytes: Uint8List.fromList([5]),
      );

      expect(dataSource.uploadedImages.first.bucket, 'chat-files');
      expect(
        dataSource.uploadedImages.first.path,
        'conversation-1/seed-1-trip-plan.pdf',
      );
      expect(dataSource.insertedMessages.first, {
        'conversation_id': 'conversation-1',
        'sender_id': 'user-1',
        'type': 'file',
        'body': '',
        'attachment': {
          'kind': 'file',
          'bucket': 'chat-files',
          'path': 'conversation-1/seed-1-trip-plan.pdf',
          'name': 'Trip Plan.pdf',
          'mime_type': 'application/pdf',
          'size': 4,
        },
      });
      expect(
        (dataSource.insertedMessages.last['attachment'] as Map)['kind'],
        'video',
      );
    },
  );

  test('sent messages are handed on for push', () async {
    final pushed = <String>[];
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
      onMessageSent: (id) async => pushed.add(id),
    );

    await repository.sendFileMessage(
      conversationId: 'conversation-1',
      fileName: 'a.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList([1]),
    );

    expect(pushed, ['inserted-1']);
  });

  test('sendFileMessage refuses files over 50 MB before uploading', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await expectLater(
      repository.sendFileMessage(
        conversationId: 'conversation-1',
        fileName: 'huge.bin',
        mimeType: 'application/octet-stream',
        bytes: Uint8List(maxChatFileBytes + 1),
      ),
      throwsA(isA<ChatFileTooLargeException>()),
    );
    expect(dataSource.uploadedImages, isEmpty);
    expect(dataSource.insertedMessages, isEmpty);
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

  test(
    'a group avatar is stored at 512 px, an animated one as it is',
    () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
        storagePathSeed: () => 'seed-1',
      );
      final big = img.Image(width: 1600, height: 1200);
      img.fill(big, color: img.ColorRgb8(30, 120, 200));
      final png = Uint8List.fromList(img.encodePng(big));

      final path = await repository.uploadGroupAvatar(
        conversationId: 'conversation-1',
        image: ChatImageUpload(
          bytes: png,
          fileName: 'Group.PNG',
          mimeType: 'image/png',
        ),
      );

      expect(path, 'group-avatars/conversation-1/seed-1-group.jpg');
      final stored = dataSource.uploadedImages.single;
      expect(stored.mimeType, 'image/jpeg');
      final decoded = img.decodeJpg(stored.bytes)!;
      expect((decoded.width, decoded.height), (512, 384));

      final frames = img.Image(width: 700, height: 700)..frameDuration = 100;
      img.fill(frames, color: img.ColorRgb8(255, 0, 0));
      frames.addFrame(img.Image(width: 700, height: 700)..frameDuration = 100);
      final gif = Uint8List.fromList(img.encodeGif(frames));
      await repository.uploadGroupAvatar(
        conversationId: 'conversation-1',
        image: ChatImageUpload(
          bytes: gif,
          fileName: 'dance.gif',
          mimeType: 'image/gif',
        ),
      );
      expect(dataSource.uploadedImages.last.mimeType, 'image/gif');
      expect(identical(dataSource.uploadedImages.last.bytes, gif), isTrue);
    },
  );

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

  test(
    'recallMessage removes the unused image the server returns, best effort',
    () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['recall_message'] = [
          {'bucket_id': 'chat-images', 'object_path': 'conversation-1/a.png'},
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await repository.recallMessage(messageId: 'message-1');

      expect(dataSource.removedObjects, {
        'chat-images': ['conversation-1/a.png'],
      });

      dataSource
        ..removedObjects.clear()
        ..removeObjectsError = StateError('storage down');
      await repository.recallMessage(messageId: 'message-1');
      expect(dataSource.removedObjects, isEmpty);
    },
  );

  test(
    'recallMessage removes nothing when the server returns no files',
    () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['recall_message'] = <Object?>[];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await repository.recallMessage(messageId: 'message-1');

      expect(dataSource.removedObjects, isEmpty);
    },
  );

  test('listMessages maps reaction summaries on each message', () async {
    final dataSource = FakeChatsDataSource()
      ..messageRows = [
        {
          'id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'type': 'text',
          'body': 'Hello',
          'created_at': '2026-05-18T04:30:00.000Z',
          'reactions': [
            {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
            {'emoji': '🎉', 'count': 1, 'reacted_by_me': false},
            {'emoji': '', 'count': 1, 'reacted_by_me': false},
          ],
        },
        {
          'id': 'message-2',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-1',
          'type': 'text',
          'body': 'No reactions',
          'created_at': '2026-05-18T04:31:00.000Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final messages = await repository.listMessages('conversation-1');
    final reactions = messages.first.reactions;

    expect(reactions.map((reaction) => reaction.emoji), ['👍', '🎉']);
    expect(reactions.map((reaction) => reaction.count), [2, 1]);
    expect(reactions.map((reaction) => reaction.reactedByMe), [true, false]);
    expect(messages.last.reactions, isEmpty);
  });

  test('toggleMessageReaction calls the reaction RPC', () async {
    final dataSource = FakeChatsDataSource();
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.toggleMessageReaction(
      messageId: 'message-1',
      emoji: ' 👍 ',
    );

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'toggle_message_reaction',
        params: {'target_message_id': 'message-1', 'target_emoji': '👍'},
      ),
    ]);
  });

  test('listMessageReactors maps reactor profile rows', () async {
    final dataSource = FakeChatsDataSource()
      ..reactorRows = [
        {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada Lovelace',
          'avatar_url': null,
          'bio': '',
          'created_at': '2026-05-18T00:00:00.000Z',
          'updated_at': '2026-05-18T00:00:00.000Z',
          'alias': 'Countess',
          'reacted_at': '2026-05-18T04:32:00.000Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final reactors = await repository.listMessageReactors(
      messageId: 'message-1',
      emoji: '🎉',
    );

    expect(reactors.single.id, 'user-2');
    expect(reactors.single.displayLabel, 'Countess');
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'list_message_reactors',
        params: {'target_message_id': 'message-1', 'target_emoji': '🎉'},
      ),
    ]);
  });

  test('listMessages maps pinned state and system pin notices', () async {
    final dataSource = FakeChatsDataSource()
      ..messageRows = [
        {
          'id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'type': 'text',
          'body': 'Pin me',
          'created_at': '2026-05-18T04:30:00.000Z',
          'is_pinned': true,
        },
        {
          'id': 'message-2',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-1',
          'type': 'system',
          'body': 'Grace pinned a message.',
          'attachment': {'kind': 'pin', 'message_id': 'message-1'},
          'created_at': '2026-05-18T04:31:00.000Z',
          'is_pinned': false,
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final messages = await repository.listMessages('conversation-1');

    expect(messages.first.isPinned, isTrue);
    expect(messages.first.pinnedMessageId, isNull);
    expect(messages.last.type, MessageType.system);
    expect(messages.last.isPinned, isFalse);
    expect(messages.last.pinnedMessageId, 'message-1');
  });

  test('listMessages maps embedded senders, aliases and nicknames', () async {
    final dataSource = FakeChatsDataSource()
      ..messageRows = [
        {
          'id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'type': 'text',
          'body': 'Hello',
          'created_at': '2026-05-18T04:30:00.000Z',
          'sender': {
            'id': 'user-2',
            'username': 'grace',
            'display_name': 'Grace Hopper',
            'avatar_url': 'user-2/avatar.png',
            'bio': '',
            'created_at': '2026-05-18T00:00:00.000Z',
            'updated_at': '2026-05-18T00:00:00.000Z',
            'contact_alias': [
              {'alias': 'Amazing Grace'},
            ],
          },
          'sender_nickname': 'Admiral',
          'sender_circle_avatar': 'user-2/1-circle.png',
          'sender_role_color': 3447003,
        },
        {
          'id': 'message-2',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-3',
          'type': 'text',
          'body': 'No embed',
          'created_at': '2026-05-18T04:31:00.000Z',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final messages = await repository.listMessages('conversation-1');

    expect(messages.first.sender?.displayName, 'Grace Hopper');
    expect(messages.first.sender?.displayLabel, 'Amazing Grace');
    expect(messages.first.sender?.avatarUrl, 'user-2/avatar.png');
    expect(messages.first.senderNickname, 'Admiral');
    expect(messages.first.senderCircleAvatarUrl, 'user-2/1-circle.png');
    expect(messages.first.senderRoleColor, 3447003);
    expect(messages.last.sender, isNull);
    expect(messages.last.senderNickname, isNull);
    expect(messages.last.senderCircleAvatarUrl, isNull);
  });

  group('link previews', () {
    test('getLinkPreview invokes the function and maps the card', () async {
      final dataSource = FakeChatsDataSource()
        ..functionResults['link-preview'] = {
          'url': 'https://example.com/',
          'status': 'ok',
          'title': ' Example Domain ',
          'description': 'An example',
          'image_url': 'https://example.com/cover.png',
          'site_name': 'Example',
          'fetched_at': '2026-10-13T09:00:00Z',
        };
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final preview = await repository.getLinkPreview('https://example.com');

      expect(dataSource.functionCalls, [
        const RpcCall(
          functionName: 'link-preview',
          params: {'url': 'https://example.com'},
        ),
      ]);
      expect(preview?.url, 'https://example.com/');
      expect(preview?.title, 'Example Domain');
      expect(preview?.description, 'An example');
      expect(preview?.imageUrl, 'https://example.com/cover.png');
      expect(preview?.siteName, 'Example');
    });

    test('getLinkPreview returns null for failed or empty previews', () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      for (final result in <Object?>[
        null,
        'oops',
        {'url': 'https://a.example/', 'status': 'blocked', 'title': 'x'},
        {'url': 'https://a.example/', 'status': 'error'},
        {'url': 'https://a.example/', 'status': 'ok', 'title': '  '},
      ]) {
        dataSource.functionResults['link-preview'] = result;
        expect(
          await repository.getLinkPreview('https://a.example'),
          isNull,
          reason: '$result',
        );
      }
    });

    test('getLinkPreview drops non-http images', () async {
      final dataSource = FakeChatsDataSource()
        ..functionResults['link-preview'] = {
          'url': 'https://a.example/',
          'status': 'ok',
          'title': 'A',
          'image_url': 'javascript:alert(1)',
        };
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final preview = await repository.getLinkPreview('https://a.example');

      expect(preview?.title, 'A');
      expect(preview?.imageUrl, isNull);
    });

    test('setMessageSuppressEmbeds calls the sender RPC', () async {
      final dataSource = FakeChatsDataSource();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      await repository.setMessageSuppressEmbeds(
        messageId: 'message-1',
        suppress: true,
      );

      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'set_message_suppress_embeds',
          params: {'target_message_id': 'message-1', 'suppress': true},
        ),
      ]);
    });

    test('listMessages maps suppress_embeds', () async {
      final dataSource = FakeChatsDataSource()
        ..messageRows = [
          {
            'id': 'message-1',
            'conversation_id': 'conversation-1',
            'sender_id': 'user-1',
            'type': 'text',
            'body': 'https://example.com',
            'created_at': '2026-05-18T04:30:00.000Z',
            'suppress_embeds': true,
          },
          {
            'id': 'message-2',
            'conversation_id': 'conversation-1',
            'sender_id': 'user-1',
            'type': 'text',
            'body': 'https://example.org',
            'created_at': '2026-05-18T04:31:00.000Z',
          },
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final messages = await repository.listMessages('conversation-1');

      expect(messages.first.suppressEmbeds, isTrue);
      expect(messages.last.suppressEmbeds, isFalse);
    });
  });

  test('pin RPCs are called with the target message', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcResults['can_current_user_pin_messages'] = true;
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    expect(await repository.canPinMessages('conversation-1'), isTrue);
    await repository.pinMessage(messageId: 'message-1');
    await repository.unpinMessage(messageId: 'message-1');

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'get_conversation_capabilities',
        params: {'target_conversation_id': 'conversation-1'},
      ),
      const RpcCall(
        functionName: 'can_current_user_pin_messages',
        params: {'target_conversation_id': 'conversation-1'},
      ),
      const RpcCall(
        functionName: 'pin_message',
        params: {'target_message_id': 'message-1'},
      ),
      const RpcCall(
        functionName: 'unpin_message',
        params: {'target_message_id': 'message-1'},
      ),
    ]);
  });

  group('threads', () {
    Map<String, dynamic> threadRow({String? archivedAt}) => {
      'id': 'thread-1',
      'conversation_id': 'thread-conversation-1',
      'parent_conversation_id': 'conversation-1',
      'root_message_id': 'message-1',
      'title': 'Plans',
      'created_by': 'user-1',
      'created_at': '2026-10-13T08:00:00Z',
      'archived_at': archivedAt,
      'last_message_at': '2026-10-13T09:00:00Z',
      'reply_count': 3,
      'unread_count': 1,
      'can_manage': true,
    };

    test('createThread sends the root and trimmed title', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['create_thread'] = threadRow();
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final thread = await repository.createThread(
        parentConversationId: 'conversation-1',
        rootMessageId: 'message-1',
        title: '  Plans ',
      );
      await repository.createThread(
        parentConversationId: 'conversation-1',
        title: '   ',
      );

      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'create_thread',
          params: {
            'parent_conversation_id': 'conversation-1',
            'root_message_id': 'message-1',
            'title': 'Plans',
          },
        ),
        const RpcCall(
          functionName: 'create_thread',
          params: {
            'parent_conversation_id': 'conversation-1',
            'root_message_id': null,
            'title': null,
          },
        ),
      ]);
      expect(thread.id, 'thread-1');
      expect(thread.conversationId, 'thread-conversation-1');
      expect(thread.rootMessageId, 'message-1');
      expect(thread.replyCount, 3);
      expect(thread.unreadCount, 1);
      expect(thread.canManage, isTrue);
      expect(thread.lastMessageAt, DateTime.utc(2026, 10, 13, 9));
    });

    test('listThreads parses every thread of the parent', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['list_threads'] = [
          threadRow(),
          {...threadRow(archivedAt: '2026-10-13T10:00:00Z'), 'id': 'thread-2'},
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final threads = await repository.listThreads('conversation-1');

      expect(dataSource.rpcCalls.single.functionName, 'list_threads');
      expect(dataSource.rpcCalls.single.params, {
        'parent_conversation_id': 'conversation-1',
      });
      expect(threads.map((thread) => thread.id), ['thread-1', 'thread-2']);
      expect(threads.map((thread) => thread.isArchived), [false, true]);
    });

    test('setThreadArchived calls archive and unarchive RPCs', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['archive_thread'] = threadRow(
          archivedAt: '2026-10-13T10:00:00Z',
        )
        ..rpcResults['unarchive_thread'] = threadRow()
        ..rpcResults['can_current_user_manage_thread'] = null;
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final archived = await repository.setThreadArchived(
        threadId: 'thread-1',
        archived: true,
      );
      final restored = await repository.setThreadArchived(
        threadId: 'thread-1',
        archived: false,
      );

      expect(archived.isArchived, isTrue);
      expect(restored.isArchived, isFalse);
      expect(await repository.canManageThread('thread-1'), isFalse);
      expect(dataSource.rpcCalls, [
        const RpcCall(
          functionName: 'archive_thread',
          params: {'target_thread_id': 'thread-1'},
        ),
        const RpcCall(
          functionName: 'unarchive_thread',
          params: {'target_thread_id': 'thread-1'},
        ),
        const RpcCall(
          functionName: 'can_current_user_manage_thread',
          params: {'target_thread_id': 'thread-1'},
        ),
      ]);
    });

    test('listMessages parses thread summaries on root messages', () async {
      final dataSource = FakeChatsDataSource()
        ..messageRows = [
          {
            'id': 'message-1',
            'conversation_id': 'conversation-1',
            'sender_id': 'user-2',
            'type': 'text',
            'body': 'Root',
            'created_at': '2026-10-13T08:00:00Z',
            'thread_summary': {
              'thread_id': 'thread-1',
              'conversation_id': 'thread-conversation-1',
              'title': 'Plans',
              'reply_count': 2,
              'last_reply_at': '2026-10-13T09:00:00Z',
              'unread_count': 1,
              'archived_at': null,
            },
          },
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final messages = await repository.listMessages('conversation-1');
      final summary = messages.single.threadSummary!;

      expect(summary.threadId, 'thread-1');
      expect(summary.conversationId, 'thread-conversation-1');
      expect(summary.replyCount, 2);
      expect(summary.unreadCount, 1);
      expect(summary.lastReplyAt, DateTime.utc(2026, 10, 13, 9));
    });

    test('thread conversations parse with their parent', () async {
      final dataSource = FakeChatsDataSource()
        ..conversationRows = [
          {
            'id': 'thread-conversation-1',
            'type': 'thread',
            'title': 'Plans',
            'unread_count': 2,
            'parent_conversation_id': 'conversation-1',
            'parent_title': 'general',
            'thread_id': 'thread-1',
            'thread_archived_at': null,
            'thread_last_activity_at': '2026-10-13T09:00:00Z',
            'circle_id': 'circle-1',
            'can_send_messages': false,
            'slowmode_seconds': 0,
          },
          {
            'id': 'conversation-3',
            'type': 'channel',
            'unread_count': 0,
            'slowmode_seconds': 30,
          },
          {'id': 'conversation-2', 'type': 'direct', 'unread_count': 0},
        ];
      final repository = SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );

      final [thread, channel, direct] = await repository.listConversations();

      expect(thread.type, ConversationType.thread);
      expect(thread.isThread, isTrue);
      expect(thread.parentConversationId, 'conversation-1');
      expect(thread.parentTitle, 'general');
      expect(thread.threadId, 'thread-1');
      expect(thread.threadLastActivityAt, DateTime.utc(2026, 10, 13, 9));
      expect(thread.canSendMessages, isFalse);
      // Older servers send no permission: sending stays allowed.
      expect(direct.canSendMessages, isTrue);
      expect(direct.slowmodeSeconds, 0);
      expect(channel.slowmodeSeconds, 30);
    });
  });

  group('opening a chat asks for less', () {
    SupabaseChatsRepository repositoryFor(FakeChatsDataSource dataSource) {
      return SupabaseChatsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'user-1',
      );
    }

    test(
      'pin, end polls and delete others share one capabilities request',
      () async {
        final dataSource = FakeChatsDataSource()
          ..rpcResults['get_conversation_capabilities'] = {
            'can_pin_messages': true,
            'can_moderate_polls': false,
            'can_moderate_messages': true,
            'can_manage_thread': false,
          };
        final repository = repositoryFor(dataSource);

        final answers = await Future.wait([
          repository.canPinMessages('conversation-1'),
          repository.canModeratePolls('conversation-1'),
          repository.canModerateMessages('conversation-1'),
        ]);

        expect(answers, [true, false, true]);
        expect(dataSource.rpcCalls, [
          const RpcCall(
            functionName: 'get_conversation_capabilities',
            params: {'target_conversation_id': 'conversation-1'},
          ),
        ]);
      },
    );

    test(
      'a thread shares the request too and needs no question of its own',
      () async {
        final dataSource = FakeChatsDataSource()
          ..rpcResults['get_conversation_capabilities'] = {
            'can_pin_messages': false,
            'can_moderate_polls': false,
            'can_moderate_messages': true,
            'can_manage_thread': true,
          };
        final repository = repositoryFor(dataSource);

        final answers = await Future.wait([
          canManageThreadOf(
            repository,
            threadConversationId: 'thread-conversation',
            threadId: 'thread-1',
          ),
          repository.canPinMessages('thread-conversation'),
          repository.canModerateMessages('thread-conversation'),
        ]);

        expect(answers, [true, false, true]);
        expect(dataSource.rpcCalls, [
          const RpcCall(
            functionName: 'get_conversation_capabilities',
            params: {'target_conversation_id': 'thread-conversation'},
          ),
        ]);
      },
    );

    test('an older server is asked about the thread on its own', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcErrors['get_conversation_capabilities'] = const PostgrestException(
          message: 'function not found',
          code: '42883',
        )
        ..rpcResults['can_current_user_manage_thread'] = true;
      final repository = repositoryFor(dataSource);

      expect(
        await canManageThreadOf(
          repository,
          threadConversationId: 'thread-conversation',
          threadId: 'thread-1',
        ),
        isTrue,
      );
      expect(dataSource.rpcCalls.map((call) => call.functionName), [
        'get_conversation_capabilities',
        'can_current_user_manage_thread',
      ]);
    });

    test('a repository without the capabilities request falls back', () async {
      final fake = _ThreadFallbackRepository();

      expect(
        await canManageThreadOf(
          fake,
          threadConversationId: 'thread-conversation',
          threadId: 'thread-1',
        ),
        isTrue,
      );
      expect(fake.asked, ['thread-1']);
    });

    test('a later question asks the server again', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['get_conversation_capabilities'] = {
          'can_pin_messages': true,
        };
      final repository = repositoryFor(dataSource);

      expect(await repository.canPinMessages('conversation-1'), isTrue);
      dataSource.rpcResults['get_conversation_capabilities'] = {
        'can_pin_messages': false,
      };
      expect(await repository.canPinMessages('conversation-1'), isFalse);
      expect(dataSource.rpcCalls, hasLength(2));
    });

    test('other conversations are asked for separately', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['get_conversation_capabilities'] = {
          'can_pin_messages': true,
        };
      final repository = repositoryFor(dataSource);
      await Future.wait([
        repository.canPinMessages('conversation-1'),
        repository.canPinMessages('conversation-2'),
      ]);
      expect(dataSource.rpcCalls, hasLength(2));
    });

    test('a server without the function is asked the old way', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcErrors['get_conversation_capabilities'] = const PostgrestException(
          message: 'Could not find the function',
          code: 'PGRST202',
        )
        ..rpcResults['can_current_user_pin_messages'] = true
        ..rpcResults['can_current_user_moderate_polls'] = false
        ..rpcResults['can_current_user_moderate_messages'] = true;
      final repository = repositoryFor(dataSource);

      expect(await repository.canPinMessages('conversation-1'), isTrue);
      expect(await repository.canModeratePolls('conversation-1'), isFalse);
      expect(await repository.canModerateMessages('conversation-1'), isTrue);
    });

    test('another failure is not hidden', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcErrors['get_conversation_capabilities'] = const PostgrestException(
          message: 'boom',
          code: '500',
        );
      final repository = repositoryFor(dataSource);
      await expectLater(
        repository.canPinMessages('conversation-1'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a conversation summary is one row, not the list', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['get_conversation_summary'] = [
          {
            'id': 'conversation-1',
            'type': 'group',
            'title': 'Hike club',
            'unread_count': 3,
          },
        ];
      final repository = repositoryFor(dataSource);

      final summary = await repository.getConversationSummary('conversation-1');

      expect(summary?.title, 'Hike club');
      expect(summary?.unreadCount, 3);
      expect(
        dataSource.rpcCalls.single.functionName,
        'get_conversation_summary',
      );
      expect(dataSource.rpcCalls.single.params, {
        'target_conversation_id': 'conversation-1',
      });
      expect(dataSource.listCalls, 0, reason: 'the list was not fetched');
    });

    test('no row means no such conversation', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcResults['get_conversation_summary'] = <Object?>[];
      final repository = repositoryFor(dataSource);
      expect(await repository.getConversationSummary('nowhere'), isNull);
      expect(dataSource.listCalls, 0);
    });

    test(
      'the header and the group details share one summary request',
      () async {
        final dataSource = FakeChatsDataSource()
          ..rpcResults['get_conversation_summary'] = [
            {
              'id': 'conversation-1',
              'type': 'group',
              'title': 'Hike club',
              'announcement': 'Bring water',
              'unread_count': 0,
            },
          ];
        final repository = repositoryFor(dataSource);

        final results = await Future.wait<Object?>([
          repository.getConversationSummary('conversation-1'),
          repository.getGroupDetail('conversation-1'),
        ]);

        expect((results[1]! as GroupDetail).title, 'Hike club');
        expect((results[1]! as GroupDetail).announcement, 'Bring water');
        expect(
          dataSource.rpcCalls.where(
            (call) => call.functionName == 'get_conversation_summary',
          ),
          hasLength(1),
        );
        expect(dataSource.listCalls, 0);
      },
    );

    test('a server without the function reads the list', () async {
      final dataSource = FakeChatsDataSource()
        ..rpcErrors['get_conversation_summary'] = const PostgrestException(
          message: 'Could not find the function',
          code: 'PGRST202',
        )
        ..conversationRows = [
          {
            'id': 'conversation-1',
            'type': 'group',
            'title': 'Old list',
            'unread_count': 0,
          },
          {'id': 'conversation-2', 'type': 'direct', 'unread_count': 0},
        ];
      final repository = repositoryFor(dataSource);
      expect(
        (await repository.getConversationSummary('conversation-1'))?.title,
        'Old list',
      );
      expect(await repository.getConversationSummary('conversation-9'), isNull);
    });
  });

  test('canPinMessages treats a null RPC result as not allowed', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcResults['can_current_user_pin_messages'] = null;
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    expect(await repository.canPinMessages('conversation-1'), isFalse);
  });

  test('pinMessage maps the pin limit error to a typed exception', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcErrors['pin_message'] = const PostgrestException(
        message: 'A conversation can have at most 50 pinned messages',
        code: '54000',
      );
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await expectLater(
      repository.pinMessage(messageId: 'message-1'),
      throwsA(isA<PinnedMessageLimitException>()),
    );
  });

  test('pinMessage rethrows other database errors', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcErrors['pin_message'] = const PostgrestException(
        message: 'Message not found or caller cannot pin messages',
        code: '42501',
      );
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await expectLater(
      repository.pinMessage(messageId: 'message-1'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('listPinnedMessages maps message, sender and pin metadata', () async {
    final dataSource = FakeChatsDataSource()
      ..rpcResults['list_pinned_messages'] = [
        {
          'message': {
            'id': 'message-1',
            'conversation_id': 'conversation-1',
            'sender_id': 'user-2',
            'type': 'text',
            'body': 'Remember this',
            'attachment': null,
            'mentions': <Object>[],
            'created_at': '2026-05-18T04:30:00.123456+00:00',
            'recalled_at': null,
            'is_pinned': true,
          },
          'sender': {
            'id': 'user-2',
            'username': 'ada',
            'display_name': 'Ada Lovelace',
            'alias': 'Countess',
            'avatar_url': null,
            'bio': '',
            'created_at': '2026-05-18T00:00:00+00:00',
            'updated_at': '2026-05-18T00:00:00+00:00',
          },
          'pinned_by': 'user-1',
          'pinned_by_name': 'Grace',
          'pinned_at': '2026-05-18T05:00:00+00:00',
        },
      ];
    final repository = SupabaseChatsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final pinned = await repository.listPinnedMessages('conversation-1');

    expect(pinned.single.message.id, 'message-1');
    expect(pinned.single.message.body, 'Remember this');
    expect(pinned.single.message.isPinned, isTrue);
    expect(pinned.single.sender.displayLabel, 'Countess');
    expect(pinned.single.pinnedBy, 'user-1');
    expect(pinned.single.pinnedByName, 'Grace');
    expect(pinned.single.pinnedAt, DateTime.utc(2026, 5, 18, 5));
    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'list_pinned_messages',
        params: {'target_conversation_id': 'conversation-1'},
      ),
    ]);
  });

  test('searchThreadMessages skips system notices', () {
    final repository = SupabaseChatsRepository.withDataSource(
      FakeChatsDataSource(),
      currentUserId: () => 'user-1',
    );
    final messages = [
      ChatMessage(
        id: 'message-1',
        conversationId: 'conversation-1',
        senderId: 'user-2',
        type: MessageType.text,
        body: 'We pinned the plan',
        createdAt: DateTime.utc(2026, 5, 18),
      ),
      ChatMessage(
        id: 'message-2',
        conversationId: 'conversation-1',
        senderId: 'user-1',
        type: MessageType.system,
        body: 'Grace pinned a message.',
        createdAt: DateTime.utc(2026, 5, 18, 0, 1),
      ),
    ];

    final results = repository.searchThreadMessages(messages, 'pinned');

    expect(results.map((message) => message.id), ['message-1']);
  });

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
  var mediaRows = <Map<String, dynamic>>[];
  var reactorRows = <Map<String, dynamic>>[];
  var readMarkerRows = <Map<String, dynamic>>[];
  var groupMemberRows = <Map<String, dynamic>>[];
  var rpcResult = 'conversation-1';
  final rpcResults = <String, Object?>{};
  final rpcErrors = <String, Object>{};
  Object? insertError;

  /// Thrown by the next inserts, one each, before [insertError].
  final insertErrors = <Object>[];
  var insertReturnsNull = false;
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
  final removedObjects = <String, List<String>>{};
  Object? removeObjectsError;
  final signedUrlCalls = <SignedUrlCall>[];
  final rpcCalls = <RpcCall>[];
  final autoModNoticeCalls = <String>[];
  Map<String, dynamic>? autoModNotice;
  final functionCalls = <RpcCall>[];
  final functionResults = <String, Object?>{};
  final functionErrors = <String, Object>{};
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
  Future<String?> insertMessage(Map<String, dynamic> values) async {
    if (insertErrors.isNotEmpty) {
      throw insertErrors.removeAt(0);
    }
    if (insertError case final error?) {
      throw error;
    }
    insertedMessages.add(values);
    if (insertReturnsNull) {
      return null;
    }
    return 'inserted-${insertedMessages.length}';
  }

  @override
  Future<Map<String, dynamic>?> takeAutoModNotice(String conversationId) async {
    autoModNoticeCalls.add(conversationId);
    return autoModNotice;
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
  Future<void> removeObjects({
    required String bucket,
    required List<String> paths,
  }) async {
    final error = removeObjectsError;
    if (error != null) {
      throw error;
    }
    removedObjects[bucket] = paths;
  }

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add(RpcCall(functionName: functionName, params: params));
    if (rpcErrors[functionName] case final error?) {
      throw error;
    }
    if (rpcResults.containsKey(functionName)) {
      return rpcResults[functionName];
    }
    if (functionName == 'search_messages') {
      return searchRows;
    }
    if (functionName == 'search_discovery') {
      return discoveryRows;
    }
    if (functionName == 'list_conversation_media') {
      return mediaRows;
    }
    if (functionName == 'list_message_reactors') {
      return reactorRows;
    }
    return rpcResult;
  }

  @override
  Future<Object?> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    functionCalls.add(RpcCall(functionName: functionName, params: body));
    if (functionErrors[functionName] case final error?) {
      throw error;
    }
    return functionResults[functionName];
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

  final pageCalls =
      <
        ({
          String conversationId,
          MessageCursor? before,
          MessageCursor? after,
          int limit,
        })
      >[];
  final byIdCalls = <List<String>>[];
  final reactionCalls = <List<String>>[];
  var reactionRows = <Map<String, dynamic>>[];
  final threadEventControllers = <String, StreamController<ThreadEvent>>{};

  @override
  Future<List<Map<String, dynamic>>> listMessagePage(
    String conversationId, {
    MessageCursor? before,
    MessageCursor? after,
    required int limit,
  }) async {
    pageCalls.add((
      conversationId: conversationId,
      before: before,
      after: after,
      limit: limit,
    ));
    return messageRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listMessagesByIds(
    String conversationId,
    List<String> messageIds,
  ) async {
    byIdCalls.add(messageIds);
    return [
      for (final row in messageRows)
        if (messageIds.contains(row['id'])) row,
    ];
  }

  @override
  Future<List<dynamic>> listMessageReactions(
    String conversationId,
    List<String> messageIds,
  ) async {
    reactionCalls.add(messageIds);
    return reactionRows;
  }

  @override
  Stream<ThreadEvent> threadEvents(String conversationId) {
    return threadEventControllers
        .putIfAbsent(
          conversationId,
          () => StreamController<ThreadEvent>.broadcast(),
        )
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

/// A repository that only knows the old question about threads.
class _ThreadFallbackRepository implements ChatsRepository {
  final asked = <String>[];

  @override
  Future<bool> canManageThread(String threadId) async {
    asked.add(threadId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
