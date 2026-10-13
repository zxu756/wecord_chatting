import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  testWidgets('circles empty state creates a circle', (tester) async {
    final circlesRepository = FakeCirclesRepository();
    final contactsRepository = FakeContactsRepository()
      ..friends = [_profile(id: 'friend-1', username: 'ada', name: 'Ada')];
    final router = GoRouter(
      initialLocation: CirclesScreen.path,
      routes: [
        GoRoute(
          path: CirclesScreen.path,
          builder: (context, state) => const CirclesScreen(),
        ),
        GoRoute(
          path: '${CirclesScreen.path}/:circleId',
          builder: (context, state) =>
              Text('Circle ${state.pathParameters['circleId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: circlesRepository,
        contactsRepository: contactsRepository,
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Circle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsLabel('Circle name'),
      'Close Friends',
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ada'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(circlesRepository.createdCircleName, 'Close Friends');
    expect(circlesRepository.createdCircleMemberIds, ['friend-1']);
    expect(find.text('Circle circle-1'), findsOneWidget);
  });

  testWidgets('circles list opens detail route', (tester) async {
    final circlesRepository = FakeCirclesRepository()
      ..circles = [
        CircleSummary(
          id: 'circle-1',
          name: 'Close Friends',
          memberCount: 3,
          channelCount: 1,
          currentUserRole: 'owner',
        ),
      ];
    final router = GoRouter(
      initialLocation: CirclesScreen.path,
      routes: [
        GoRoute(
          path: CirclesScreen.path,
          builder: (context, state) => const CirclesScreen(),
        ),
        GoRoute(
          path: '${CirclesScreen.path}/:circleId',
          builder: (context, state) =>
              Text('Circle ${state.pathParameters['circleId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: circlesRepository,
        contactsRepository: FakeContactsRepository(),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close Friends'));
    await tester.pumpAndSettle();

    expect(find.text('Circle circle-1'), findsOneWidget);
  });

  testWidgets('join with invite accepts a pasted link', (tester) async {
    final router = _inviteRouter(inviteBuilder: (code) => Text('Invite $code'));
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: FakeCirclesRepository(),
        contactsRepository: FakeContactsRepository(),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Join with invite'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a code');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();
    expect(find.text('Enter an invite code or link'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://wecord.example/#/invite/AbCdEfGh23',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();

    expect(find.text('Invite abcdefgh23'), findsOneWidget);
  });

  testWidgets('invite page previews the circle and joins it', (tester) async {
    final repository = FakeCirclesRepository()
      ..preview = const CircleInvitePreview(
        code: 'abcdefgh23',
        alreadyMember: false,
        circle: CircleInvitePreviewCircle(
          id: 'circle-9',
          name: 'Book Club',
          memberCount: 4,
        ),
      );
    final router = _inviteRouter(
      initialLocation: '/invite/abcdefgh23',
      inviteBuilder: (code) => CircleInviteScreen(code: code),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: repository,
        contactsRepository: FakeContactsRepository(),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You have been invited to join'), findsOneWidget);
    expect(find.text('Book Club'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Join circle'));
    await tester.pumpAndSettle();

    expect(repository.previewedCodes, ['abcdefgh23']);
    expect(repository.acceptedCodes, ['abcdefgh23']);
    expect(find.text('Circle circle-9'), findsOneWidget);
  });

  testWidgets('invite page explains invalid invites', (tester) async {
    final repository = FakeCirclesRepository()
      ..preview = const CircleInvitePreview(
        code: 'abcdefgh23',
        alreadyMember: false,
        invalidReason: CircleInviteInvalidReason.expired,
      );
    final router = _inviteRouter(
      initialLocation: '/invite/abcdefgh23',
      inviteBuilder: (code) => CircleInviteScreen(code: code),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: repository,
        contactsRepository: FakeContactsRepository(),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite invalid'), findsOneWidget);
    expect(find.text('This invite has expired.'), findsOneWidget);
    expect(find.text('Join circle'), findsNothing);

    await tester.tap(find.text('Back to circles'));
    await tester.pumpAndSettle();
    expect(find.text('Circles'), findsOneWidget);
    expect(repository.acceptedCodes, isEmpty);
  });

  testWidgets('invite page opens the circle for existing members', (
    tester,
  ) async {
    final repository = FakeCirclesRepository()
      ..preview = const CircleInvitePreview(
        code: 'abcdefgh23',
        alreadyMember: true,
        invalidReason: CircleInviteInvalidReason.exhausted,
        circle: CircleInvitePreviewCircle(
          id: 'circle-9',
          name: 'Book Club',
          memberCount: 1,
        ),
      );
    final router = _inviteRouter(
      initialLocation: '/invite/abcdefgh23',
      inviteBuilder: (code) => CircleInviteScreen(code: code),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        circlesRepository: repository,
        contactsRepository: FakeContactsRepository(),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 member'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open circle'));
    await tester.pumpAndSettle();

    expect(repository.acceptedCodes, isEmpty);
    expect(find.text('Circle circle-9'), findsOneWidget);
  });

  testWidgets('invite sheet creates, copies, lists and revokes links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repository = FakeCirclesRepository()
      ..invites = [
        CircleInvite(
          code: 'oldcode234',
          circleId: 'circle-1',
          createdAt: DateTime.utc(2026, 10, 13),
          maxUses: 10,
          useCount: 3,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          circlesRepositoryProvider.overrideWithValue(repository),
          contactsRepositoryProvider.overrideWithValue(
            FakeContactsRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CircleInviteSheet(
              detail: const CircleDetail(
                circle: CircleSummary(
                  id: 'circle-1',
                  name: 'Close Friends',
                  memberCount: 1,
                  channelCount: 1,
                  currentUserRole: 'owner',
                ),
                members: [],
                channels: [],
                posts: [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite links'), findsOneWidget);
    expect(find.text('/invite/oldcode234'), findsOneWidget);
    expect(find.textContaining('3 / 10 uses'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy link'));
    await tester.pump();
    expect(clipboard.last, '/invite/oldcode234');

    await tester.tap(find.text('1 day'));
    await tester.tap(find.text('10 uses'));
    await tester.pump();
    await tester.tap(find.text('Create link'));
    await tester.pumpAndSettle();

    expect(repository.createdInvites.single, (
      circleId: 'circle-1',
      expiresIn: const Duration(days: 1),
      maxUses: 10,
    ));
    expect(clipboard.last, '/invite/newcode234');
    expect(find.text('/invite/newcode234'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('circle-invite-oldcode234')),
        matching: find.byTooltip('Revoke'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.revokedCodes, ['oldcode234']);
    expect(find.text('/invite/oldcode234'), findsNothing);
    expect(find.text('/invite/newcode234'), findsOneWidget);
  });
}

GoRouter _inviteRouter({
  required Widget Function(String code) inviteBuilder,
  String initialLocation = CirclesScreen.path,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: CirclesScreen.path,
        builder: (context, state) => const CirclesScreen(),
      ),
      GoRoute(
        path: '${CirclesScreen.path}/:circleId',
        builder: (context, state) =>
            Text('Circle ${state.pathParameters['circleId']}'),
      ),
      GoRoute(
        path: '${CircleInviteScreen.path}/:code',
        builder: (context, state) =>
            inviteBuilder(state.pathParameters['code']!),
      ),
    ],
  );
}

Widget _app({
  required FakeCirclesRepository circlesRepository,
  required FakeContactsRepository contactsRepository,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      circlesRepositoryProvider.overrideWithValue(circlesRepository),
      contactsRepositoryProvider.overrideWithValue(contactsRepository),
    ],
    child: MaterialApp.router(routerConfig: router),
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
  var circles = <CircleSummary>[];
  var details = <String, CircleDetail>{};
  var createdCircleName = '';
  var createdCircleMemberIds = <String>[];
  var invites = <CircleInvite>[];
  CircleInvitePreview? preview;
  final previewedCodes = <String>[];
  final acceptedCodes = <String>[];
  final revokedCodes = <String>[];
  final createdInvites =
      <({String circleId, Duration? expiresIn, int? maxUses})>[];

  @override
  Future<List<CircleSummary>> listCircles() async => circles;

  @override
  Future<String> createInvite({
    required String circleId,
    Duration? expiresIn,
    int? maxUses,
  }) async {
    createdInvites.add((
      circleId: circleId,
      expiresIn: expiresIn,
      maxUses: maxUses,
    ));
    const code = 'newcode234';
    invites = [
      CircleInvite(
        code: code,
        circleId: circleId,
        createdAt: DateTime.utc(2026, 10, 13, 1),
        maxUses: maxUses,
        useCount: 0,
      ),
      ...invites,
    ];
    return code;
  }

  @override
  Future<List<CircleInvite>> listInvites(String circleId) async => invites;

  @override
  Future<void> revokeInvite(String code) async {
    revokedCodes.add(code);
    invites = invites.where((invite) => invite.code != code).toList();
  }

  @override
  Future<CircleInvitePreview> getInvitePreview(String code) async {
    previewedCodes.add(code);
    return preview!;
  }

  @override
  Future<String> acceptInvite(String code) async {
    acceptedCodes.add(code);
    return preview!.circle!.id;
  }

  @override
  Future<String> createCircle({
    required String name,
    List<String> memberIds = const <String>[],
  }) async {
    createdCircleName = name;
    createdCircleMemberIds = memberIds;
    return 'circle-1';
  }

  @override
  Future<CircleDetail> getCircleDetail(String circleId) async =>
      details[circleId]!;

  @override
  Stream<void> circleChanges(String circleId) => const Stream<void>.empty();

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
  }) async => 'channel-1';

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
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) async {}

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
