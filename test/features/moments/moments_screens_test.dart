import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_settings_screen.dart';

import '../../mobile/phone_test_support.dart';
import '../wallpapers/wallpaper_fakes.dart' show samplePhotoBytes;
import 'moments_fakes.dart';

Future<PhoneWorld> openMoments(
  WidgetTester tester,
  FakeMomentsRepository repository, {
  String location = '/moments',
  FakeFriendTagsRepository? tags,
  FakeMomentPhotoPicker? picker,
}) async {
  usePhoneViewport(tester, notchedPhone);
  final world = PhoneWorld()
    ..extraOverrides = momentsOverrides(
      repository: repository,
      tags: tags,
      picker: picker,
    );
  await world.open(tester, location);
  await settle(tester);
  return world;
}

void main() {
  group('the feed', () {
    testWidgets('shows my cover header and friends\' posts, newest first', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post('p1', body: 'Newest', minutesAgo: 5),
          post(
            'p2',
            authorId: 'user-3',
            authorName: 'Grace Hopper',
            body: 'Older one',
            minutesAgo: 120,
          ),
        ],
      );
      await openMoments(tester, repository);

      expect(find.byKey(const ValueKey('moments-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('moments-cover-name')), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Older one'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('moment-p1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('moment-p2'))).dy),
      );
      // Opening Moments clears the badge on its entry.
      expect(repository.markSeenCalls, 1);
    });

    testWidgets('says when nothing is there yet and offers to post', (
      tester,
    ) async {
      final world = await openMoments(tester, FakeMomentsRepository());

      expect(find.byKey(const ValueKey('moments-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moments-empty-post')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments/compose');
    });

    testWidgets('likes and unlikes a post', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);

      await tester.tap(find.byKey(const ValueKey('moment-like-p1')));
      await settle(tester);
      expect(repository.likeCalls, [('p1', true)]);
      expect(find.byKey(const ValueKey('moment-likes-line')), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('moment-like-p1')));
      await settle(tester);
      expect(repository.likeCalls.last, ('p1', false));
      expect(find.byKey(const ValueKey('moment-likes-line')), findsNothing);
    });

    testWidgets('shows the first comments and a way to see them all', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'p1',
            likes: const [
              MomentLiker(userId: 'user-3', name: 'Grace Hopper'),
              MomentLiker(userId: 'user-4', name: 'Linus'),
            ],
            comments: [
              comment('c1', 'user-3', 'Grace Hopper', 'Gorgeous'),
              comment(
                'c2',
                'user-4',
                'Linus',
                'Count me in next time',
                replyToId: 'c1',
                replyToUserId: 'user-3',
                replyToName: 'Grace Hopper',
              ),
              comment('c3', 'user-3', 'Grace Hopper', 'Third'),
              comment('c4', 'user-4', 'Linus', 'Fourth'),
            ],
          ),
        ],
      );
      await openMoments(tester, repository);

      expect(find.text('Grace Hopper, Linus'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-c3')), findsOneWidget);
      // Three are shown; the fourth is behind "View all".
      expect(find.byKey(const ValueKey('moment-comment-c4')), findsNothing);
      expect(find.text('View all 4 comments'), findsOneWidget);
      expect(
        find.textContaining('replied', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('loads the next page near the end of the list', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          for (var i = 0; i < 45; i++)
            post('p${i.toString().padLeft(2, '0')}', minutesAgo: i + 1),
        ],
      );
      await openMoments(tester, repository);
      expect(repository.feedCalls, hasLength(1));
      expect(repository.feedCalls.first.beforeAt, isNull);

      for (var round = 0; round < 12; round++) {
        await tester.drag(
          find.byKey(const ValueKey('moments-list')),
          const Offset(0, -900),
        );
        await settle(tester);
      }

      // Keyset pages: each asks for what is older than the last one shown.
      expect(repository.feedCalls.length, greaterThanOrEqualTo(3));
      expect(repository.feedCalls[1].beforeAt, isNotNull);
      expect(repository.feedCalls[1].beforeId, isNotNull);
      expect(find.text("You're all caught up"), findsOneWidget);
    });

    testWidgets('a friend\'s page lists only their posts', (tester) async {
      final repository =
          FakeMomentsRepository(
              posts: [
                post('p1', body: 'Bart says hi'),
                post(
                  'p2',
                  authorId: 'user-3',
                  authorName: 'Grace Hopper',
                  body: 'Grace says hi',
                ),
              ],
            )
            ..profiles['user-3'] = const MomentsProfile(
              userId: 'user-3',
              name: 'Grace Hopper',
            );
      await openMoments(tester, repository, location: '/moments/of/user-3');

      // (The feed underneath loads too: the page opens on top of it.)
      expect(
        repository.feedCalls.where((call) => call.authorId == 'user-3'),
        hasLength(1),
      );
      expect(find.text('Grace says hi'), findsOneWidget);
      expect(find.text('Bart says hi'), findsNothing);
      // No compose button on somebody else's page, and no cover editing.
      expect(find.byKey(const ValueKey('moments-compose')), findsNothing);
      expect(find.byKey(const ValueKey('moments-change-cover')), findsNothing);
    });

    testWidgets('deleting my own post asks first', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          post(
            'mine',
            authorId: 'user-1',
            authorName: 'Ada Lovelace',
            body: 'My own words',
            visibility: MomentVisibility.private,
          ),
        ],
      );
      await openMoments(tester, repository);

      // Only I see that it is private.
      expect(
        find.byKey(const ValueKey('moment-audience-chip')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('moment-delete-mine')));
      await settle(tester);
      expect(find.text('Delete this Moment?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(repository.deletedPosts, isEmpty);

      await tester.tap(find.byKey(const ValueKey('moment-delete-mine')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moment-delete-confirm')));
      await settle(tester);
      expect(repository.deletedPosts, ['mine']);
      expect(find.text('My own words'), findsNothing);
    });

    testWidgets('others\' posts have no delete button', (tester) async {
      await openMoments(tester, FakeMomentsRepository(posts: [post('p1')]));
      expect(find.byKey(const ValueKey('moment-delete-p1')), findsNothing);
      expect(find.byKey(const ValueKey('moment-audience-chip')), findsNothing);
    });

    testWidgets('changing the cover uploads the picked picture', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      final picker = FakeMomentPhotoPicker()
        ..cover = samplePhotoBytes(width: 400, height: 300);
      await openMoments(tester, repository, picker: picker);

      await tester.tap(find.byKey(const ValueKey('moments-change-cover')));
      await settle(tester);

      expect(repository.coversSet, 1);
      expect(repository.settingsValue.coverPath, isNotNull);
    });

    testWidgets('shows a pill when there are new likes and comments', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(posts: [post('p1')])
        ..notificationList = [
          MomentNotification(
            id: 'n1',
            kind: MomentNotificationKind.like,
            postId: 'p1',
            actorId: 'user-3',
            actorName: 'Grace Hopper',
            createdAt: DateTime.now().toUtc(),
            isUnread: true,
          ),
        ];
      final world = await openMoments(tester, repository);

      expect(find.text('1 new like or comment'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moments-unread-pill')));
      await settle(tester);
      expect(world.router.state.uri.path, '/notifications');
    });
  });

  group('settings', () {
    testWidgets('changes the visible range', (tester) async {
      final repository = FakeMomentsRepository();
      final world = PhoneWorld()
        ..extraOverrides = momentsOverrides(repository: repository);
      await pumpStandalone(tester, world, const MomentsSettingsScreen());

      expect(find.text('Visible range'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('moments-range-row')));
      await settle(tester);
      for (final label in [
        'All',
        'Last 6 months',
        'Last month',
        'Last 3 days',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('Last month'));
      await settle(tester);

      expect(repository.ranges, [MomentsRange.oneMonth]);
      expect(find.text('Last month'), findsOneWidget);
    });

    testWidgets('hides Moments from friends and hides theirs', (tester) async {
      final repository = FakeMomentsRepository();
      final world = PhoneWorld()
        ..extraOverrides = momentsOverrides(repository: repository);
      await pumpStandalone(tester, world, const MomentsSettingsScreen());

      await tester.tap(find.byKey(const ValueKey('moments-hide-mine-row')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moments-pref-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-pref-user-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-pref-done')));
      await settle(tester);

      expect(repository.prefCalls, [
        ('user-2', true, null),
        ('user-3', true, null),
      ]);
      expect(repository.prefs.every((pref) => pref.hideMine), isTrue);
      expect(find.text('2'), findsOneWidget);

      // Taking one back turns the switch off for that friend only.
      await tester.tap(find.byKey(const ValueKey('moments-hide-mine-row')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moments-pref-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-pref-done')));
      await settle(tester);
      expect(repository.prefCalls.last, ('user-2', false, null));

      await tester.tap(find.byKey(const ValueKey('moments-hide-theirs-row')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('moments-pref-user-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-pref-done')));
      await settle(tester);
      expect(repository.prefCalls.last, ('user-4', null, true));
    });
  });
}
