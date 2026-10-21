import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/channel_types/channel_types_repository.dart';
import 'package:wecord/features/circles/channel_types/media_wall.dart';
import 'package:wecord/features/circles/channel_types/qa_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/forum.dart';

import '../../mobile/phone_test_support.dart';
import 'channel_types_fakes.dart';

const _galleryPath = '/circles/circle-1/channels/$galleryConversationId';
const _galleryExtra = ChatThreadRouteExtra(
  title: 'photo-wall',
  type: ConversationType.channel,
  circleId: 'circle-1',
);
const _askPath = '/circles/circle-1/channels/$askConversationId';
const _askExtra = ChatThreadRouteExtra(
  title: 'ask-the-group',
  type: ConversationType.channel,
  circleId: 'circle-1',
);
const _postPath = '/circles/circle-1/channels/$askPostConversationId';
const _postExtra = ChatThreadRouteExtra(
  title: 'Why do my night photos come out so grainy?',
  type: ConversationType.thread,
  circleId: 'circle-1',
);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the models', () {
    test('the two new kinds read from the server and hold posts', () {
      expect(CircleChannelKind.fromJson('media'), CircleChannelKind.media);
      expect(CircleChannelKind.fromJson('qa'), CircleChannelKind.qa);
      expect(CircleChannelKind.media.value, 'media');
      expect(CircleChannelKind.qa.value, 'qa');
      // Unknown kinds from newer servers still read as text.
      expect(CircleChannelKind.fromJson('gallery'), CircleChannelKind.text);

      CircleChannel channel(CircleChannelKind kind) => CircleChannel(
        id: 'c',
        circleId: 'circle',
        conversationId: 'conv',
        name: 'n',
        position: 0,
        kind: kind,
      );
      for (final kind in [
        CircleChannelKind.forum,
        CircleChannelKind.media,
        CircleChannelKind.qa,
      ]) {
        expect(channel(kind).isForum, isTrue, reason: kind.value);
        expect(channel(kind).isTextLike, isFalse, reason: kind.value);
        expect(channel(kind).isVoice, isFalse, reason: kind.value);
      }
      expect(channel(CircleChannelKind.media).isMedia, isTrue);
      expect(channel(CircleChannelKind.media).isQa, isFalse);
      expect(channel(CircleChannelKind.qa).isQa, isTrue);
      expect(channel(CircleChannelKind.forum).isMedia, isFalse);
      expect(channel(CircleChannelKind.text).isForum, isFalse);
      expect(channel(CircleChannelKind.announcement).isForum, isFalse);
    });

    test('a post carries its solved mark', () {
      final solved = ForumPost.fromJson({
        'id': 'p',
        'conversation_id': 'pc',
        'channel_id': 'ch',
        'title': 'Q',
        'created_at': '2026-10-21T08:00:00Z',
        'solved_at': '2026-10-21T09:00:00Z',
        'solved_message_id': 'm-2',
      });
      expect(solved.isSolved, isTrue);
      expect(solved.solvedMessageId, 'm-2');
      expect(solved.solvedAt, DateTime.utc(2026, 10, 21, 9));

      final open = ForumPost.fromJson({
        'id': 'p',
        'conversation_id': 'pc',
        'channel_id': 'ch',
        'title': 'Q',
        'created_at': '2026-10-21T08:00:00Z',
        'solved_at': null,
        'solved_message_id': null,
      });
      expect(open.isSolved, isFalse);
      expect(open.solvedMessageId, isNull);
    });

    test('the state of a question', () {
      final state = QaPostState.fromJson({
        'thread_id': 't',
        'channel_id': 'ch',
        'circle_id': 'ci',
        'solved': true,
        'solved_at': '2026-10-21T09:00:00Z',
        'answer_message_id': 'm-2',
        'opening_message_id': 'm-1',
        'can_mark': true,
      });
      expect(state.solved && state.canMark, isTrue);
      expect(state.isAnswer('m-2'), isTrue);
      expect(state.isAnswer('m-1'), isFalse);
      final bare = QaPostState.fromJson({'thread_id': 't'});
      expect(bare.solved || bare.canMark, isFalse);
      expect(bare.answerMessageId, isNull);
    });

    test('the status filter names what the server expects', () {
      expect(
        [for (final s in QaStatusFilter.values) s.value],
        ['all', 'unsolved', 'solved'],
      );
    });

    test('a wall has two columns on a phone and at most six', () {
      expect(mediaWallColumns(340), 2);
      expect(mediaWallColumns(500), 2);
      expect(mediaWallColumns(700), 4);
      expect(mediaWallColumns(1200), 6);
      expect(mediaWallColumns(3000), 6);
    });
  });

  group('the repository', () {
    test('asks for the state of a post', () async {
      final rpc = QaRpc();
      final repository = ChannelTypesRepository(rpc.call);
      final state = await repository.postState(askPostConversationId);
      expect(state?.canMark, isTrue);
      expect(rpc.paramsOf('get_qa_post_state').single, {
        'target_conversation_id': askPostConversationId,
      });
      expect(await repository.postState('another'), isNull);
    });

    test('marks a question solved with its answer, and reopens it', () async {
      final rpc = QaRpc();
      final repository = ChannelTypesRepository(rpc.call);
      var state = await repository.markSolved(
        askPostId,
        answerMessageId: askAnswerId,
      );
      expect(state?.solved, isTrue);
      expect(state?.answerMessageId, askAnswerId);
      expect(rpc.paramsOf('mark_post_solved').single, {
        'target_thread_id': askPostId,
        'answer_message_id': askAnswerId,
      });
      state = await repository.reopen(askPostId);
      expect(state?.solved, isFalse);
      expect(rpc.paramsOf('reopen_qa_post').single, {
        'target_thread_id': askPostId,
      });
      await repository.markSolved(askPostId);
      expect(
        rpc.paramsOf('mark_post_solved').last['answer_message_id'],
        isNull,
      );
    });

    test('lists questions with a status and a cursor', () async {
      final rpc = QaRpc();
      final repository = ChannelTypesRepository(rpc.call);
      final solved = await repository.listPosts(
        channelId: askChannelId,
        status: QaStatusFilter.solved,
        sort: ForumPostSort.created,
        tagId: 'tag-1',
        before: ForumPostCursor(at: DateTime.utc(2026, 10, 20), id: 'p-9'),
        limit: 10,
      );
      expect(solved.map((p) => p.id), ['q-solved']);
      expect(solved.single.isSolved, isTrue);
      expect(rpc.paramsOf('list_qa_posts').single, {
        'target_channel_id': askChannelId,
        'sort_order': 'created',
        'filter_tag_id': 'tag-1',
        'filter_status': 'solved',
        'before_at': '2026-10-20T00:00:00.000Z',
        'before_id': 'p-9',
        'limit_count': 10,
      });
      final open = await repository.listPosts(
        channelId: askChannelId,
        status: QaStatusFilter.unsolved,
      );
      expect(open.map((p) => p.id), ['q-rules', askPostId]);
    });
  });

  group('a media channel', () {
    testWidgets('lists its posts as a wall of pictures', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      expect(find.byKey(const ValueKey('media-wall')), findsOneWidget);
      expect(find.byKey(const ValueKey('forum-post-list')), findsNothing);
      for (final id in ['pic-pinned', 'pic-1', 'pic-2', 'pic-3', 'pic-4']) {
        expect(
          find.byKey(ValueKey('media-post-$id')),
          findsOneWidget,
          reason: id,
        );
      }
      // Pinned first; the unread and the pinned posts say so.
      expect(find.byKey(const ValueKey('media-wall-pinned')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-wall-unread')), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('Monthly theme: golden hour'), findsOneWidget);
      expect(find.byKey(const ValueKey('forum-new-post')), findsOneWidget);
      expect(find.text('Your best shots from the trail.'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a tile reads out the title, the author and the picture', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Sunrise over Half Dome.*, Posted by Grace.*, 14 replies, Unread, '
            r'Pink clouds over a granite dome$',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
      await world.close(tester);
    });

    testWidgets('opens a post from its tile', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      await tester.tap(find.byKey(const ValueKey('media-post-pic-2')));
      await settle(tester);
      expect(find.byKey(const ValueKey('media-wall')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-thread-header')),
          matching: find.text('Night sky from Glacier Point'),
        ),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a tile\'s menu pins and archives, like a forum post', (
      tester,
    ) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('media-post-pic-1')),
          matching: find.byKey(const ValueKey('media-wall-options')),
        ),
      );
      await settle(tester);
      expect(find.text('Pin post'), findsOneWidget);
      expect(find.text('Edit tags'), findsOneWidget);
      expect(find.text('Archive post'), findsOneWidget);
      // Nothing Q&A about a picture wall.
      expect(find.text('Mark as solved'), findsNothing);
      await tester.tap(find.text('Pin post'));
      await settle(tester);
      expect(world.circles.forumCalls.last, 'pin pic-1 true');
      await world.close(tester);
    });

    testWidgets('a post needs a picture, and can describe it', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      world.imagePicker.nextImage = ChatImageUpload(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        fileName: 'kite.png',
        mimeType: 'image/png',
      );
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      await tester.tap(find.byKey(const ValueKey('forum-new-post')));
      await settle(tester);
      expect(find.text('Add picture'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('forum-post-title-field')),
        'Kite day',
      );
      await tester.enterText(
        find.byKey(const ValueKey('forum-post-body-field')),
        'Windy at the pier',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forum-post-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
      await settle(tester);
      // Words are not enough in a media channel.
      expect(find.text('Add a picture to post here.'), findsOneWidget);
      expect(world.circles.createdForumPosts, isEmpty);

      await tester.tap(find.byKey(const ValueKey('forum-post-add-image')));
      await settle(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('forum-post-image-alt-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forum-post-image-alt-field')),
        '  A red kite over the pier  ',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forum-post-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
      await settle(tester);

      final created = world.circles.createdForumPosts.single;
      expect(created.title, 'Kite day');
      expect(created.hasImage, isTrue);
      expect(world.circles.lastForumImage?.alt, 'A red kite over the pier');
      expect(
        world.circles.forumCalls.single,
        'upload $galleryConversationId kite.png',
      );
      await world.close(tester);
    });

    testWidgets('a picture without a description is sent without one', (
      tester,
    ) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      world.imagePicker.nextImage = ChatImageUpload(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        fileName: 'plain.png',
        mimeType: 'image/png',
      );
      await world.open(tester, _galleryPath, extra: _galleryExtra);

      await tester.tap(find.byKey(const ValueKey('forum-new-post')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('forum-post-title-field')),
        'Plain',
      );
      await tester.tap(find.byKey(const ValueKey('forum-post-add-image')));
      await settle(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('forum-post-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('forum-post-submit')));
      await settle(tester);
      expect(world.circles.lastForumImage, isNotNull);
      expect(world.circles.lastForumImage?.alt, isNull);
      await world.close(tester);
    });

    testWidgets('an empty wall says so and offers the first picture', (
      tester,
    ) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      world.circles.forumPosts = [
        for (final post in world.circles.forumPosts)
          if (post.channelId != galleryChannelId) post,
      ];
      await world.open(tester, _galleryPath, extra: _galleryExtra);
      expect(find.text('No pictures yet'), findsOneWidget);
      expect(
        find.text('Share the first picture with New post.'),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a read-only wall offers no new post', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      // Viewing, reacting and nothing else.
      world.circles.detail = circleDetailWithChannelTypes(
        permissions: CirclePermission.viewChannel.bit,
      );
      await world.open(tester, _galleryPath, extra: _galleryExtra);
      expect(find.byKey(const ValueKey('forum-new-post')), findsNothing);
      expect(find.byKey(const ValueKey('forum-read-only')), findsOneWidget);
      expect(
        find.text('You cannot post in this media channel.'),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });

  group('a Q&A channel', () {
    testWidgets('lists questions and marks the solved ones', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _askPath, extra: _askExtra);

      expect(find.byKey(const ValueKey('forum-post-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('qa-status-filters')), findsOneWidget);
      expect(find.text('Gear, trips and technique questions.'), findsOneWidget);
      expect(find.text('Ask a question'), findsOneWidget);
      expect(find.byKey(const ValueKey('qa-solved-badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('forum-post-q-solved')),
          matching: find.byKey(const ValueKey('qa-solved-badge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('forum-post-$askPostId')),
          matching: find.byKey(const ValueKey('qa-solved-badge')),
        ),
        findsNothing,
      );
      await world.close(tester);
    });

    testWidgets('the status chips ask the server for the solved or open ones', (
      tester,
    ) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world);
      await world.open(tester, _askPath, extra: _askExtra);
      expect(qa.paramsOf('list_qa_posts').last['filter_status'], 'all');

      await tester.tap(find.byKey(const ValueKey('qa-status-solved')));
      await settle(tester);
      expect(qa.paramsOf('list_qa_posts').last['filter_status'], 'solved');
      expect(find.text('Which lens for the Milky Way?'), findsOneWidget);
      expect(
        find.text('Why do my night photos come out so grainy?'),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('qa-status-unsolved')));
      await settle(tester);
      expect(qa.paramsOf('list_qa_posts').last['filter_status'], 'unsolved');
      expect(find.text('Which lens for the Milky Way?'), findsNothing);
      expect(
        find.text('Why do my night photos come out so grainy?'),
        findsOneWidget,
      );

      qa.posts = [];
      await tester.tap(find.byKey(const ValueKey('qa-status-solved')));
      await settle(tester);
      expect(find.text('No solved questions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qa-status-unsolved')));
      await settle(tester);
      expect(find.text('No open questions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qa-status-all')));
      await settle(tester);
      expect(find.text('No questions yet'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a question\'s menu marks it solved or opens it again', (
      tester,
    ) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world);
      await world.open(tester, _askPath, extra: _askExtra);

      Finder optionsOf(String id) => find.descendant(
        of: find.byKey(ValueKey('forum-post-$id')),
        matching: find.byTooltip('Post options'),
      );

      await tester.tap(optionsOf(askPostId));
      await settle(tester);
      expect(find.text('Reopen question'), findsNothing);
      await tester.tap(find.text('Mark as solved'));
      await settle(tester);
      expect(qa.paramsOf('mark_post_solved').single, {
        'target_thread_id': askPostId,
        'answer_message_id': null,
      });

      await tester.tap(optionsOf('q-solved'));
      await settle(tester);
      expect(find.text('Mark as solved'), findsNothing);
      await tester.tap(find.text('Reopen question'));
      await settle(tester);
      expect(qa.paramsOf('reopen_qa_post').single, {
        'target_thread_id': 'q-solved',
      });
      await world.close(tester);
    });

    testWidgets('asking opens a question form', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, _askPath, extra: _askExtra);
      await tester.tap(find.byKey(const ValueKey('forum-new-post')));
      await settle(tester);
      expect(find.text('Ask in ask-the-group'), findsOneWidget);
      expect(find.text('Question'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      // A picture is optional here, and there is no description field
      // before one is chosen.
      expect(find.text('Add image'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('forum-post-image-alt-field')),
        findsNothing,
      );
      await world.close(tester);
    });

    testWidgets('a failing server leaves the list as it was', (tester) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world);
      await world.open(tester, _askPath, extra: _askExtra);
      qa.failing.add('mark_post_solved');
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('forum-post-$askPostId')),
          matching: find.byTooltip('Post options'),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Mark as solved'));
      await settle(tester);
      expect(
        find.text('Could not mark the question solved. Try again.'),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });

  group('a question\'s page', () {
    Future<(PhoneWorld, QaRpc)> open(
      WidgetTester tester, {
      bool canMark = true,
    }) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world, canMark: canMark);
      await world.open(tester, _postPath, extra: _postExtra);
      return (world, qa);
    }

    testWidgets('the asker accepts an answer and it is marked', (tester) async {
      final (world, qa) = await open(tester);
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsNothing);

      await tester.longPress(find.textContaining('Try ISO 3200'));
      await settle(tester);
      expect(find.text('Accept as answer'), findsOneWidget);
      await tester.tap(find.text('Accept as answer'));
      await settle(tester);

      expect(qa.paramsOf('mark_post_solved').single, {
        'target_thread_id': askPostId,
        'answer_message_id': askAnswerId,
      });
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsOneWidget);
      expect(find.text('Accepted answer'), findsOneWidget);

      // The accepted answer offers to take the mark off, which reopens the
      // question; the other answer offers to take the mark.
      await tester.longPress(find.textContaining('Try ISO 3200'));
      await settle(tester);
      expect(find.text('Remove accepted answer'), findsOneWidget);
      await tester.tap(find.text('Remove accepted answer'));
      await settle(tester);
      expect(qa.paramsOf('reopen_qa_post').single, {
        'target_thread_id': askPostId,
      });
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsNothing);
      await world.close(tester);
    });

    testWidgets('another answer takes the mark over', (tester) async {
      final (world, qa) = await open(tester);
      await tester.longPress(find.textContaining('Try ISO 3200'));
      await settle(tester);
      await tester.tap(find.text('Accept as answer'));
      await settle(tester);
      await tester.longPress(find.textContaining('Stack five frames'));
      await settle(tester);
      expect(find.text('Accept as answer'), findsOneWidget);
      await tester.tap(find.text('Accept as answer'));
      await settle(tester);
      expect(
        qa.paramsOf('mark_post_solved').last['answer_message_id'],
        askOtherAnswerId,
      );
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('the question itself cannot be its own answer', (tester) async {
      final (world, _) = await open(tester);
      await tester.longPress(find.textContaining('Shot at ISO 6400'));
      await settle(tester);
      expect(find.text('Accept as answer'), findsNothing);
      await world.close(tester);
    });

    testWidgets('someone who cannot mark the question is offered nothing', (
      tester,
    ) async {
      final (world, _) = await open(tester, canMark: false);
      await tester.longPress(find.textContaining('Try ISO 3200'));
      await settle(tester);
      expect(find.text('Accept as answer'), findsNothing);
      expect(find.text('Reply'), findsWidgets);
      await world.close(tester);
    });

    testWidgets('the accepted answer is marked for everyone', (tester) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world, canMark: false)
        ..solved = true
        ..answerMessageId = askAnswerId;
      expect(qa.state['solved'], isTrue);
      await world.open(tester, _postPath, extra: _postExtra);
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a failure says so and keeps the page as it was', (
      tester,
    ) async {
      final (world, qa) = await open(tester);
      qa.failing.add('mark_post_solved');
      await tester.longPress(find.textContaining('Try ISO 3200'));
      await settle(tester);
      await tester.tap(find.text('Accept as answer'));
      await settle(tester);
      expect(
        find.text('Could not change the accepted answer. Try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsNothing);
      await world.close(tester);
    });

    /// A wide window on a desktop platform, where the header has a More
    /// button, for the length of the test.
    void wideTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(
            tester,
            const PhoneViewport(
              name: 'desktop',
              size: Size(1440, 900),
              devicePixelRatio: 1,
            ),
          );
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    wideTest('the header marks the question solved and opens it again', (
      tester,
    ) async {
      final (world, qa) = await open(tester);
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await settle(tester);
      expect(find.text('Reopen question'), findsNothing);
      await tester.tap(find.text('Mark as solved'));
      await settle(tester);
      expect(qa.paramsOf('mark_post_solved').single, {
        'target_thread_id': askPostId,
        'answer_message_id': null,
      });
      expect(find.text('Marked as solved.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await settle(tester);
      expect(find.text('Mark as solved'), findsNothing);
      await tester.tap(find.text('Reopen question'));
      await settle(tester);
      expect(qa.paramsOf('reopen_qa_post').single, {
        'target_thread_id': askPostId,
      });
      await world.close(tester);
    });

    wideTest('someone who cannot mark it has no such entry', (tester) async {
      final (world, _) = await open(tester, canMark: false);
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await settle(tester);
      expect(find.text('Mark as solved'), findsNothing);
      expect(find.text('Reopen question'), findsNothing);
      await world.close(tester);
    });

    wideTest('an ordinary forum post has none of it', (tester) async {
      final world = PhoneWorld();
      final qa = addChannelTypes(world);
      world.chats.messages = forumPostMessages();
      await world.open(
        tester,
        '/circles/circle-1/channels/post-conv-1',
        extra: const ChatThreadRouteExtra(
          title: forumPostTitle,
          type: ConversationType.thread,
          circleId: 'circle-1',
        ),
      );
      // The page asked, and was told it is no Q&A post.
      expect(
        qa.paramsOf('get_qa_post_state').single['target_conversation_id'],
        'post-conv-1',
      );
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await settle(tester);
      expect(find.text('Mark as solved'), findsNothing);
      expect(find.text('Reopen question'), findsNothing);
      expect(find.byKey(const ValueKey('qa-accepted-answer')), findsNothing);
      await world.close(tester);
    });
  });

  group('the channel sheet and lists', () {
    testWidgets('offers the two kinds when creating a channel', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      await world.open(tester, '/circles/circle-1');
      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      await tester.ensureVisible(find.text('Create channel'));
      await settle(tester);
      await tester.tap(find.text('Create channel'));
      await settle(tester);

      expect(find.text('Media'), findsWidgets);
      expect(find.text('Q&A'), findsWidgets);
      expect(
        find.text('A wall of pictures: every post needs a picture.'),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('the channel list shows their icons', (tester) async {
      final world = PhoneWorld();
      addChannelTypes(world);
      usePhoneViewport(
        tester,
        const PhoneViewport(
          name: 'desktop',
          size: Size(1400, 900),
          devicePixelRatio: 1,
        ),
      );
      await world.open(tester, '/circles/circle-1');
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('circle-channel-row-$galleryChannelId'),
          ),
          matching: find.byIcon(Icons.photo_library_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('circle-channel-row-$askChannelId')),
          matching: find.byIcon(Icons.help_outline_rounded),
        ),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });
}
