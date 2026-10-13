import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  testWidgets('narrow circle home opens channels full screen', (tester) async {
    final repository = FakeCirclesRepository()
      ..detail = _detail()
      ..circles = [_detail().circle];
    final router = _narrowRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    // Circle rail beside the channel list, no tabs.
    expect(find.byKey(const ValueKey('circle-rail-circle-1')), findsOneWidget);
    expect(find.byType(CircleChannelSidebar), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Close Friends'), findsWidgets);
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conversation-1'), findsOneWidget);
    expect(find.byType(CircleChannelSidebar), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Thread conversation-1'), findsNothing);
    expect(find.byType(CircleChannelSidebar), findsOneWidget);
    expect(find.text('general'), findsOneWidget);
  });

  group('threads', () {
    final now = DateTime.now().toUtc();
    ConversationSummary thread(
      String id,
      String title, {
      DateTime? lastActivityAt,
      DateTime? archivedAt,
      int unreadCount = 0,
      String parent = 'conversation-1',
    }) {
      return ConversationSummary(
        id: id,
        type: ConversationType.thread,
        unreadCount: unreadCount,
        title: title,
        parentConversationId: parent,
        parentTitle: 'general',
        circleId: 'circle-1',
        threadId: 'id-$id',
        threadArchivedAt: archivedAt,
        threadLastActivityAt: lastActivityAt ?? now,
      );
    }

    final conversations = [
      thread('thread-a', 'Weekend plans', unreadCount: 1),
      thread(
        'thread-b',
        'Older active',
        lastActivityAt: now.subtract(const Duration(days: 2)),
      ),
      thread(
        'thread-archived',
        'Archived talk',
        archivedAt: now.subtract(const Duration(hours: 1)),
      ),
      thread(
        'thread-stale',
        'Stale talk',
        lastActivityAt: now.subtract(const Duration(days: 8)),
      ),
    ];

    test('activeThreadsByParent keeps recent unarchived threads', () {
      final byParent = activeThreadsByParent(conversations, now: now);
      expect(byParent.keys, ['conversation-1']);
      expect(byParent['conversation-1']!.map((thread) => thread.id), [
        'thread-a',
        'thread-b',
      ]);
    });

    testWidgets('wide sidebar lists threads and opens them in a panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeCirclesRepository()
        ..detail = _detail()
        ..circles = [_detail().circle];
      final router = GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) => CircleDetailScreen(
              circleId: state.pathParameters['circleId']!,
              channelViewBuilder: (context, channel, actions) => Scaffold(
                appBar: AppBar(title: Text(channel.name), actions: actions),
              ),
              threadViewBuilder: (context, thread, actions) => Scaffold(
                appBar: AppBar(
                  title: Text('Panel ${thread.title}'),
                  actions: actions,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(
          repository,
          FakeContactsRepository(),
          router,
          conversations: conversations,
        ),
      );
      await tester.pumpAndSettle();

      final weekend = find.byKey(const ValueKey('circle-thread-thread-a'));
      expect(weekend, findsOneWidget);
      expect(find.text('Older active'), findsOneWidget);
      expect(find.text('Archived talk'), findsNothing);
      expect(find.text('Stale talk'), findsNothing);
      // Indented under their channel.
      expect(
        tester.getTopLeft(find.text('general').first).dy,
        lessThan(tester.getTopLeft(find.text('Weekend plans')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Weekend plans')).dx,
        greaterThan(tester.getTopLeft(find.text('general').first).dx),
      );
      expect(
        find.descendant(
          of: weekend,
          matching: find.byKey(const ValueKey('channel-unread-pill')),
        ),
        findsOneWidget,
      );
      expect(find.byType(CircleMemberList), findsOneWidget);

      await tester.tap(find.text('Weekend plans'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('circle-thread-panel')), findsOneWidget);
      expect(find.text('Panel Weekend plans'), findsOneWidget);
      // The panel replaces the member list.
      expect(find.byType(CircleMemberList), findsNothing);

      await tester.tap(find.byTooltip('Close thread'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('circle-thread-panel')), findsNothing);
      expect(find.byType(CircleMemberList), findsOneWidget);
    });

    testWidgets('narrow sidebar pushes threads full screen', (tester) async {
      final repository = FakeCirclesRepository()
        ..detail = _detail()
        ..circles = [_detail().circle];
      final router = _narrowRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(
          repository,
          FakeContactsRepository(),
          router,
          conversations: conversations,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weekend plans'));
      await tester.pumpAndSettle();

      // Pushed on the nested circle route, as a thread.
      expect(find.text('Thread thread-a'), findsOneWidget);
      expect(
        tester
            .widget<CircleChannelThreadScreen>(
              find.byType(CircleChannelThreadScreen),
            )
            .conversationId,
        'thread-a',
      );
    });
  });

  testWidgets('narrow channel threads open the member list as a drawer', (
    tester,
  ) async {
    final base = _detail();
    final repository = FakeCirclesRepository()
      ..onlineUserIds = {'user-1'}
      ..detail = CircleDetail(
        circle: base.circle,
        members: [
          CircleMember(
            profile: _profile(id: 'user-1', username: 'xu', name: 'Xu'),
            role: 'owner',
            isCurrentUser: true,
          ),
          CircleMember(
            profile: _profile(id: 'user-3', username: 'amy', name: 'Amy'),
            role: 'member',
            nickname: 'Ames',
          ),
        ],
        channels: base.channels,
        posts: const [],
      );
    repository.circles = [repository.detail.circle];
    final router = _narrowRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();

    expect(find.text('ONLINE — 1'), findsNothing);
    await tester.tap(find.byTooltip('Show member list'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('ONLINE — 1'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-online-user-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('member-offline-user-3')), findsOneWidget);

    await tester.longPress(find.text('Ames'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Amelia');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.nicknameUpdates, [
      (userId: 'user-3', nickname: 'Amelia'),
    ]);
  });

  testWidgets('narrow feed opens as a page and back returns home', (
    tester,
  ) async {
    final repository = FakeCirclesRepository()
      ..detail = _detail()
      ..circles = [_detail().circle];
    final router = _narrowRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.byType(CircleChannelSidebar), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsNothing);
    expect(find.byType(CircleChannelSidebar), findsOneWidget);
  });

  testWidgets('narrow circle home shows categories with saved collapse', (
    tester,
  ) async {
    final base = _detail();
    final repository = FakeCirclesRepository()
      ..detail = CircleDetail(
        circle: base.circle,
        members: base.members,
        channels: [
          ...base.channels,
          const CircleChannel(
            id: 'channel-2',
            circleId: 'circle-1',
            conversationId: 'conversation-2',
            name: 'clips',
            position: 1,
            categoryId: 'category-1',
          ),
          const CircleChannel(
            id: 'channel-3',
            circleId: 'circle-1',
            conversationId: 'conversation-3',
            name: 'reels',
            position: 2,
            categoryId: 'category-1',
          ),
        ],
        categories: const [
          CircleChannelCategory(
            id: 'category-1',
            circleId: 'circle-1',
            name: 'Media',
            position: 0,
          ),
        ],
        posts: const [],
      );
    final store = InMemoryCircleCategoryCollapseStore({
      'circle-1': {'category-1'},
    });
    final router = _narrowRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        repository,
        FakeContactsRepository(),
        router,
        collapseStore: store,
        conversations: const [
          ConversationSummary(
            id: 'conversation-3',
            type: ConversationType.channel,
            unreadCount: 4,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MEDIA'), findsOneWidget);
    expect(find.text('clips'), findsNothing);
    // Unread channels stay visible in a collapsed category.
    expect(find.text('reels'), findsOneWidget);

    await tester.tap(find.text('MEDIA'));
    await tester.pumpAndSettle();
    expect(find.text('clips'), findsOneWidget);
    expect(store.collapsed['circle-1'], isEmpty);
  });

  testWidgets('circle detail creates channels and invites friends', (
    tester,
  ) async {
    final repository = FakeCirclesRepository()..detail = _detail();
    final contacts = FakeContactsRepository()
      ..friends = [_profile(id: 'friend-2', username: 'grace', name: 'Grace')];
    final router = GoRouter(
      initialLocation: '/circles/circle-1',
      routes: [
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) =>
              CircleDetailScreen(circleId: state.pathParameters['circleId']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, contacts, router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Circle menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Channel name'), 'photos');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(repository.createdChannelName, 'photos');

    await tester.tap(find.byTooltip('Circle menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Grace'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
    await tester.pumpAndSettle();
    expect(repository.invitedMemberIds, ['friend-2']);
  });

  testWidgets('wide circle detail opens a channel workspace', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final detail = _detail();
    final repository = FakeCirclesRepository()
      ..circles = [detail.circle]
      ..detail = CircleDetail(
        circle: detail.circle,
        members: detail.members,
        channels: [
          ...detail.channels,
          const CircleChannel(
            id: 'channel-2',
            circleId: 'circle-1',
            conversationId: 'conversation-2',
            name: 'photos',
            position: 1,
            categoryId: 'category-1',
          ),
          const CircleChannel(
            id: 'channel-3',
            circleId: 'circle-1',
            conversationId: 'conversation-3',
            name: 'videos',
            position: 2,
            categoryId: 'category-1',
          ),
        ],
        categories: const [
          CircleChannelCategory(
            id: 'category-1',
            circleId: 'circle-1',
            name: 'Media',
            position: 0,
          ),
        ],
        posts: const [],
      );
    final router = GoRouter(
      initialLocation: '/circles/circle-1',
      routes: [
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) => CircleDetailScreen(
            circleId: state.pathParameters['circleId']!,
            channelViewBuilder: (context, channel, actions) => Scaffold(
              appBar: AppBar(
                title: Text('Channel ${channel.name}'),
                actions: actions,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('circle-rail-circle-1')), findsOneWidget);
    expect(find.text('Channel general'), findsOneWidget);
    expect(find.text('ONLINE — 1'), findsOneWidget);

    await tester.tap(find.text('photos'));
    await tester.pumpAndSettle();
    expect(find.text('Channel photos'), findsOneWidget);

    await tester.tap(find.text('MEDIA'));
    await tester.pumpAndSettle();
    // Uncategorized channels never collapse; the open channel stays listed.
    expect(find.text('general'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.text('videos'), findsNothing);

    await tester.tap(find.byTooltip('Hide member list'));
    await tester.pumpAndSettle();
    expect(find.text('ONLINE — 1'), findsNothing);

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
  });
  testWidgets('wide member list groups members by presence', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final detail = _detail();
    final repository = FakeCirclesRepository()
      ..circles = [detail.circle]
      ..onlineUserIds = {'user-1', 'user-2', 'user-3', 'user-4'}
      ..detail = CircleDetail(
        circle: detail.circle,
        members: [
          CircleMember(
            profile: _profile(id: 'user-4', username: 'zed', name: 'Zed'),
            role: 'member',
          ),
          CircleMember(
            profile: _profile(id: 'user-5', username: 'bea', name: 'Bea'),
            role: 'admin',
          ),
          CircleMember(
            profile: _profile(id: 'user-3', username: 'amy', name: 'Amy')
                .copyWith(
                  customStatus: const CustomStatus(
                    emoji: '🎯',
                    text: 'Focusing',
                  ),
                ),
            role: 'member',
          ),
          CircleMember(
            profile: _profile(id: 'user-2', username: 'yan', name: 'Yan')
                .copyWith(
                  customStatus: CustomStatus(
                    text: 'Gone',
                    expiresAt: DateTime.now().toUtc().subtract(
                      const Duration(minutes: 1),
                    ),
                  ),
                ),
            role: 'admin',
          ),
          ...detail.members,
          CircleMember(
            profile: _profile(id: 'user-6', username: 'abe', name: 'Abe'),
            role: 'member',
          ),
        ],
        channels: detail.channels,
        posts: const [],
      );
    final router = GoRouter(
      initialLocation: '/circles/circle-1',
      routes: [
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) => CircleDetailScreen(
            circleId: state.pathParameters['circleId']!,
            channelViewBuilder: (context, channel, actions) => Scaffold(
              appBar: AppBar(title: Text(channel.name), actions: actions),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    expect(find.text('ONLINE — 4'), findsOneWidget);
    expect(find.text('OFFLINE — 2'), findsOneWidget);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    // Online: owner, then admins, then members, each by name.
    expect(top('ONLINE — 4'), lessThan(top('Xu')));
    expect(top('Xu'), lessThan(top('Yan')));
    expect(top('Yan'), lessThan(top('Amy')));
    expect(top('Amy'), lessThan(top('Zed')));
    // Offline: by name, after every online member.
    expect(top('Zed'), lessThan(top('OFFLINE — 2')));
    expect(top('OFFLINE — 2'), lessThan(top('Abe')));
    expect(top('Abe'), lessThan(top('Bea')));

    expect(find.byKey(const ValueKey('member-online-user-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('member-offline-user-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('member-online-user-5')), findsNothing);

    // Custom statuses show under names; expired ones do not.
    expect(find.text('🎯 Focusing'), findsOneWidget);
    expect(top('Amy'), lessThan(top('🎯 Focusing')));
    expect(find.text('Gone'), findsNothing);
  });
  group('circle roles', () {
    const everyone = CircleRole(
      id: 'role-everyone',
      name: '@everyone',
      position: 0,
      permissions: 1 | 2 | 64 | 8192,
      isDefault: true,
      memberCount: 5,
    );
    const mods = CircleRole(
      id: 'role-mods',
      name: 'Mods',
      position: 3,
      color: 0x3498DB,
      hoist: true,
      permissions: 4 | 16 | 32 | 128,
      memberCount: 1,
    );
    const crew = CircleRole(
      id: 'role-crew',
      name: 'Crew',
      position: 2,
      color: 0xE91E63,
      hoist: true,
      permissions: 16,
      memberCount: 1,
    );
    const helpers = CircleRole(
      id: 'role-helpers',
      name: 'Helpers',
      position: 1,
      color: 0x2ECC71,
      permissions: 0,
      memberCount: 2,
    );

    Future<FakeCirclesRepository> pumpRoles(
      WidgetTester tester, {
      required String currentUserId,
      required int permissions,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final base = _detail();
      CircleMember member(
        String id,
        String name,
        String role, [
        List<String> roleIds = const [],
      ]) {
        return CircleMember(
          profile: _profile(id: id, username: name.toLowerCase(), name: name),
          role: role,
          roleIds: roleIds,
          isCurrentUser: id == currentUserId,
        );
      }

      final repository = FakeCirclesRepository()
        ..onlineUserIds = {'user-1', 'user-2', 'user-3', 'user-4'}
        ..detail = CircleDetail(
          circle: CircleSummary(
            id: 'circle-1',
            name: 'Close Friends',
            memberCount: 5,
            channelCount: 1,
            currentUserRole: currentUserId == 'user-1' ? 'owner' : 'member',
            currentUserPermissions: permissions,
          ),
          roles: const [mods, crew, helpers, everyone],
          members: [
            member('user-1', 'Xu', 'owner'),
            member('user-2', 'Yan', 'admin', ['role-mods']),
            member('user-3', 'Amy', 'member', ['role-crew', 'role-helpers']),
            member('user-4', 'Bo', 'member', ['role-helpers']),
            member('user-5', 'Cy', 'member'),
          ],
          channels: base.channels,
          posts: const [],
        );
      repository.circles = [repository.detail.circle];
      final router = GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) => CircleDetailScreen(
              circleId: state.pathParameters['circleId']!,
              channelViewBuilder: (context, channel, actions) => Scaffold(
                appBar: AppBar(title: Text(channel.name), actions: actions),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> openRolesPage(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();
    }

    testWidgets('member list groups online members by hoisted role', (
      tester,
    ) async {
      await pumpRoles(tester, currentUserId: 'user-1', permissions: 32767);

      double y(String text) => tester.getTopLeft(find.text(text).last).dy;
      expect(find.text('MODS — 1'), findsOneWidget);
      expect(find.text('CREW — 1'), findsOneWidget);
      expect(find.text('ONLINE — 2'), findsOneWidget);
      expect(find.text('OFFLINE — 1'), findsOneWidget);
      // Helpers is not hoisted, so Bo stays under Online.
      expect(find.textContaining('HELPERS'), findsNothing);
      expect(y('MODS — 1'), lessThan(y('Yan')));
      expect(y('Yan'), lessThan(y('CREW — 1')));
      expect(y('CREW — 1'), lessThan(y('Amy')));
      expect(y('Amy'), lessThan(y('ONLINE — 2')));
      expect(y('ONLINE — 2'), lessThan(y('Xu')));
      expect(y('Xu'), lessThan(y('Bo')));
      expect(y('Bo'), lessThan(y('OFFLINE — 1')));

      // Names take the highest coloured role's colour.
      Color? colorOf(String name) =>
          tester.widget<Text>(find.text(name).last).style?.color;
      expect(colorOf('Yan'), const Color(0xFF3498DB));
      expect(colorOf('Amy'), const Color(0xFFE91E63));
      expect(colorOf('Bo'), const Color(0xFF2ECC71));
      expect(colorOf('Cy'), isNull);
    });

    testWidgets('the owner creates, edits and deletes roles', (tester) async {
      final repository = await pumpRoles(
        tester,
        currentUserId: 'user-1',
        permissions: 32767,
      );
      await openRolesPage(tester);

      expect(find.text('Mods'), findsOneWidget);
      expect(find.text('@everyone'), findsOneWidget);
      expect(find.text('Every member'), findsOneWidget);
      expect(find.text('2 members'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Mods'), lessThan(y('Crew')));
      expect(y('Crew'), lessThan(y('Helpers')));
      expect(y('Helpers'), lessThan(y('@everyone')));

      await tester.tap(find.byTooltip('Create role'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Role name'),
        'Artists',
      );
      await tester.tap(find.byTooltip('#E67E22'));
      await tester.tap(find.text('Show separately'));
      final manageMessages = find.byKey(
        const ValueKey('role-permission-manage_messages'),
      );
      // The focused name field would scroll itself back into view.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(manageMessages);
      await tester.pumpAndSettle();
      await tester.tap(manageMessages);
      await tester.pumpAndSettle();
      final create = find.widgetWithText(FilledButton, 'Create');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(repository.roleCalls, ['create Artists 15105570 4 true']);

      await tester.tap(find.text('Helpers'));
      await tester.pumpAndSettle();
      expect(find.text('Edit role'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Role name'),
        'Helpers 2',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        repository.roleCalls.last,
        'update role-helpers Helpers 2 3066993 0 false',
      );

      await tester.tap(find.text('Crew'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete role'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repository.roleCalls.last, 'delete role-crew');

      // @everyone only offers its permissions.
      await tester.tap(find.text('@everyone'));
      await tester.pumpAndSettle();
      expect(find.text('Every member has these permissions.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Role name'), findsNothing);
      expect(find.text('Show separately'), findsNothing);
    });

    testWidgets('roles at or above the user stay locked', (tester) async {
      final repository = await pumpRoles(
        tester,
        currentUserId: 'user-3',
        // @everyone plus manage_roles from Crew.
        permissions: 1 | 2 | 64 | 8192 | 16,
      );
      await openRolesPage(tester);

      // Only Helpers (below Crew) can move; Mods and Crew are locked.
      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));

      await tester.tap(find.text('Mods'));
      await tester.pumpAndSettle();
      expect(
        find.text('This role ranks at or above your highest role.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Helpers'));
      await tester.pumpAndSettle();
      // Permissions the user lacks cannot be granted.
      SwitchListTile permissionSwitch(String key) =>
          tester.widget(find.byKey(ValueKey('role-permission-$key')));
      expect(permissionSwitch('manage_roles').onChanged, isNotNull);
      expect(permissionSwitch('kick_members').onChanged, isNull);
      expect(repository.roleCalls, isEmpty);
    });

    testWidgets('reordering keeps locked roles in place', (tester) async {
      final repository = await pumpRoles(
        tester,
        currentUserId: 'user-1',
        permissions: 32767,
      );
      await openRolesPage(tester);

      // Drag Helpers above Crew.
      final handle = find.descendant(
        of: find.byKey(const ValueKey('circle-role-role-helpers')),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var step = 0; step < 4; step++) {
        await gesture.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(repository.roleCalls, [
        'reorder role-mods,role-helpers,role-crew',
      ]);
    });

    testWidgets("managing a member's roles from the member list", (
      tester,
    ) async {
      final repository = await pumpRoles(
        tester,
        currentUserId: 'user-3',
        permissions: 1 | 2 | 64 | 8192 | 16,
      );

      await tester.longPress(find.text('Bo'));
      await tester.pumpAndSettle();
      expect(find.text('Change nickname'), findsNothing);
      await tester.tap(find.text('Manage roles'));
      await tester.pumpAndSettle();

      CheckboxListTile box(String id) =>
          tester.widget(find.byKey(ValueKey('member-role-$id')));
      expect(box('role-mods').onChanged, isNull);
      expect(box('role-crew').onChanged, isNull);
      expect(box('role-helpers').value, isTrue);
      await tester.tap(find.byKey(const ValueKey('member-role-role-helpers')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repository.roleCalls, ['assign user-4 ']);

      // The owner's roles are off limits.
      await tester.longPress(find.text('Xu'));
      await tester.pumpAndSettle();
      expect(find.text('Manage roles'), findsNothing);
    });

    testWidgets('kicking is limited to members ranked below', (tester) async {
      final repository = await pumpRoles(
        tester,
        currentUserId: 'user-3',
        // @everyone plus manage_roles and kick_members.
        permissions: 1 | 2 | 64 | 8192 | 16 | 32,
      );

      for (final name in ['Yan', 'Xu', 'Amy']) {
        await tester.longPress(find.text(name).last);
        await tester.pumpAndSettle();
        expect(find.text('View profile'), findsOneWidget, reason: name);
        expect(find.text('Kick'), findsNothing, reason: name);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      await tester.longPress(find.text('Bo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();
      expect(find.text('Kick Bo'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.kickedUserIds, isEmpty);

      await tester.longPress(find.text('Bo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();
      expect(repository.kickedUserIds, ['user-4']);
      expect(find.text('Kicked Bo.'), findsOneWidget);
    });

    testWidgets('plain members get no role management', (tester) async {
      await pumpRoles(
        tester,
        currentUserId: 'user-5',
        permissions: 1 | 2 | 64 | 8192,
      );

      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      expect(find.text('Roles'), findsNothing);
      await tester.tapAt(const Offset(1000, 800));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Bo'));
      await tester.pumpAndSettle();
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Manage roles'), findsNothing);
      expect(find.text('Kick'), findsNothing);
    });
  });

  group('channel permissions', () {
    const everyone = CircleRole(
      id: 'role-everyone',
      name: '@everyone',
      position: 0,
      permissions: 1 | 2 | 64 | 8192,
      isDefault: true,
    );
    const mods = CircleRole(
      id: 'role-mods',
      name: 'Mods',
      position: 2,
      permissions: 1 | 2 | 16,
    );
    const helpers = CircleRole(
      id: 'role-helpers',
      name: 'Helpers',
      position: 1,
      permissions: 0,
    );

    Future<FakeCirclesRepository> pumpChannels(
      WidgetTester tester, {
      required String currentUserId,
      required int permissions,
      int channelPermissions = 1 | 2 | 64 | 8192 | 16,
      List<CircleChannelOverwrite> overwrites = const [],
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      CircleMember member(
        String id,
        String name,
        String role, [
        List<String> roleIds = const [],
      ]) {
        return CircleMember(
          profile: _profile(id: id, username: name.toLowerCase(), name: name),
          role: role,
          roleIds: roleIds,
          isCurrentUser: id == currentUserId,
        );
      }

      final repository = FakeCirclesRepository()
        ..channelOverwrites = overwrites
        ..detail = CircleDetail(
          circle: CircleSummary(
            id: 'circle-1',
            name: 'Close Friends',
            memberCount: 3,
            channelCount: 2,
            currentUserRole: currentUserId == 'user-1' ? 'owner' : 'member',
            currentUserPermissions: permissions,
          ),
          roles: const [mods, helpers, everyone],
          members: [
            member('user-1', 'Xu', 'owner'),
            member('user-2', 'Yan', 'admin', ['role-mods']),
            member('user-3', 'Amy', 'member', ['role-helpers']),
          ],
          channels: [
            CircleChannel(
              id: 'channel-1',
              circleId: 'circle-1',
              conversationId: 'conversation-1',
              name: 'general',
              position: 0,
              currentUserPermissions: channelPermissions,
            ),
            const CircleChannel(
              id: 'channel-2',
              circleId: 'circle-1',
              conversationId: 'conversation-2',
              name: 'staff',
              position: 1,
              isPrivate: true,
            ),
          ],
          posts: const [],
        );
      repository.circles = [repository.detail.circle];
      final router = GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) => CircleDetailScreen(
              circleId: state.pathParameters['circleId']!,
              channelViewBuilder: (context, channel, actions) => Scaffold(
                appBar: AppBar(title: Text(channel.name), actions: actions),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('private channels show a lock in the sidebar', (tester) async {
      await pumpChannels(
        tester,
        currentUserId: 'user-3',
        permissions: 1 | 2 | 64 | 8192,
      );

      final staffRow = find.ancestor(
        of: find.text('staff'),
        matching: find.byType(CircleChannelRow),
      );
      expect(
        find.descendant(
          of: staffRow,
          matching: find.byKey(const ValueKey('channel-lock-icon')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('channel-lock-icon')), findsOneWidget);
      // Plain members get neither the settings action nor the menu.
      expect(find.byTooltip('Channel settings'), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('staff')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Channel settings'), findsNothing);
    });

    testWidgets('managers make a channel private and read-only', (
      tester,
    ) async {
      final repository = await pumpChannels(
        tester,
        currentUserId: 'user-2',
        permissions: 1 | 2 | 64 | 8192 | 16,
      );

      await tester.tap(find.byTooltip('Channel settings'));
      await tester.pumpAndSettle();

      expect(find.text('Channel settings'), findsOneWidget);
      expect(find.text('# general'), findsOneWidget);
      await tester.tap(find.text('Private channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read-only channel'));
      await tester.pumpAndSettle();

      expect(repository.overwriteCalls, [
        'privacy channel-1 true false',
        'privacy channel-1 false true',
      ]);
    });

    testWidgets('right click on a channel opens its settings', (tester) async {
      await pumpChannels(
        tester,
        currentUserId: 'user-1',
        permissions: CirclePermission.all,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('staff')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings'));
      await tester.pumpAndSettle();

      expect(find.text('# staff'), findsOneWidget);
      expect(find.text('Private channel'), findsOneWidget);
      final privateSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('channel-private-switch')),
      );
      expect(privateSwitch.value, isTrue);
    });

    testWidgets('overwrites are edited with allow, inherit and deny', (
      tester,
    ) async {
      final repository = await pumpChannels(
        tester,
        currentUserId: 'user-2',
        permissions: 1 | 2 | 64 | 8192 | 16,
        overwrites: const [
          CircleChannelOverwrite(
            id: 'ow-everyone',
            channelId: 'channel-1',
            roleId: 'role-everyone',
            deny: 2,
          ),
          CircleChannelOverwrite(
            id: 'ow-mods',
            channelId: 'channel-1',
            roleId: 'role-mods',
            allow: 2,
          ),
          CircleChannelOverwrite(
            id: 'ow-amy',
            channelId: 'channel-1',
            userId: 'user-3',
            allow: 1,
          ),
        ],
      );

      await tester.tap(find.byTooltip('Channel settings'));
      await tester.pumpAndSettle();

      expect(find.text('Denied: Send messages'), findsOneWidget);
      expect(find.text('Allowed: Send messages'), findsOneWidget);
      expect(find.text('Allowed: View channels'), findsOneWidget);
      // Mods is the caller's own rank: shown but not editable.
      final modsTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('channel-overwrite-ow-mods')),
      );
      expect(modsTile.onTap, isNull);

      await tester.tap(find.text('Amy'));
      await tester.pumpAndSettle();
      final sendRow = find.byKey(const ValueKey('overwrite-row-send_messages'));
      await tester.tap(
        find.descendant(of: sendRow, matching: find.byTooltip('Deny')),
      );
      await tester.pumpAndSettle();
      // Manage messages is not the caller's to give.
      final manageRow = find.byKey(
        const ValueKey('overwrite-row-manage_messages'),
      );
      final manageButton = tester.widget<SegmentedButton<OverwriteState>>(
        find.descendant(
          of: manageRow,
          matching: find.byType(SegmentedButton<OverwriteState>),
        ),
      );
      expect(manageButton.onSelectionChanged, isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.overwriteCalls, ['set channel-1 user-3 1 2']);
    });

    testWidgets('roles and members get new overwrites', (tester) async {
      final repository = await pumpChannels(
        tester,
        currentUserId: 'user-2',
        permissions: 1 | 2 | 64 | 8192 | 16,
      );

      await tester.tap(find.byTooltip('Channel settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('No role or member has its own permissions here yet.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add role or member'));
      await tester.pumpAndSettle();
      // Roles below the caller and members below them (or themselves).
      expect(find.text('Helpers'), findsOneWidget);
      expect(find.text('@everyone'), findsOneWidget);
      expect(find.text('Mods'), findsNothing);
      expect(find.text('Xu'), findsNothing);
      expect(find.text('Amy'), findsOneWidget);
      expect(find.text('Yan'), findsOneWidget);

      await tester.tap(find.text('Helpers'));
      await tester.pumpAndSettle();
      final viewRow = find.byKey(const ValueKey('overwrite-row-view_channel'));
      await tester.tap(
        find.descendant(of: viewRow, matching: find.byTooltip('Allow')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.overwriteCalls, ['set channel-1 role-helpers 1 0']);
    });

    testWidgets('channel managers set slowmode', (tester) async {
      final repository = await pumpChannels(
        tester,
        currentUserId: 'user-3',
        // manage_channels without manage_roles.
        permissions: 1 | 2 | 64 | 8192 | 8,
      );

      await tester.tap(find.byTooltip('Channel settings'));
      await tester.pumpAndSettle();
      expect(find.text('Private channel'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('channel-slowmode-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5m').last);
      await tester.pumpAndSettle();

      expect(repository.overwriteCalls, ['slowmode channel-1 300']);
    });

    test('slowmode spares members who manage messages', () {
      const channel = CircleChannel(
        id: 'channel-1',
        circleId: 'circle-1',
        conversationId: 'conversation-1',
        name: 'general',
        position: 0,
        slowmodeSeconds: 30,
      );
      CircleDetail detailWith(int permissions) => CircleDetail(
        circle: CircleSummary(
          id: 'circle-1',
          name: 'Close Friends',
          memberCount: 1,
          channelCount: 1,
          currentUserRole: 'member',
          currentUserPermissions: permissions,
        ),
        members: const [],
        channels: const [channel],
        posts: const [],
      );

      expect(detailWith(1 | 2).slowmodeFor(channel), 30);
      expect(detailWith(1 | 2 | 4).slowmodeFor(channel), 0);
    });

    testWidgets('failed saves show a snackbar', (tester) async {
      final repository =
          await pumpChannels(
              tester,
              currentUserId: 'user-1',
              permissions: CirclePermission.all,
              overwrites: const [
                CircleChannelOverwrite(
                  id: 'ow-helpers',
                  channelId: 'channel-1',
                  roleId: 'role-helpers',
                  allow: 1,
                ),
              ],
            )
            ..overwriteError = StateError('nope');

      await tester.tap(find.byTooltip('Channel settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Helpers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(repository.overwriteCalls, ['set channel-1 role-helpers 0 0']);
      expect(
        find.text('Could not save channel permissions. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('circle nicknames', () {
    Future<FakeCirclesRepository> pumpWorkspace(
      WidgetTester tester, {
      required String currentUserRole,
      required String currentUserId,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final base = _detail();
      CircleMember member(String id, String name, String role, {String? nick}) {
        return CircleMember(
          profile: _profile(id: id, username: name.toLowerCase(), name: name),
          role: role,
          nickname: nick,
          isCurrentUser: id == currentUserId,
        );
      }

      final repository = FakeCirclesRepository()
        ..onlineUserIds = {'user-1', 'user-2', 'user-3'}
        ..detail = CircleDetail(
          circle: CircleSummary(
            id: 'circle-1',
            name: 'Close Friends',
            memberCount: 3,
            channelCount: 1,
            currentUserRole: currentUserRole,
          ),
          members: [
            member('user-1', 'Xu', 'owner', nick: 'Captain'),
            member('user-2', 'Yan', 'admin'),
            member('user-3', 'Amy', 'member', nick: 'Ames'),
          ],
          channels: base.channels,
          posts: const [],
        );
      repository.circles = [repository.detail.circle];
      final router = GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) => CircleDetailScreen(
              circleId: state.pathParameters['circleId']!,
              channelViewBuilder: (context, channel, actions) => Scaffold(
                appBar: AppBar(title: Text(channel.name), actions: actions),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('member list shows nicknames instead of display names', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        currentUserRole: 'admin',
        currentUserId: 'user-2',
      );

      expect(find.text('Captain'), findsOneWidget);
      expect(find.text('Ames'), findsOneWidget);
      expect(find.text('Xu'), findsNothing);
      expect(find.text('Amy'), findsNothing);
      expect(find.text('Yan'), findsOneWidget);
    });

    testWidgets('admins change a member nickname from the member menu', (
      tester,
    ) async {
      final repository = await pumpWorkspace(
        tester,
        currentUserRole: 'admin',
        currentUserId: 'user-2',
      );

      await tester.longPress(find.text('Ames'));
      await tester.pumpAndSettle();
      expect(find.text('View profile'), findsOneWidget);
      await tester.tap(find.text('Change nickname'));
      await tester.pumpAndSettle();

      expect(find.text('Only shown in this circle for Amy.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Amelia  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.nicknameUpdates, [
        (userId: 'user-3', nickname: 'Amelia'),
      ]);
    });

    testWidgets('reset clears an existing nickname', (tester) async {
      final repository = await pumpWorkspace(
        tester,
        currentUserRole: 'member',
        currentUserId: 'user-3',
      );

      await tester.longPress(find.text('Ames'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change nickname'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(repository.nicknameUpdates, [(userId: 'user-3', nickname: null)]);
    });

    testWidgets('admins cannot rename the owner', (tester) async {
      await pumpWorkspace(
        tester,
        currentUserRole: 'admin',
        currentUserId: 'user-2',
      );

      await tester.longPress(find.text('Captain'));
      await tester.pumpAndSettle();
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Change nickname'), findsNothing);
    });

    testWidgets('members cannot rename other members', (tester) async {
      await pumpWorkspace(
        tester,
        currentUserRole: 'member',
        currentUserId: 'user-3',
      );

      await tester.longPress(find.text('Yan'));
      await tester.pumpAndSettle();
      expect(find.text('Change nickname'), findsNothing);
    });

    testWidgets('the circle menu changes my own nickname', (tester) async {
      final repository = await pumpWorkspace(
        tester,
        currentUserRole: 'member',
        currentUserId: 'user-3',
      );

      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      // Plain members can invite (an @everyone permission) and rename
      // themselves, but not manage channels or roles.
      expect(find.text('Invite friends'), findsOneWidget);
      expect(find.text('Create channel'), findsNothing);
      expect(find.text('Roles'), findsNothing);
      await tester.tap(find.text('Change my nickname'));
      await tester.pumpAndSettle();

      expect(find.text('Only shown in this circle.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Amy B');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.nicknameUpdates, [
        (userId: 'user-3', nickname: 'Amy B'),
      ]);
    });

    testWidgets('the circle menu opens notification settings', (tester) async {
      final repository = await pumpWorkspace(
        tester,
        currentUserRole: 'member',
        currentUserId: 'user-3',
      );

      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notification settings'));
      await tester.pumpAndSettle();

      expect(find.text('Close Friends'), findsWidgets);
      expect(find.text('For 15 minutes'), findsOneWidget);
      expect(find.text('Until I turn it back on'), findsOneWidget);

      await tester.tap(find.text('Only @mentions'));
      await tester.pumpAndSettle();
      expect(
        repository.notificationUpdates.single.level,
        CircleNotificationLevel.mentions,
      );
      expect(repository.notificationUpdates.single.mutedUntil, isNull);

      final before = DateTime.now().toUtc();
      await tester.tap(find.text('For 1 hour'));
      await tester.pumpAndSettle();
      final muted = repository.notificationUpdates.last;
      expect(muted.level, CircleNotificationLevel.mentions);
      expect(
        muted.mutedUntil!.difference(before).inMinutes,
        inInclusiveRange(59, 60),
      );
      expect(find.textContaining('Muted until'), findsOneWidget);
      expect(find.text('For 1 hour'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Unmute'));
      await tester.pumpAndSettle();
      expect(repository.notificationUpdates.last.mutedUntil, isNull);
      expect(
        repository.notificationUpdates.last.level,
        CircleNotificationLevel.mentions,
      );
      expect(find.text('For 1 hour'), findsOneWidget);
    });
  });

  testWidgets('narrow circle detail opens notification settings', (
    tester,
  ) async {
    final repository = FakeCirclesRepository()
      ..detail = _detail()
      ..notificationSettings = CircleNotificationSettings(
        circleId: 'circle-1',
        level: CircleNotificationLevel.none,
        mutedUntil: DateTime.now().toUtc().add(circleMuteIndefinitely),
      );
    final router = GoRouter(
      initialLocation: '/circles/circle-1',
      routes: [
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) =>
              CircleDetailScreen(circleId: state.pathParameters['circleId']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Circle menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();

    expect(find.text('Muted until you turn it back on'), findsOneWidget);
    final levels = tester.widget<RadioGroup<CircleNotificationLevel>>(
      find.byType(RadioGroup<CircleNotificationLevel>),
    );
    expect(levels.groupValue, CircleNotificationLevel.none);

    await tester.tap(find.text('All messages'));
    await tester.pumpAndSettle();
    // Changing the level keeps the indefinite mute.
    final saved = repository.notificationUpdates.single;
    expect(saved.level, CircleNotificationLevel.all);
    expect(saved.isMutedIndefinitelyAt(DateTime.now().toUtc()), isTrue);
  });

  group('channel categories', () {
    const textCategory = CircleChannelCategory(
      id: 'cat-a',
      circleId: 'circle-1',
      name: 'Text',
      position: 0,
    );
    const mediaCategory = CircleChannelCategory(
      id: 'cat-b',
      circleId: 'circle-1',
      name: 'Media',
      position: 1,
    );

    CircleChannel channel(String name, int position, [String? categoryId]) {
      return CircleChannel(
        id: name,
        circleId: 'circle-1',
        conversationId: 'conversation-$name',
        name: name,
        position: position,
        categoryId: categoryId,
      );
    }

    Future<FakeCirclesRepository> pumpCategories(
      WidgetTester tester, {
      String role = 'owner',
      InMemoryCircleCategoryCollapseStore? collapseStore,
      Map<String, int> unread = const {},
      List<CircleChannel>? channels,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final base = _detail();
      final repository = FakeCirclesRepository()
        ..detail = CircleDetail(
          circle: CircleSummary(
            id: 'circle-1',
            name: 'Close Friends',
            memberCount: 1,
            channelCount: 4,
            currentUserRole: role,
          ),
          members: base.members,
          channels:
              channels ??
              [
                channel('general', 0),
                channel('chat', 1, 'cat-a'),
                channel('memes', 2, 'cat-a'),
                channel('clips', 3, 'cat-b'),
              ],
          categories: const [textCategory, mediaCategory],
          posts: const [],
        );
      repository.circles = [repository.detail.circle];
      final router = GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) => CircleDetailScreen(
              circleId: state.pathParameters['circleId']!,
              channelViewBuilder: (context, channel, actions) => Scaffold(
                appBar: AppBar(
                  title: Text('Channel ${channel.name}'),
                  actions: actions,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(
          repository,
          FakeContactsRepository(),
          router,
          collapseStore: collapseStore,
          conversations: [
            for (final entry in unread.entries)
              ConversationSummary(
                id: 'conversation-${entry.key}',
                type: ConversationType.channel,
                unreadCount: entry.value,
              ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Finder sidebarText(String text) {
      return find.descendant(
        of: find.byType(CircleChannelSidebar),
        matching: find.text(text),
      );
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(sidebarText(text)).dy;

    ReorderableListView channelList(WidgetTester tester) {
      return tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
    }

    testWidgets('uncategorized channels come first, then each category', (
      tester,
    ) async {
      await pumpCategories(tester);

      expect(find.text('Channel general'), findsOneWidget);
      final order = ['general', 'TEXT', 'chat', 'memes', 'MEDIA', 'clips'];
      for (var index = 1; index < order.length; index++) {
        expect(
          top(tester, order[index - 1]),
          lessThan(top(tester, order[index])),
          reason: '${order[index - 1]} above ${order[index]}',
        );
      }
    });

    testWidgets('collapse state is saved and restored per circle', (
      tester,
    ) async {
      final store = InMemoryCircleCategoryCollapseStore({
        'circle-1': {'cat-a'},
        'circle-2': {'cat-b'},
      });
      await pumpCategories(tester, collapseStore: store);

      expect(sidebarText('chat'), findsNothing);
      expect(sidebarText('memes'), findsNothing);
      expect(sidebarText('clips'), findsOneWidget);

      await tester.tap(sidebarText('MEDIA'));
      await tester.pumpAndSettle();
      expect(sidebarText('clips'), findsNothing);
      expect(store.collapsed['circle-1'], {'cat-a', 'cat-b'});

      await tester.tap(sidebarText('TEXT'));
      await tester.pumpAndSettle();
      expect(sidebarText('chat'), findsOneWidget);
      expect(store.collapsed['circle-1'], {'cat-b'});
      expect(store.collapsed['circle-2'], {'cat-b'});
    });

    testWidgets('collapsed categories keep the open and unread channels', (
      tester,
    ) async {
      await pumpCategories(
        tester,
        unread: {'memes': 2},
        channels: [
          channel('general', 0),
          channel('chat', 1, 'cat-a'),
          channel('memes', 2, 'cat-a'),
          channel('quiet', 3, 'cat-a'),
          channel('clips', 4, 'cat-b'),
        ],
      );

      await tester.tap(sidebarText('chat'));
      await tester.pumpAndSettle();
      await tester.tap(sidebarText('TEXT'));
      await tester.pumpAndSettle();

      expect(sidebarText('chat'), findsOneWidget);
      expect(sidebarText('memes'), findsOneWidget);
      expect(sidebarText('quiet'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('circle-channel-memes')),
          matching: find.byKey(const ValueKey('channel-unread-pill')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dragging a channel saves the new layout', (tester) async {
      final repository = await pumpCategories(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(sidebarText('clips')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(repository.reorderedLayouts, [
        {
          'categories': ['cat-a', 'cat-b'],
          'channels': [
            {'id': 'clips', 'category_id': null},
            {'id': 'general', 'category_id': null},
            {'id': 'chat', 'category_id': 'cat-a'},
            {'id': 'memes', 'category_id': 'cat-a'},
          ],
        },
      ]);
      expect(top(tester, 'clips'), lessThan(top(tester, 'general')));
    });

    testWidgets('channels move across categories and categories reorder', (
      tester,
    ) async {
      final repository = await pumpCategories(tester);

      // Entries: general, TEXT, chat, memes, MEDIA, clips.
      channelList(tester).onReorderItem!(0, 5);
      await tester.pumpAndSettle();
      expect(repository.reorderedLayouts.last, {
        'categories': ['cat-a', 'cat-b'],
        'channels': [
          {'id': 'chat', 'category_id': 'cat-a'},
          {'id': 'memes', 'category_id': 'cat-a'},
          {'id': 'clips', 'category_id': 'cat-b'},
          {'id': 'general', 'category_id': 'cat-b'},
        ],
      });
      expect(top(tester, 'clips'), lessThan(top(tester, 'general')));

      // Entries now: TEXT, chat, memes, MEDIA, clips, general.
      channelList(tester).onReorderItem!(3, 0);
      await tester.pumpAndSettle();
      expect(repository.reorderedLayouts.last, {
        'categories': ['cat-b', 'cat-a'],
        'channels': [
          {'id': 'clips', 'category_id': 'cat-b'},
          {'id': 'general', 'category_id': 'cat-b'},
          {'id': 'chat', 'category_id': 'cat-a'},
          {'id': 'memes', 'category_id': 'cat-a'},
        ],
      });
      expect(top(tester, 'MEDIA'), lessThan(top(tester, 'TEXT')));
      expect(top(tester, 'general'), lessThan(top(tester, 'TEXT')));

      // Dropping an entry where it was is not a change.
      channelList(tester).onReorderItem!(1, 1);
      await tester.pumpAndSettle();
      expect(repository.reorderedLayouts, hasLength(2));
    });

    testWidgets('a failed reorder rolls back and explains', (tester) async {
      final repository = await pumpCategories(tester)
        ..reorderCompleter = Completer<void>()
        ..reorderError = Exception('offline');

      channelList(tester).onReorderItem!(5, 0);
      await tester.pump();
      // Shown right away while saving.
      expect(top(tester, 'clips'), lessThan(top(tester, 'general')));

      repository.reorderCompleter!.complete();
      await tester.pumpAndSettle();
      expect(top(tester, 'general'), lessThan(top(tester, 'clips')));
      expect(top(tester, 'MEDIA'), lessThan(top(tester, 'clips')));
      expect(
        find.text('Could not reorder channels. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('members cannot reorder or manage categories', (tester) async {
      await pumpCategories(tester, role: 'member');

      expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(find.byTooltip('Category options'), findsNothing);
      expect(find.byTooltip('Create channel'), findsNothing);
      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      expect(find.text('Create category'), findsNothing);
    });

    testWidgets('managers create, rename and delete categories', (
      tester,
    ) async {
      final repository = await pumpCategories(tester);

      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Voice  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Category options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename category'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Media'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Clips');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Category options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.categoryCalls, [
        'create Voice',
        'rename cat-b Clips',
        'delete cat-a',
      ]);
    });

    testWidgets('a category creates channels inside it', (tester) async {
      final repository = await pumpCategories(tester);

      await tester.tap(find.byTooltip('Create channel').last);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(DropdownButtonFormField<String?>, 'Media'),
        findsOneWidget,
      );
      await tester.enterText(find.bySemanticsLabel('Channel name'), 'reels');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(repository.createdChannelName, 'reels');
      expect(repository.createdChannelCategoryId, 'cat-b');

      // The circle menu starts without a category, which can be picked.
      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('Channel name'), 'talk');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(repository.createdChannelName, 'talk');
      expect(repository.createdChannelCategoryId, 'cat-a');
    });
  });

  group('circle rail indicators', () {
    CircleSummary circle(
      String id, {
      int unread = 0,
      int mentions = 0,
      bool muted = false,
    }) {
      return CircleSummary(
        id: id,
        name: 'Circle $id',
        memberCount: 2,
        channelCount: 1,
        unreadCount: unread,
        mentionCount: mentions,
        isMuted: muted,
      );
    }

    Future<FakeCirclesRepository> pumpRail(
      WidgetTester tester,
      List<CircleSummary> circles,
    ) async {
      final repository = FakeCirclesRepository()..circles = circles;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            circlesRepositoryProvider.overrideWithValue(repository),
            conversationsProvider.overrideWith(
              (ref) async => const <ConversationSummary>[],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Row(children: [CircleRail(selectedCircleId: 'selected')]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Finder inItem(String circleId, Key key) {
      return find.descendant(
        of: find.byKey(ValueKey('circle-rail-$circleId')),
        matching: find.byKey(key),
      );
    }

    double pillHeight(WidgetTester tester, String circleId) {
      return tester
          .getSize(inItem(circleId, const ValueKey('circle-rail-pill')))
          .height;
    }

    double iconOpacity(WidgetTester tester, String circleId) {
      return tester
          .widget<Opacity>(inItem(circleId, const ValueKey('circle-rail-icon')))
          .opacity;
    }

    testWidgets('unread circles show a short pill', (tester) async {
      await pumpRail(tester, [
        circle('read'),
        circle('unread', unread: 3),
        circle('selected', unread: 3),
      ]);

      expect(pillHeight(tester, 'read'), 0);
      expect(pillHeight(tester, 'unread'), 8);
      expect(pillHeight(tester, 'selected'), 40);
      expect(find.byKey(const ValueKey('circle-mention-badge')), findsNothing);
    });

    testWidgets('mentions show a red count badge', (tester) async {
      await pumpRail(tester, [
        circle('few', unread: 2, mentions: 2),
        circle('many', unread: 120, mentions: 120),
      ]);

      expect(
        find.descendant(
          of: inItem('few', const ValueKey('circle-mention-badge')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inItem('many', const ValueKey('circle-mention-badge')),
          matching: find.text('99+'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('muted circles are dimmed without pill but keep mentions', (
      tester,
    ) async {
      await pumpRail(tester, [
        circle('muted', unread: 5, muted: true),
        circle('muted-mentioned', unread: 5, mentions: 3, muted: true),
        circle('loud', unread: 5),
      ]);

      expect(pillHeight(tester, 'muted'), 0);
      expect(pillHeight(tester, 'muted-mentioned'), 0);
      expect(
        inItem('muted', const ValueKey('circle-mention-badge')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: inItem('muted-mentioned', const ValueKey('circle-mention-badge')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(iconOpacity(tester, 'muted'), lessThan(1));
      expect(iconOpacity(tester, 'muted-mentioned'), lessThan(1));
      expect(iconOpacity(tester, 'loud'), 1);
    });

    testWidgets('the rail refreshes when conversations change', (tester) async {
      final repository = await pumpRail(tester, [circle('busy')]);
      expect(pillHeight(tester, 'busy'), 0);

      repository.circles = [circle('busy', unread: 1, mentions: 1)];
      ProviderScope.containerOf(
        tester.element(find.byType(CircleRail)),
      ).invalidate(conversationsProvider);
      await tester.pumpAndSettle();

      expect(pillHeight(tester, 'busy'), 8);
      expect(
        inItem('busy', const ValueKey('circle-mention-badge')),
        findsOneWidget,
      );
    });
  });

  group('leaving and ownership', () {
    GoRouter circlesRouter() {
      return GoRouter(
        initialLocation: '/circles/circle-1',
        routes: [
          GoRoute(
            path: '/circles',
            builder: (context, state) =>
                const Scaffold(body: Text('Circles list')),
          ),
          GoRoute(
            path: '/circles/:circleId',
            builder: (context, state) =>
                CircleDetailScreen(circleId: state.pathParameters['circleId']!),
          ),
        ],
      );
    }

    CircleDetail memberDetail() {
      final detail = _detail();
      return CircleDetail(
        circle: const CircleSummary(
          id: 'circle-1',
          name: 'Close Friends',
          memberCount: 2,
          channelCount: 1,
          currentUserRole: 'member',
        ),
        members: [
          CircleMember(
            profile: _profile(id: 'user-1', username: 'xu', name: 'Xu'),
            role: 'owner',
          ),
          CircleMember(
            profile: _profile(id: 'user-2', username: 'ada', name: 'Ada'),
            role: 'member',
            isCurrentUser: true,
          ),
        ],
        channels: detail.channels,
        posts: const [],
      );
    }

    CircleDetail ownerDetail() {
      final detail = _detail();
      return CircleDetail(
        circle: detail.circle,
        members: [
          CircleMember(
            profile: _profile(id: 'user-1', username: 'xu', name: 'Xu'),
            role: 'owner',
            isCurrentUser: true,
          ),
          CircleMember(
            profile: _profile(id: 'user-2', username: 'ada', name: 'Ada'),
            role: 'member',
          ),
          CircleMember(
            profile: _profile(id: 'user-3', username: 'bo', name: 'Bo'),
            role: 'member',
          ),
        ],
        channels: detail.channels,
        posts: const [],
      );
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('members leave after confirming and land on Circles', (
      tester,
    ) async {
      final repository = FakeCirclesRepository()..detail = memberDetail();
      final router = circlesRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();

      await openMenu(tester);
      expect(find.text('Transfer ownership'), findsNothing);
      await tester.tap(find.text('Leave circle'));
      await tester.pumpAndSettle();
      expect(find.text('Leave Close Friends'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.leftCircleIds, isEmpty);

      await openMenu(tester);
      await tester.tap(find.text('Leave circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(repository.leftCircleIds, ['circle-1']);
      expect(find.text('Circles list'), findsOneWidget);
      expect(find.text('Left Close Friends.'), findsOneWidget);
    });

    testWidgets('owners transfer ownership after typing the circle name', (
      tester,
    ) async {
      final repository = FakeCirclesRepository()..detail = ownerDetail();
      final router = circlesRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();

      await openMenu(tester);
      expect(find.text('Leave circle'), findsNothing);
      await tester.tap(find.text('Transfer ownership'));
      await tester.pumpAndSettle();

      FilledButton transfer() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Transfer'),
      );
      // The owner is not a candidate.
      expect(find.byKey(const ValueKey('transfer-owner-user-1')), findsNothing);
      expect(transfer().onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('transfer-owner-user-3')));
      await tester.pump();
      expect(transfer().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('transfer-confirm-name')),
        'Close friends',
      );
      await tester.pump();
      expect(transfer().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('transfer-confirm-name')),
        'Close Friends',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.ownershipTransfers, [
        (circleId: 'circle-1', newOwnerId: 'user-3'),
      ]);
      expect(find.text('Bo now owns the circle.'), findsOneWidget);
    });

    testWidgets('a circle the user lost shows a friendly state', (
      tester,
    ) async {
      final repository = FakeCirclesRepository()
        ..detail = memberDetail()
        ..detailError = const CircleMembershipLostException('circle-1')
        ..circles = [
          const CircleSummary(
            id: 'circle-2',
            name: 'Book Club',
            memberCount: 3,
            channelCount: 1,
          ),
        ];
      final router = circlesRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("You're no longer a member of this circle"),
        findsOneWidget,
      );
      expect(find.byType(CircleRail), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-rail-circle-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('circle-rail-circle-2')),
        findsOneWidget,
      );

      await tester.tap(find.text('Back to Circles'));
      await tester.pumpAndSettle();
      expect(find.text('Circles list'), findsOneWidget);
    });
  });

  group('audit log', () {
    final now = DateTime.utc(2026, 10, 14, 12);

    Future<FakeCirclesRepository> openLog(
      WidgetTester tester, {
      List<CircleAuditEntry>? entries,
      int pageSize = 50,
    }) async {
      final repository = FakeCirclesRepository()
        ..detail = _detail()
        ..auditEntries = entries ?? sampleAuditEntries(now: now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circlesRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: CircleAuditLogScreen(
              circleId: 'circle-1',
              pageSize: pageSize,
              now: () => now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    String summary(WidgetTester tester, String id) {
      final text = tester.widget<Text>(
        find.byKey(ValueKey('circle-audit-summary-$id')),
      );
      return text.textSpan!.toPlainText();
    }

    testWidgets('is in the circle menu only with view audit log', (
      tester,
    ) async {
      final repository = FakeCirclesRepository()..detail = _detail();
      final router = _narrowRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(repository, FakeContactsRepository(), router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      expect(find.text('Audit log'), findsOneWidget);
      await tester.tap(find.text('Audit log'));
      await tester.pumpAndSettle();
      expect(find.byType(CircleAuditLogScreen), findsOneWidget);

      final member = FakeCirclesRepository()
        ..detail = CircleDetail(
          circle: const CircleSummary(
            id: 'circle-1',
            name: 'Close Friends',
            memberCount: 2,
            channelCount: 1,
            currentUserRole: 'member',
            currentUserPermissions: 1 | 2,
          ),
          members: const [],
          channels: _detail().channels,
          posts: const [],
        );
      final memberRouter = _narrowRouter();
      addTearDown(memberRouter.dispose);
      await tester.pumpWidget(
        _app(member, FakeContactsRepository(), memberRouter),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Circle menu'));
      await tester.pumpAndSettle();
      expect(find.text('Audit log'), findsNothing);
    });

    testWidgets('lists entries with summaries, times and details', (
      tester,
    ) async {
      await openLog(tester);

      expect(summary(tester, 'audit-0'), 'Ada created channel #general');
      expect(find.text('5m ago'), findsOneWidget);
      expect(
        summary(tester, 'audit-1'),
        'Grace updated role Moderators of the Valley',
      );
      expect(summary(tester, 'audit-2'), 'Ada set slowmode in #general to 2m');

      // Role changes expand into old → new lines with permission names.
      expect(find.textContaining('Send messages'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('circle-audit-audit-1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Mods → Moderators of the Valley',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'View channels → View channels, Send messages',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('#3498DB', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('loads older pages while scrolling', (tester) async {
      final repository = await openLog(
        tester,
        entries: sampleAuditEntries(now: now, count: 45),
        pageSize: 20,
      );
      expect(repository.auditCalls.first.before, isNull);
      expect(repository.auditCalls.first.limit, 20);

      final list = find.byKey(const ValueKey('circle-audit-log-list'));
      for (var step = 0; step < 30; step++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pumpAndSettle();
      }

      expect(repository.auditCalls.length, 3);
      expect(
        repository.auditCalls[1].before,
        sampleAuditEntries(now: now, count: 45)[19].createdAt,
      );
      expect(
        find.byKey(const ValueKey('circle-audit-audit-44')),
        findsOneWidget,
      );
    });

    testWidgets('filters by action group', (tester) async {
      final repository = await openLog(tester);

      await tester.tap(find.byTooltip('Filter by action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roles').last);
      await tester.pumpAndSettle();

      expect(repository.auditCalls.last.action, 'role');
      expect(
        find.byKey(const ValueKey('circle-audit-audit-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('circle-audit-audit-0')), findsNothing);

      await tester.tap(find.byTooltip('Show all actions'));
      await tester.pumpAndSettle();
      expect(repository.auditCalls.last.action, isNull);
      expect(
        find.byKey(const ValueKey('circle-audit-audit-0')),
        findsOneWidget,
      );
    });

    testWidgets('says when nothing matches', (tester) async {
      await openLog(tester, entries: const []);
      expect(find.text('Nothing has been logged yet.'), findsOneWidget);
    });
  });
}

/// The circle route plus the nested channel route the app uses for pushed
/// channels, with a stand-in thread.
GoRouter _narrowRouter() {
  return GoRouter(
    initialLocation: '/circles/circle-1',
    routes: [
      GoRoute(
        path: '/circles/:circleId',
        builder: (context, state) =>
            CircleDetailScreen(circleId: state.pathParameters['circleId']!),
        routes: [
          GoRoute(
            path: 'channels/:conversationId',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              final extra = state.extra! as ChatThreadRouteExtra;
              expect(state.pathParameters['circleId'], 'circle-1');
              expect(extra.circleId, 'circle-1');
              expect(
                extra.type,
                anyOf(ConversationType.channel, ConversationType.thread),
              );
              return CircleChannelThreadScreen(
                circleId: state.pathParameters['circleId']!,
                conversationId: conversationId,
                title: extra.title,
                threadBuilder: (context, actions) => Scaffold(
                  appBar: AppBar(
                    title: Text('Thread $conversationId'),
                    actions: actions,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
}

Widget _app(
  FakeCirclesRepository circlesRepository,
  FakeContactsRepository contactsRepository,
  GoRouter router, {
  InMemoryCircleCategoryCollapseStore? collapseStore,
  List<ConversationSummary>? conversations,
}) {
  return ProviderScope(
    overrides: [
      circlesRepositoryProvider.overrideWithValue(circlesRepository),
      contactsRepositoryProvider.overrideWithValue(contactsRepository),
      onlineUserIdsProvider.overrideWith(
        (ref) => Stream.value(circlesRepository.onlineUserIds),
      ),
      circleCategoryCollapseStoreProvider.overrideWithValue(
        collapseStore ?? InMemoryCircleCategoryCollapseStore(),
      ),
      if (conversations != null)
        conversationsProvider.overrideWith((ref) async => conversations),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class InMemoryCircleCategoryCollapseStore
    implements CircleCategoryCollapseStore {
  InMemoryCircleCategoryCollapseStore([Map<String, Set<String>>? initial])
    : collapsed = {...?initial};

  final Map<String, Set<String>> collapsed;

  @override
  Future<Set<String>> load(String circleId) async => {...?collapsed[circleId]};

  @override
  Future<void> save(String circleId, Set<String> collapsedCategoryIds) async {
    collapsed[circleId] = {...collapsedCategoryIds};
  }
}

CircleDetail _detail() {
  final owner = _profile(id: 'user-1', username: 'xu', name: 'Xu');
  return CircleDetail(
    circle: const CircleSummary(
      id: 'circle-1',
      name: 'Close Friends',
      memberCount: 1,
      channelCount: 1,
      currentUserRole: 'owner',
    ),
    members: [CircleMember(profile: owner, role: 'owner')],
    channels: const [
      CircleChannel(
        id: 'channel-1',
        circleId: 'circle-1',
        conversationId: 'conversation-1',
        name: 'general',
        position: 0,
      ),
    ],
    posts: const [],
  );
}

class FakeContactsRepository implements ContactsRepository {
  var friends = <Profile>[];

  @override
  Future<List<Profile>> listFriends() async => friends;

  @override
  Future<void> acceptFriendRequest(String requestId) async {}

  @override
  Future<List<IncomingFriendRequest>> listIncomingRequests() async => const [];

  @override
  Future<void> rejectFriendRequest(String requestId) async {}

  @override
  Future<List<Profile>> searchProfiles(String query) async => const [];

  @override
  Future<void> sendFriendRequest(String receiverId) async {}

  @override
  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  }) async {}
}

class FakeCirclesRepository implements CirclesRepository {
  late CircleDetail detail;
  var circles = <CircleSummary>[];
  var createdChannelName = '';
  String? createdChannelCategoryId;
  final categoryCalls = <String>[];
  final reorderedLayouts = <Map<String, dynamic>>[];
  Completer<void>? reorderCompleter;
  Object? reorderError;
  var invitedMemberIds = <String>[];
  final roleCalls = <String>[];
  final kickedUserIds = <String>[];

  /// Fed to [onlineUserIdsProvider] by [_app].
  var onlineUserIds = <String>{'user-1'};
  final nicknameUpdates = <({String userId, String? nickname})>[];
  CircleNotificationSettings? notificationSettings;
  final notificationUpdates = <CircleNotificationSettings>[];

  @override
  Future<void> kickMember({
    required String circleId,
    required String userId,
  }) async {
    kickedUserIds.add(userId);
  }

  final leftCircleIds = <String>[];
  final ownershipTransfers = <({String circleId, String newOwnerId})>[];

  @override
  Future<void> leaveCircle(String circleId) async {
    leftCircleIds.add(circleId);
  }

  /// Every audit entry, newest first; pages are served like the server.
  var auditEntries = <CircleAuditEntry>[];
  final auditCalls = <({DateTime? before, int limit, String? action})>[];

  @override
  Future<List<CircleAuditEntry>> listAuditLog({
    required String circleId,
    DateTime? before,
    int limit = 50,
    String? action,
  }) async {
    auditCalls.add((before: before, limit: limit, action: action));
    return auditEntries
        .where(
          (entry) =>
              (before == null || entry.createdAt.isBefore(before)) &&
              (action == null ||
                  entry.action == action ||
                  entry.group.filter == action),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  }) async {
    ownershipTransfers.add((circleId: circleId, newOwnerId: newOwnerId));
  }

  var channelOverwrites = <CircleChannelOverwrite>[];
  final overwriteCalls = <String>[];
  Object? overwriteError;

  @override
  Future<List<CircleChannelOverwrite>> listChannelOverwrites(
    String channelId,
  ) async => channelOverwrites;

  @override
  Future<void> setChannelOverwrite({
    required String channelId,
    String? roleId,
    String? userId,
    required int allow,
    required int deny,
  }) async {
    overwriteCalls.add('set $channelId ${roleId ?? userId} $allow $deny');
    final error = overwriteError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setChannelPrivacy({
    required String channelId,
    required bool isPrivate,
    required bool isReadOnly,
  }) async {
    overwriteCalls.add('privacy $channelId $isPrivate $isReadOnly');
  }

  @override
  Future<void> setChannelSlowmode({
    required String channelId,
    required int seconds,
  }) async {
    overwriteCalls.add('slowmode $channelId $seconds');
  }

  @override
  Future<String> createRole({
    required String circleId,
    required String name,
    int? color,
    int permissions = 0,
    bool hoist = false,
  }) async {
    roleCalls.add('create $name $color $permissions $hoist');
    return 'role-new';
  }

  @override
  Future<void> updateRole({
    required String roleId,
    required String name,
    int? color,
    required int permissions,
    bool hoist = false,
  }) async {
    roleCalls.add('update $roleId $name $color $permissions $hoist');
  }

  @override
  Future<void> deleteRole(String roleId) async {
    roleCalls.add('delete $roleId');
  }

  @override
  Future<void> reorderRoles({
    required String circleId,
    required List<String> roleIds,
  }) async {
    roleCalls.add('reorder ${roleIds.join(',')}');
  }

  @override
  Future<void> setMemberRoles({
    required String circleId,
    required String userId,
    required List<String> roleIds,
  }) async {
    roleCalls.add('assign $userId ${roleIds.join(',')}');
  }

  @override
  Future<CircleNotificationSettings> getNotificationSettings(
    String circleId,
  ) async =>
      notificationSettings ?? CircleNotificationSettings(circleId: circleId);

  @override
  Future<CircleNotificationSettings> setNotificationSettings({
    required String circleId,
    required CircleNotificationLevel level,
    DateTime? mutedUntil,
  }) async {
    final settings = CircleNotificationSettings(
      circleId: circleId,
      level: level,
      mutedUntil: mutedUntil,
    );
    notificationUpdates.add(settings);
    notificationSettings = settings;
    return settings;
  }

  @override
  Future<CircleDetail> getCircleDetail(String circleId) async {
    final error = detailError;
    if (error != null) {
      throw error;
    }
    return detail;
  }

  /// Thrown by [getCircleDetail] instead of returning [detail].
  Object? detailError;

  @override
  Stream<void> circleChanges(String circleId) => const Stream<void>.empty();

  @override
  Future<void> setNickname({
    required String circleId,
    required String userId,
    required String? nickname,
  }) async {
    nicknameUpdates.add((userId: userId, nickname: nickname));
  }

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
    String? categoryId,
  }) async {
    createdChannelName = name;
    createdChannelCategoryId = categoryId;
    return 'channel-2';
  }

  @override
  Future<String> createChannelCategory({
    required String circleId,
    required String name,
  }) async {
    categoryCalls.add('create $name');
    return 'category-new';
  }

  @override
  Future<void> renameChannelCategory({
    required String categoryId,
    required String name,
  }) async {
    categoryCalls.add('rename $categoryId $name');
  }

  @override
  Future<void> deleteChannelCategory(String categoryId) async {
    categoryCalls.add('delete $categoryId');
  }

  @override
  Future<void> reorderChannels({
    required String circleId,
    required CircleChannelLayout layout,
  }) async {
    reorderedLayouts.add(layout.toJson());
    final completer = reorderCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (reorderError != null) {
      throw reorderError!;
    }
  }

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) async {
    invitedMemberIds = memberIds;
  }

  @override
  Future<List<CircleSummary>> listCircles() async => circles;

  @override
  Future<String> createInvite({
    required String circleId,
    Duration? expiresIn,
    int? maxUses,
  }) async => 'invite1234';

  @override
  Future<List<CircleInvite>> listInvites(String circleId) async => const [];

  @override
  Future<void> revokeInvite(String code) async {}

  @override
  Future<CircleInvitePreview> getInvitePreview(String code) {
    throw UnimplementedError();
  }

  @override
  Future<String> acceptInvite(String code) async => 'circle-1';

  @override
  Future<String> createCircle({
    required String name,
    List<String> memberIds = const <String>[],
  }) async => 'circle-1';

  @override
  Future<String> createComment({
    required String postId,
    required String body,
  }) async => 'comment-1';

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async => 'signed';

  @override
  Future<String> createPost({
    required String circleId,
    required String body,
    ImageAttachment? image,
  }) async => 'post-1';

  @override
  Future<void> deletePost(String postId) async {}

  @override
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String details = '',
  }) async {}

  @override
  Future<void> togglePostLike({
    required String postId,
    required bool liked,
  }) async {}

  @override
  Future<ImageAttachment> uploadPostImage({
    required String circleId,
    required dynamic image,
  }) {
    throw UnimplementedError();
  }
}

Profile _profile({
  required String id,
  required String username,
  required String name,
}) {
  return Profile(
    id: id,
    username: username,
    displayName: name,
    bio: '',
    createdAt: DateTime.utc(2026, 5, 19),
    updatedAt: DateTime.utc(2026, 5, 19),
  );
}

/// Audit entries a minute apart, newest first: three handmade ones, then
/// pins up to [count].
List<CircleAuditEntry> sampleAuditEntries({
  required DateTime now,
  int count = 3,
}) {
  const ada = CircleAuditActor(
    id: 'user-1',
    username: 'ada',
    displayName: 'Ada',
  );
  const grace = CircleAuditActor(
    id: 'user-2',
    username: 'grace',
    displayName: 'Grace Hopper',
    nickname: 'Grace',
  );
  final handmade = [
    CircleAuditEntry(
      id: 'audit-0',
      circleId: 'circle-1',
      action: 'channel_create',
      targetType: 'channel',
      targetId: 'channel-1',
      targetLabel: 'general',
      changes: const {'name': 'general', 'category_id': null},
      createdAt: now.subtract(const Duration(minutes: 5)),
      actor: ada,
    ),
    CircleAuditEntry(
      id: 'audit-1',
      circleId: 'circle-1',
      action: 'role_update',
      targetType: 'role',
      targetId: 'role-1',
      targetLabel: 'Moderators of the Valley',
      changes: const {
        'name': {'old': 'Mods', 'new': 'Moderators of the Valley'},
        'color': {'old': null, 'new': 0x3498DB},
        'permissions': {'old': 1, 'new': 3},
        'hoist': {'old': false, 'new': true},
      },
      createdAt: now.subtract(const Duration(minutes: 6)),
      actor: grace,
    ),
    CircleAuditEntry(
      id: 'audit-2',
      circleId: 'circle-1',
      action: 'channel_slowmode_update',
      targetType: 'channel',
      targetId: 'channel-1',
      targetLabel: 'general',
      changes: const {
        'slowmode_seconds': {'old': 0, 'new': 120},
      },
      createdAt: now.subtract(const Duration(minutes: 7)),
      actor: ada,
    ),
  ];
  return [
    for (var index = 0; index < count; index++)
      index < handmade.length
          ? handmade[index]
          : CircleAuditEntry(
              id: 'audit-$index',
              circleId: 'circle-1',
              action: 'message_pin',
              targetType: 'message',
              targetId: 'message-$index',
              targetLabel: 'general',
              createdAt: now.subtract(Duration(minutes: 5 + index)),
              actor: ada,
            ),
  ];
}
