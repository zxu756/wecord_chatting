import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  testWidgets('circle detail opens channel threads', (tester) async {
    final repository = FakeCirclesRepository()..detail = _detail();
    final router = GoRouter(
      initialLocation: '/circles/circle-1',
      routes: [
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) =>
              CircleDetailScreen(circleId: state.pathParameters['circleId']!),
        ),
        GoRoute(
          path: '${ChatsScreen.path}/:conversationId',
          builder: (context, state) =>
              Text('Thread ${state.pathParameters['conversationId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, FakeContactsRepository(), router));
    await tester.pumpAndSettle();

    expect(find.text('Close Friends'), findsOneWidget);
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conversation-1'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Create channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Channel name'), 'photos');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(repository.createdChannelName, 'photos');

    await tester.tap(find.byTooltip('Invite friends'));
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

    await tester.tap(find.text('TEXT CHANNELS'));
    await tester.pumpAndSettle();
    expect(find.text('general'), findsNothing);
    expect(find.text('photos'), findsOneWidget);

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

    expect(repository.presenceRequests, contains('circle-1'));
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

    await tester.tap(find.byTooltip('Notification settings'));
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
}

Widget _app(
  FakeCirclesRepository circlesRepository,
  FakeContactsRepository contactsRepository,
  GoRouter router,
) {
  return ProviderScope(
    overrides: [
      circlesRepositoryProvider.overrideWithValue(circlesRepository),
      contactsRepositoryProvider.overrideWithValue(contactsRepository),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
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
  var invitedMemberIds = <String>[];
  var onlineUserIds = <String>{'user-1'};
  final presenceRequests = <String>[];
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
  Stream<Set<String>> circlePresence(String circleId) {
    presenceRequests.add(circleId);
    return Stream<Set<String>>.value(onlineUserIds);
  }

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
  }) async {
    createdChannelName = name;
    return 'channel-2';
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
