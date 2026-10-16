import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  test('listCircles maps list_circle_summaries rows', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_circle_summaries'] = [
        {
          'id': 'circle-1',
          'name': 'Close Friends',
          'member_count': 3,
          'channel_count': 1,
          'current_user_role': 'owner',
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final circles = await repository.listCircles();

    expect(circles.single.name, 'Close Friends');
    expect(circles.single.memberCount, 3);
    expect(circles.single.currentUserRole, 'owner');
    expect(circles.single.unreadCount, 0);
    expect(circles.single.mentionCount, 0);
    expect(circles.single.isMuted, isFalse);
    expect(dataSource.calls.single.functionName, 'list_circle_summaries');
    expect(dataSource.calls.single.params, isEmpty);
  });

  test('listCircles maps unread, mention and mute state', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_circle_summaries'] = [
        {
          'id': 'circle-1',
          'name': 'Close Friends',
          'member_count': 3,
          'channel_count': 2,
          'current_user_role': 'member',
          'unread_count': 4,
          'mention_count': 2,
          'is_muted': true,
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final circle = (await repository.listCircles()).single;

    expect(circle.unreadCount, 4);
    expect(circle.mentionCount, 2);
    expect(circle.isMuted, isTrue);
    expect(circle.toJson(), containsPair('mention_count', 2));
  });

  test('getCircleDetail maps get_circle_detail JSON payload', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle': {
          'id': 'circle-1',
          'name': 'Close Friends',
          'member_count': 2,
          'channel_count': 1,
          'current_user_role': 'admin',
        },
        'members': [
          {
            'role': 'owner',
            'nickname': 'Countess',
            'is_current_user': true,
            'profile': _profileRow(id: 'u1', name: 'Ada'),
          },
        ],
        'channels': [
          {
            'id': 'channel-1',
            'circle_id': 'circle-1',
            'conversation_id': 'conversation-1',
            'name': 'General',
            'position': 0,
          },
          {
            'id': 'channel-2',
            'circle_id': 'circle-1',
            'conversation_id': 'conversation-2',
            'name': 'Clips',
            'position': 1,
            'category_id': 'category-1',
          },
        ],
        'categories': [
          {
            'id': 'category-1',
            'circle_id': 'circle-1',
            'name': 'Media',
            'position': 0,
            'created_at': '2026-10-13T00:00:00Z',
          },
        ],
        'posts': [
          {
            'id': 'post-1',
            'circle_id': 'circle-1',
            'author_id': 'u1',
            'body': 'Hello',
            'created_at': '2026-05-19T00:00:00Z',
            'updated_at': '2026-05-19T00:00:00Z',
            'author': _profileRow(id: 'u1', name: 'Ada'),
            'comments': [
              {
                'id': 'comment-1',
                'post_id': 'post-1',
                'author_id': 'u2',
                'body': 'Hi',
                'created_at': '2026-05-19T00:01:00Z',
                'updated_at': '2026-05-19T00:01:00Z',
                'author': _profileRow(id: 'u2', name: 'Grace'),
              },
            ],
            'like_count': 4,
            'comment_count': 1,
            'liked_by_current_user': true,
          },
        ],
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final detail = await repository.getCircleDetail('circle-1');

    expect(detail.circle.name, 'Close Friends');
    expect(detail.members.single.profile.id, 'u1');
    expect(detail.members.single.nickname, 'Countess');
    expect(detail.members.single.displayName, 'Countess');
    expect(detail.members.single.isCurrentUser, isTrue);
    expect(detail.channels.map((channel) => channel.name), [
      'General',
      'Clips',
    ]);
    expect(detail.channels.first.categoryId, isNull);
    expect(detail.channels.last.categoryId, 'category-1');
    expect(detail.categories.single.id, 'category-1');
    expect(detail.categories.single.name, 'Media');
    expect(detail.posts.single.comments.single.body, 'Hi');
    expect(dataSource.calls.single.functionName, 'get_circle_detail');
    expect(dataSource.calls.single.params, {'target_circle_id': 'circle-1'});
  });

  test('setNickname trims and calls set_circle_nickname', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.setNickname(
      circleId: 'circle-1',
      userId: 'u2',
      nickname: '  Grace  ',
    );
    await repository.setNickname(
      circleId: 'circle-1',
      userId: 'u2',
      nickname: '   ',
    );

    expect(dataSource.calls.map((call) => call.functionName), [
      'set_circle_nickname',
      'set_circle_nickname',
    ]);
    expect(dataSource.calls.first.params, {
      'target_circle_id': 'circle-1',
      'target_user_id': 'u2',
      'nickname': 'Grace',
    });
    expect(dataSource.calls.last.params['nickname'], isNull);
  });

  test('role methods call the role RPCs', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'role-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final roleId = await repository.createRole(
      circleId: 'circle-1',
      name: '  Mods ',
      color: 0x3498DB,
      permissions: 4 | 16,
      hoist: true,
    );
    await repository.updateRole(
      roleId: 'role-1',
      name: 'Moderators',
      permissions: 4,
    );
    await repository.deleteRole('role-1');
    await repository.reorderRoles(
      circleId: 'circle-1',
      roleIds: ['role-2', 'role-1'],
    );
    await repository.setMemberRoles(
      circleId: 'circle-1',
      userId: 'u2',
      roleIds: ['role-2'],
    );

    expect(roleId, 'role-1');
    expect(dataSource.calls.map((call) => call.functionName), [
      'create_circle_role',
      'update_circle_role',
      'delete_circle_role',
      'reorder_circle_roles',
      'set_member_roles',
    ]);
    expect(dataSource.calls[0].params, {
      'target_circle_id': 'circle-1',
      'role_name': 'Mods',
      'role_color': 0x3498DB,
      'role_permissions': 20,
      'role_hoist': true,
    });
    expect(dataSource.calls[1].params, {
      'target_role_id': 'role-1',
      'role_name': 'Moderators',
      'role_color': null,
      'role_permissions': 4,
      'role_hoist': false,
    });
    expect(dataSource.calls[2].params, {'target_role_id': 'role-1'});
    expect(dataSource.calls[3].params, {
      'target_circle_id': 'circle-1',
      'role_ids': ['role-2', 'role-1'],
    });
    expect(dataSource.calls[4].params, {
      'target_circle_id': 'circle-1',
      'target_user_id': 'u2',
      'role_ids': ['role-2'],
    });
  });

  test('kickMember calls kick_circle_member', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.kickMember(circleId: 'circle-1', userId: 'u2');

    expect(dataSource.calls.single.functionName, 'kick_circle_member');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'target_user_id': 'u2',
    });
  });

  test('banMember bans and removes the deleted messages\' media', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['ban_circle_member'] = [
        {'bucket_id': 'chat-images', 'object_path': 'c1/a.png'},
        {'bucket_id': 'chat-images', 'object_path': 'c1/b.png'},
        {'bucket_id': 'voice-messages', 'object_path': 'c1/v.m4a'},
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.banMember(
      circleId: 'circle-1',
      userId: 'u2',
      reason: '  spam  ',
      deleteMessageHours: 24,
    );

    expect(dataSource.calls.single.functionName, 'ban_circle_member');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'target_user_id': 'u2',
      'ban_reason': 'spam',
      'delete_message_hours': 24,
    });
    expect(
      [
        for (final removed in dataSource.removedObjects)
          '${removed.bucket}: ${removed.paths.join(', ')}',
      ],
      ['chat-images: c1/a.png, c1/b.png', 'voice-messages: c1/v.m4a'],
    );
  });

  test('banMember sends no reason when it is blank', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.banMember(circleId: 'circle-1', userId: 'u2', reason: ' ');

    expect(dataSource.calls.single.params['ban_reason'], isNull);
    expect(dataSource.calls.single.params['delete_message_hours'], 0);
    expect(dataSource.removedObjects, isEmpty);
  });

  test('listBans, unbanMember and timeoutMember call their RPCs', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_circle_bans'] = [
        {
          'user_id': 'u2',
          'username': 'bo',
          'display_name': '',
          'avatar_url': null,
          'reason': 'spam',
          'banned_by_name': 'Xu',
          'created_at': '2026-10-14T08:00:00Z',
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final bans = await repository.listBans('circle-1');
    expect(bans.single.userId, 'u2');
    expect(bans.single.name, 'bo');
    expect(bans.single.reason, 'spam');
    expect(bans.single.bannedByName, 'Xu');

    await repository.unbanMember(circleId: 'circle-1', userId: 'u2');
    expect(dataSource.calls.last.functionName, 'unban_circle_member');

    dataSource.rpcValue = '2026-10-14T09:00:00+00:00';
    final until = await repository.timeoutMember(
      circleId: 'circle-1',
      userId: 'u3',
      duration: const Duration(hours: 1),
    );
    expect(dataSource.calls.last.functionName, 'timeout_circle_member');
    expect(dataSource.calls.last.params, {
      'target_circle_id': 'circle-1',
      'target_user_id': 'u3',
      'duration_seconds': 3600,
    });
    expect(until, DateTime.utc(2026, 10, 14, 9));

    dataSource.rpcValue = null;
    expect(
      await repository.timeoutMember(
        circleId: 'circle-1',
        userId: 'u3',
        duration: Duration.zero,
      ),
      isNull,
    );
    expect(dataSource.calls.last.params['duration_seconds'], 0);
  });

  test('leaveCircle and transferOwnership call their RPCs', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.leaveCircle('circle-1');
    await repository.transferOwnership(circleId: 'circle-1', newOwnerId: 'u2');

    expect(dataSource.calls.map((call) => call.functionName), [
      'leave_circle',
      'transfer_circle_ownership',
    ]);
    expect(dataSource.calls.first.params, {'target_circle_id': 'circle-1'});
    expect(dataSource.calls.last.params, {
      'target_circle_id': 'circle-1',
      'new_owner_id': 'u2',
    });
  });

  test('getCircleDetail reports a lost membership when denied', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await expectLater(
      repository.getCircleDetail('circle-1'),
      throwsA(
        isA<CircleMembershipLostException>().having(
          (error) => error.circleId,
          'circleId',
          'circle-1',
        ),
      ),
    );
  });

  test('listAuditLog calls list_circle_audit_log and maps entries', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = [
        {
          'id': 'audit-1',
          'circle_id': 'circle-1',
          'action': 'role_update',
          'target_type': 'role',
          'target_id': 'role-1',
          'target_label': 'Mods',
          'changes': {
            'name': {'old': 'Mod', 'new': 'Mods'},
          },
          'created_at': '2026-10-14T01:02:03Z',
          'actor': {
            'id': 'u1',
            'username': 'ada',
            'display_name': 'Ada',
            'avatar_url': null,
            'nickname': 'Countess',
          },
        },
        {
          'id': 'audit-2',
          'circle_id': 'circle-1',
          'action': 'member_leave',
          'target_type': 'member',
          'target_id': null,
          'target_label': null,
          'changes': {},
          'created_at': '2026-10-14T01:00:00Z',
          'actor': null,
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final entries = await repository.listAuditLog(
      circleId: 'circle-1',
      before: DateTime.utc(2026, 10, 14, 2),
      limit: 20,
      action: 'role',
    );

    expect(dataSource.calls.single.functionName, 'list_circle_audit_log');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'before': '2026-10-14T02:00:00.000Z',
      'limit_count': 20,
      'action_filter': 'role',
    });
    expect(entries.first.action, 'role_update');
    expect(entries.first.group, CircleAuditActionGroup.role);
    expect(entries.first.actor?.name, 'Countess');
    expect(entries.first.changes['name'], {'old': 'Mod', 'new': 'Mods'});
    expect(entries.first.createdAt, DateTime.utc(2026, 10, 14, 1, 2, 3));
    expect(entries.last.actor, isNull);
    expect(entries.last.group, CircleAuditActionGroup.member);
  });

  test('channel overwrite methods call the overwrite RPCs', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = [
        {
          'id': 'ow-1',
          'channel_id': 'channel-1',
          'role_id': 'everyone',
          'user_id': null,
          'allow': 0,
          'deny': 1,
        },
        {
          'id': 'ow-2',
          'channel_id': 'channel-1',
          'role_id': null,
          'user_id': 'u2',
          'allow': 1 | 2,
          'deny': 0,
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final overwrites = await repository.listChannelOverwrites('channel-1');
    await repository.setChannelOverwrite(
      channelId: 'channel-1',
      roleId: 'role-1',
      allow: 1,
      deny: 2,
    );
    await repository.setChannelPrivacy(
      channelId: 'channel-1',
      isPrivate: true,
      isReadOnly: false,
    );
    await repository.setChannelSlowmode(channelId: 'channel-1', seconds: 30);

    expect(dataSource.calls.map((call) => call.functionName), [
      'list_channel_overwrites',
      'set_channel_overwrite',
      'set_channel_privacy',
      'set_channel_slowmode',
    ]);
    expect(dataSource.calls[3].params, {
      'target_channel_id': 'channel-1',
      'seconds': 30,
    });
    expect(dataSource.calls[0].params, {'target_channel_id': 'channel-1'});
    expect(dataSource.calls[1].params, {
      'target_channel_id': 'channel-1',
      'target_role_id': 'role-1',
      'target_user_id': null,
      'allow_bits': 1,
      'deny_bits': 2,
    });
    expect(dataSource.calls[2].params, {
      'target_channel_id': 'channel-1',
      'private': true,
      'read_only': false,
    });
    expect(overwrites.first.roleId, 'everyone');
    expect(
      overwrites.first.stateOf(CirclePermission.viewChannel),
      OverwriteState.deny,
    );
    expect(overwrites.last.userId, 'u2');
    expect(
      overwrites.last.stateOf(CirclePermission.sendMessages),
      OverwriteState.allow,
    );
    expect(
      overwrites.last.stateOf(CirclePermission.manageMessages),
      OverwriteState.inherit,
    );
  });

  test('forum posts and tags go through RPCs', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_forum_posts'] = [
        {
          'id': 'thread-1',
          'conversation_id': 'conv-t1',
          'channel_id': 'channel-1',
          'title': 'Help',
          'created_by': 'u1',
          'created_at': '2026-10-14T10:00:00.123456+00:00',
          'last_activity_at': '2026-10-14T11:00:00+00:00',
          'archived_at': null,
          'is_pinned': true,
          'author': {
            'id': 'u1',
            'username': 'ada',
            'display_name': 'Ada',
            'avatar_url': null,
            'bio': '',
            'created_at': '2026-01-01T00:00:00+00:00',
            'updated_at': '2026-01-01T00:00:00+00:00',
            'nickname': 'Countess',
            'role_color': 0x3498DB,
          },
          'tags': [
            {
              'id': 'tag-1',
              'channel_id': 'channel-1',
              'name': 'Bug',
              'emoji': '🐛',
              'position': 0,
            },
          ],
          'opening_message': {
            'id': 'm1',
            'type': 'text',
            'body': '**Hi**',
            'recalled': false,
          },
          'reply_count': 3,
          'thumbnail': {
            'kind': 'image',
            'bucket': 'chat-images',
            'path': 'conv-forum/a.png',
            'mime_type': 'image/png',
            'size': 10,
          },
          'unread_count': 2,
          'can_manage': true,
        },
        {
          'id': 'thread-2',
          'conversation_id': 'conv-t2',
          'channel_id': 'channel-1',
          'title': 'Gone',
          'created_at': '2026-10-14T09:00:00+00:00',
          'last_activity_at': '2026-10-14T09:00:00+00:00',
          'author': null,
          'tags': const [],
          'opening_message': null,
          // Not a usable image: no thumbnail.
          'thumbnail': {'kind': 'image', 'bucket': 'chat-images'},
        },
      ]
      ..rpcValue = 'tag-new';
    final repository = SupabaseCirclesRepository(
      dataSource,
      storagePathSeed: () => 'seed',
    );

    final posts = await repository.listForumPosts(
      channelId: 'channel-1',
      sort: ForumPostSort.created,
      tagId: 'tag-1',
      before: ForumPostCursor(
        at: DateTime.utc(2026, 10, 14, 12, 0, 0, 0, 5),
        id: 'thread-0',
      ),
      limit: 10,
    );
    expect(dataSource.calls.last.params, {
      'target_channel_id': 'channel-1',
      'sort_order': 'created',
      'filter_tag_id': 'tag-1',
      'before_at': '2026-10-14T12:00:00.000005Z',
      'before_id': 'thread-0',
      'limit_count': 10,
    });
    final [post, gone] = posts;
    expect(post.title, 'Help');
    expect(post.isPinned, isTrue);
    expect(post.author!.name, 'Countess');
    expect(post.author!.roleColor, 0x3498DB);
    expect(post.tags.single.label, '🐛 Bug');
    expect(post.body, '**Hi**');
    expect(post.replyCount, 3);
    expect(post.unreadCount, 2);
    expect(post.thumbnail!.path, 'conv-forum/a.png');
    expect(post.canManage, isTrue);
    expect(post.cursorFor(ForumPostSort.created).at, post.createdAt);
    expect(post.cursorFor(ForumPostSort.activity).at, post.lastActivityAt);
    expect(post.createdAt.microsecond, 456);
    expect(gone.author, isNull);
    expect(gone.body, isEmpty);
    expect(gone.thumbnail, isNull);

    dataSource.calls.clear();
    final image = await repository.uploadForumImage(
      forumConversationId: 'conv-forum',
      image: ChatImageUpload(
        bytes: Uint8List.fromList(const [1, 2]),
        fileName: 'My Photo.PNG',
        mimeType: 'image/png',
      ),
    );
    expect(dataSource.uploads.single.bucket, 'chat-images');
    expect(dataSource.uploads.single.path, 'conv-forum/seed-my-photo.png');
    expect(image.path, 'conv-forum/seed-my-photo.png');

    dataSource.rpcRows.clear();
    dataSource.rpcValue = {
      'id': 'thread-3',
      'conversation_id': 'conv-t3',
      'channel_id': 'channel-1',
      'title': 'New',
      'created_at': '2026-10-14T12:00:00+00:00',
    };
    final created = await repository.createForumPost(
      channelId: 'channel-1',
      title: ' New ',
      body: ' Body ',
      tagIds: const ['tag-1'],
      image: image,
      mentions: const [
        MessageMention(userId: 'user-2', displayName: 'Bart', start: 0, end: 5),
      ],
    );
    expect(created.id, 'thread-3');
    expect(dataSource.calls.last.functionName, 'create_forum_post');
    expect(dataSource.calls.last.params, {
      'target_channel_id': 'channel-1',
      'post_title': 'New',
      'post_body': 'Body',
      'tag_ids': ['tag-1'],
      'post_attachment': image.toJson(),
      'post_mentions': [
        {
          'user_id': 'user-2',
          'display_name': 'Bart',
          'start': 0,
          'end': 5,
          'kind': 'user',
        },
      ],
    });

    // AutoMod drops a refused post and says why through its notice.
    dataSource.rpcValue = {
      'automod_blocked': true,
      'conversation_id': 'conv-forum',
    };
    await expectLater(
      repository.createForumPost(
        channelId: 'channel-1',
        title: 'Bad',
        body: 'Bad words',
      ),
      throwsA(isA<AutoModBlockedException>()),
    );
    expect(dataSource.calls.last.functionName, 'take_automod_notice');
    expect(dataSource.calls.last.params, {
      'target_conversation_id': 'conv-forum',
    });

    dataSource.rpcValue = 'tag-new';
    await repository.setForumPostTags(threadId: 'thread-3', tagIds: const []);
    await repository.pinForumPost(threadId: 'thread-3', pinned: true);
    expect(
      await repository.createForumTag(
        channelId: 'channel-1',
        name: ' Bug ',
        emoji: ' ',
      ),
      'tag-new',
    );
    await repository.updateForumTag(tagId: 'tag-1', name: 'Bugs', emoji: '🐞');
    await repository.deleteForumTag('tag-1');
    await repository.reorderForumTags(
      channelId: 'channel-1',
      tagIds: const ['tag-2', 'tag-1'],
    );
    await repository.createChannel(
      circleId: 'circle-1',
      name: 'qa',
      kind: CircleChannelKind.forum,
    );
    final calls = dataSource.calls.skip(dataSource.calls.length - 7).toList();
    expect(
      [for (final call in calls) call.functionName],
      [
        'set_forum_post_tags',
        'pin_forum_post',
        'create_forum_tag',
        'update_forum_tag',
        'delete_forum_tag',
        'reorder_forum_tags',
        'create_circle_channel',
      ],
    );
    expect(calls[0].params, {'target_thread_id': 'thread-3', 'tag_ids': []});
    expect(calls[1].params, {'target_thread_id': 'thread-3', 'pinned': true});
    expect(calls[2].params, {
      'target_channel_id': 'channel-1',
      'tag_name': 'Bug',
      'tag_emoji': null,
    });
    expect(calls[3].params, {
      'target_tag_id': 'tag-1',
      'tag_name': 'Bugs',
      'tag_emoji': '🐞',
    });
    expect(calls[4].params, {'target_tag_id': 'tag-1'});
    expect(calls[5].params, {
      'target_channel_id': 'channel-1',
      'tag_ids': ['tag-2', 'tag-1'],
    });
    expect(calls[6].params, {
      'target_circle_id': 'circle-1',
      'channel_name': 'qa',
      'target_kind': 'forum',
    });
  });

  test('forum channels carry their tags in order', () {
    final channel = CircleChannel.fromJson({
      'id': 'channel-1',
      'circle_id': 'circle-1',
      'conversation_id': 'conversation-1',
      'name': 'help',
      'kind': 'forum',
      'tags': [
        {'id': 'b', 'channel_id': 'channel-1', 'name': 'Second', 'position': 1},
        {
          'id': 'a',
          'channel_id': 'channel-1',
          'name': 'First',
          'emoji': ' ',
          'position': 0,
        },
      ],
    });
    expect(channel.isForum, isTrue);
    expect(channel.tags.map((tag) => tag.id), ['a', 'b']);
    expect(channel.tags.first.emoji, isNull);
    expect(channel.tags.first.label, 'First');
  });

  test('channels are renamed and deleted through RPCs', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository(dataSource);

    await repository.updateChannel(
      channelId: 'channel-1',
      name: ' lobby ',
      topic: '  Say hi  ',
    );
    await repository.updateChannel(
      channelId: 'channel-1',
      name: 'lobby',
      topic: '   ',
    );
    await repository.deleteChannel('channel-1');

    expect(dataSource.calls.map((call) => call.functionName), [
      'update_circle_channel',
      'update_circle_channel',
      'delete_circle_channel',
    ]);
    expect(dataSource.calls[0].params, {
      'target_channel_id': 'channel-1',
      'channel_name': 'lobby',
      'channel_topic': 'Say hi',
    });
    expect(dataSource.calls[1].params['channel_topic'], isNull);
    expect(dataSource.calls[2].params, {'target_channel_id': 'channel-1'});
  });

  test('deleting a channel removes the files of its messages', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['delete_circle_channel'] = [
        {'bucket_id': 'chat-images', 'object_path': 'c1/a.png'},
        {'bucket_id': 'chat-files', 'object_path': 't1/doc.pdf'},
        {'bucket_id': 'chat-images', 'object_path': 'c1/b.png'},
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.deleteChannel('channel-1');

    expect(dataSource.calls.single.functionName, 'delete_circle_channel');
    expect(
      [
        for (final removed in dataSource.removedObjects)
          '${removed.bucket}: ${removed.paths.join(', ')}',
      ],
      ['chat-images: c1/a.png, c1/b.png', 'chat-files: t1/doc.pdf'],
    );
  });

  test('CircleDetail uses channel permissions after overwrites', () {
    final detail = CircleDetail.fromJson({
      'circle': {
        'id': 'circle-1',
        'name': 'Circle',
        'current_user_role': 'member',
        'current_user_permissions': 1 | 2 | 64 | 8192,
      },
      'roles': const [],
      'members': const [],
      'channels': [
        {
          'id': 'channel-1',
          'circle_id': 'circle-1',
          'conversation_id': 'conversation-1',
          'name': 'announcements',
          'position': 0,
          'current_user_permissions': 1,
          'is_private': false,
          'is_read_only': true,
          'slowmode_seconds': 300,
          'topic': 'News only',
          'kind': 'text',
        },
        {
          'id': 'channel-2',
          'circle_id': 'circle-1',
          'conversation_id': 'conversation-2',
          'name': 'legacy',
          'position': 1,
        },
      ],
      'posts': const [],
    });
    final [readOnly, legacy] = detail.channels;

    expect(readOnly.isReadOnly, isTrue);
    expect(readOnly.isPrivate, isFalse);
    expect(readOnly.currentUserPermissions, 1);
    expect(readOnly.slowmodeSeconds, 300);
    expect(detail.slowmodeFor(readOnly), 300);
    expect(legacy.slowmodeSeconds, 0);
    expect(readOnly.topic, 'News only');
    expect(readOnly.kind, CircleChannelKind.text);
    expect(legacy.topic, isNull);
    expect(legacy.kind, CircleChannelKind.text);
    expect(CircleChannelKind.fromJson('forum'), CircleChannelKind.forum);
    expect(CircleChannelKind.fromJson('stage'), CircleChannelKind.stage);
    expect(CircleChannelKind.fromJson('later'), CircleChannelKind.text);
    expect(detail.canInChannel(readOnly, CirclePermission.viewChannel), isTrue);
    expect(
      detail.canInChannel(readOnly, CirclePermission.sendMessages),
      isFalse,
    );
    // Payloads without channel permissions fall back to the circle's.
    expect(detail.canInChannel(legacy, CirclePermission.sendMessages), isTrue);
    expect(CirclePermission.channelPermissionMask, 1 | 2 | 4 | 64 | 256 | 8192);
  });

  test('getCircleDetail maps roles and permissions', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle': {
          'id': 'circle-1',
          'name': 'Circle',
          'current_user_role': 'member',
          'current_user_permissions': 1 | 2 | 16,
        },
        'roles': [
          {
            'id': 'everyone',
            'name': '@everyone',
            'color': null,
            'position': 0,
            'permissions': 3,
            'hoist': false,
            'is_default': true,
            'member_count': 2,
          },
          {
            'id': 'mods',
            'name': 'Mods',
            'color': 3447003,
            'position': 1,
            'permissions': 16,
            'hoist': true,
            'is_default': false,
            'member_count': 1,
          },
        ],
        'members': [
          {
            'role': 'admin',
            'is_current_user': true,
            'role_ids': ['mods'],
            'profile': _profileRow(id: 'u1', name: 'One'),
          },
        ],
        'channels': const [],
        'posts': const [],
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final detail = await repository.getCircleDetail('circle-1');

    expect(detail.circle.currentUserPermissions, 19);
    expect([for (final role in detail.roles) role.name], ['Mods', '@everyone']);
    expect(detail.roles.first.color, 3447003);
    expect(detail.roles.first.hoist, isTrue);
    expect(detail.roles.last.isDefault, isTrue);
    expect(detail.roles.last.memberCount, 2);
    expect(detail.members.single.roleIds, ['mods']);
    expect(detail.canManageRoles, isTrue);
    expect(detail.currentUserRank, 1);
    expect(detail.assignableRoles, isEmpty);
  });

  test('getNotificationSettings maps the settings payload', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle_id': 'circle-1',
        'level': 'mentions',
        'muted_until': '2026-10-13T10:00:00+00:00',
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final settings = await repository.getNotificationSettings('circle-1');

    expect(
      dataSource.calls.single.functionName,
      'get_circle_notification_settings',
    );
    expect(dataSource.calls.single.params, {'target_circle_id': 'circle-1'});
    expect(settings.circleId, 'circle-1');
    expect(settings.level, CircleNotificationLevel.mentions);
    expect(settings.mutedUntil, DateTime.utc(2026, 10, 13, 10));
    expect(settings.isMutedAt(DateTime.utc(2026, 10, 13, 9)), isTrue);
    expect(settings.isMutedAt(DateTime.utc(2026, 10, 13, 11)), isFalse);
  });

  test('getNotificationSettings defaults unknown levels to all', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle_id': 'circle-1',
        'level': null,
        'muted_until': null,
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final settings = await repository.getNotificationSettings('circle-1');

    expect(settings.level, CircleNotificationLevel.all);
    expect(settings.mutedUntil, isNull);
    expect(settings.isMutedAt(DateTime.utc(2026)), isFalse);
  });

  test('setNotificationSettings sends level and UTC mute end', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle_id': 'circle-1',
        'level': 'none',
        'muted_until': null,
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.setNotificationSettings(
      circleId: 'circle-1',
      level: CircleNotificationLevel.none,
      mutedUntil: DateTime.utc(2026, 10, 13, 10, 15),
    );
    final cleared = await repository.setNotificationSettings(
      circleId: 'circle-1',
      level: CircleNotificationLevel.none,
    );

    expect(
      dataSource.calls.first.functionName,
      'set_circle_notification_settings',
    );
    expect(dataSource.calls.first.params, {
      'target_circle_id': 'circle-1',
      'level': 'none',
      'muted_until': '2026-10-13T10:15:00.000Z',
    });
    expect(dataSource.calls.last.params['muted_until'], isNull);
    expect(cleared.level, CircleNotificationLevel.none);
  });

  test('indefinite circle mutes are recognised', () {
    final now = DateTime.utc(2026, 10, 13);
    final forever = CircleNotificationSettings(
      circleId: 'circle-1',
      mutedUntil: now.add(circleMuteIndefinitely),
    );
    final oneDay = CircleNotificationSettings(
      circleId: 'circle-1',
      mutedUntil: now.add(const Duration(hours: 24)),
    );

    expect(forever.isMutedIndefinitelyAt(now), isTrue);
    expect(oneDay.isMutedIndefinitelyAt(now), isFalse);
    expect(oneDay.isMutedAt(now), isTrue);
  });

  test('CircleDetail limits who may change nicknames', () {
    CircleMember member(String id, String role, {bool self = false}) {
      return CircleMember(
        profile: Profile.fromJson(_profileRow(id: id, name: id)),
        role: role,
        isCurrentUser: self,
      );
    }

    CircleDetail detail(String role) {
      return CircleDetail(
        circle: CircleSummary(
          id: 'circle-1',
          name: 'Circle',
          memberCount: 3,
          channelCount: 0,
          currentUserRole: role,
        ),
        members: const [],
        channels: const [],
        posts: const [],
      );
    }

    final owner = member('owner', 'owner');
    final admin = member('admin', 'admin');
    final other = member('other', 'member');
    final me = member('me', 'member', self: true);

    // Payloads without roles fall back to the legacy owner / admin ranks.
    expect(detail('member').canChangeNickname(me), isTrue);
    expect(detail('member').canChangeNickname(other), isFalse);
    expect(detail('admin').canChangeNickname(other), isTrue);
    expect(detail('admin').canChangeNickname(admin), isFalse);
    expect(detail('admin').canChangeNickname(owner), isFalse);
    expect(
      detail('owner').canChangeNickname(member('owner', 'owner', self: true)),
      isTrue,
    );
    expect(detail('owner').canChangeNickname(admin), isTrue);
  });

  test('CircleDetail applies role permissions and hierarchy', () {
    const everyone = CircleRole(
      id: 'everyone',
      name: '@everyone',
      position: 0,
      permissions: 1 | 2 | 64 | 8192,
      isDefault: true,
    );
    const mod = CircleRole(
      id: 'mod',
      name: 'Mod',
      position: 2,
      color: 0x3498DB,
      hoist: true,
      permissions: 16 | 128,
    );
    const helper = CircleRole(
      id: 'helper',
      name: 'Helper',
      position: 1,
      color: 0x2ECC71,
      permissions: 2,
    );
    CircleMember member(String id, List<String> roleIds, {bool self = false}) {
      return CircleMember(
        profile: Profile.fromJson(_profileRow(id: id, name: id)),
        role: id == 'owner' ? 'owner' : 'member',
        roleIds: roleIds,
        isCurrentUser: self,
      );
    }

    final me = member('me', ['mod'], self: true);
    final peer = member('peer', ['mod']);
    final helped = member('helped', ['helper']);
    final owner = member('owner', const []);
    final detail = CircleDetail.fromJson({
      'circle': {
        'id': 'circle-1',
        'name': 'Circle',
        'current_user_role': 'member',
        'current_user_permissions': 1 | 2 | 64 | 8192 | 16 | 128,
      },
      'roles': [
        for (final role in [everyone, helper, mod])
          {
            'id': role.id,
            'name': role.name,
            'color': role.color,
            'position': role.position,
            'permissions': role.permissions,
            'hoist': role.hoist,
            'is_default': role.isDefault,
          },
      ],
      'members': const [],
      'channels': const [],
      'posts': const [],
    });
    final withMembers = CircleDetail(
      circle: detail.circle,
      roles: detail.roles,
      members: [me, peer, helped, owner],
      channels: const [],
      posts: const [],
    );

    expect(
      [for (final role in detail.roles) role.id],
      ['mod', 'helper', 'everyone'],
    );
    expect(withMembers.canManageRoles, isTrue);
    expect(withMembers.canManageChannels, isFalse);
    expect(withMembers.canCreateInvites, isTrue);
    expect(withMembers.currentUserRank, 2);
    expect(withMembers.rankOf(owner), circleOwnerRank);
    expect(
      [for (final role in withMembers.assignableRoles) role.id],
      ['helper'],
    );
    expect(withMembers.canManageRolesOf(helped), isTrue);
    expect(withMembers.canManageRolesOf(owner), isFalse);
    expect(withMembers.canChangeNickname(helped), isTrue);
    expect(withMembers.canChangeNickname(peer), isFalse);
    expect(withMembers.canChangeNickname(owner), isFalse);
    // Mod has no kick_members.
    expect(withMembers.canKick(helped), isFalse);
    expect(withMembers.roleColorOf(helped), 0x2ECC71);
    expect(withMembers.hoistedRoleOf(peer)?.id, 'mod');
    expect(withMembers.hoistedRoleOf(helped), isNull);
    expect(CirclePermission.kickMembers.isGrantedBy(16384), isTrue);
  });

  test('createCircle trims name and calls create_circle rpc', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'circle-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final id = await repository.createCircle(
      name: ' Close Friends ',
      memberIds: ['u2'],
    );

    expect(id, 'circle-1');
    expect(dataSource.calls.single.functionName, 'create_circle');
    expect(dataSource.calls.single.params, {
      'circle_name': 'Close Friends',
      'member_ids': ['u2'],
    });
  });

  test(
    'createChannel trims name and calls create_circle_channel rpc',
    () async {
      final dataSource = FakeCirclesDataSource()..rpcValue = 'channel-1';
      final repository = SupabaseCirclesRepository.withDataSource(dataSource);

      final id = await repository.createChannel(
        circleId: 'circle-1',
        name: ' General ',
      );

      expect(id, 'channel-1');
      expect(dataSource.calls.single.functionName, 'create_circle_channel');
      expect(dataSource.calls.single.params, {
        'target_circle_id': 'circle-1',
        'channel_name': 'General',
      });
    },
  );

  test('createChannel sends the category when given', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'channel-2';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.createChannel(
      circleId: 'circle-1',
      name: 'clips',
      categoryId: 'category-1',
    );

    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'channel_name': 'clips',
      'target_category_id': 'category-1',
    });
  });

  test('category RPCs trim names and pass ids', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'category-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final id = await repository.createChannelCategory(
      circleId: 'circle-1',
      name: ' Media ',
    );
    await repository.renameChannelCategory(
      categoryId: 'category-1',
      name: ' Clips ',
    );
    await repository.deleteChannelCategory('category-1');

    expect(id, 'category-1');
    expect(dataSource.calls.map((call) => call.functionName), [
      'create_channel_category',
      'rename_channel_category',
      'delete_channel_category',
    ]);
    expect(dataSource.calls[0].params, {
      'target_circle_id': 'circle-1',
      'category_name': 'Media',
    });
    expect(dataSource.calls[1].params, {
      'target_category_id': 'category-1',
      'category_name': 'Clips',
    });
    expect(dataSource.calls[2].params, {'target_category_id': 'category-1'});
  });

  test('reorderChannels sends the full layout', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);
    CircleChannel channel(String id, int position, [String? categoryId]) {
      return CircleChannel(
        id: id,
        circleId: 'circle-1',
        conversationId: 'conversation-$id',
        name: id,
        position: position,
        categoryId: categoryId,
      );
    }

    final layout = CircleChannelLayout.fromChannels(
      categories: const [
        CircleChannelCategory(
          id: 'a',
          circleId: 'circle-1',
          name: 'A',
          position: 0,
        ),
        CircleChannelCategory(
          id: 'b',
          circleId: 'circle-1',
          name: 'B',
          position: 1,
        ),
      ],
      channels: [
        channel('general', 0),
        channel('a1', 1, 'a'),
        channel('b1', 2, 'b'),
        channel('lost', 3, 'deleted-category'),
      ],
    ).moveCategory('b', 0).moveChannel('general', categoryId: 'a', index: 1);

    await repository.reorderChannels(circleId: 'circle-1', layout: layout);

    expect(dataSource.calls.single.functionName, 'reorder_circle_channels');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'layout': {
        'categories': ['b', 'a'],
        'channels': [
          {'id': 'lost', 'category_id': null},
          {'id': 'b1', 'category_id': 'b'},
          {'id': 'a1', 'category_id': 'a'},
          {'id': 'general', 'category_id': 'a'},
        ],
      },
    });
    expect(layout.orderedChannels.map((channel) => channel.position), [
      0,
      1,
      2,
      3,
    ]);
    expect(layout.orderedCategories.map((category) => category.position), [
      0,
      1,
    ]);
  });

  test('inviteMembers calls invite_circle_members rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.inviteMembers(circleId: 'circle-1', memberIds: ['u2']);

    expect(dataSource.calls.single.functionName, 'invite_circle_members');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'member_ids': ['u2'],
    });
  });

  test('createPost trims body and sends image attachment map', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'post-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);
    const image = ImageAttachment(
      bucket: 'chat-media',
      path: 'circle-1/image.jpg',
      mimeType: 'image/jpeg',
      size: 3,
      width: 10,
      height: 20,
    );

    final id = await repository.createPost(
      circleId: 'circle-1',
      body: ' Hello ',
      image: image,
    );

    expect(id, 'post-1');
    expect(dataSource.calls.single.functionName, 'create_circle_post');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'body': 'Hello',
      'attachment': image.toJson(),
    });
  });

  test('createPost sends null attachment without image', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'post-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.createPost(circleId: 'circle-1', body: ' Hello ');

    expect(dataSource.calls.single.params['attachment'], isNull);
  });

  test('togglePostLike calls toggle_circle_post_like rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.togglePostLike(postId: 'post-1', liked: true);

    expect(dataSource.calls.single.functionName, 'toggle_circle_post_like');
    expect(dataSource.calls.single.params, {
      'target_post_id': 'post-1',
      'liked': true,
    });
  });

  test(
    'createComment trims body and calls create_circle_post_comment rpc',
    () async {
      final dataSource = FakeCirclesDataSource()..rpcValue = 'comment-1';
      final repository = SupabaseCirclesRepository.withDataSource(dataSource);

      final id = await repository.createComment(postId: 'post-1', body: ' Hi ');

      expect(id, 'comment-1');
      expect(
        dataSource.calls.single.functionName,
        'create_circle_post_comment',
      );
      expect(dataSource.calls.single.params, {
        'target_post_id': 'post-1',
        'body': 'Hi',
      });
    },
  );

  test('deletePost calls delete_circle_post rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.deletePost('post-1');

    expect(dataSource.calls.single.functionName, 'delete_circle_post');
    expect(dataSource.calls.single.params, {'target_post_id': 'post-1'});
  });

  test('reportPost serializes reason and details', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.reportPost(
      postId: 'post-1',
      reason: ReportReason.spam,
      details: 'Looks automated',
    );

    expect(dataSource.calls.single.functionName, 'report_circle_post');
    expect(dataSource.calls.single.params, {
      'target_post_id': 'post-1',
      'report_reason': ReportReason.spam.toJson(),
      'report_details': 'Looks automated',
    });
  });

  test(
    'uploadPostImage uploads to chat-media and returns ImageAttachment',
    () async {
      final dataSource = FakeCirclesDataSource();
      final repository = SupabaseCirclesRepository.withDataSource(
        dataSource,
        storagePathSeed: () => 'seed',
      );
      final image = ChatImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: ' My Photo.JPG ',
        mimeType: 'image/jpeg',
        width: 100,
        height: 200,
      );

      final attachment = await repository.uploadPostImage(
        circleId: 'circle-1',
        image: image,
      );

      expect(dataSource.uploads.single.bucket, 'chat-media');
      expect(dataSource.uploads.single.path, 'circle-1/seed-my-photo.jpg');
      expect(dataSource.uploads.single.mimeType, 'image/jpeg');
      expect(attachment.toJson(), {
        'kind': 'image',
        'bucket': 'chat-media',
        'path': 'circle-1/seed-my-photo.jpg',
        'mime_type': 'image/jpeg',
        'size': 3,
        'width': 100,
        'height': 200,
      });
    },
  );

  test('createImageUrl signs image attachment URLs', () async {
    final dataSource = FakeCirclesDataSource()..signedUrl = 'signed-url';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final url = await repository.createImageUrl(
      const ImageAttachment(
        bucket: 'chat-media',
        path: 'circle-1/image.jpg',
        mimeType: 'image/jpeg',
        size: 3,
      ),
    );

    expect(url, 'signed-url');
    expect(dataSource.signedUrlCalls.single, {
      'bucket': 'chat-media',
      'path': 'circle-1/image.jpg',
      'expiresIn': const Duration(hours: 1),
    });
  });

  test('createInvite sends expiry hours and max uses', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'abcdefgh23';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final code = await repository.createInvite(
      circleId: 'circle-1',
      expiresIn: const Duration(days: 7),
      maxUses: 10,
    );
    await repository.createInvite(circleId: 'circle-1');

    expect(code, 'abcdefgh23');
    expect(dataSource.calls.first.functionName, 'create_circle_invite');
    expect(dataSource.calls.first.params, {
      'target_circle_id': 'circle-1',
      'expires_in_hours': 168,
      'max_uses': 10,
    });
    expect(dataSource.calls.last.params, {
      'target_circle_id': 'circle-1',
      'expires_in_hours': null,
      'max_uses': null,
    });
  });

  test('listInvites maps list_circle_invites rows', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_circle_invites'] = [
        {
          'code': 'abcdefgh23',
          'circle_id': 'circle-1',
          'created_by': 'u1',
          'created_by_name': 'Ada',
          'created_at': '2026-10-13T00:00:00Z',
          'expires_at': '2026-10-20T00:00:00Z',
          'max_uses': 10,
          'use_count': 3,
        },
        {
          'code': 'zyxwvuts98',
          'circle_id': 'circle-1',
          'created_by': null,
          'created_by_name': null,
          'created_at': '2026-10-12T00:00:00Z',
          'expires_at': null,
          'max_uses': null,
          'use_count': 0,
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final invites = await repository.listInvites('circle-1');

    expect(dataSource.calls.single.functionName, 'list_circle_invites');
    expect(dataSource.calls.single.params, {'target_circle_id': 'circle-1'});
    expect(invites.first.code, 'abcdefgh23');
    expect(invites.first.createdByName, 'Ada');
    expect(invites.first.expiresAt, DateTime.utc(2026, 10, 20));
    expect(invites.first.maxUses, 10);
    expect(invites.first.useCount, 3);
    expect(invites.last.expiresAt, isNull);
    expect(invites.last.maxUses, isNull);
  });

  test('revokeInvite calls revoke_circle_invite rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.revokeInvite('abcdefgh23');

    expect(dataSource.calls.single.functionName, 'revoke_circle_invite');
    expect(dataSource.calls.single.params, {'invite_code': 'abcdefgh23'});
  });

  test('getInvitePreview maps valid and invalid previews', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'code': 'abcdefgh23',
        'invalid_reason': null,
        'already_member': false,
        'expires_at': null,
        'circle': {
          'id': 'circle-1',
          'name': 'Book Club',
          'avatar_url': null,
          'member_count': 4,
        },
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final preview = await repository.getInvitePreview('abcdefgh23');

    expect(dataSource.calls.single.functionName, 'get_circle_invite_preview');
    expect(dataSource.calls.single.params, {'invite_code': 'abcdefgh23'});
    expect(preview.canJoin, isTrue);
    expect(preview.circle!.name, 'Book Club');
    expect(preview.circle!.memberCount, 4);

    dataSource.rpcValue = {
      'code': 'abcdefgh23',
      'invalid_reason': 'revoked',
      'already_member': false,
      'circle': null,
    };
    final invalid = await repository.getInvitePreview('abcdefgh23');

    expect(invalid.canJoin, isFalse);
    expect(invalid.invalidReason, CircleInviteInvalidReason.revoked);
    expect(invalid.circle, isNull);
  });

  test('acceptInvite returns the joined circle id', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'circle-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final circleId = await repository.acceptInvite('abcdefgh23');

    expect(circleId, 'circle-1');
    expect(dataSource.calls.single.functionName, 'accept_circle_invite');
    expect(dataSource.calls.single.params, {'invite_code': 'abcdefgh23'});
  });
  group('events', () {
    Map<String, dynamic> eventJson({String id = 'event-1'}) => {
      'id': id,
      'circle_id': 'circle-1',
      'title': 'Hike',
      'description': 'Bring water',
      'location_type': 'external',
      'location_text': 'Mission Peak',
      'starts_at': '2026-10-20T15:00:00+00:00',
      'ends_at': null,
      'created_by': 'user-2',
      'creator': {
        'id': 'user-2',
        'username': 'bart',
        'display_name': 'Bart',
        'bio': '',
        'created_at': '2026-01-01T00:00:00+00:00',
        'updated_at': '2026-01-01T00:00:00+00:00',
        'nickname': 'Bart the Bold',
      },
      'interested_count': 3,
      'interested_by_me': true,
      'can_manage': false,
    };

    test('listEvents maps list_circle_events rows', () async {
      final dataSource = FakeCirclesDataSource()
        ..rpcRows['list_circle_events'] = [eventJson()];
      final repository = SupabaseCirclesRepository(dataSource);

      final events = await repository.listEvents(
        circleId: 'circle-1',
        includePast: true,
      );

      expect(dataSource.calls.single.params, {
        'target_circle_id': 'circle-1',
        'include_past': true,
      });
      final event = events.single;
      expect(event.title, 'Hike');
      expect(event.locationType, CircleEventLocationType.external);
      expect(event.locationLabel, 'Mission Peak');
      expect(event.creator!.name, 'Bart the Bold');
      expect(event.interestedCount, 3);
      expect(event.interestedByMe, isTrue);
      expect(
        event.effectiveEndsAt,
        DateTime.parse('2026-10-20T17:00:00+00:00'),
      );
    });

    test('create and update send trimmed fields in UTC', () async {
      final dataSource = FakeCirclesDataSource()..rpcValue = eventJson();
      final repository = SupabaseCirclesRepository(dataSource);
      final start = DateTime.utc(2026, 10, 20, 15);

      await repository.createEvent(
        circleId: 'circle-1',
        title: ' Hike ',
        description: '  ',
        locationType: CircleEventLocationType.external,
        channelId: 'ignored',
        locationText: ' Mission Peak ',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 2)),
      );
      expect(dataSource.calls.last.functionName, 'create_circle_event');
      expect(dataSource.calls.last.params, {
        'target_circle_id': 'circle-1',
        'event_title': 'Hike',
        'event_description': null,
        'event_location_type': 'external',
        'event_channel_id': null,
        'event_location_text': 'Mission Peak',
        'event_starts_at': '2026-10-20T15:00:00.000Z',
        'event_ends_at': '2026-10-20T17:00:00.000Z',
      });

      await repository.updateEvent(
        eventId: 'event-1',
        title: 'Call',
        description: ' Agenda ',
        locationType: CircleEventLocationType.text,
        channelId: 'channel-1',
        locationText: 'ignored',
        startsAt: start,
      );
      expect(dataSource.calls.last.functionName, 'update_circle_event');
      expect(dataSource.calls.last.params, {
        'target_event_id': 'event-1',
        'event_title': 'Call',
        'event_description': 'Agenda',
        'event_location_type': 'text',
        'event_channel_id': 'channel-1',
        'event_location_text': null,
        'event_starts_at': '2026-10-20T15:00:00.000Z',
        'event_ends_at': null,
      });
    });

    test(
      'cancel, interest, interested and reminders call their RPCs',
      () async {
        final dataSource = FakeCirclesDataSource()
          ..rpcRows['cancel_circle_event'] = []
          ..rpcRows['list_event_interested'] = [
            {
              'id': 'user-3',
              'username': 'grace',
              'display_name': 'Grace',
              'bio': '',
              'created_at': '2026-01-01T00:00:00+00:00',
              'updated_at': '2026-01-01T00:00:00+00:00',
            },
          ]
          ..rpcRows['list_my_upcoming_event_reminders'] = [
            {
              'event_id': 'event-1',
              'circle_id': 'circle-1',
              'circle_name': 'Hikers',
              'title': 'Hike',
              'starts_at': '2026-10-20T15:00:00+00:00',
              'location': 'Mission Peak',
              'notification_level': 'none',
              'muted_until': null,
            },
          ];
        final repository = SupabaseCirclesRepository(dataSource);

        dataSource.rpcRows.remove('cancel_circle_event');
        dataSource.rpcValue = {
          ...eventJson(),
          'cancelled_at': '2026-10-14T12:00:00+00:00',
        };
        final cancelled = await repository.cancelEvent('event-1');
        expect(cancelled.isCancelled, isTrue);
        expect(dataSource.calls.last.params, {'target_event_id': 'event-1'});

        dataSource.rpcValue = true;
        expect(await repository.toggleEventInterest('event-1'), isTrue);
        expect(dataSource.calls.last.functionName, 'toggle_event_interest');

        final people = await repository.listEventInterested('event-1');
        expect(people.single.name, 'Grace');

        final reminders = await repository.listMyEventReminders();
        expect(
          dataSource.calls.last.functionName,
          'list_my_upcoming_event_reminders',
        );
        expect(reminders.single.circleName, 'Hikers');
        expect(
          reminders.single.notificationLevel,
          CircleNotificationLevel.none,
        );
      },
    );
  });

  test('event status, payloads and calendar files', () {
    final start = DateTime.utc(2026, 10, 20, 15);
    final event = CircleEvent(
      id: 'event-1',
      circleId: 'circle-1',
      title: 'Hike, then lunch',
      description: 'Bring **water**',
      locationType: CircleEventLocationType.text,
      channelName: 'general',
      startsAt: start,
    );
    expect(
      event.statusAt(start.subtract(const Duration(minutes: 1))),
      CircleEventStatus.scheduled,
    );
    expect(event.statusAt(start), CircleEventStatus.ongoing);
    expect(
      event.statusAt(start.add(const Duration(hours: 2))),
      CircleEventStatus.over,
    );
    expect(event.locationLabel, '#general');
    expect(
      parseCircleEventNotificationPayload(
        circleEventNotificationPayload('circle-1', 'event-1'),
      ),
      (circleId: 'circle-1', eventId: 'event-1'),
    );
    expect(parseCircleEventNotificationPayload('conversation-1'), isNull);
  });
}

