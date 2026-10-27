// Topics in Moments (B8): tags in the text open a page of the Moments I can
// see with that topic, the topics list, and the suggestions in the composer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'moments_fakes.dart';
import 'moments_screens_test.dart' show openMoments;

MomentTopic _topic(String tag, int count) => MomentTopic(
  tag: tag,
  postCount: count,
  lastAt: DateTime.utc(2026, 10, 27, 8),
);

void main() {
  group('topics in the feed', () {
    testWidgets('a tag in a post opens the page of that topic', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [
          post('p1', body: '#lake', minutesAgo: 5),
          post('p2', body: 'Nothing here', minutesAgo: 10),
          post('p3', body: 'Walk by the #lake today', minutesAgo: 20),
        ],
      );
      final world = await openMoments(tester, repository);

      // The tag is the start of the line; the text field spans the card.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('moment-body-p1'))) +
            const Offset(12, 10),
      );
      await settle(tester);

      expect(world.router.state.uri.path, '/moments/tag/lake');
      expect(find.byKey(const ValueKey('moments-topic-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-p3')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-p2')), findsNothing);
    });

    testWidgets('a topic nobody used says so', (tester) async {
      await openMoments(
        tester,
        FakeMomentsRepository(posts: [post('p1')]),
        location: '/moments/tag/lake',
      );
      expect(find.text('No Moments with this topic'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-p1')), findsNothing);
    });

    testWidgets('the topics list opens a topic', (tester) async {
      final repository = FakeMomentsRepository(
        posts: [post('p1', body: 'On the #lake')],
      )..topicList = [_topic('lake', 3), _topic('city', 1)];
      final world = await openMoments(tester, repository);

      await tester.tap(find.byKey(const ValueKey('moments-topics')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments/topics');
      expect(find.byKey(const ValueKey('moment-topic-lake')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-topic-city')), findsOneWidget);
      expect(find.text('3 Moments'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-topic-lake')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments/tag/lake');
      expect(find.byKey(const ValueKey('moment-p1')), findsOneWidget);
    });

    testWidgets('no topics yet is said kindly', (tester) async {
      await openMoments(
        tester,
        FakeMomentsRepository(),
        location: '/moments/topics',
      );
      expect(find.text('No topics yet'), findsOneWidget);
    });
  });

  group('topics in the composer', () {
    testWidgets('a topic friends used is added to the text by one press', (
      tester,
    ) async {
      final repository = FakeMomentsRepository()
        ..topicList = [_topic('lake', 3)];
      await openMoments(tester, repository, location: '/moments/compose');

      await tester.enterText(
        find.byKey(const ValueKey('moment-text')),
        'Morning walk',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(WeCordChip, '#lake'));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('moment-text')),
      );
      expect(field.controller!.text, contains('#lake'));

      await tester.tap(find.byKey(const ValueKey('moment-post')));
      await settle(tester);
      expect(repository.created.single.body, contains('#lake'));
    });
  });
}
