import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_post_grid_card.dart';
import 'package:wecord/features/circles/circle_posts_screens.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/channel_webhook.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_ban.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_channel_overwrite.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/ui/ui.dart';

void main() {
  testWidgets('feed composer creates text posts', (tester) async {
    final repository = FakeCirclesRepository()..detail = _detail(posts: []);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.enterText(_bodyField(), 'Weekend photos');
    await tester.tap(find.byTooltip('Post'));
    await tester.pumpAndSettle();

    final call = _calls('create_circle_post').single;
    expect(call.name, 'create_circle_post');
    expect(call.params['body'], 'Weekend photos');
    expect(call.params['target_circle_id'], 'circle-1');
    expect(call.params['post_title'], isNull);
    expect(call.params['post_tags'], isEmpty);
  });

  testWidgets('feed composer sends a title and picked topics', (tester) async {
    final repository = FakeCirclesRepository()..detail = _detail(posts: []);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Title (optional)'),
      '  Lake   trip ',
    );
    await tester.enterText(_bodyField(), 'Pictures #lake');
    await tester.tap(find.byTooltip('Add topics'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a topic'),
      '#Hiking',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('#hiking'), findsOneWidget);
    await tester.tap(find.byTooltip('Post'));
    await tester.pumpAndSettle();

    final call = _calls('create_circle_post').single;
    expect(call.params['post_title'], 'Lake trip');
    expect(call.params['post_tags'], ['hiking']);
    expect(call.params['body'], 'Pictures #lake');
  });

  testWidgets('feed composer uploads image posts', (tester) async {
    final repository = FakeCirclesRepository()..detail = _detail(posts: []);
    final imagePicker = FakeImagePickerService()
      ..image = ChatImageUpload(
        bytes: Uint8List(3),
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(repository, router: router, imagePicker: imagePicker),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add image'));
    await tester.pumpAndSettle();
    await tester.enterText(_bodyField(), 'A snapshot');
    await tester.tap(find.byTooltip('Post'));
    await tester.pumpAndSettle();

    expect(repository.uploadedImageFileName, 'photo.png');
    expect(
      (_calls('create_circle_post').single.params['attachment']
          as Map<String, dynamic>)['path'],
      'circle-1/photo.png',
    );
  });

  testWidgets('post tile likes, comments, and deletes posts', (tester) async {
    final repository = FakeCirclesRepository()
      ..detail = _detail(posts: [_post(isOwnPost: true, canManagePost: true)]);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Like post'));
    await tester.pumpAndSettle();
    expect(repository.likedPostId, 'post-1');
    expect(repository.likedValue, true);

    await tester.tap(find.byTooltip('Comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Looks good');
    await tester.tap(find.widgetWithText(WeCordButton, 'Comment'));
    await tester.pumpAndSettle();
    expect(repository.commentedPostId, 'post-1');
    expect(repository.commentBody, 'Looks good');

    await tester.tap(find.byTooltip('Post actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repository.deletedPostId, 'post-1');
  });

  testWidgets('post tile reports other people posts', (tester) async {
    final repository = FakeCirclesRepository()
      ..detail = _detail(posts: [_post(isOwnPost: false)]);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Post actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(WeCordButton, 'Submit report'));
    await tester.pumpAndSettle();

    expect(repository.reportedPostId, 'post-1');
    expect(repository.reportedReason, ReportReason.spam);
  });

  group('circle posts 2.0', () {
    Future<void> openFeed(
      WidgetTester tester,
      List<CirclePost> posts, {
      String location = '/circles/circle-1',
    }) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeCirclesRepository()
        ..detail = _detail(posts: posts);
      final router = _router(location: location);
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(repository, router: router));
      await tester.pumpAndSettle();
      if (location == '/circles/circle-1') {
        await tester.tap(find.text('Feed'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a post shows its title, topics and featured mark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openFeed(tester, [
        _postV2(
          title: 'Lake trip',
          tags: ['lake', 'hiking'],
          featured: true,
          body: 'Pictures from #lake',
        ),
      ]);

      expect(find.text('Lake trip'), findsOneWidget);
      expect(find.text('#hiking'), findsWidgets);
      expect(find.text('Featured'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Featured post')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a moderator features and un-features a post', (tester) async {
      await openFeed(tester, [
        _postV2(id: 'a', canFeature: true),
        _postV2(id: 'b', canFeature: true, featured: true),
      ]);

      await tester.tap(find.byTooltip('Post actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature'));
      await tester.pumpAndSettle();
      var call = _calls('set_circle_post_featured').single;
      expect(call.params['target_post_id'], 'a');
      expect(call.params['featured'], true);

      await tester.tap(find.byTooltip('Post actions').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Featured'));
      await tester.pumpAndSettle();
      call = _calls('set_circle_post_featured').last;
      expect(call.params['target_post_id'], 'b');
      expect(call.params['featured'], false);
    });

    testWidgets('a member who cannot feature does not see the action', (
      tester,
    ) async {
      await openFeed(tester, [_postV2(canFeature: false)]);
      await tester.tap(find.byTooltip('Post actions'));
      await tester.pumpAndSettle();
      expect(find.text('Feature'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('the author edits the title, the text and the topics', (
      tester,
    ) async {
      await openFeed(tester, [
        _postV2(
          isOwn: true,
          title: 'Old title',
          tags: ['lake', 'hiking'],
          body: 'Pictures from #lake',
        ),
      ]);

      await tester.tap(find.byTooltip('Post actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      // The topic written in the text comes back from the text; only the
      // picked one is in the editor.
      expect(find.text('#hiking'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)').last,
        'New title',
      );
      await tester.tap(find.widgetWithText(WeCordButton, 'Save'));
      await tester.pumpAndSettle();

      final call = _calls('update_circle_post').single;
      expect(call.params['target_post_id'], 'post-1');
      expect(call.params['post_title'], 'New title');
      expect(call.params['body'], 'Pictures from #lake');
      expect(call.params['post_tags'], ['hiking']);
    });

    testWidgets('the filters keep the featured posts or one topic', (
      tester,
    ) async {
      await openFeed(tester, [
        _postV2(id: 'a', title: 'Alpha', tags: ['lake']),
        _postV2(id: 'b', title: 'Beta', tags: ['city'], featured: true),
      ]);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.widgetWithText(WeCordChip, 'Featured'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.widgetWithText(WeCordChip, 'All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(WeCordChip, '#lake').first);
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);

      // Pressing the chosen topic again lets go of it.
      await tester.tap(find.widgetWithText(WeCordChip, '#lake').first);
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('a filter with nothing in it says so', (tester) async {
      await openFeed(tester, [_postV2(title: 'Alpha')]);
      await tester.tap(find.widgetWithText(WeCordChip, 'Featured'));
      await tester.pumpAndSettle();
      expect(find.text('No posts match'), findsOneWidget);
    });

    testWidgets('the grid shows cards that open the post', (tester) async {
      await openFeed(tester, [
        _postV2(id: 'a', title: 'Alpha', featured: true),
        _postV2(id: 'b', title: 'Beta'),
      ]);
      await tester.tap(find.byTooltip('Grid view'));
      await tester.pumpAndSettle();
      expect(find.byType(CirclePostGridCard), findsNWidgets(2));
      expect(find.byTooltip('List view'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(find.byType(CirclePostDetailScreen), findsOneWidget);
    });

    testWidgets('the post page shows every comment', (tester) async {
      await openFeed(tester, [
        _postV2(
          id: 'a',
          title: 'Alpha',
          comments: [
            for (var i = 1; i <= 4; i++) _comment('c$i', 'Comment $i'),
          ],
        ),
      ], location: circlePostPath('circle-1', 'a'));
      for (var i = 1; i <= 4; i++) {
        expect(find.textContaining('Comment $i'), findsOneWidget);
      }
    });

    testWidgets('a post that is gone says so', (tester) async {
      await openFeed(
        tester,
        const [],
        location: circlePostPath('circle-1', 'gone'),
      );
      expect(find.text('This post is not available.'), findsOneWidget);
    });

    testWidgets('the posts page opens filtered by a topic', (tester) async {
      await openFeed(tester, [
        _postV2(id: 'a', title: 'Alpha', tags: ['lake']),
        _postV2(id: 'b', title: 'Beta', tags: ['city']),
      ], location: circlePostsPath('circle-1', tag: 'lake'));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });
  });
}

/// The calls the circle post repository made, with their parameters.
final rpcCalls = <({String name, Map<String, dynamic> params})>[];

Iterable<({String name, Map<String, dynamic> params})> _calls(String name) =>
    rpcCalls.where((call) => call.name == name);

Finder _bodyField() => find.widgetWithText(TextField, 'Share with this Circle');

Widget _app(
  FakeCirclesRepository repository, {
  required GoRouter router,
  ImagePickerService? imagePicker,
}) {
  rpcCalls.clear();
  return ProviderScope(
    overrides: [
      circlesRepositoryProvider.overrideWithValue(repository),
      circleRpcProvider.overrideWithValue((name, params) async {
        rpcCalls.add((name: name, params: params));
        return name == 'set_circle_post_featured' ? true : 'post-new';
      }),
      if (imagePicker != null)
        imagePickerServiceProvider.overrideWithValue(imagePicker),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

GoRouter _router({String location = '/circles/circle-1'}) {
  return GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/circles/:circleId',
        builder: (context, state) =>
            CircleDetailScreen(circleId: state.pathParameters['circleId']!),
        routes: [
          GoRoute(
            path: 'posts',
            builder: (context, state) => CirclePostsScreen(
              circleId: state.pathParameters['circleId']!,
              tag: state.uri.queryParameters['tag'],
              featuredOnly: state.uri.queryParameters['featured'] == '1',
            ),
            routes: [
              GoRoute(
                path: ':postId',
                builder: (context, state) => CirclePostDetailScreen(
                  circleId: state.pathParameters['circleId']!,
                  postId: state.pathParameters['postId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

CircleDetail _detail({required List<CirclePost> posts}) {
  final owner = _profile(id: 'user-1', username: 'xu', name: 'Xu');
  return CircleDetail(
    circle: const CircleSummary(
      id: 'circle-1',
      name: 'Close Friends',
      memberCount: 2,
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
    posts: posts,
  );
}

CirclePost _post({required bool isOwnPost, bool canManagePost = false}) {
  return CirclePost(
    id: 'post-1',
    circleId: 'circle-1',
    authorId: 'user-1',
    body: 'First Circle post',
    createdAt: DateTime.utc(2026, 5, 19, 1),
    updatedAt: DateTime.utc(2026, 5, 19, 1),
    author: _profile(id: 'user-1', username: 'xu', name: 'Xu'),
    comments: [
      CirclePostComment(
        id: 'comment-1',
        postId: 'post-1',
        authorId: 'user-2',
        body: 'Nice',
        createdAt: DateTime.utc(2026, 5, 19, 2),
        updatedAt: DateTime.utc(2026, 5, 19, 2),
        author: _profile(id: 'user-2', username: 'grace', name: 'Grace'),
      ),
    ],
    isOwnPost: isOwnPost,
    canManagePost: canManagePost,
    likeCount: 2,
    commentCount: 1,
  );
}

CirclePostComment _comment(String id, String body) {
  return CirclePostComment(
    id: id,
    postId: 'post-1',
    authorId: 'user-2',
    body: body,
    createdAt: DateTime.utc(2026, 5, 19, 2),
    updatedAt: DateTime.utc(2026, 5, 19, 2),
    author: _profile(id: 'user-2', username: 'grace', name: 'Grace'),
  );
}

CirclePost _postV2({
  String id = 'post-1',
  String? title,
  List<String> tags = const [],
  bool featured = false,
  bool canFeature = false,
  bool isOwn = false,
  String body = 'Some text',
  List<CirclePostComment> comments = const [],
}) {
  return CirclePost(
    id: id,
    circleId: 'circle-1',
    authorId: 'user-1',
    body: body,
    title: title,
    tags: tags,
    featuredAt: featured ? DateTime.utc(2026, 5, 20) : null,
    canFeaturePost: canFeature,
    createdAt: DateTime.utc(2026, 5, 19, 1),
    updatedAt: DateTime.utc(2026, 5, 19, 1),
    author: _profile(id: 'user-1', username: 'xu', name: 'Xu'),
    comments: comments,
    isOwnPost: isOwn,
    canManagePost: isOwn,
    likeCount: 2,
    commentCount: comments.length,
  );
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

class FakeImagePickerService implements ImagePickerService {
  ChatImageUpload? image;

  @override
  Future<ChatImageUpload?> pickImage() async => image;
}

class FakeCirclesRepository implements CirclesRepository {
  @override
  Future<List<ChannelWebhook>> listChannelWebhooks(String channelId) async =>
      const [];

  @override
  Future<ChannelWebhookSecret> createChannelWebhook({
    required String channelId,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChannelWebhook> renameChannelWebhook({
    required String webhookId,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChannelWebhookSecret> regenerateWebhookToken(String webhookId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteChannelWebhook(String webhookId) async {}

  late CircleDetail detail;
  var createdPostCircleId = '';
  var createdPostBody = '';
  ImageAttachment? createdPostImage;
  var uploadedImageFileName = '';
  var likedPostId = '';
  bool? likedValue;
  var commentedPostId = '';
  var commentBody = '';
  var deletedPostId = '';
  var reportedPostId = '';
  ReportReason? reportedReason;

  @override
  Future<void> kickMember({
    required String circleId,
    required String userId,
  }) async {}

  @override
  Future<void> leaveCircle(String circleId) async {}

  @override
  Future<List<CircleAuditEntry>> listAuditLog({
    required String circleId,
    DateTime? before,
    int limit = 50,
    String? action,
  }) async => const [];

  @override
  Future<void> transferOwnership({
    required String circleId,
    required String newOwnerId,
  }) async {}

  @override
  Future<List<CircleChannelOverwrite>> listChannelOverwrites(
    String channelId,
  ) async => const [];

  @override
  Future<void> setChannelOverwrite({
    required String channelId,
    String? roleId,
    String? userId,
    required int allow,
    required int deny,
  }) async {}

  @override
  Future<void> setChannelPrivacy({
    required String channelId,
    required bool isPrivate,
    required bool isReadOnly,
  }) async {}

  @override
  Future<void> setChannelSlowmode({
    required String channelId,
    required int seconds,
  }) async {}

  @override
  Future<void> updateChannel({
    required String channelId,
    required String name,
    String? topic,
  }) async {}

  @override
  Future<void> deleteChannel(String channelId) async {}

  @override
  Future<List<CircleEvent>> listEvents({
    required String circleId,
    bool includePast = false,
  }) async => const [];

  @override
  Future<CircleEvent> createEvent({
    required String circleId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
    Map<String, Object?>? options,
  }) => throw UnimplementedError();

  @override
  Future<CircleEvent> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required CircleEventLocationType locationType,
    String? channelId,
    String? locationText,
    required DateTime startsAt,
    DateTime? endsAt,
    Map<String, Object?>? options,
  }) => throw UnimplementedError();

  @override
  Future<CircleEvent> cancelEvent(String eventId) => throw UnimplementedError();

  @override
  Future<bool> toggleEventInterest(String eventId) =>
      throw UnimplementedError();

  @override
  Future<List<CircleEventPerson>> listEventInterested(String eventId) async =>
      const [];

  @override
  Future<List<CircleEventReminder>> listMyEventReminders() async => const [];

  @override
  Future<String> createRole({
    required String circleId,
    required String name,
    int? color,
    int permissions = 0,
    bool hoist = false,
  }) async => 'role-new';

  @override
  Future<void> updateRole({
    required String roleId,
    required String name,
    int? color,
    required int permissions,
    bool hoist = false,
  }) async {}

  @override
  Future<void> deleteRole(String roleId) async {}

  @override
  Future<void> reorderRoles({
    required String circleId,
    required List<String> roleIds,
  }) async {}

  @override
  Future<void> setMemberRoles({
    required String circleId,
    required String userId,
    required List<String> roleIds,
  }) async {}

  @override
  Future<CircleNotificationSettings> getNotificationSettings(
    String circleId,
  ) async => CircleNotificationSettings(circleId: circleId);

  @override
  Future<CircleNotificationSettings> setNotificationSettings({
    required String circleId,
    required CircleNotificationLevel level,
    DateTime? mutedUntil,
  }) async => CircleNotificationSettings(
    circleId: circleId,
    level: level,
    mutedUntil: mutedUntil,
  );

  @override
  Future<CircleDetail> getCircleDetail(String circleId) async => detail;

  @override
  Stream<void> circleChanges(String circleId) => const Stream<void>.empty();

  @override
  Future<List<ForumPost>> listForumPosts({
    required String channelId,
    ForumPostSort sort = ForumPostSort.activity,
    String? tagId,
    ForumPostCursor? before,
    int limit = 25,
  }) async => const [];

  @override
  Future<ForumPost> createForumPost({
    required String channelId,
    required String title,
    required String body,
    List<String> tagIds = const [],
    ImageAttachment? image,
    List<MessageMention> mentions = const [],
  }) => throw UnimplementedError();

  @override
  Future<ImageAttachment> uploadForumImage({
    required String forumConversationId,
    required ChatImageUpload image,
  }) => throw UnimplementedError();

  @override
  Future<void> setForumPostTags({
    required String threadId,
    required List<String> tagIds,
  }) async {}

  @override
  Future<void> pinForumPost({
    required String threadId,
    required bool pinned,
  }) async {}

  @override
  Future<String> createForumTag({
    required String channelId,
    required String name,
    String? emoji,
  }) async => 'tag-1';

  @override
  Future<void> updateForumTag({
    required String tagId,
    required String name,
    String? emoji,
  }) async {}

  @override
  Future<void> deleteForumTag(String tagId) async {}

  @override
  Future<void> reorderForumTags({
    required String channelId,
    required List<String> tagIds,
  }) async {}

  @override
  Stream<void> forumChanges({
    required String channelId,
    required String conversationId,
  }) => const Stream<void>.empty();

  @override
  Future<void> setNickname({
    required String circleId,
    required String userId,
    required String? nickname,
  }) async {}

  @override
  Future<String> createPost({
    required String circleId,
    required String body,
    ImageAttachment? image,
  }) async {
    createdPostCircleId = circleId;
    createdPostBody = body;
    createdPostImage = image;
    return 'post-2';
  }

  final bannedUserIds = <String>[];
  final unbannedUserIds = <String>[];
  final timeouts = <({String userId, Duration duration})>[];
  List<CircleBan> bans = const [];

  @override
  Future<void> banMember({
    required String circleId,
    required String userId,
    String? reason,
    int deleteMessageHours = 0,
    Duration? duration,
  }) async {
    bannedUserIds.add(userId);
  }

  @override
  Future<void> unbanMember({
    required String circleId,
    required String userId,
  }) async {
    unbannedUserIds.add(userId);
  }

  @override
  Future<List<CircleBan>> listBans(String circleId) async => bans;

  @override
  Future<DateTime?> timeoutMember({
    required String circleId,
    required String userId,
    required Duration duration,
  }) async {
    timeouts.add((userId: userId, duration: duration));
    return duration == Duration.zero ? null : DateTime.now().add(duration);
  }

  @override
  Future<ImageAttachment> uploadPostImage({
    required String circleId,
    required ChatImageUpload image,
  }) async {
    uploadedImageFileName = image.fileName;
    return ImageAttachment(
      bucket: 'chat-media',
      path: '$circleId/${image.fileName}',
      mimeType: image.mimeType,
      size: image.bytes.length,
    );
  }

  @override
  Future<void> togglePostLike({
    required String postId,
    required bool liked,
  }) async {
    likedPostId = postId;
    likedValue = liked;
  }

  @override
  Future<String> createComment({
    required String postId,
    required String body,
  }) async {
    commentedPostId = postId;
    commentBody = body;
    return 'comment-2';
  }

  @override
  Future<void> deletePost(String postId) async {
    deletedPostId = postId;
  }

  @override
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String details = '',
  }) async {
    reportedPostId = postId;
    reportedReason = reason;
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async =>
      'https://example.com/image.png';

  @override
  Future<List<CircleSummary>> listCircles() async => const [];

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
  Future<String> createChannelCategory({
    required String circleId,
    required String name,
  }) async => 'category-1';

  @override
  Future<void> renameChannelCategory({
    required String categoryId,
    required String name,
  }) async {}

  @override
  Future<void> deleteChannelCategory(String categoryId) async {}

  @override
  Future<void> reorderChannels({
    required String circleId,
    required CircleChannelLayout layout,
  }) async {}

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
    String? categoryId,
    CircleChannelKind kind = CircleChannelKind.text,
  }) async => 'channel-2';

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) async {}
}
