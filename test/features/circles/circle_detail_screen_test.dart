import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/conversation.dart';
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
            profile: _profile(id: 'user-3', username: 'amy', name: 'Amy'),
            role: 'member',
          ),
          CircleMember(
            profile: _profile(id: 'user-2', username: 'yan', name: 'Yan'),
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
      // Plain members only get the nickname entry.
      expect(find.text('Invite friends'), findsNothing);
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
              expect(extra.type, ConversationType.channel);
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

  /// Fed to [onlineUserIdsProvider] by [_app].
  var onlineUserIds = <String>{'user-1'};
  final nicknameUpdates = <({String userId, String? nickname})>[];
  CircleNotificationSettings? notificationSettings;
  final notificationUpdates = <CircleNotificationSettings>[];

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
  Future<CircleDetail> getCircleDetail(String circleId) async => detail;

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
