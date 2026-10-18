import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ai_guard_screen.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'ai_guard_fakes.dart';

Widget app(FakeGuardRpc rpc, Widget home, {ThemeData? theme}) {
  return ProviderScope(
    overrides: [
      circleAiGuardRepositoryProvider.overrideWithValue(
        CircleAiGuardRepository(rpc),
      ),
    ],
    child: MaterialApp(theme: theme ?? WeCordTheme.light(), home: home),
  );
}

/// A tall window, so the whole settings list is on screen.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool switchValue(WidgetTester tester) => tester
    .widget<WeCordSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('ai-guard-switch')),
        matching: find.byType(WeCordSwitch),
      ),
    )
    .value;

void main() {
  group('repository', () {
    test('reads and writes the guard through its functions', () async {
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(
          enabled: true,
          rule: 'message_count',
          count: 20,
          action: 'flag',
          circleAi: false,
        )
        ..results['list_message_reviews'] = [reviewJson()]
        ..results['count_message_reviews'] = 3;
      final repository = CircleAiGuardRepository(rpc);

      final guard = await repository.getGuard('circle-1');
      expect(guard.enabled, isTrue);
      expect(guard.newRule, AiGuardNewRule.messageCount);
      expect(guard.messageCount, 20);
      expect(guard.action, AiGuardAction.flag);
      expect(guard.circleAiEnabled, isFalse);
      expect(guard.isActive, isFalse);

      await repository.saveGuard(
        'circle-1',
        const CircleAiGuard(
          enabled: true,
          newRule: AiGuardNewRule.joinedDays,
          joinedDays: 7,
          action: AiGuardAction.hold,
        ),
      );
      expect(rpc.guardCalls('set_circle_ai_guard').single, {
        'target_circle_id': 'circle-1',
        'guard_enabled': true,
        'guard_new_rule': 'joined_days',
        'guard_joined_days': 7,
        'guard_message_count': 10,
        'guard_action': 'hold',
      });

      final reviews = await repository.listReviews('circle-1');
      expect(reviews.single.held, isTrue);
      expect(reviews.single.verdict, AiGuardVerdict.spam);
      expect(reviews.single.reason, 'Sells pills');
      expect(await repository.countReviews('circle-1'), 3);

      await repository.approve('message-1');
      await repository.remove('message-2');
      expect(rpc.guardCalls('decide_message_review'), [
        {'target_message_id': 'message-1', 'decision': 'approve'},
        {'target_message_id': 'message-2', 'decision': 'remove'},
      ]);
    });

    test('unknown categories read as other', () {
      expect(AiGuardVerdict.fromKey('weird'), AiGuardVerdict.other);
      expect(AiGuardNewRule.fromKey(null), AiGuardNewRule.joinedDays);
      expect(AiGuardAction.fromKey('flag'), AiGuardAction.flag);
    });
  });

  group('settings', () {
    testWidgets('is off by default, with the privacy note in its footer', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson()
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();

      expect(find.text('AI guard for new members'), findsOneWidget);
      expect(switchValue(tester), isFalse);
      // The options only show once it is on.
      expect(find.text('Who counts as new'), findsNothing);
      expect(find.text('Hold for review'), findsNothing);
      expect(
        find.textContaining(
          'Only the text of messages from new members is sent to the AI '
          'provider',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ai-guard-ai-off')), findsNothing);
    });

    testWidgets('turning it on saves and shows who counts as new and what '
        'happens to flagged messages', (tester) async {
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson()
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai-guard-switch')));
      await tester.pumpAndSettle();

      expect(
        rpc.guardCalls('set_circle_ai_guard').single,
        containsPair('guard_enabled', true),
      );
      expect(switchValue(tester), isTrue);
      expect(find.text('Who counts as new'), findsOneWidget);
      expect(find.text('Recently joined'), findsOneWidget);
      expect(find.text('Few messages'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('Hold for review'), findsOneWidget);
      expect(find.text('Flag only'), findsOneWidget);
      expect(
        find.text(
          'Members who joined less than 3 days ago. Moderators and '
          'managers are never checked.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('each choice is saved: days, message count and action', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai-guard-days-7')));
      await tester.pumpAndSettle();
      expect(
        rpc.guardCalls('set_circle_ai_guard').last,
        containsPair('guard_joined_days', 7),
      );

      await tester.tap(find.byKey(const ValueKey('ai-guard-rule-messages')));
      await tester.pumpAndSettle();
      expect(
        rpc.guardCalls('set_circle_ai_guard').last,
        containsPair('guard_new_rule', 'message_count'),
      );
      expect(find.byKey(const ValueKey('ai-guard-count-5')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-guard-count-5')));
      await tester.pumpAndSettle();
      expect(
        rpc.guardCalls('set_circle_ai_guard').last,
        containsPair('guard_message_count', 5),
      );
      expect(
        find.text(
          'Members who have sent fewer than 5 messages in this circle. '
          'Moderators and managers are never checked.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ai-guard-action-flag')));
      await tester.pumpAndSettle();
      expect(
        rpc.guardCalls('set_circle_ai_guard').last,
        containsPair('guard_action', 'flag'),
      );
      // The server's answer is what the form shows.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('a saved count outside the presets still shows', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(
          enabled: true,
          rule: 'message_count',
          count: 12,
        )
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-guard-count-12')), findsOneWidget);
    });

    testWidgets('explains that it needs the circle AI switch', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(
          enabled: true,
          circleAi: false,
        )
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-guard-ai-off')), findsOneWidget);
      expect(
        find.textContaining('AI features are turned off in this circle'),
        findsOneWidget,
      );
      expect(find.text('On, but AI is off in this circle'), findsOneWidget);
    });

    testWidgets('goes back and says so when saving fails', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson()
        ..results['count_message_reviews'] = 0
        ..failing.add('set_circle_ai_guard');
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai-guard-switch')));
      await tester.pumpAndSettle();

      expect(switchValue(tester), isFalse);
      expect(
        find.text("Couldn't save the AI guard. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('moderators see how many messages wait', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 4;
      await tester.pumpWidget(app(rpc, CircleAiGuardScreen(detail: detail())));
      await tester.pumpAndSettle();
      expect(find.text('4 waiting'), findsOneWidget);
      expect(find.byType(CountBadge), findsOneWidget);
    });

    testWidgets('without manage messages there is no Review row', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true);
      await tester.pumpWidget(
        app(
          rpc,
          CircleAiGuardScreen(
            detail: detail(permissions: CirclePermission.manageCircle.bit),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-guard-open-review')), findsNothing);
      expect(rpc.guardCalls('count_message_reviews'), isEmpty);
    });
  });

  group('review queue', () {
    DateTime now() => DateTime.utc(2026, 5, 18, 4, 30);

    testWidgets('shows each message with the AI category and reason', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [
          reviewJson(),
          reviewJson(
            id: 'message-2',
            state: 'flagged',
            verdict: 'scam',
            reason: 'Asks for a password',
            body: 'Send me your password',
          ),
        ];
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Newt'), findsNWidgets(2));
      expect(find.text('#general · 30m ago'), findsNWidgets(2));
      expect(find.text('Cheap pills at pills.example'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-held')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-flagged')), findsOneWidget);
      expect(
        find.textContaining('Spam · Sells pills', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Scam or phishing · Asks for a password',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the Chinese reason in Chinese, else the English one', (
      tester,
    ) async {
      tall(tester);
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [
          reviewJson(reasonZh: '推销药品'),
          reviewJson(
            id: 'message-2',
            state: 'flagged',
            verdict: 'scam',
            reason: 'Asks for a password',
          ),
        ];
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('垃圾信息 · 推销药品', findRichText: true),
        findsOneWidget,
      );
      // No Chinese reason (an older review): the English one.
      expect(
        find.textContaining('· Asks for a password', findRichText: true),
        findsOneWidget,
      );
    });

    test('the reason follows the app language', () {
      final review = MessageReview.fromJson(reviewJson(reasonZh: '推销药品'));
      expect(review.localizedReason, 'Sells pills');
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(review.localizedReason, '推销药品');
      expect(
        MessageReview.fromJson(reviewJson(reasonZh: '  ')).localizedReason,
        'Sells pills',
      );
    });

    testWidgets('approving releases it and refreshes the queue', (
      tester,
    ) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [reviewJson()];
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();

      rpc.results['list_message_reviews'] = <Map<String, dynamic>>[];
      await tester.tap(find.byKey(const ValueKey('review-approve')));
      await tester.pumpAndSettle();

      expect(rpc.guardCalls('decide_message_review').single, {
        'target_message_id': 'message-1',
        'decision': 'approve',
      });
      expect(find.text('Message approved.'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-empty')), findsOneWidget);
    });

    testWidgets('removing asks first', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [reviewJson()];
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove this message?'), findsOneWidget);
      expect(rpc.guardCalls('decide_message_review'), isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rpc.guardCalls('decide_message_review'), isEmpty);

      rpc.results['list_message_reviews'] = <Map<String, dynamic>>[];
      await tester.tap(find.byKey(const ValueKey('review-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(WeCordButton, 'Remove').last);
      await tester.pumpAndSettle();

      expect(rpc.guardCalls('decide_message_review').single, {
        'target_message_id': 'message-1',
        'decision': 'remove',
      });
      expect(find.text('Message removed.'), findsOneWidget);
    });

    testWidgets('says so when somebody else decided first', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [reviewJson()]
        ..failing.add('decide_message_review');
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review-approve')));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't update this message. It may already be reviewed."),
        findsOneWidget,
      );
    });

    testWidgets('an empty queue says nothing is waiting', (tester) async {
      tall(tester);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        app(rpc, CircleReviewScreen(circleId: 'circle-1', now: now)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing to review'), findsOneWidget);
    });
  });
}
