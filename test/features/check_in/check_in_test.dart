import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/check_in/check_in_card.dart';
import 'package:wecord/features/check_in/check_in_create_page.dart';
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_page.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import 'check_in_fakes.dart';

Widget app(FakeCheckInRepository repository, Widget home) {
  return ProviderScope(
    retry: (count, error) => null,
    overrides: [
      ...checkInOverrides(repository),
      authRepositoryProvider.overrideWithValue(
        chat_fakes.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(theme: WeCordTheme.light(), home: home),
  );
}

Widget cardApp(FakeCheckInRepository repository) => app(
  repository,
  const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: CheckInCardView(
        card: CheckInCard(checkInId: 'ci-1', title: 'Read 20 pages'),
      ),
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

/// [name] checked in on each of the [days] (0 is today, 1 yesterday ...).
void ran(
  FakeCheckInRepository repository,
  String userId,
  String name,
  Iterable<int> days,
) {
  for (final back in days) {
    repository.addEntry(
      userId,
      name,
      fakeToday.subtract(Duration(days: back)),
      note: back == 0 ? 'chapter ${back + 1}' : '',
    );
  }
}

void main() {
  group('models', () {
    test('a snapshot reads the server and works out the share', () {
      final snapshot = CheckInSnapshot.fromJson({
        'id': 'ci-1',
        'conversation_id': 'g',
        'message_id': 'm',
        'title': 'Read',
        'description': 'Daily',
        'time_zone': 'Pacific/Auckland',
        'remind_minute': 540,
        'ends_on': '2026-12-31',
        'today': '2026-10-28',
        'closed': false,
        'can_manage': true,
        'today_count': 18,
        'member_total': 30,
        'my_checked_in': true,
        'my_note': 'ok',
        'my_photo': {'bucket': 'chat-images', 'path': 'g/check-ins/ci-1/a.jpg'},
        'my_streak': 7,
        'my_best_streak': 12,
        'my_total_days': 40,
      });
      expect(snapshot.todayFraction, closeTo(0.6, 0.0001));
      expect(snapshot.endsOn, DateTime(2026, 12, 31));
      expect(snapshot.today, DateTime(2026, 10, 28));
      expect(snapshot.remindMinute, 540);
      expect(snapshot.myPhoto?.path, 'g/check-ins/ci-1/a.jpg');
      expect(snapshot.isOpen, isTrue);
      expect(snapshot.streakAtRisk, isFalse);
    });

    test('an empty chat has a share of zero, not a division by zero', () {
      final snapshot = CheckInSnapshot(
        id: 'a',
        conversationId: 'b',
        title: 't',
        today: DateTime(2026),
        memberTotal: 0,
        todayCount: 3,
      );
      expect(snapshot.todayFraction, 0);
    });

    test('the detail reads the list, the leaders and my days', () {
      final detail = CheckInDetail.fromJson({
        'id': 'ci-1',
        'conversation_id': 'g',
        'title': 'Read',
        'today': '2026-10-28',
        'entries': [
          {
            'id': 'e1',
            'user_id': 'u',
            'name': 'Bob',
            'day': '2026-10-28',
            'note': 'x',
            'streak': 3,
            'created_at': '2026-10-28T08:00:00Z',
          },
        ],
        'leaders': [
          {'user_id': 'u', 'name': 'Bob', 'streak': 3},
        ],
        'my_days': ['2026-10-27', '2026-10-28'],
      });
      expect(detail.entries.single.name, 'Bob');
      expect(detail.leaders.single.streak, 3);
      expect(detail.myDays, {DateTime(2026, 10, 27), DateTime(2026, 10, 28)});
    });

    test('dates are written and read the way the server does', () {
      expect(checkInDateText(DateTime(2026, 3, 5)), '2026-03-05');
      expect(checkInDateFrom('2026-03-05'), DateTime(2026, 3, 5));
      expect(checkInDateFrom('x'), isNull);
      expect(checkInDateFrom(null), isNull);
    });

    test('a message with a check-in attachment is a check-in card', () {
      ChatMessage message(
        Map<String, dynamic>? attachment, {
        DateTime? recalled,
      }) => ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'u',
        type: MessageType.text,
        body: 'x',
        createdAt: DateTime(2026),
        attachment: attachment,
        recalledAt: recalled,
      );
      expect(
        message({
          'kind': 'check_in',
          'check_in_id': 'ci',
          'title': 'T',
        }).checkInCard?.checkInId,
        'ci',
      );
      expect(message({'kind': 'form', 'form_id': 'f'}).checkInCard, isNull);
      expect(message(null).checkInCard, isNull);
      expect(
        message({
          'kind': 'check_in',
          'check_in_id': 'ci',
        }, recalled: DateTime(2026)).checkInCard,
        isNull,
      );
    });

    test('server refusals become the right failure', () {
      CheckInFailureKind kind(String message, {String? code}) =>
          CheckInException.fromPostgrest(
            PostgrestException(message: message, code: code),
          ).kind;
      expect(kind('check_in_closed'), CheckInFailureKind.closed);
      expect(kind('check_in_too_many'), CheckInFailureKind.tooMany);
      expect(kind('check_in_photo_invalid'), CheckInFailureKind.badPhoto);
      expect(kind('check_in_not_allowed'), CheckInFailureKind.notAllowed);
      expect(kind('Check-in not found'), CheckInFailureKind.gone);
      expect(kind('nope', code: '42501'), CheckInFailureKind.forbidden);
      expect(kind('boom'), CheckInFailureKind.other);
      for (final value in CheckInFailureKind.values) {
        expect(CheckInException(value).message, isNotEmpty);
      }
    });

    test('the words are Chinese in Chinese', () {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(tr('{count}-day streak', {'count': 7}), '连续 7 天');
      expect(tr('Daily check-in'), '每日打卡');
      expect(tr('Check in'), '打卡');
    });
  });

  group('the card', () {
    testWidgets('shows today, my run and a Check in button', (tester) async {
      final repository = FakeCheckInRepository();
      ran(repository, 'user-3', 'Bob', [0, 1, 2]);
      ran(repository, 'user-1', 'Ada', [1, 2, 3]);
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);

      expect(find.text('Read 20 pages'), findsOneWidget);
      expect(find.text('Today 1/30'), findsOneWidget);
      // Yesterday and two days before: a run of 3 still alive, to keep going.
      expect(find.text('You are on a 3-day streak'), findsOneWidget);
      expect(find.byKey(const ValueKey('check-in-do-ci-1')), findsOneWidget);
    });

    testWidgets('one tap checks in, and the card says so', (tester) async {
      final repository = FakeCheckInRepository();
      ran(repository, 'user-1', 'Ada', [1, 2]);
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('check-in-do-ci-1')));
      await settle(tester);

      expect(repository.calls, contains('submit'));
      expect(find.byKey(const ValueKey('check-in-do-ci-1')), findsNothing);
      expect(find.text('Checked in today'), findsOneWidget);
      expect(find.text('You are on a 3-day streak'), findsOneWidget);
      expect(find.text('Checked in. 3-day streak!'), findsOneWidget);
      expect(find.text('Today 1/30'), findsOneWidget);
    });

    testWidgets('a first day says Checked in without a streak', (tester) async {
      final repository = FakeCheckInRepository();
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      expect(find.text('Check in today to start a streak'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('check-in-do-ci-1')));
      await settle(tester);
      expect(find.text('Checked in.'), findsOneWidget);
    });

    testWidgets('someone else checking in changes the count live', (
      tester,
    ) async {
      final repository = FakeCheckInRepository();
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      expect(find.text('Today 0/30'), findsOneWidget);

      ran(repository, 'user-3', 'Bob', [0]);
      repository.touch();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Today 1/30'), findsOneWidget);
    });

    testWidgets('a closed check-in has no button and says Closed', (
      tester,
    ) async {
      final repository = FakeCheckInRepository(closed: true);
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      expect(find.byKey(const ValueKey('check-in-do-ci-1')), findsNothing);
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('a refused check-in tells the person and refreshes', (
      tester,
    ) async {
      final repository = FakeCheckInRepository();
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      repository.closed = true;
      await tester.tap(find.byKey(const ValueKey('check-in-do-ci-1')));
      await settle(tester);
      expect(find.text('This check-in is closed.'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('a card that cannot load says so and tries again on tap', (
      tester,
    ) async {
      final repository = FakeCheckInRepository()..getError = StateError('x');
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      expect(
        find.text("Couldn't load this check-in. Tap to try again."),
        findsOneWidget,
      );
      repository.getError = null;
      await tester.tap(
        find.text("Couldn't load this check-in. Tap to try again."),
      );
      await settle(tester);
      expect(find.text('Today 0/30'), findsOneWidget);
    });

    testWidgets('the card reads as one button to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repository = FakeCheckInRepository();
      ran(repository, 'user-1', 'Ada', [1, 2]);
      await tester.pumpWidget(cardApp(repository));
      await settle(tester);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Daily check-in: Read 20 pages, Today 0/30, You are on a 2-day streak',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the page', () {
    Future<void> open(WidgetTester tester, FakeCheckInRepository repo) async {
      // Tall, so the whole page is built (a list builds what is on screen).
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(repo, const CheckInPage(checkInId: 'ci-1')));
      await settle(tester);
    }

    testWidgets('lists today, the longest runs and my days', (tester) async {
      final repository = FakeCheckInRepository(
        description: 'Post a line a day.',
      );
      ran(repository, 'user-3', 'Bob', [0, 1, 2, 3]);
      ran(repository, 'user-4', 'Cy', [0]);
      ran(repository, 'user-1', 'Ada', [1, 2]);
      await open(tester, repository);

      expect(find.text('Today 2/30'), findsWidgets);
      expect(find.text('Post a line a day.'), findsOneWidget);
      expect(find.text('Longest streaks'), findsOneWidget);
      expect(find.text('4-day streak'), findsWidgets);
      expect(find.byKey(const ValueKey('check-in-entry-e0')), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('Cy'), findsOneWidget);
      expect(find.text('chapter 1'), findsNWidgets(2));
      expect(find.text('Your last 5 weeks'), findsOneWidget);
    });

    testWidgets('Check in on the page checks in; undo takes it back', (
      tester,
    ) async {
      final repository = FakeCheckInRepository();
      await open(tester, repository);

      await tester.tap(find.byKey(const ValueKey('check-in-now')));
      await settle(tester);
      expect(repository.submitted, hasLength(1));
      expect(find.byKey(const ValueKey('check-in-edit')), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('check-in-undo')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('check-in-undo')));
      await settle(tester);
      expect(repository.calls, contains('undo'));
      expect(find.byKey(const ValueKey('check-in-now')), findsOneWidget);
      expect(find.text("Today's check-in was taken back."), findsOneWidget);
    });

    testWidgets('the note sheet sends a note and a picture', (tester) async {
      final repository = FakeCheckInRepository();
      await open(tester, repository);

      await tester.tap(find.byKey(const ValueKey('check-in-with-note')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('check-in-note-field')),
        'Read two chapters',
      );
      await tester.tap(find.byKey(const ValueKey('check-in-photo-add')));
      await settle(tester);
      expect(repository.uploads, hasLength(1));
      expect(
        find.byKey(const ValueKey('check-in-photo-remove')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('check-in-save')));
      await settle(tester);

      expect(repository.submitted.single.note, 'Read two chapters');
      expect(
        repository.submitted.single.photo?.path,
        'group-1/check-ins/ci-1/1.jpg',
      );
      expect(find.text('Read two chapters'), findsOneWidget);
    });

    testWidgets('an earlier day is one tap back, and forward again', (
      tester,
    ) async {
      final repository = FakeCheckInRepository();
      repository.addEntry(
        'user-3',
        'Bob',
        fakeToday.subtract(const Duration(days: 1)),
        note: 'yesterday I ran',
      );
      await open(tester, repository);
      expect(find.text('Nobody has checked in yet today.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('check-in-day-back')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('check-in-day-back')));
      await settle(tester);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('yesterday I ran'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('check-in-day-forward')));
      await settle(tester);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('only its maker and moderators can close it', (tester) async {
      final plain = FakeCheckInRepository();
      await open(tester, plain);
      await tester.scrollUntilVisible(
        find.text('Your last 5 weeks'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('check-in-close')), findsNothing);

      final manager = FakeCheckInRepository(canManage: true);
      await open(tester, manager);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('check-in-close')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('check-in-close')));
      await settle(tester);
      expect(manager.closed, isTrue);
      expect(find.text('Reopen this check-in'), findsOneWidget);
      // A closed check-in has no bar to check in with.
      expect(find.byKey(const ValueKey('check-in-now')), findsNothing);
    });

    testWidgets('a check-in that went away says so', (tester) async {
      final repository = FakeCheckInRepository()
        ..detailError = const CheckInException(CheckInFailureKind.gone);
      await open(tester, repository);
      expect(
        find.text("This check-in isn't available any more."),
        findsOneWidget,
      );
    });

    testWidgets('the picture of a check-in opens full size', (tester) async {
      final repository = FakeCheckInRepository();
      repository.addEntry(
        'user-3',
        'Bob',
        fakeToday,
        photo: const FormImageAnswer(
          bucket: 'chat-images',
          path: 'group-1/check-ins/ci-1/p.jpg',
        ),
      );
      final handle = tester.ensureSemantics();
      await open(tester, repository);
      expect(find.bySemanticsLabel('Open picture'), findsOneWidget);
      handle.dispose();
    });
  });

  group('making one', () {
    /// The create page, opened over a page with a button as it is from the
    /// chat, so that it can close itself. [posted] receives what it answers.
    Future<void> launch(
      WidgetTester tester,
      FakeCheckInRepository repository,
      List<bool?> posted,
    ) async {
      await tester.pumpWidget(
        app(
          repository,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => posted.add(
                  await showCheckInCreate(context, conversationId: 'group-1'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('posts the title, the zone and the settings', (tester) async {
      final repository = FakeCheckInRepository();
      final posted = <bool?>[];
      await launch(tester, repository, posted);

      await tester.tap(find.byKey(const ValueKey('check-in-post')));
      await settle(tester);
      expect(find.text('Give the check-in a title.'), findsOneWidget);
      expect(repository.created, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('check-in-title-field')),
        '  Read 20 pages ',
      );
      await tester.tap(find.byKey(const ValueKey('check-in-setting-remind')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('check-in-setting-remind-time')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('check-in-post')));
      await settle(tester);

      final (conversation, draft) = repository.created.single;
      expect(conversation, 'group-1');
      expect(draft.title.trim(), 'Read 20 pages');
      expect(draft.remindMinute, 20 * 60);
      expect(draft.endsOn, isNull);
      expect(posted, [true]);
    });

    testWidgets('a refusal stays on the page with the reason', (tester) async {
      final repository = FakeCheckInRepository()
        ..createError = const CheckInException(CheckInFailureKind.tooMany);
      final posted = <bool?>[];
      await launch(tester, repository, posted);
      await tester.enterText(
        find.byKey(const ValueKey('check-in-title-field')),
        'Run',
      );
      await tester.tap(find.byKey(const ValueKey('check-in-post')));
      await settle(tester);
      expect(
        find.text('This chat already has 5 open check-ins. Close one first.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('check-in-create-page')),
        findsOneWidget,
      );
      expect(posted, isEmpty);
    });
  });
}
