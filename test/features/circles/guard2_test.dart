import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ai_guard_screen.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/circles/guard2/review_media.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'ai_guard_fakes.dart';
import 'guard2_fakes.dart';

Widget app(
  FakeGuardRpc rpc,
  FakeGuard2Rpc guard2,
  Widget home, {
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      circleAiGuardRepositoryProvider.overrideWithValue(
        CircleAiGuardRepository(rpc),
      ),
      guard2RepositoryProvider.overrideWithValue(Guard2Repository(guard2.call)),
      reviewImageUrlProvider.overrideWith(
        (ref, file) async => 'https://example.test/${file.path}',
      ),
    ],
    child: MaterialApp(theme: theme ?? WeCordTheme.light(), home: home),
  );
}

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool switchOf(WidgetTester tester, String key) => tester
    .widget<WeCordSwitch>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(WeCordSwitch),
      ),
    )
    .value;

final now = DateTime.utc(2026, 10, 20, 4, 30);

void main() {
  group('repository', () {
    test('reads and writes the scope through its functions', () async {
      final rpc = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson(vision: true);
      final repository = Guard2Repository(rpc.call);

      final scope = await repository.getScope('circle-1');
      expect(scope.polls, isTrue);
      expect(scope.items, isTrue);
      expect(scope.images, isFalse);
      expect(scope.visionAvailable, isTrue);

      final saved = await repository.saveScope(
        'circle-1',
        scope.copyWith(images: true, polls: false),
      );
      expect(rpc.callsTo('set_circle_ai_guard_scope').single, {
        'target_circle_id': 'circle-1',
        'scope_polls': false,
        'scope_items': true,
        'scope_images': true,
      });
      expect(saved.images, isTrue);
      expect(saved.visionAvailable, isTrue);
    });

    test('lists, counts and dismisses flagged items', () async {
      final rpc = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [
          itemJson(),
          itemJson(id: 'item-2', type: 'task_item', title: 'Send me a code'),
        ]
        ..results['count_guard_item_reviews'] = 2;
      final repository = Guard2Repository(rpc.call);

      final items = await repository.listItems('circle-1');
      expect(items.map((item) => item.type), [
        GuardItemType.note,
        GuardItemType.taskItem,
      ]);
      expect(items.first.verdict, AiGuardVerdict.scam);
      expect(items.first.channelName, 'general');
      expect(await repository.countItems('circle-1'), 2);

      await repository.dismiss('item-1');
      expect(rpc.callsTo('dismiss_guard_item_review').single, {
        'target_review_id': 'item-1',
      });
    });

    test('defaults and unknown values are safe', () {
      final scope = CircleAiGuardScope.fromJson(const {});
      expect(scope.polls, isTrue);
      expect(scope.items, isTrue);
      expect(scope.images, isFalse);
      expect(scope.visionAvailable, isFalse);
      expect(GuardItemType.fromKey('weird'), GuardItemType.note);
    });

    test('the reason follows the app language', () {
      final item = GuardItemReview.fromJson(itemJson(reasonZh: '虚假奖品'));
      expect(item.localizedReason, 'Fake prize');
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(item.localizedReason, '虚假奖品');
    });

    test('the media of a review is merged in by message', () async {
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [
          reviewJson(id: 'message-1', body: ''),
          reviewJson(id: 'message-2', body: 'Cash or pills?'),
          reviewJson(id: 'message-3'),
        ]
        ..results['list_message_review_media'] = [
          {
            'message_id': 'message-1',
            'type': 'image',
            'media': {'bucket': 'chat-images', 'path': 'c/p.png'},
          },
          {
            'message_id': 'message-2',
            'type': 'poll',
            'media': {
              'options': ['Cash', 'Pills'],
            },
          },
        ];
      final reviews = await CircleAiGuardRepository(
        rpc,
      ).listReviews('circle-1');
      expect(reviews.map((review) => review.type), ['image', 'poll', 'text']);
      expect(reviews[0].media!['path'], 'c/p.png');
      expect(reviews[1].media!['options'], ['Cash', 'Pills']);
      expect(reviews[2].media, isNull);

      // Without the media function the cards are plain.
      rpc.failing.add('list_message_review_media');
      final plain = await CircleAiGuardRepository(rpc).listReviews('circle-1');
      expect(plain.map((review) => review.type), ['text', 'text', 'text']);
    });
  });

  group('settings', () {
    testWidgets('shows what the guard also checks, once it is on', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 0;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson();
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-guard-scope')), findsOneWidget);
      expect(find.text('Also checks'), findsOneWidget);
      expect(switchOf(tester, 'ai-guard-scope-polls'), isTrue);
      expect(switchOf(tester, 'ai-guard-scope-items'), isTrue);
      expect(switchOf(tester, 'ai-guard-scope-images'), isFalse);
      // The server cannot read pictures yet: said plainly.
      expect(
        find.text(
          'Not set up on this server yet, so pictures are sent as usual.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is not shown while the guard is off', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson()
        ..results['count_message_reviews'] = 0;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson();
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-guard-scope')), findsNothing);
      expect(guard2.callsTo('get_circle_ai_guard_scope'), isEmpty);
    });

    testWidgets('turning on pictures saves at once', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 0;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson(vision: true);
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Sent to the AI provider's picture model. Costs more than text.",
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ai-guard-scope-images')));
      await tester.pumpAndSettle();

      expect(guard2.callsTo('set_circle_ai_guard_scope').single, {
        'target_circle_id': 'circle-1',
        'scope_polls': true,
        'scope_items': true,
        'scope_images': true,
      });
      expect(switchOf(tester, 'ai-guard-scope-images'), isTrue);
    });

    testWidgets('a failed save goes back and says so', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 0;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson()
        ..failing.add('set_circle_ai_guard_scope');
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai-guard-scope-polls')));
      await tester.pumpAndSettle();

      expect(switchOf(tester, 'ai-guard-scope-polls'), isTrue);
      expect(
        find.text("Couldn't save the AI guard. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('a person who cannot read the scope sees no section', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 0;
      final guard2 = FakeGuard2Rpc()..failing.add('get_circle_ai_guard_scope');
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-guard-scope')), findsNothing);
      expect(find.text('Who counts as new'), findsOneWidget);
    });
  });

  group('review queue', () {
    testWidgets('a held picture shows the picture, a poll its options', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [
          reviewJson(id: 'message-1', body: '', verdict: 'sexual'),
          reviewJson(
            id: 'message-2',
            body: 'Cash or pills?',
            verdict: 'spam',
            state: 'flagged',
          ),
        ]
        ..results['list_message_review_media'] = [
          {
            'message_id': 'message-1',
            'type': 'image',
            'media': {
              'bucket': 'chat-images',
              'path': 'c/p.png',
              'mime_type': 'image/png',
            },
          },
          {
            'message_id': 'message-2',
            'type': 'poll',
            'media': {
              'options': ['Cash', 'Pills'],
            },
          },
        ];
      final guard2 = FakeGuard2Rpc();
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('review-picture')), findsOneWidget);
      // A picture has no text to show.
      expect(find.byKey(const ValueKey('review-body')), findsOneWidget);
      expect(find.text('Cash or pills?'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-poll-options')), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Pills'), findsOneWidget);
    });

    testWidgets('flagged events, notes and tasks have cards of their own', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc();
      final guard2 = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [
          itemJson(),
          itemJson(
            id: 'item-2',
            type: 'task_item',
            title: 'Send me your password',
            detail: 'Quick',
            verdict: 'scam',
            reason: 'Asks for a password',
          ),
        ]
        ..results['count_guard_item_reviews'] = 2;
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('review-items-header')), findsOneWidget);
      expect(
        find.text('Events, notes and tasks flagged by the AI guard'),
        findsOneWidget,
      );
      expect(find.text('Win a free prize'), findsOneWidget);
      expect(find.text('Send me your password'), findsOneWidget);
      expect(find.text('Quick'), findsOneWidget);
      expect(
        find.textContaining(
          'Scam or phishing · Fake prize',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Task'), findsOneWidget);
      // Only items are waiting: no "Nothing to review".
      expect(find.byKey(const ValueKey('review-empty')), findsNothing);
    });

    testWidgets('dismissing a card closes it and refreshes the queue', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc();
      final guard2 = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [itemJson()]
        ..results['count_guard_item_reviews'] = 1;
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      guard2.results['list_guard_item_reviews'] = <Map<String, dynamic>>[];
      guard2.results['count_guard_item_reviews'] = 0;
      await tester.tap(find.byKey(const ValueKey('review-item-dismiss')));
      await tester.pumpAndSettle();

      expect(guard2.callsTo('dismiss_guard_item_review').single, {
        'target_review_id': 'item-1',
      });
      expect(find.text('Card dismissed.'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-item-item-1')), findsNothing);
      expect(find.byKey(const ValueKey('review-empty')), findsOneWidget);
    });

    testWidgets('a card someone else closed first says so', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc();
      final guard2 = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [itemJson()]
        ..results['count_guard_item_reviews'] = 1
        ..failing.add('dismiss_guard_item_review');
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review-item-dismiss')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't update this card. It may already be reviewed."),
        findsOneWidget,
      );
    });

    testWidgets('items that cannot be read leave the message queue alone', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [reviewJson()];
      final guard2 = FakeGuard2Rpc()
        ..failing.addAll([
          'list_guard_item_reviews',
          'count_guard_item_reviews',
        ]);
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('review-items')), findsNothing);
      expect(find.text('Cheap pills at pills.example'), findsOneWidget);
    });

    testWidgets('the waiting count includes flagged items', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 2;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson()
        ..results['count_guard_item_reviews'] = 3;
      await tester.pumpWidget(
        app(rpc, guard2, CircleAiGuardScreen(detail: detail())),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 waiting'), findsWidgets);
    });

    testWidgets('reads in Chinese', (tester) async {
      tall(tester);
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      final rpc = FakeGuardRpc();
      final guard2 = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [itemJson(reasonZh: '虚假奖品')]
        ..results['count_guard_item_reviews'] = 1;
      await tester.pumpWidget(
        app(
          rpc,
          guard2,
          CircleReviewScreen(circleId: 'circle-1', now: () => now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 守护标记的活动、笔记和任务'), findsOneWidget);
      expect(
        find.textContaining('诈骗或钓鱼 · 虚假奖品', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
