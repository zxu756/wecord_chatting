
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moment_card_view.dart';
import 'package:wecord/features/moments/moment_mentions.dart';
import 'package:wecord/features/moments/moment_notification_card.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'moments_compose_detail_test.dart' show typeIn;
import '../wallpapers/wallpaper_fakes.dart' show samplePhotoBytes;
import 'moments_fakes.dart';
import 'moments_screens_test.dart' show openMoments;

FakeFriendTagsRepository _tags() => FakeFriendTagsRepository(
  const FriendTagsData(
    tags: [
      FriendTag(id: 'tag-family', name: 'Family'),
      FriendTag(id: 'tag-work', name: 'Work'),
    ],
    members: {
      'tag-family': {'user-2'},
      'tag-work': {'user-3', 'user-4'},
    },
  ),
);

Profile _friend(String id, String name) => Profile(
  id: id,
  username: id,
  displayName: name,
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('models', () {
    test(
      'a Moment carries pins, reminders, descriptions and comment pictures',
      () {
        final post = MomentPost.fromJson({
          'id': 'p1',
          'author_id': 'u1',
          'author_name': 'Ada',
          'kind': 'photos',
          'photos': [
            {
              'path': 'u1/p1-0.jpg',
              'thumb': 'u1/p1-0-t.jpg',
              'w': 10,
              'h': 10,
              'alt': '  A dog asleep  ',
            },
            {'path': 'u1/p1-1.jpg', 'thumb': 'u1/p1-1-t.jpg', 'alt': 5},
          ],
          'visibility': 'friends',
          'created_at': '2026-10-20T08:00:00Z',
          'pinned_at': '2026-10-20T09:00:00Z',
          'mentioned_me': true,
          'mentions': [
            {'user_id': 'u2', 'name': 'Bob'},
          ],
          'comments': [
            {
              'id': 'c1',
              'user_id': 'u2',
              'name': 'Bob',
              'body': '',
              'created_at': '2026-10-20T08:05:00Z',
              'image': {
                'path': 'u2/c-c1.png',
                'w': 300,
                'h': 200,
                'alt': 'a cat',
              },
            },
          ],
        });
        expect(post.isPinned, isTrue);
        expect(post.mentionedMe, isTrue);
        expect(post.mentions.single.name, 'Bob');
        expect(post.photos[0].alt, 'A dog asleep');
        expect(post.photos[1].alt, isNull);
        final image = post.comments.single.image!;
        expect(image.path, 'u2/c-c1.png');
        expect(image.alt, 'a cat');
        expect(image.asPhoto.path, 'u2/c-c1.png');
        // A Moment from before 2.0 has none of it.
        final old = MomentPost.fromJson({
          'id': 'p0',
          'author_id': 'u1',
          'created_at': '2026-10-01T08:00:00Z',
        });
        expect(old.isPinned, isFalse);
        expect(old.mentionedMe, isFalse);
        expect(old.mentions, isEmpty);
      },
    );

    test('copyWith keeps the pin and can take it away', () {
      final pinned = post('p1', pinnedAt: DateTime.utc(2026, 10, 20));
      expect(pinned.copyWith(likeCount: 3).isPinned, isTrue);
      expect(pinned.copyWith(clearPin: true).isPinned, isFalse);
      expect(
        post('p2').copyWith(pinnedAt: DateTime.utc(2026)).isPinned,
        isTrue,
      );
    });

    test('notifications know reminders and picture-only comments', () {
      final reminder = MomentNotification.fromJson({
        'id': 'n1',
        'kind': 'mention',
        'post_id': 'p1',
        'actor_id': 'u1',
        'actor_name': 'Ada',
        'created_at': '2026-10-20T08:00:00Z',
        'is_unread': true,
        'has_image': false,
      });
      expect(reminder.kind, MomentNotificationKind.mention);
      final comment = MomentNotification.fromJson({
        'id': 'n2',
        'kind': 'comment',
        'post_id': 'p1',
        'actor_id': 'u2',
        'created_at': '2026-10-20T08:00:00Z',
        'has_image': true,
      });
      expect(comment.hasImage, isTrue);
    });

    test('a card tells who and the start of it', () {
      final card = MomentCardInfo.fromJson({
        'post_id': 'p1',
        'author_id': 'u1',
        'author_name': 'Ada',
        'kind': 'photos',
        'excerpt': 'North lot',
        'thumb': 'u1/p1-0-t.jpg',
        'photo_count': 3,
      });
      expect(card.kind, MomentKind.photos);
      expect(card.photoCount, 3);
    });

    test('a video can be three minutes, with half a second of slack', () {
      expect(
        maxMomentVideoDuration,
        const Duration(seconds: 180, milliseconds: 500),
      );
      expect(maxMomentMentions, 30);
      expect(maxMomentPins, 3);
    });

    test('a Moment card is a text message with the card attachment', () {
      ChatMessage message(Map<String, dynamic>? attachment) => ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        type: MessageType.text,
        body: '[Moment]',
        createdAt: DateTime.utc(2026, 10, 20),
        attachment: attachment,
      );
      expect(
        message({'kind': momentCardKind, 'post_id': 'p9'}).momentCardPostId,
        'p9',
      );
      expect(message({'kind': 'note'}).momentCardPostId, isNull);
      expect(message({'kind': momentCardKind}).momentCardPostId, isNull);
      expect(message(null).momentCardPostId, isNull);
      expect(
        message({
          'kind': momentCardKind,
          'post_id': 'p9',
        }).copyWith(recalledAt: DateTime.utc(2026)).momentCardPostId,
        isNull,
      );
    });
  });

  group('who can be reminded', () {
    final friends = [
      _friend('user-2', 'Bart'),
      _friend('user-3', 'Grace'),
      _friend('user-4', 'Linus'),
      _friend('user-5', 'Edsger'),
    ];
    const tags = FriendTagsData(
      tags: [FriendTag(id: 'work', name: 'Work')],
      members: {
        'work': {'user-3', 'user-4'},
      },
    );

    List<String> ids(MomentAudience audience) => [
      for (final friend in momentMentionCandidates(
        friends: friends,
        tags: tags,
        audience: audience,
      ))
        friend.id,
    ];

    test('all friends see a Moment for friends', () {
      expect(ids(MomentAudience.everyone), hasLength(4));
    });

    test('nobody sees a Moment for the author alone', () {
      expect(
        ids(const MomentAudience(visibility: MomentVisibility.private)),
        isEmpty,
      );
    });

    test('only the chosen friends and tags see "Only share with"', () {
      expect(
        ids(
          const MomentAudience(
            visibility: MomentVisibility.only,
            friendIds: {'user-2'},
            tagIds: {'work'},
          ),
        ),
        ['user-2', 'user-3', 'user-4'],
      );
    });

    test('everyone but the chosen see "Don\'t share with"', () {
      expect(
        ids(
          const MomentAudience(
            visibility: MomentVisibility.except,
            friendIds: {'user-2'},
            tagIds: {'work'},
          ),
        ),
        ['user-5'],
      );
    });

    test('people who can no longer see it are dropped from the choice', () {
      expect(keepMentionable({'user-2', 'user-3'}, [friends[1]]), {'user-3'});
    });

    test('the summary names two and counts the rest', () {
      expect(momentMentionSummary({}, friends), '');
      expect(momentMentionSummary({'user-2'}, friends), 'Bart');
      expect(
        momentMentionSummary({'user-2', 'user-3', 'user-4', 'user-5'}, friends),
        'Bart, Grace and 2 more',
      );
    });
  });

  group('the composer: remind who to read', () {
    Future<FakeMomentsRepository> open(WidgetTester tester) async {
      final repository = FakeMomentsRepository();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        tags: _tags(),
      );
      await typeIn(tester, 'moment-text', 'Come and see');
      return repository;
    }

    testWidgets('picks friends and posts with them', (tester) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('moment-mention')));
      await settle(tester);
      expect(find.text('Remind who to read'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('mention-friend-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(MomentMentionSheet.doneKey));
      await settle(tester);

      // The row names them.
      expect(find.textContaining('Bart'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.mentionedIds, ['user-2']);
    });

    testWidgets('a Moment for the author alone has nobody to remind', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const ValueKey('moment-mention')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-audience')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-private')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-mention')), findsNothing);
    });

    testWidgets('narrowing the audience drops who can no longer see it', (
      tester,
    ) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('moment-mention')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('mention-friend-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mention-friend-user-3')));
      await tester.pump();
      await tester.tap(find.byKey(MomentMentionSheet.doneKey));
      await settle(tester);

      // Only the Work tag (Grace and Linus) sees it now: Bart is dropped.
      await tester.tap(find.byKey(const ValueKey('moment-audience')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-only')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-tag-tag-work')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.mentionedIds, ['user-3']);
    });

    testWidgets('the list is only the friends who can see it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('moment-audience')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-only')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-tag-tag-family')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('moment-mention')));
      await settle(tester);
      // Family is Bart alone.
      expect(
        find.byKey(const ValueKey('mention-friend-user-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mention-friend-user-3')), findsNothing);
    });
  });

  group('the composer: describing photos', () {
    testWidgets('a description goes with its photo', (tester) async {
      final repository = FakeMomentsRepository();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: FakeMomentPhotoPicker(available: 2),
      );
      await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-describe')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-draft-describe-1')));
      await settle(tester);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey('pick-1')),
        '  A dog asleep on a sofa ',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);
      expect(find.text('1 of 2 described'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.photoAlts, [
        null,
        'A dog asleep on a sofa',
      ]);
    });

    testWidgets('all the photos can be described at once', (tester) async {
      final repository = FakeMomentsRepository();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: FakeMomentPhotoPicker(available: 2),
      );
      await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-describe')));
      await settle(tester);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey('pick-0')),
        'First',
      );
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey('pick-1')),
        'Second',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);
      expect(find.text('2 of 2 described'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.photoAlts, ['First', 'Second']);
    });
  });

  group('the feed', () {
    testWidgets('a described photo reads aloud its description and shows ALT', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(posts: []);
      repository.posts = [
        post(
          'p1',
          photos: [
            ...photos(repository, 'p1', 2).indexed.map(
              (entry) => MomentPhoto(
                path: entry.$2.path,
                thumb: entry.$2.thumb,
                width: 480,
                height: 320,
                alt: entry.$1 == 0 ? 'A dog asleep on a sofa' : null,
              ),
            ),
          ],
        ),
      ];
      final handle = tester.ensureSemantics();
      await openMoments(tester, repository);

      expect(find.byKey(const ValueKey('moment-photo-alt-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-photo-alt-1')), findsNothing);
      expect(
        find.bySemanticsLabel('Photo 1 of 2: A dog asleep on a sofa'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('moment-photo-alt-0')));
      await settle(tester);
      expect(find.text('Picture description'), findsOneWidget);
      expect(find.text('A dog asleep on a sofa'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'a comment that is only a sticker shows it with its description',
      (tester) async {
        final repository = FakeMomentsRepository(
          posts: [
            post(
              'p1',
              comments: [
                comment(
                  'c1',
                  'user-3',
                  'Grace Hopper',
                  '',
                  image: const MomentCommentImage(
                    path: 'user-3/c-c1.png',
                    width: 200,
                    height: 200,
                    alt: 'a thumbs up cat',
                  ),
                ),
              ],
            ),
          ],
        );
        final handle = tester.ensureSemantics();
        await openMoments(tester, repository);
        expect(
          find.byKey(const ValueKey('moment-comment-image-user-3/c-c1.png')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Grace Hopper sent a picture: a thumbs up cat'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Image: a thumbs up cat'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('a reminder is marked for the friend and named to the author', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post('p1', body: 'Look', mentionedMe: true),
          post(
            'p2',
            authorId: 'user-1',
            authorName: 'Ada Lovelace',
            body: 'Mine',
            minutesAgo: 90,
            mentions: const [
              MomentMention(userId: 'user-2', name: 'Bart'),
              MomentMention(userId: 'user-3', name: 'Grace'),
            ],
          ),
        ],
      );
      await openMoments(tester, repository);
      expect(find.text('Reminded you to read this'), findsOneWidget);
      expect(find.text('Reminded: Bart, Grace'), findsOneWidget);
    });
  });

  group('pinning', () {
    testWidgets('pins and unpins my own Moment', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          post('p1', authorId: 'user-1', authorName: 'Ada Lovelace'),
          post('p2', minutesAgo: 90),
        ],
      );
      await openMoments(tester, repository);
      // Only my own Moments can be pinned.
      expect(find.byKey(const ValueKey('moment-pin-p2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('moment-pin-p1')));
      await settle(tester);
      expect(repository.pinCalls, [('p1', true)]);
      expect(find.text('Pinned to your page'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-pin-p1')));
      await settle(tester);
      expect(repository.pinCalls.last, ('p1', false));
    });

    testWidgets('a fourth pin is refused with a reason', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [post('p1', authorId: 'user-1', authorName: 'Ada Lovelace')],
      )..pinLimit = 0;
      await openMoments(tester, repository);

      await tester.tap(find.byKey(const ValueKey('moment-pin-p1')));
      await settle(tester);
      expect(
        find.text('You can pin up to 3 Moments. Unpin one first.'),
        findsOneWidget,
      );
    });

    testWidgets('a pinned Moment is marked on its author\'s page', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'p1',
            authorId: 'user-3',
            authorName: 'Grace Hopper',
            pinnedAt: DateTime.now().toUtc(),
          ),
          post(
            'p2',
            authorId: 'user-3',
            authorName: 'Grace Hopper',
            minutesAgo: 90,
          ),
        ],
      );
      await openMoments(tester, repository, location: '/moments/of/user-3');
      expect(find.byKey(const ValueKey('moment-pinned-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-pinned-p2')), findsNothing);
    });

    testWidgets('the main feed does not mark pins', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [post('p1', pinnedAt: DateTime.now().toUtc())],
      );
      await openMoments(tester, repository);
      expect(find.byKey(const ValueKey('moment-pinned-p1')), findsNothing);
    });
  });

  group('sending a Moment to a chat', () {
    testWidgets('chooses a chat and sends the card', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);

      await tester.tap(find.byKey(const ValueKey('moment-share-p1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-share-target-dm-1')));
      await settle(tester);

      expect(repository.cardsSent, [('dm-1', 'p1')]);
      expect(find.text('Moment sent'), findsOneWidget);
    });

    testWidgets('a refused send says so and stays open', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);

      await tester.tap(find.byKey(const ValueKey('moment-share-p1')));
      await settle(tester);
      repository.failNext = Exception('offline');
      await tester.tap(find.byKey(const ValueKey('moment-share-target-dm-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-share-error')), findsOneWidget);
      expect(repository.cardsSent, isEmpty);
    });

    testWidgets('a Moment only for me has no share button', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'p1',
            authorId: 'user-1',
            authorName: 'Ada Lovelace',
            visibility: MomentVisibility.private,
          ),
        ],
      );
      await openMoments(tester, repository);
      expect(find.byKey(const ValueKey('moment-share-p1')), findsNothing);
    });
  });

  group('the card in a chat', () {
    late PhoneWorld world;
    late FakeMomentsRepository repository;

    setUp(() {
      repository = FakeMomentsRepository(posts: [post('p1')]);
      world = PhoneWorld()
        ..extraOverrides = momentsOverrides(repository: repository);
    });

    Future<void> openDirect(WidgetTester tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
    }

    void sendCard() {
      world.chats.messages = [
        phoneMessage(
          'card-1',
          bart,
          '[Moment]',
          minutesAgo: 3,
          attachment: {'kind': momentCardKind, 'post_id': 'p1'},
        ),
      ];
    }

    testWidgets('shows who and the start of the Moment, and opens it', (
      tester,
    ) async {
      repository.cardInfos['p1'] = const MomentCardInfo(
        postId: 'p1',
        authorId: 'user-2',
        authorName: 'Bart the Bold',
        kind: MomentKind.text,
        excerpt: 'Sunrise from the north lot',
      );
      sendCard();
      await openDirect(tester);

      expect(find.byKey(const ValueKey('moment-card-p1')), findsOneWidget);
      expect(find.text('Bart the Bold'), findsWidgets);
      expect(find.text('Sunrise from the north lot'), findsOneWidget);
      // The bubble does not repeat the placeholder body.
      expect(find.text('[Moment]'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('moment-card-p1')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments/p1');
      await world.close(tester);
    });

    testWidgets('a reader who may not see it gets nothing of it', (
      tester,
    ) async {
      // The server answers no row: the card holds no words of its own.
      sendCard();
      await openDirect(tester);

      expect(find.text("Can't view this Moment"), findsWidgets);
      expect(find.text('Sunrise from the north lot'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('moment-card-p1')));
      await settle(tester);
      expect(world.router.state.uri.path, isNot('/moments/p1'));
      await world.close(tester);
    });
  });

  group('a picture on a comment', () {
    Future<(FakeMomentsRepository, FakeMomentPhotoPicker)> openDetail(
      WidgetTester tester, {
      MomentCommentPicture? photo,
    }) async {
      final repository = FakeMomentsRepository(
        posts: [post('p1', body: 'Look at this')],
      );
      final picker = FakeMomentPhotoPicker()
        ..commentPhoto =
            photo ??
            MomentCommentPicture(
              bytes: samplePhotoBytes(width: 120, height: 90),
              extension: 'jpg',
              width: 120,
              height: 90,
            );
      await openMoments(
        tester,
        repository,
        location: '/moments/p1',
        picker: picker,
      );
      return (repository, picker);
    }

    testWidgets('a picture alone is enough to send', (tester) async {
      final (repository, picker) = await openDetail(tester);
      expect(
        tester
            .widget<WeCordIconButton>(
              find.byKey(const ValueKey('moment-comment-send')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('moment-comment-attach')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-attach-photo')));
      await settle(tester);
      expect(picker.commentPhotoPicks, 1);
      expect(
        find.byKey(const ValueKey('moment-comment-picture')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('moment-comment-send')));
      await settle(tester);
      expect(repository.comments.single.$2, '');
      expect(repository.commentPictures.single, isNotNull);
      // Sent: the preview is gone and the comment shows its picture.
      expect(
        find.byKey(const ValueKey('moment-comment-picture')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('moment-comment-image-user-1/c-comment-1.jpg'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the picture can be described or taken off', (tester) async {
      final (repository, _) = await openDetail(tester);
      await tester.tap(find.byKey(const ValueKey('moment-comment-attach')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-attach-photo')));
      await settle(tester);

      await tester.tap(
        find.byKey(const ValueKey('moment-comment-picture-describe')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey('comment')),
        'A cat waving',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);
      expect(find.text('A cat waving'), findsOneWidget);

      await typeIn(tester, 'moment-comment-field', 'Ha');
      await tester.tap(find.byKey(const ValueKey('moment-comment-send')));
      await settle(tester);
      expect(repository.commentPictures.single!.alt, 'A cat waving');
      expect(repository.comments.single.$2, 'Ha');

      // Another one, taken off before sending.
      await tester.tap(find.byKey(const ValueKey('moment-comment-attach')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-attach-photo')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('moment-comment-picture-remove')),
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey('moment-comment-picture')),
        findsNothing,
      );
      expect(
        tester
            .widget<WeCordIconButton>(
              find.byKey(const ValueKey('moment-comment-send')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('deleting my comment takes its picture file with it', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'p1',
            comments: [
              comment(
                'c1',
                'user-1',
                'Ada Lovelace',
                '',
                image: const MomentCommentImage(path: 'user-1/c-c1.png'),
              ),
            ],
          ),
        ],
      );
      await openMoments(tester, repository, location: '/moments/p1');
      // The name at the top of the line (the picture below opens itself).
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('moment-comment-c1'))) +
            const Offset(12, 10),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-delete')));
      await settle(tester);

      expect(repository.deletedComments, ['c1']);
      expect(repository.deletedCommentImages, ['user-1/c-c1.png']);
    });

    testWidgets(
      'someone else\'s comment is deleted without touching its file',
      (tester) async {
        final repository = FakeMomentsRepository(
          posts: [
            post(
              'p1',
              authorId: 'user-1',
              authorName: 'Ada Lovelace',
              comments: [
                comment(
                  'c1',
                  'user-3',
                  'Grace Hopper',
                  '',
                  image: const MomentCommentImage(path: 'user-3/c-c1.png'),
                ),
              ],
            ),
          ],
        );
        await openMoments(tester, repository, location: '/moments/p1');
        await tester.longPressAt(
          tester.getTopLeft(find.byKey(const ValueKey('moment-comment-c1'))) +
              const Offset(12, 10),
        );
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('comment-delete')));
        await settle(tester);

        expect(repository.deletedComments, ['c1']);
        expect(repository.deletedCommentImages, [null]);
      },
    );
  });

  group('notifications', () {
    testWidgets('a reminder reads as one, a picture-only comment says so', (
      tester,
    ) async {
      final repository = FakeMomentsRepository()
        ..notificationList = [
          MomentNotification(
            id: 'n1',
            kind: MomentNotificationKind.mention,
            postId: 'p1',
            actorId: 'user-2',
            actorName: 'Bart the Bold',
            createdAt: DateTime.now().toUtc(),
            isUnread: true,
            postExcerpt: 'Come and see',
          ),
          MomentNotification(
            id: 'n2',
            kind: MomentNotificationKind.comment,
            postId: 'p1',
            actorId: 'user-3',
            actorName: 'Grace Hopper',
            createdAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
            isUnread: false,
            hasImage: true,
          ),
        ];
      final world = PhoneWorld()
        ..extraOverrides = momentsOverrides(repository: repository);
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/notifications');
      await settle(tester);

      expect(find.byType(MomentNotificationCard), findsNWidgets(2));
      expect(
        find.textContaining(
          'reminded you to read their Moment',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('[Picture]'), findsOneWidget);
      await world.close(tester);
    });
  });
}
