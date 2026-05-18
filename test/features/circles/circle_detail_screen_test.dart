import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/circle.dart';
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
  var createdChannelName = '';
  var invitedMemberIds = <String>[];

  @override
  Future<CircleDetail> getCircleDetail(String circleId) async => detail;

  @override
  Stream<void> circleChanges(String circleId) => const Stream<void>.empty();

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
  Future<List<CircleSummary>> listCircles() async => const [];

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
