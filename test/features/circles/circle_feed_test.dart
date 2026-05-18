import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  testWidgets('feed composer creates text posts', (tester) async {
    final repository = FakeCirclesRepository()..detail = _detail(posts: []);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Weekend photos');
    await tester.tap(find.byTooltip('Post'));
    await tester.pumpAndSettle();

    expect(repository.createdPostBody, 'Weekend photos');
    expect(repository.createdPostCircleId, 'circle-1');
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
    await tester.enterText(find.byType(TextField).first, 'A snapshot');
    await tester.tap(find.byTooltip('Post'));
    await tester.pumpAndSettle();

    expect(repository.uploadedImageFileName, 'photo.png');
    expect(repository.createdPostImage?.path, 'circle-1/photo.png');
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
    await tester.enterText(find.bySemanticsLabel('Comment'), 'Looks good');
    await tester.tap(find.widgetWithText(FilledButton, 'Comment'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
    await tester.pumpAndSettle();

    expect(repository.reportedPostId, 'post-1');
    expect(repository.reportedReason, ReportReason.spam);
  });
}

Widget _app(
  FakeCirclesRepository repository, {
  required GoRouter router,
  ImagePickerService? imagePicker,
}) {
  return ProviderScope(
    overrides: [
      circlesRepositoryProvider.overrideWithValue(repository),
      if (imagePicker != null)
        imagePickerServiceProvider.overrideWithValue(imagePicker),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/circles/circle-1',
    routes: [
      GoRoute(
        path: '/circles/:circleId',
        builder: (context, state) =>
            CircleDetailScreen(circleId: state.pathParameters['circleId']!),
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
  Future<CircleDetail> getCircleDetail(String circleId) async => detail;

  @override
  Stream<void> circleChanges(String circleId) => const Stream<void>.empty();

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
  Future<String> createCircle({
    required String name,
    List<String> memberIds = const <String>[],
  }) async => 'circle-1';

  @override
  Future<String> createChannel({
    required String circleId,
    required String name,
  }) async => 'channel-2';

  @override
  Future<void> inviteMembers({
    required String circleId,
    required List<String> memberIds,
  }) async {}
}
