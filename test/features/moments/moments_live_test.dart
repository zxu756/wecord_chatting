import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_settings_screen.dart';

import '../../mobile/phone_test_support.dart';
import 'moments_fakes.dart';
import 'moments_screens_test.dart' show openMoments;

/// Live Moments: signals say "something changed" and the app reads the data
/// again through the same functions.
void main() {
  Future<void> wait(WidgetTester tester) async {
    await tester.pump(momentsLiveDelay + const Duration(milliseconds: 100));
    await settle(tester);
  }

  group('the feed', () {
    testWidgets('shows "1 new post" when a friend posts and loads it on tap', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(
        posts: [post('p1', body: 'Already here', minutesAgo: 60)],
      );
      await openMoments(tester, repository);
      expect(repository.hasSignalListener, isTrue);
      expect(find.byKey(const ValueKey('moments-new-pill')), findsNothing);

      repository.posts = [
        post('p2', body: 'Just posted', minutesAgo: 1),
        ...repository.posts,
      ];
      repository.emit(MomentsSignalKind.post, 'p2');
      await wait(tester);

      expect(find.byKey(const ValueKey('moments-new-pill')), findsOneWidget);
      expect(find.text('1 new post'), findsOneWidget);
      // The list does not jump under the reader.
      expect(find.text('Just posted'), findsNothing);

      repository.posts = [
        post('p3', body: 'Another', minutesAgo: 0),
        ...repository.posts,
      ];
      repository.emit(MomentsSignalKind.post, 'p3');
      await wait(tester);
      expect(find.text('2 new posts'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moments-new-pill')));
      await settle(tester);
      expect(find.byKey(const ValueKey('moments-new-pill')), findsNothing);
      expect(find.text('Just posted'), findsOneWidget);
      expect(find.text('Another'), findsOneWidget);
    });

    testWidgets('a signal for a post the person may not see shows nothing', (
      tester,
    ) async {
      // The server only signals what the person may see, and the app reads
      // the feed through the same function as always: a signal alone, with
      // nothing new in the feed, adds nothing.
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);

      repository.emit(MomentsSignalKind.post, 'hidden-post');
      await wait(tester);

      expect(find.byKey(const ValueKey('moments-new-pill')), findsNothing);
      expect(find.text('Sunrise from the north lot'), findsOneWidget);
    });

    testWidgets('likes and comments appear on a visible post live', (
      tester,
    ) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);
      expect(find.byKey(const ValueKey('moment-likes-line')), findsNothing);

      repository.posts = [
        post(
          'p1',
          likes: const [MomentLiker(userId: 'user-3', name: 'Grace Hopper')],
          comments: [comment('c1', 'user-3', 'Grace Hopper', 'Gorgeous')],
        ),
      ];
      repository.emit(MomentsSignalKind.reaction, 'p1');
      await wait(tester);

      expect(find.byKey(const ValueKey('moment-likes-line')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-comment-c1')), findsOneWidget);

      // And a comment taken back.
      repository.posts = [post('p1')];
      repository.emit(MomentsSignalKind.reaction, 'p1');
      await wait(tester);
      expect(find.byKey(const ValueKey('moment-comment-c1')), findsNothing);
    });

    testWidgets('a burst of signals is read once', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);
      final before = repository.postCalls;

      for (var i = 0; i < 5; i++) {
        repository.emit(MomentsSignalKind.reaction, 'p1');
      }
      await wait(tester);

      expect(repository.postCalls, before + 1);
    });

    testWidgets('a removed post leaves the feed', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          post('p1', body: 'Going'),
          post('p2', body: 'Staying'),
        ],
      );
      await openMoments(tester, repository);
      expect(find.text('Going'), findsOneWidget);

      repository.posts = [post('p2', body: 'Staying')];
      repository.emit(MomentsSignalKind.postRemoved, 'p1');
      await wait(tester);

      expect(find.text('Going'), findsNothing);
      expect(find.text('Staying'), findsOneWidget);
    });

    testWidgets('reconnecting reads the newest page again', (tester) async {
      final repository = FakeMomentsRepository(posts: [post('p1')]);
      await openMoments(tester, repository);

      repository.posts = [
        post('p9', body: 'Missed while offline'),
        ...repository.posts,
      ];
      repository.emit(MomentsSignalKind.resync);
      await wait(tester);

      expect(find.text('1 new post'), findsOneWidget);
    });
  });

  group('the Moments entry and Notifications', () {
    testWidgets('the unseen summary is read again when a friend posts', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      final container = ProviderContainer(
        overrides: [
          ...momentsOverrides(repository: repository),
          momentsUserIdProvider.overrideWithValue('user-1'),
        ],
      );
      addTearDown(container.dispose);
      final unseen = container.listen(momentsUnseenProvider, (_, _) {});
      addTearDown(unseen.close);
      await container.read(momentsUnseenProvider.future);
      final before = repository.unseenCalls;
      expect(repository.hasSignalListener, isTrue);

      repository.unseenValue = const MomentsUnseen(
        count: 1,
        latestAuthorId: 'user-2',
        latestAuthorName: 'Bart the Bold',
      );
      repository.emit(MomentsSignalKind.post, 'p2');
      await tester.pump();
      await tester.pump(momentsLiveDelay + const Duration(milliseconds: 100));
      final next = await container.read(momentsUnseenProvider.future);

      expect(repository.unseenCalls, before + 1);
      expect(next.count, 1);
      expect(next.latestAuthorName, 'Bart the Bold');
    });

    testWidgets('a like on my post refreshes the notification badge', (
      tester,
    ) async {
      final repository = FakeMomentsRepository();
      final container = ProviderContainer(
        overrides: [
          ...momentsOverrides(repository: repository),
          momentsUserIdProvider.overrideWithValue('user-1'),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(momentNotificationsProvider, (_, _) {});
      addTearDown(sub.close);
      final unreadSub = container.listen(
        momentNotificationsUnreadProvider,
        (_, _) {},
      );
      addTearDown(unreadSub.close);
      await container.read(momentNotificationsProvider.future);
      expect(container.read(momentNotificationsUnreadProvider), 0);

      repository.notificationList = [
        MomentNotification(
          id: 'n1',
          kind: MomentNotificationKind.like,
          postId: 'p1',
          actorId: 'user-2',
          actorName: 'Bart the Bold',
          createdAt: DateTime.now().toUtc(),
          isUnread: true,
        ),
      ];
      repository.emit(MomentsSignalKind.reaction, 'p1');
      await tester.pump();
      await tester.pump(momentsLiveDelay + const Duration(milliseconds: 100));
      await container.read(momentNotificationsProvider.future);

      expect(container.read(momentNotificationsUnreadProvider), 1);
    });
  });

  group('Settings -> Moments', () {
    testWidgets('turns push for likes and comments off and on', (tester) async {
      final repository = FakeMomentsRepository();
      final world = PhoneWorld()
        ..extraOverrides = momentsOverrides(repository: repository);
      await pumpStandalone(tester, world, const MomentsSettingsScreen());

      final row = find.byKey(const ValueKey('moments-push-row'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await settle(tester);
      expect(repository.pushSwitches, [false]);
      expect(repository.settingsValue.pushEnabled, isFalse);

      await tester.tap(row);
      await settle(tester);
      expect(repository.pushSwitches, [false, true]);
    });
  });
}
