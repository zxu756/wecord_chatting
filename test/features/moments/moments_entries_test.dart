import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';

import '../../accessibility/a11y_screens.dart' show desktopViewport;
import '../../mobile/phone_test_support.dart';
import 'moments_fakes.dart';

MomentNotification notice(
  String id,
  MomentNotificationKind kind, {
  bool unread = true,
  String postId = 'p1',
  String snippet = '',
}) {
  return MomentNotification(
    id: id,
    kind: kind,
    postId: postId,
    actorId: 'user-3',
    actorName: 'Grace Hopper',
    snippet: snippet,
    postExcerpt: 'The summit at dawn',
    createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    isUnread: unread,
  );
}

Future<PhoneWorld> open(
  WidgetTester tester,
  FakeMomentsRepository repository,
  String location, {
  PhoneViewport viewport = notchedPhone,
}) async {
  usePhoneViewport(tester, viewport);
  final world = PhoneWorld()
    ..extraOverrides = momentsOverrides(repository: repository);
  await world.open(tester, location);
  await settle(tester);
  return world;
}

void main() {
  group('Notifications', () {
    FakeMomentsRepository repository() =>
        FakeMomentsRepository(posts: [post('p1', authorId: 'user-1')])
          ..notificationList = [
            notice('n1', MomentNotificationKind.like),
            notice(
              'n2',
              MomentNotificationKind.comment,
              snippet: 'Gorgeous light',
            ),
            notice(
              'n3',
              MomentNotificationKind.reply,
              unread: false,
              snippet: 'Agreed with you',
            ),
          ];

    testWidgets('likes, comments and replies show as cards', (tester) async {
      await open(tester, repository(), '/notifications');
      final chip = find.byKey(const ValueKey('inbox-filter-moments'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await settle(tester);

      expect(
        find.textContaining('liked your Moment', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('commented on your Moment', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('replied to your comment', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Gorgeous light'), findsOneWidget);
      expect(find.text('Agreed with you'), findsOneWidget);
    });

    testWidgets('the Moments chip narrows to them and counts the unread', (
      tester,
    ) async {
      await open(tester, repository(), '/notifications');
      final chip = find.byKey(const ValueKey('inbox-filter-moments'));
      await tester.ensureVisible(chip);
      await tester.pump();
      expect(
        find.descendant(of: chip, matching: find.text('Moments 2')),
        findsOneWidget,
      );

      await tester.tap(chip);
      await settle(tester);
      expect(find.byKey(const ValueKey('inbox-moment-n1')), findsOneWidget);
      // Mentions and requests are not Moments.
      expect(find.textContaining('wants to be your friend'), findsNothing);
    });

    testWidgets('opening one marks it read and opens the Moment', (
      tester,
    ) async {
      final fake = repository();
      final world = await open(tester, fake, '/notifications');

      await tester.tap(find.byKey(const ValueKey('inbox-moment-n2')));
      await settle(tester);

      expect(fake.readNotifications, [
        ['n2'],
      ]);
      expect(world.router.state.uri.path, '/moments/p1');
      expect(
        find.byKey(const ValueKey('moment-comment-field')),
        findsOneWidget,
      );
    });

    testWidgets('unread ones count on the Notifications badge', (tester) async {
      final world = await open(
        tester,
        FakeMomentsRepository(posts: [post('p1')]),
        '/notifications',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WeCordApp)),
      );
      final before = container.read(inboxBadgeCountProvider);
      world.router.go('/');
      await tester.pump();

      final fake = repository();
      final other = await open(tester, fake, '/notifications');
      final container2 = ProviderScope.containerOf(
        tester.element(find.byType(WeCordApp)),
      );
      container2.listen(inboxBadgeCountProvider, (_, _) {});
      container2.listen(momentNotificationsProvider, (_, _) {});
      await settle(tester);
      expect(container2.read(inboxBadgeCountProvider), before + 2);
      expect(other.router.state.uri.path, '/notifications');
    });

    testWidgets('says so when there is nothing under Moments', (tester) async {
      await open(tester, FakeMomentsRepository(), '/notifications');
      final chip = find.byKey(const ValueKey('inbox-filter-moments'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await settle(tester);
      expect(
        find.text('Likes and comments on your Moments show up here.'),
        findsOneWidget,
      );
    });
  });

  group('the Moments entry', () {
    FakeMomentsRepository withNew() =>
        FakeMomentsRepository(posts: [post('p1')])
          ..unseenValue = const MomentsUnseen(
            count: 2,
            latestAuthorId: 'user-3',
            latestAuthorName: 'Grace Hopper',
          );

    testWidgets('on the phone home, next to Add friend and Saved', (
      tester,
    ) async {
      await open(tester, FakeMomentsRepository(), '/');

      expect(
        find.byKey(const ValueKey('phone-home-add-friends')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('phone-home-saved')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-home-moments')), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);
      // Nothing new, no badge.
      expect(find.byKey(const ValueKey('moments-unseen-avatar')), findsNothing);
    });

    testWidgets('shows the latest poster\'s avatar while there is news', (
      tester,
    ) async {
      final repository = withNew();
      final world = await open(tester, repository, '/');
      expect(
        find.byKey(const ValueKey('moments-unseen-avatar')),
        findsOneWidget,
      );

      // Opening Moments clears it.
      await tester.tap(find.byKey(const ValueKey('phone-home-moments')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments');
      expect(repository.markSeenCalls, 1);
      world.router.go('/');
      await settle(tester);
      expect(find.byKey(const ValueKey('moments-unseen-avatar')), findsNothing);
    });

    testWidgets('in the desktop sidebar after Saved', (tester) async {
      final repository = withNew();
      final world = await open(
        tester,
        repository,
        '/',
        viewport: desktopViewport,
      );

      for (final key in [
        'home-friends',
        'home-inbox',
        'home-saved',
        'home-moments',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-moments'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('home-saved'))).dy,
        ),
      );
      expect(
        find.byKey(const ValueKey('moments-unseen-avatar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('home-moments')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments');
      // The sidebar stays, with Moments selected.
      expect(find.byKey(const ValueKey('home-moments')), findsOneWidget);
      expect(find.byKey(const ValueKey('moments-list')), findsOneWidget);
    });
  });

  group('the posts store', () {
    testWidgets('a like that fails is taken back', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      final container = ProviderContainer(
        overrides: momentsOverrides(repository: repository),
      );
      addTearDown(container.dispose);
      final store = container.read(momentPostsStoreProvider.notifier);
      store.put(repository.posts.first);

      repository.failNext = Exception('offline');
      await expectLater(store.setLiked('p1', liked: true), throwsException);

      final after = container.read(momentPostsStoreProvider)['p1']!;
      expect(after.likedByMe, isFalse);
      expect(after.likeCount, 0);
    });

    testWidgets('a post that is gone leaves the store when read again', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      final container = ProviderContainer(
        overrides: momentsOverrides(repository: repository),
      );
      addTearDown(container.dispose);
      final store = container.read(momentPostsStoreProvider.notifier);
      store.put(repository.posts.first);
      repository.posts = [];

      expect(await store.refresh('p1'), isNull);
      expect(container.read(momentPostsStoreProvider), isEmpty);
    });
  });
}
