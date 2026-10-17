import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
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

Future<void> typeIn(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

void main() {
  group('the composer', () {
    testWidgets('posting needs something to say, then posts text', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      await openMoments(tester, repository, location: '/moments/compose');

      WeCordButton postButton() => tester.widget<WeCordButton>(
        find.byKey(const ValueKey('moment-post')),
      );
      expect(postButton().onPressed, isNull);

      await typeIn(tester, 'moment-text', '   ');
      expect(postButton().onPressed, isNull);
      await typeIn(tester, 'moment-text', 'First light on the ridge');
      expect(postButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      final created = repository.created.single;
      expect(created.body, 'First light on the ridge');
      expect(created.photoCount, 0);
      expect(created.audience, MomentAudience.everyone);
      // Back on the feed, with the new post at the top.
      expect(find.text('First light on the ridge'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-text')), findsNothing);
    });

    testWidgets('adds up to nine photos, removes one, and posts them', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker(available: 4);
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );

      await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-draft-3')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-draft-remove-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-draft-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-draft-3')), findsNothing);

      // Photos alone are enough, and no link goes with them.
      expect(find.byKey(const ValueKey('moment-add-link')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      final created = repository.created.single;
      expect(created.photoCount, 3);
      expect(created.body, isEmpty);
      // The full picture and its thumbnail were both uploaded.
      expect(repository.bucket.length, 6);
    });

    testWidgets('stops at nine photos', (tester) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker(available: 20);
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        picker: picker,
      );

      await tester.tap(find.byKey(const ValueKey('moment-add-photos')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-draft-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-draft-9')), findsNothing);
      // Full: the add tile is gone.
      expect(find.byKey(const ValueKey('moment-add-photos')), findsNothing);
    });

    testWidgets(
      'a link needs a web address; photos and links exclude each other',
      (tester) async {
        final repository = FakeMomentsRepository();
        await openMoments(tester, repository, location: '/moments/compose');

        await tester.tap(find.byKey(const ValueKey('moment-add-link')));
        await settle(tester);
        // The photo strip makes way for the link fields.
        expect(find.byKey(const ValueKey('moment-add-photos')), findsNothing);

        await typeIn(tester, 'moment-link-field', 'not a link');
        expect(
          find.text('Enter a web address starting with https://'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<WeCordButton>(find.byKey(const ValueKey('moment-post')))
              .onPressed,
          isNull,
        );

        await typeIn(tester, 'moment-link-field', 'https://example.com/trail');
        await typeIn(tester, 'moment-link-title-field', 'Trail map');
        await tester.tap(find.byKey(const ValueKey('moment-post')));
        await settle(tester);

        final created = repository.created.single;
        expect(created.linkUrl, 'https://example.com/trail');
        expect(created.linkTitle, 'Trail map');
      },
    );

    testWidgets('adds a place', (tester) async {
      final repository = FakeMomentsRepository();
      await openMoments(tester, repository, location: '/moments/compose');

      await typeIn(tester, 'moment-text', 'Coffee');
      await tester.tap(find.byKey(const ValueKey('moment-add-location')));
      await settle(tester);
      await typeIn(tester, 'moment-location-field', 'Lisbon');
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      expect(repository.created.single.location, 'Lisbon');
    });

    testWidgets('a failed post says so and keeps the draft', (tester) async {
      final repository = FakeMomentsRepository()
        ..failNext = Exception('offline');
      await openMoments(tester, repository, location: '/moments/compose');

      await typeIn(tester, 'moment-text', 'Will retry');
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      expect(find.byKey(const ValueKey('moment-error')), findsOneWidget);
      expect(repository.created, isEmpty);
      expect(find.text('Will retry'), findsOneWidget);

      // Trying again works, with the same id.
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.body, 'Will retry');
    });
  });

  group('who can see it', () {
    Future<FakeMomentsRepository> openComposer(WidgetTester tester) async {
      final repository = FakeMomentsRepository();
      await openMoments(
        tester,
        repository,
        location: '/moments/compose',
        tags: _tags(),
      );
      await typeIn(tester, 'moment-text', 'Quiet news');
      return repository;
    }

    Future<void> openAudience(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('moment-audience')));
      await settle(tester);
    }

    testWidgets('offers friends, only me, only share with, don\'t share with', (
      tester,
    ) async {
      await openComposer(tester);
      await openAudience(tester);

      for (final key in ['friends', 'private', 'only', 'except']) {
        expect(find.byKey(ValueKey('audience-$key')), findsOneWidget);
      }
      expect(find.text('Only me'), findsOneWidget);
      expect(find.text('Only share with'), findsOneWidget);
      expect(find.text("Don't share with"), findsOneWidget);
    });

    testWidgets('private posts for the author only', (tester) async {
      final repository = await openComposer(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-private')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);

      expect(find.text('Only me'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(
        repository.created.single.audience.visibility,
        MomentVisibility.private,
      );
    });

    testWidgets('only share with: needs a choice, takes friends and tags', (
      tester,
    ) async {
      final repository = await openComposer(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-only')));
      await settle(tester);

      // Nothing chosen yet: Done waits.
      expect(find.byKey(const ValueKey('audience-incomplete')), findsOneWidget);
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('audience-done')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('audience-tag-tag-family')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('audience-friend-user-4')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-friend-user-4')));
      await tester.pump();
      expect(find.byKey(const ValueKey('audience-incomplete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);

      // The line names the tag and the friend.
      expect(find.textContaining('Only: Family, Linus'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      final audience = repository.created.single.audience;
      expect(audience.visibility, MomentVisibility.only);
      expect(audience.tagIds, {'tag-family'});
      expect(audience.friendIds, {'user-4'});
    });

    testWidgets('don\'t share with: hides from tags and friends', (
      tester,
    ) async {
      final repository = await openComposer(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-except')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-tag-tag-work')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);

      expect(find.textContaining('Not: Work'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      final audience = repository.created.single.audience;
      expect(audience.visibility, MomentVisibility.except);
      expect(audience.tagIds, {'tag-work'});
    });

    testWidgets('switching back to friends drops the lists', (tester) async {
      final repository = await openComposer(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-only')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('audience-friend-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-friends')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('audience-friend-user-2')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);

      // The lists are only sent for the modes that use them.
      expect(repository.created.single.audience.usesLists, isFalse);
    });
  });

  group('a post and its comments', () {
    FakeMomentsRepository repositoryWithComments() {
      final repository = FakeMomentsRepository();
      repository.posts = [
        post(
          'p1',
          body: 'The summit at dawn',
          photos: photos(repository, 'p1', 3),
          location: 'Serra da Estrela',
          likes: const [MomentLiker(userId: 'user-3', name: 'Grace Hopper')],
          comments: [
            comment('c1', 'user-3', 'Grace Hopper', 'Gorgeous light'),
            comment('c2', 'user-1', 'Ada Lovelace', 'Thanks, it was cold'),
          ],
        ),
      ];
      return repository;
    }

    testWidgets('shows the text, place, photos and every comment', (
      tester,
    ) async {
      await openMoments(
        tester,
        repositoryWithComments(),
        location: '/moments/p1',
      );

      expect(find.text('The summit at dawn'), findsOneWidget);
      expect(find.text('Serra da Estrela'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-photo-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-c2')), findsOneWidget);
    });

    testWidgets('writes a comment', (tester) async {
      final repository = repositoryWithComments();
      await openMoments(tester, repository, location: '/moments/p1');

      expect(
        tester
            .widget<WeCordIconButton>(
              find.byKey(const ValueKey('moment-comment-send')),
            )
            .onPressed,
        isNull,
      );
      await typeIn(tester, 'moment-comment-field', 'Wish I was there');
      await tester.tap(find.byKey(const ValueKey('moment-comment-send')));
      await settle(tester);

      expect(repository.comments, [('p1', 'Wish I was there', null)]);
      expect(find.text(': Wish I was there', findRichText: true), findsNothing);
      expect(
        find.textContaining('Wish I was there', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('moment-comment-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('tapping a friend\'s comment replies to it', (tester) async {
      final repository = repositoryWithComments();
      await openMoments(tester, repository, location: '/moments/p1');

      await tester.tap(find.byKey(const ValueKey('moment-comment-c1')));
      await settle(tester);
      expect(find.text('Replying to Grace Hopper'), findsOneWidget);

      await typeIn(tester, 'moment-comment-field', 'Agreed!');
      await tester.tap(find.byKey(const ValueKey('moment-comment-send')));
      await settle(tester);
      expect(repository.comments.single, ('p1', 'Agreed!', 'c1'));
      expect(find.text('Replying to Grace Hopper'), findsNothing);
      expect(
        find.textContaining('replied', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('the reply can be cancelled', (tester) async {
      final repository = repositoryWithComments();
      await openMoments(tester, repository, location: '/moments/p1');

      await tester.tap(find.byKey(const ValueKey('moment-comment-c1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-reply-cancel')));
      await settle(tester);
      expect(find.text('Replying to Grace Hopper'), findsNothing);

      await typeIn(tester, 'moment-comment-field', 'Just a comment');
      await tester.tap(find.byKey(const ValueKey('moment-comment-send')));
      await settle(tester);
      expect(repository.comments.single.$3, isNull);
    });

    testWidgets('opens straight into a reply from the feed', (tester) async {
      await openMoments(
        tester,
        repositoryWithComments(),
        location: '/moments/p1?reply=c1',
      );
      expect(find.text('Replying to Grace Hopper'), findsOneWidget);
    });

    testWidgets('deletes my own comment from its menu', (tester) async {
      final repository = repositoryWithComments();
      await openMoments(tester, repository, location: '/moments/p1');

      // Tapping my own comment offers delete, not reply.
      await tester.tap(find.byKey(const ValueKey('moment-comment-c2')));
      await settle(tester);
      expect(find.byKey(const ValueKey('comment-reply')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('comment-delete')));
      await settle(tester);

      expect(repository.deletedComments, ['c2']);
      expect(find.byKey(const ValueKey('moment-comment-c2')), findsNothing);
    });

    testWidgets(
      'nobody but the commenter and the poster can delete a comment',
      (tester) async {
        final repository = repositoryWithComments();
        await openMoments(tester, repository, location: '/moments/p1');

        // Bart's post, Grace's comment: Ada may only reply.
        await tester.longPress(find.byKey(const ValueKey('moment-comment-c1')));
        await settle(tester);
        expect(find.byKey(const ValueKey('comment-reply')), findsOneWidget);
        expect(find.byKey(const ValueKey('comment-delete')), findsNothing);
      },
    );

    testWidgets('the poster deletes anybody\'s comment on their post', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'mine',
            authorId: 'user-1',
            authorName: 'Ada Lovelace',
            comments: [comment('c1', 'user-3', 'Grace Hopper', 'Rude comment')],
          ),
        ],
      );
      await openMoments(tester, repository, location: '/moments/mine');

      await tester.longPress(find.byKey(const ValueKey('moment-comment-c1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-delete')));
      await settle(tester);
      expect(repository.deletedComments, ['c1']);
    });

    testWidgets('a Moment that is gone says so', (tester) async {
      await openMoments(
        tester,
        FakeMomentsRepository(),
        location: '/moments/missing',
      );
      expect(find.byKey(const ValueKey('moment-gone')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-field')), findsNothing);
    });

    testWidgets('opens a picture full screen', (tester) async {
      await openMoments(
        tester,
        repositoryWithComments(),
        location: '/moments/p1',
      );
      await tester.tap(find.byKey(const ValueKey('moment-photo-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-photo-viewer')), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-photo-close')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moment-photo-viewer')), findsNothing);
    });
  });
}
