import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/circles/circle_invite_sheet.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/join_requests/join_gate.dart';
import 'package:wecord/features/circles/join_requests/join_request_inbox_card.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/join_requests/join_settings_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'ai_guard_fakes.dart';
import 'circle_routes_test.dart'
    show FakeCirclesRepository, FakeContactsRepository;
import 'join_requests_fakes.dart';

Widget _app(
  Widget home, {
  JoinRpc? rpc,
  FakeGuardRpc? guard,
  List<Override> overrides = const [],
  ThemeData? theme,
}) {
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [
      if (rpc != null) circleRpcProvider.overrideWithValue(rpc.call),
      if (guard != null)
        circleAiGuardRepositoryProvider.overrideWithValue(
          CircleAiGuardRepository(guard),
        ),
      ...overrides,
    ],
    child: MaterialApp(theme: theme ?? WeCordTheme.light(), home: home),
  );
}

void _tall(WidgetTester tester, {Size size = const Size(800, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('models', () {
    test('a state parses, and says whether joining needs a review', () {
      final state = CircleJoinState.fromJson(joinStateJson());
      expect(state.mode, CircleJoinMode.apply);
      expect(state.needsReview, isTrue);
      expect(state.questions.map((q) => q.prompt), [
        'Why do you want to join?',
        'How did you find us?',
      ]);
      expect(state.questions[1].kind, JoinQuestionKind.choice);
      expect(state.questions[1].required, isFalse);
      expect(state.questions[1].options, [
        'A friend',
        'Search',
        'Social media',
      ]);

      // A member, an invite that skips review, and the other modes do not.
      expect(
        CircleJoinState.fromJson(joinStateJson(isMember: true)).needsReview,
        isFalse,
      );
      expect(
        CircleJoinState.fromJson(joinStateJson(skipReview: true)).needsReview,
        isFalse,
      );
      expect(
        CircleJoinState.fromJson(joinStateJson(mode: 'open')).needsReview,
        isFalse,
      );
      expect(CircleJoinMode.fromKey('invite_only'), CircleJoinMode.inviteOnly);
      expect(CircleJoinMode.fromKey('weird'), CircleJoinMode.open);
    });

    test('the join button follows the state', () {
      final now = DateTime.utc(2026, 10, 22, 12);
      JoinButtonPlan plan(Map<String, dynamic>? json, {bool invite = false}) =>
          planJoinButton(
            json == null ? null : CircleJoinState.fromJson(json),
            viaInvite: invite,
            now: now,
          );

      expect(plan(null).kind, JoinButtonKind.join);
      expect(plan(null).label, 'Join circle');
      expect(plan(joinStateJson()).kind, JoinButtonKind.sendRequest);
      expect(plan(joinStateJson()).label, 'Send request');
      expect(plan(joinStateJson(mode: 'open')).kind, JoinButtonKind.join);
      expect(plan(joinStateJson(skipReview: true)).kind, JoinButtonKind.join);
      expect(
        plan(joinStateJson(request: requestInfoJson())).label,
        'Request sent',
      );
      expect(plan(joinStateJson(request: requestInfoJson())).enabled, isFalse);
      expect(plan(joinStateJson(closed: true)).enabled, isFalse);
      // Invite only: closed from Explore, open to an invite.
      expect(plan(joinStateJson(mode: 'invite_only')).label, 'Invite only');
      expect(plan(joinStateJson(mode: 'invite_only')).enabled, isFalse);
      expect(
        plan(joinStateJson(mode: 'invite_only'), invite: true).kind,
        JoinButtonKind.join,
      );
      // Denied: wait until the retry time.
      final denied = joinStateJson(
        request: requestInfoJson(status: 'denied'),
        retryAt: '2026-10-23T08:00:00Z',
      );
      expect(plan(denied).enabled, isFalse);
      expect(plan(denied).label, 'Try again tomorrow');
      final retry = joinStateJson(
        request: requestInfoJson(status: 'denied'),
        retryAt: '2026-10-22T08:00:00Z',
      );
      expect(plan(retry).kind, JoinButtonKind.sendRequest);
    });

    test('answers are complete when every required question has one', () {
      final questions = CircleJoinState.fromJson(joinStateJson()).questions;
      expect(joinAnswersComplete(questions, {}), isFalse);
      expect(joinAnswersComplete(questions, {'q1': '   '}), isFalse);
      expect(joinAnswersComplete(questions, {'q1': 'Because'}), isTrue);
      expect(
        joinAnswersComplete(questions, {'q1': 'x' * (joinAnswerMaxLength + 1)}),
        isFalse,
      );
      expect(joinAnswersJson({'q1': ' Because ', 'q2': ''}), [
        {'question_id': 'q1', 'answer': 'Because'},
      ]);
    });

    test('a question is valid with words, and a choice with two options', () {
      const text = JoinQuestion(
        id: '',
        kind: JoinQuestionKind.text,
        prompt: 'Why?',
      );
      expect(text.isValid, isTrue);
      expect(text.copyWith(prompt: '  ').isValid, isFalse);
      final choice = text.copyWith(
        kind: JoinQuestionKind.choice,
        options: ['One', ' '],
      );
      expect(choice.isValid, isFalse);
      expect(choice.copyWith(options: ['One', 'Two']).isValid, isTrue);
      expect(choice.copyWith(options: ['One', 'One']).isValid, isFalse);
      expect(choice.copyWith(options: ['One', 'Two']).toJson(), {
        'kind': 'choice',
        'prompt': 'Why?',
        'options': ['One', 'Two'],
        'required': true,
      });
    });

    test('refusals are worded for the person', () {
      expect(
        joinErrorMessage(Exception('Banned from this circle')),
        "You're banned from this circle.",
      );
      expect(
        joinErrorMessage(Exception('This circle is invite only')),
        'This circle is invite only.',
      );
      expect(
        joinErrorMessage(Exception('This circle is not accepting new members')),
        'This circle is not taking new members.',
      );
      expect(
        joinErrorMessage(
          Exception('Your request was declined. You can apply again tomorrow.'),
        ),
        'Your request was turned down. You can ask again tomorrow.',
      );
      expect(
        joinErrorMessage(Exception('Answer the required questions')),
        'Answer the required questions first.',
      );
      expect(joinErrorMessage(Exception('boom')), isNull);
    });

    test('the permissions follow create_invites and kick_members', () {
      expect(detail().canReviewJoinRequests, isTrue);
      expect(detail().canSkipJoinReview, isTrue);
      final onlyInvites = detail(
        permissions: CirclePermission.maskOf([
          CirclePermission.viewChannel,
          CirclePermission.createInvites,
        ]),
      );
      expect(onlyInvites.canSkipJoinReview, isFalse);
      expect(onlyInvites.canReviewJoinRequests, isFalse);
      expect(onlyInvites.canOpenReview, isFalse);
      final onlyKick = detail(
        permissions: CirclePermission.maskOf([
          CirclePermission.viewChannel,
          CirclePermission.kickMembers,
        ]),
      );
      expect(onlyKick.canOpenReview, isTrue);
      expect(onlyKick.canSkipJoinReview, isFalse);
      final onlyMessages = detail(
        permissions: CirclePermission.maskOf([
          CirclePermission.viewChannel,
          CirclePermission.manageMessages,
        ]),
      );
      expect(onlyMessages.canOpenReview, isTrue);
      expect(onlyMessages.canReviewJoinRequests, isFalse);
    });
  });

  group('repository', () {
    test('calls the functions with the names the database has', () async {
      final rpc = JoinRpc()
        ..answer('get_circle_join_state', joinStateJson())
        ..answer('count_join_requests', 4)
        ..answer('list_join_requests', [pendingRequestJson()])
        ..answer('decide_join_request', null)
        ..answer('cancel_join_request', null)
        ..answer('list_my_join_requests', [myRequestJson()])
        ..answer('dismiss_join_request_result', null)
        ..answer('accept_circle_invite', 'circle-9')
        ..answer('list_circle_invites_skipping_review', ['abc', 'def'])
        ..answer('create_circle_invite', 'newcode')
        ..answer('set_circle_join_settings', null);
      final repository = JoinRequestsRepository(rpc.call);

      final state = await repository.getState('circle-9', inviteCode: 'abc');
      expect(state!.mode, CircleJoinMode.apply);
      expect(rpc.paramsOf('get_circle_join_state').single, {
        'target_circle_id': 'circle-9',
        'invite_code': 'abc',
      });
      await repository.getState('circle-9');
      expect(rpc.paramsOf('get_circle_join_state').last, {
        'target_circle_id': 'circle-9',
      });

      expect(await repository.count('circle-9'), 4);
      final pending = await repository.list('circle-9');
      expect(pending.single.name, 'Nia Novak');
      expect(pending.single.answers.first.answer, startsWith('I paint'));
      expect(pending.single.invitedByName, isNull);

      await repository.decide('req-1', approve: true);
      await repository.decide('req-2', approve: false, note: '  not now  ');
      await repository.decide('req-3', approve: false, note: '   ');
      expect(rpc.paramsOf('decide_join_request'), [
        {'request_id': 'req-1', 'approve': true},
        {'request_id': 'req-2', 'approve': false, 'decision_note': 'not now'},
        {'request_id': 'req-3', 'approve': false},
      ]);

      expect((await repository.listMine()).single.circleName, 'Pixel Painters');
      await repository.dismiss('req-1');
      await repository.cancel('circle-9');
      expect(rpc.paramsOf('cancel_join_request').single, {
        'target_circle_id': 'circle-9',
      });

      expect(
        await repository.acceptInvite('abc', answers: {'q1': 'Because'}),
        'circle-9',
      );
      expect(rpc.paramsOf('accept_circle_invite').single, {
        'invite_code': 'abc',
        'answers': [
          {'question_id': 'q1', 'answer': 'Because'},
        ],
      });

      expect(await repository.invitesSkippingReview('circle-9'), {
        'abc',
        'def',
      });
      expect(
        await repository.createInvite(
          circleId: 'circle-9',
          skipReview: true,
          expiresIn: const Duration(days: 7),
          maxUses: 5,
        ),
        'newcode',
      );
      expect(rpc.paramsOf('create_circle_invite').single, {
        'target_circle_id': 'circle-9',
        'expires_in_hours': 168,
        'max_uses': 5,
        'skip_review': true,
      });

      await repository.saveSettings(
        'circle-9',
        const CircleJoinSettings(
          mode: CircleJoinMode.apply,
          questions: [
            JoinQuestion(
              id: 'q1',
              kind: JoinQuestionKind.text,
              prompt: ' Why? ',
            ),
          ],
        ),
      );
      expect(rpc.paramsOf('set_circle_join_settings').single, {
        'target_circle_id': 'circle-9',
        'new_mode': 'apply',
        'question_list': [
          {'id': 'q1', 'kind': 'text', 'prompt': 'Why?', 'required': true},
        ],
      });
    });

    test(
      'a state that cannot be read falls back to joining as before',
      () async {
        final container = ProviderContainer(
          overrides: [circleRpcProvider.overrideWithValue(JoinRpc().call)],
        );
        addTearDown(container.dispose);
        expect(
          await container.read(
            circleJoinStateProvider((circleId: 'c', inviteCode: null)).future,
          ),
          isNull,
        );
        expect(await container.read(joinRequestCountProvider('c').future), 0);
        expect(await container.read(myJoinRequestsProvider.future), isEmpty);
      },
    );

    test('the Review badge adds join requests to held messages', () async {
      final rpc = JoinRpc()..answer('count_join_requests', 2);
      final guard = FakeGuardRpc()..results['count_message_reviews'] = 3;
      final container = ProviderContainer(
        retry: noProviderRetry,
        overrides: [
          circleRpcProvider.overrideWithValue(rpc.call),
          circleAiGuardRepositoryProvider.overrideWithValue(
            CircleAiGuardRepository(guard),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(messageReviewCountProvider('circle-1').future),
        5,
      );
    });
  });

  group('the Review page', () {
    testWidgets('lists the requests with a red count and their answers', (
      tester,
    ) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('list_join_requests', [
          pendingRequestJson(),
          pendingRequestJson(
            id: 'req-2',
            name: 'Omar',
            username: 'omar',
            invitedBy: 'Bob',
            answers: const [],
          ),
        ]);
      final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(
            circleId: 'circle-9',
            now: () => DateTime.utc(2026, 10, 22, 10),
          ),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Join requests'), findsOneWidget);
      final count = tester.widget<CountBadge>(
        find.byKey(const ValueKey('join-requests-count')),
      );
      expect(count.count, 2);
      expect(count.tone, BadgeTone.mention);
      expect(find.text('Nia Novak'), findsOneWidget);
      expect(find.text('@nia · 30m ago'), findsOneWidget);
      expect(find.text('Why do you want to join?'), findsOneWidget);
      expect(find.text('I paint pixel art and want critique.'), findsOneWidget);
      expect(find.text('A friend'), findsOneWidget);
      expect(find.text('Invited by Bob'), findsOneWidget);
      // The AI guard's queue is still on the same page.
      expect(find.text('Nothing to review'), findsOneWidget);
    });

    testWidgets('shows nothing extra without requests or permission', (
      tester,
    ) async {
      final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
      final none = JoinRpc()..answer('list_join_requests', []);
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: none,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Join requests'), findsNothing);
      expect(find.byKey(const ValueKey('join-requests-error')), findsNothing);
      expect(find.text('Nothing to review'), findsOneWidget);

      final denied = JoinRpc()
        ..handlers['list_join_requests'] = (_) =>
            throw Exception('Only members who can remove members (42501)');
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: denied,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Join requests'), findsNothing);
      expect(find.byKey(const ValueKey('join-requests-error')), findsNothing);
    });

    testWidgets('a failed load says so and tries again', (tester) async {
      var fail = true;
      final rpc = JoinRpc()
        ..handlers['list_join_requests'] = (_) {
          if (fail) {
            throw Exception('offline');
          }
          return [pendingRequestJson()];
        };
      final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load join requests.'), findsOneWidget);

      fail = false;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('join-requests-error')),
          matching: find.text('Try again'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nia Novak'), findsOneWidget);
    });

    testWidgets('Approve lets the person in and the card goes away', (
      tester,
    ) async {
      _tall(tester);
      var pending = [pendingRequestJson(), pendingRequestJson(id: 'req-2')];
      final rpc = JoinRpc()
        ..handlers['list_join_requests'] = (_) {
          return pending;
        }
        ..handlers['decide_join_request'] = (params) {
          pending = [
            for (final row in pending)
              if (row['id'] != params['request_id']) row,
          ];
          return null;
        }
        ..answer('count_join_requests', 0);
      final guard = FakeGuardRpc()
        ..results['list_message_reviews'] = []
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nia Novak'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('join-request-approve')).first,
      );
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('decide_join_request').single, {
        'request_id': 'req-1',
        'approve': true,
      });
      expect(find.text('Nia Novak'), findsOneWidget);
      expect(find.text('Nia Novak can join now.'), findsOneWidget);
      expect(
        tester
            .widget<CountBadge>(
              find.byKey(const ValueKey('join-requests-count')),
            )
            .count,
        1,
      );
    });

    testWidgets('Deny asks for an optional reason the person will read', (
      tester,
    ) async {
      _tall(tester);
      var pending = [pendingRequestJson()];
      final rpc = JoinRpc()
        ..handlers['list_join_requests'] = (_) {
          return pending;
        }
        ..handlers['decide_join_request'] = (_) {
          pending = [];
          return null;
        }
        ..answer('count_join_requests', 0);
      final guard = FakeGuardRpc()
        ..results['list_message_reviews'] = []
        ..results['count_message_reviews'] = 0;
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('join-request-deny')));
      await tester.pumpAndSettle();
      expect(find.text('Turn down Nia Novak?'), findsOneWidget);

      // Cancelling decides nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('decide_join_request'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('join-request-deny')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('join-deny-note')),
        'Please read the rules first',
      );
      await tester.tap(find.byKey(const ValueKey('join-deny-confirm')));
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('decide_join_request').single, {
        'request_id': 'req-1',
        'approve': false,
        'decision_note': 'Please read the rules first',
      });
      expect(find.text('Nia Novak'), findsNothing);
    });

    testWidgets('a request someone else decided first says so', (tester) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('list_join_requests', [pendingRequestJson()])
        ..handlers['decide_join_request'] = (_) =>
            throw Exception('Request already decided');
      final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('join-request-approve')));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't update this request. It may already be decided."),
        findsOneWidget,
      );
    });

    testWidgets('reads in Chinese', (tester) async {
      _tall(tester);
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      final rpc = JoinRpc()
        ..answer('list_join_requests', [pendingRequestJson(invitedBy: 'Bob')]);
      final guard = FakeGuardRpc()..results['list_message_reviews'] = [];
      await tester.pumpWidget(
        _app(
          CircleReviewScreen(circleId: 'circle-9'),
          rpc: rpc,
          guard: guard,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('入圈申请'), findsOneWidget);
      expect(find.text('由 Bob 邀请'), findsOneWidget);
      expect(find.text('批准'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
    });
  });

  group('settings', () {
    JoinRpc settingsRpc({
      String mode = 'open',
      List<Map<String, dynamic>> questions = const [],
    }) => JoinRpc()
      ..answer('get_circle_join_settings', {
        'join_mode': mode,
        'questions': questions,
      })
      ..answer('set_circle_join_settings', null);

    testWidgets('picks a mode and saves it', (tester) async {
      _tall(tester);
      final rpc = settingsRpc();
      await tester.pumpWidget(
        _app(const CircleJoinSettingsScreen(circleId: 'circle-9'), rpc: rpc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apply to join'), findsOneWidget);
      expect(find.text('Invite only'), findsOneWidget);
      // The questions only matter while people apply.
      expect(find.text('Questions'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('join-mode-invite_only')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('join-settings-save')));
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('set_circle_join_settings').single, {
        'target_circle_id': 'circle-9',
        'new_mode': 'invite_only',
        'question_list': <Object?>[],
      });
      expect(find.text('Join settings saved.'), findsNothing); // popped
    });

    testWidgets('adds questions, a choice with options, and saves them', (
      tester,
    ) async {
      _tall(tester);
      final rpc = settingsRpc(mode: 'apply');
      await tester.pumpWidget(
        _app(const CircleJoinSettingsScreen(circleId: 'circle-9'), rpc: rpc),
      );
      await tester.pumpAndSettle();
      expect(find.text('Questions'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('join-add-question')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('join-question-0')),
        'Why do you want to join?',
      );
      await tester.tap(find.byKey(const ValueKey('join-add-question')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('join-question-1')),
        'Which do you play?',
      );
      await tester.tap(find.byKey(const ValueKey('join-kind-choice-1')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('join-option-1-0')),
        'Chess',
      );
      await tester.enterText(
        find.byKey(const ValueKey('join-option-1-1')),
        'Go',
      );
      await tester.tap(find.byKey(const ValueKey('join-required-1')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('join-settings-save')));
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('set_circle_join_settings').single, {
        'target_circle_id': 'circle-9',
        'new_mode': 'apply',
        'question_list': [
          {
            'kind': 'text',
            'prompt': 'Why do you want to join?',
            'required': true,
          },
          {
            'kind': 'choice',
            'prompt': 'Which do you play?',
            'options': ['Chess', 'Go'],
            'required': false,
          },
        ],
      });
    });

    testWidgets('an unfinished question stops the save', (tester) async {
      _tall(tester);
      final rpc = settingsRpc(mode: 'apply');
      await tester.pumpWidget(
        _app(const CircleJoinSettingsScreen(circleId: 'circle-9'), rpc: rpc),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('join-add-question')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('join-settings-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('join-settings-error')), findsOneWidget);
      expect(rpc.paramsOf('set_circle_join_settings'), isEmpty);
    });

    testWidgets('at most five questions, and a question can be removed', (
      tester,
    ) async {
      _tall(tester, size: const Size(800, 4000));
      final rpc = settingsRpc(
        mode: 'apply',
        questions: [
          for (var i = 0; i < 5; i++)
            questionJson(id: 'q$i', prompt: 'Question text $i'),
        ],
      );
      await tester.pumpWidget(
        _app(const CircleJoinSettingsScreen(circleId: 'circle-9'), rpc: rpc),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('join-add-question')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('join-remove-question-0')));
      await tester.pump();
      expect(find.text('Question text 0'), findsNothing);
      expect(find.byKey(const ValueKey('join-add-question')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('join-settings-save')));
      await tester.pumpAndSettle();
      final saved =
          rpc.paramsOf('set_circle_join_settings').single['question_list']
              as List;
      expect(saved.map((q) => (q as Map)['id']), ['q1', 'q2', 'q3', 'q4']);
    });

    testWidgets('a failed load can be retried', (tester) async {
      var fail = true;
      final rpc = JoinRpc()
        ..handlers['get_circle_join_settings'] = (_) {
          if (fail) {
            throw Exception('offline');
          }
          return {'join_mode': 'open', 'questions': <Object?>[]};
        };
      await tester.pumpWidget(
        _app(const CircleJoinSettingsScreen(circleId: 'circle-9'), rpc: rpc),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load join settings.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Apply to join'), findsOneWidget);
    });
  });

  group('the invite page', () {
    const preview = CircleInvitePreview(
      code: 'abcdefgh23',
      alreadyMember: false,
      circle: CircleInvitePreviewCircle(
        id: 'circle-9',
        name: 'Pixel Painters',
        memberCount: 12,
      ),
    );

    Future<FakeCirclesRepository> pump(WidgetTester tester, JoinRpc rpc) async {
      _tall(tester, size: const Size(800, 1800));
      final repository = FakeCirclesRepository()..preview = preview;
      final router = GoRouter(
        initialLocation: '/invite/abcdefgh23',
        routes: [
          GoRoute(
            path: '${CircleRoutes.path}/:circleId',
            builder: (context, state) =>
                Text('Circle ${state.pathParameters['circleId']}'),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const Text('Home'),
          ),
          GoRoute(
            path: '/invite/:code',
            builder: (context, state) =>
                CircleInviteScreen(code: state.pathParameters['code']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            circlesRepositoryProvider.overrideWithValue(repository),
            contactsRepositoryProvider.overrideWithValue(
              FakeContactsRepository(),
            ),
            circleRpcProvider.overrideWithValue(rpc.call),
          ],
          child: MaterialApp.router(
            theme: WeCordTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('in a circle that reviews, answers go with a request', (
      tester,
    ) async {
      final rpc = JoinRpc()
        ..answer('get_circle_join_state', joinStateJson())
        ..answer('accept_circle_invite', 'circle-9');
      final repository = await pump(tester, rpc);

      expect(find.textContaining('approve everyone who joins'), findsOneWidget);
      expect(find.text('Why do you want to join?'), findsOneWidget);
      // The button waits for the required answer.
      final send = find.widgetWithText(WeCordButton, 'Send request');
      expect(tester.widget<WeCordButton>(send).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('join-answer-q1')),
        'I love pixel art',
      );
      await tester.tap(find.byKey(const ValueKey('join-option-q2-Search')));
      await tester.pump();
      expect(tester.widget<WeCordButton>(send).onPressed, isNotNull);

      // The server now has a request waiting.
      rpc.answer(
        'get_circle_join_state',
        joinStateJson(request: requestInfoJson()),
      );
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('accept_circle_invite').single, {
        'invite_code': 'abcdefgh23',
        'answers': [
          {'question_id': 'q1', 'answer': 'I love pixel art'},
          {'question_id': 'q2', 'answer': 'Search'},
        ],
      });
      // The plain join was not used, and the page stays, saying it waits.
      expect(repository.acceptedCodes, isEmpty);
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Circle circle-9'), findsNothing);
    });

    testWidgets('a waiting request can be withdrawn', (tester) async {
      final rpc = JoinRpc()
        ..answer(
          'get_circle_join_state',
          joinStateJson(request: requestInfoJson()),
        )
        ..answer('cancel_join_request', null);
      await pump(tester, rpc);
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.byKey(const ValueKey('join-questions')), findsNothing);

      rpc.answer('get_circle_join_state', joinStateJson());
      await tester.tap(find.byKey(const ValueKey('join-cancel-request')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('cancel_join_request').single, {
        'target_circle_id': 'circle-9',
      });
      expect(find.text('Waiting for review'), findsNothing);
      expect(find.text('Send request'), findsOneWidget);
    });

    testWidgets('a denied person reads the note and waits', (tester) async {
      final rpc = JoinRpc()
        ..answer(
          'get_circle_join_state',
          joinStateJson(
            request: requestInfoJson(
              status: 'denied',
              note: 'Read the rules first',
            ),
            retryAt: DateTime.now()
                .toUtc()
                .add(const Duration(hours: 5))
                .toIso8601String(),
          ),
        );
      await pump(tester, rpc);
      expect(find.text('Your request was turned down'), findsOneWidget);
      expect(
        find.textContaining('Their note: Read the rules first'),
        findsOneWidget,
      );
      final button = find.widgetWithText(WeCordButton, 'Try again tomorrow');
      expect(tester.widget<WeCordButton>(button).onPressed, isNull);
    });

    testWidgets('an invite that skips review joins at once, as before', (
      tester,
    ) async {
      final rpc = JoinRpc()
        ..answer('get_circle_join_state', joinStateJson(skipReview: true));
      final repository = await pump(tester, rpc);
      expect(find.byKey(const ValueKey('join-questions')), findsNothing);
      await tester.tap(find.widgetWithText(WeCordButton, 'Join circle'));
      await tester.pumpAndSettle();
      expect(repository.acceptedCodes, ['abcdefgh23']);
      expect(find.text('Circle circle-9'), findsOneWidget);
    });

    testWidgets('an open circle, or an unreadable state, joins as before', (
      tester,
    ) async {
      final rpc = JoinRpc(); // every call fails: the state is unknown
      final repository = await pump(tester, rpc);
      await tester.tap(find.widgetWithText(WeCordButton, 'Join circle'));
      await tester.pumpAndSettle();
      expect(repository.acceptedCodes, ['abcdefgh23']);
    });

    testWidgets('a refusal from the server is worded', (tester) async {
      final rpc = JoinRpc()
        ..answer('get_circle_join_state', joinStateJson())
        ..handlers['accept_circle_invite'] = (_) =>
            throw Exception('Banned from this circle');
      await pump(tester, rpc);
      await tester.enterText(
        find.byKey(const ValueKey('join-answer-q1')),
        'Hello',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(WeCordButton, 'Send request'));
      await tester.pumpAndSettle();
      expect(find.text("You're banned from this circle."), findsOneWidget);
    });
  });

  group('the invite sheet', () {
    Future<(JoinRpc, FakeCirclesRepository)> pump(
      WidgetTester tester, {
      required bool canSkip,
    }) async {
      _tall(tester, size: const Size(800, 2600));
      final rpc = JoinRpc()
        ..answer('list_circle_invites_skipping_review', ['skipcode1'])
        ..answer('create_circle_invite', 'madecode1');
      final repository = FakeCirclesRepository()
        ..invites = [
          CircleInvite(
            code: 'skipcode1',
            circleId: 'circle-1',
            createdBy: 'user-1',
            createdAt: DateTime.utc(2026, 10, 20),
            useCount: 2,
          ),
          CircleInvite(
            code: 'plaincode',
            circleId: 'circle-1',
            createdBy: 'user-1',
            createdAt: DateTime.utc(2026, 10, 20),
            useCount: 0,
          ),
        ];
      final permissions = canSkip
          ? CirclePermission.all
          : CirclePermission.maskOf([
              CirclePermission.viewChannel,
              CirclePermission.createInvites,
            ]);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            circlesRepositoryProvider.overrideWithValue(repository),
            contactsRepositoryProvider.overrideWithValue(
              FakeContactsRepository(),
            ),
            circleRpcProvider.overrideWithValue(rpc.call),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(
              body: CircleInviteSheet(detail: detail(permissions: permissions)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (rpc, repository);
    }

    testWidgets('members who may skip review can make such a link', (
      tester,
    ) async {
      final (rpc, repository) = await pump(tester, canSkip: true);
      expect(find.text('Skip review'), findsOneWidget);
      expect(find.textContaining('skips review'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('invite-skip-review')));
      await tester.pump();
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();
      expect(
        rpc.paramsOf('create_circle_invite').single['skip_review'],
        isTrue,
      );
      expect(repository.createdInvites, isEmpty);
    });

    testWidgets('without the switch the link is made as before', (
      tester,
    ) async {
      final (rpc, repository) = await pump(tester, canSkip: true);
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('create_circle_invite'), isEmpty);
      expect(repository.createdInvites, hasLength(1));
    });

    testWidgets('others do not see the option', (tester) async {
      final (rpc, _) = await pump(tester, canSkip: false);
      expect(find.text('Skip review'), findsNothing);
      expect(find.byKey(const ValueKey('invite-skip-review')), findsNothing);
      expect(rpc.paramsOf('list_circle_invites_skipping_review'), isEmpty);
    });
  });

  group('Notifications', () {
    Future<JoinRpc> pump(
      WidgetTester tester,
      MyJoinRequest request, {
      List<Override> overrides = const [],
    }) async {
      _tall(tester, size: const Size(800, 900));
      final rpc = JoinRpc()
        ..answer('cancel_join_request', null)
        ..answer('dismiss_join_request_result', null)
        ..answer('list_my_join_requests', []);
      await tester.pumpWidget(
        _app(
          Scaffold(body: JoinRequestInboxCard(request: request)),
          rpc: rpc,
          overrides: overrides,
        ),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('an approval opens the circle and is dismissed', (
      tester,
    ) async {
      final request = MyJoinRequest.fromJson(myRequestJson(status: 'approved'));
      _tall(tester, size: const Size(800, 900));
      final rpc = JoinRpc()
        ..answer('dismiss_join_request_result', null)
        ..answer('list_my_join_requests', []);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                Scaffold(body: JoinRequestInboxCard(request: request)),
          ),
          GoRoute(
            path: '${CircleRoutes.path}/:circleId',
            builder: (context, state) =>
                Text('Circle ${state.pathParameters['circleId']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
          child: MaterialApp.router(
            theme: WeCordTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Pixel Painters approved your request to join',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.text('Open it to read the rules and say hello.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('join-request-open')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('dismiss_join_request_result').single, {
        'request_id': 'req-1',
      });
      expect(find.text('Circle circle-9'), findsOneWidget);
    });

    testWidgets('a denial shows the note and Got it dismisses', (tester) async {
      final rpc = await pump(
        tester,
        MyJoinRequest.fromJson(
          myRequestJson(status: 'denied', note: 'Read the rules first'),
        ),
      );
      expect(
        find.textContaining('turned down your request', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Read the rules first'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join-request-dismiss')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('dismiss_join_request_result'), hasLength(1));
    });

    testWidgets('a waiting request can be cancelled', (tester) async {
      final rpc = await pump(tester, MyJoinRequest.fromJson(myRequestJson()));
      expect(
        find.textContaining('is waiting for review', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('join-request-cancel')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('cancel_join_request').single, {
        'target_circle_id': 'circle-9',
      });
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      await pump(
        tester,
        MyJoinRequest.fromJson(myRequestJson(status: 'approved')),
      );
      expect(
        find.textContaining('通过了你的入圈申请', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('打开圈子'), findsOneWidget);
    });
  });
}