class FakeCirclesDataSource implements CirclesDataSource {
  final rpcRows = <String, List<Map<String, dynamic>>>{};
  Object? rpcValue;
  String signedUrl = 'signed-url';
  final calls = <RpcCall>[];
  final uploads = <UploadCall>[];
  final signedUrlCalls = <Map<String, Object>>[];
  final changes = StreamController<void>.broadcast();

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add(RpcCall(functionName: functionName, params: params));
    return rpcRows[functionName] ?? rpcValue;
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add(
      UploadCall(bucket: bucket, path: path, bytes: bytes, mimeType: mimeType),
    );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async {
    signedUrlCalls.add({
      'bucket': bucket,
      'path': path,
      'expiresIn': expiresIn,
    });
    return signedUrl;
  }

  final removedObjects = <({String bucket, List<String> paths})>[];

  @override
  Future<void> removeObjects({
    required String bucket,
    required List<String> paths,
  }) async {
    removedObjects.add((bucket: bucket, paths: paths));
  }

  @override
  Stream<void> circleChanges(String circleId) => changes.stream;

  @override
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  }) => changes.stream;
}

class RpcCall {
  const RpcCall({required this.functionName, required this.params});

  final String functionName;
  final Map<String, dynamic> params;
}

class UploadCall {
  const UploadCall({
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.mimeType,
  });

  final String bucket;
  final String path;
  final Uint8List bytes;
  final String mimeType;
}

Map<String, dynamic> _profileRow({required String id, required String name}) {
  return {
    'id': id,
    'username': name.toLowerCase(),
    'display_name': name,
    'avatar_url': null,
    'bio': '',
    'created_at': '2026-05-19T00:00:00Z',
    'updated_at': '2026-05-19T00:00:00Z',
  };
}
