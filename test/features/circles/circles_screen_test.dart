import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
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

  @override
  Future<List<CircleSummary>> listCircles() async => circles;

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
