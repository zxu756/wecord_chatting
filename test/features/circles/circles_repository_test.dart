import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
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

  @override
  Stream<void> circleChanges(String circleId) => changes.stream;
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
