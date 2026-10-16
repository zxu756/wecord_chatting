import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_sheet.dart';
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'later_fakes.dart';

final _now = DateTime(2026, 10, 17, 15, 30);

ScheduledMessage _scheduled(
  String id,
  String body, {
  Duration after = const Duration(hours: 2),
  ScheduledMessageStatus status = ScheduledMessageStatus.pending,
  String? error,
  List<Map<String, dynamic>> mentions = const [],
}) {
  return ScheduledMessage(
    id: id,
    conversationId: 'conversation-1',
    body: body,
    sendAt: _now.add(after).toUtc(),
    status: status,
    lastError: error,
    mentions: mentions,
  );
}

Widget _host(
  Widget child,
  FakeScheduledMessagesRepository repository, {
  RecordingPushRepository? push,
  bool dark = false,
}) {
  return ProviderScope(
    overrides: [
      scheduledMessagesRepositoryProvider.overrideWithValue(repository),
      pushRepositoryProvider.overrideWithValue(
        push ?? RecordingPushRepository(),
      ),
    ],
    child: MaterialApp(
      theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

void main() {
  group('model', () {
    test('parses a server row', () {
      final message = ScheduledMessage.fromJson({
        'id': 's1',
        'conversation_id': 'c1',
        'body': 'See you',
        'mentions': [
          {'kind': 'user', 'user_id': 'u2', 'start': 0, 'end': 4},
        ],
        'send_at': '2026-10-18T01:00:00+00:00',
        'status': 'failed',
        'last_error': 'automod:Blocked word',
      });
      expect(message.sendAt, DateTime.utc(2026, 10, 18, 1));
      expect(message.isFailed, isTrue);
      expect(message.mentions.single['user_id'], 'u2');
      expect(message.failureReason, 'AutoMod blocked it: Blocked word');
    });

    test('names why a message was not sent', () {
      expect(
        _scheduled('s', 'x', status: ScheduledMessageStatus.failed).failureReason,
        'It could not be sent.',
      );
      expect(
        _scheduled(
          's',
          'x',
          status: ScheduledMessageStatus.failed,
          error: 'Conversation not found or caller is not a member',
        ).failureReason,
        'Conversation not found or caller is not a member',
      );
      expect(_scheduled('s', 'x').failureReason, isNull);
    });

    test('mentions follow their text when the message is edited', () {
      final mentions = [
        {'kind': 'user', 'user_id': 'u2', 'start': 6, 'end': 10},
      ];
      expect(
        retainMentions(
          oldBody: 'Hello @Bob',
          newBody: 'Oh, hello @Bob!',
          mentions: mentions,
        ).single,
        containsPair('start', 10),
      );
      // The text moved: the closest copy is taken.
      expect(
        retainMentions(
          oldBody: 'Hello @Bob and @Bob',
          newBody: 'Hi @Bob and @Bob',
          mentions: [
            {'kind': 'user', 'user_id': 'u2', 'start': 15, 'end': 19},
          ],
        ).single,
        allOf(containsPair('start', 12), containsPair('end', 16)),
      );
      // Gone with the text.
      expect(
        retainMentions(
          oldBody: 'Hello @Bob',
          newBody: 'Hello there',
          mentions: mentions,
        ),
        isEmpty,
      );
    });
  });

  group('when sheet', () {
    Future<DateTime?> open(
      WidgetTester tester, {
      Future<DateTime?> Function(BuildContext, DateTime)? customPicker,
    }) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showWeCordSheet<DateTime>(
                    context,
                    title: 'When',
                    builder: (context, _) => WhenSheet(
                      picks: schedulePicks,
                      customPicker: customPicker,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await withClock(Clock.fixed(_now), () async {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      });
      return result;
    }

    testWidgets('lists the quick picks with their times', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await open(tester);
      });
      expect(find.byKey(const ValueKey('when-inOneHour')), findsOneWidget);
      expect(find.byKey(const ValueKey('when-tonight')), findsOneWidget);
      expect(find.byKey(const ValueKey('when-tomorrowMorning')), findsOneWidget);
      expect(find.text('Today 4:30 PM'), findsOneWidget);
      expect(find.text('Today 8:00 PM'), findsOneWidget);
      expect(find.text('Tomorrow 9:00 AM'), findsOneWidget);
      expect(find.text('Pick date and time'), findsOneWidget);
      expect(find.textContaining('Your time zone: '), findsOneWidget);
    });

    testWidgets('returns the quick pick that was tapped', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showWhenSheet(
                    context,
                    title: 'When',
                    picks: schedulePicks,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('when-tomorrowMorning')));
      await tester.pumpAndSettle();
      final tomorrow = clock.now().add(const Duration(days: 1));
      expect(picked, isNotNull);
      expect(picked!.hour, 9);
      expect(picked!.day, tomorrow.day);
    });

    testWidgets('a custom time in the future is returned', (tester) async {
      DateTime? picked;
      final custom = DateTime(2026, 11, 3, 14, 45);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showWeCordSheet<DateTime>(
                    context,
                    builder: (context, _) => WhenSheet(
                      picks: schedulePicks,
                      customPicker: (context, now) async => custom,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('when-custom')));
      await tester.pumpAndSettle();
      expect(picked, custom);
    });

    testWidgets('a custom time in the past is refused', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: WhenSheet(
              picks: schedulePicks,
              customPicker: (context, now) async =>
                  now.subtract(const Duration(hours: 1)),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('when-custom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('when-error')), findsOneWidget);
      expect(find.text('Pick a time in the future.'), findsOneWidget);
    });

    testWidgets('the real pickers return the chosen date and time', (
      tester,
    ) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await pickDateAndTime(
                    context,
                    now: DateTime(2026, 10, 17, 15, 30),
                    initial: DateTime(2026, 10, 18, 9),
                  );
                },
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      // Move to the 20th, then accept the date and the suggested time.
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2026, 10, 20, 9));
    });
  });

  group('scheduled list', () {
    Widget sheetHost(
      FakeScheduledMessagesRepository repository, {
      RecordingPushRepository? push,
      VoidCallback? onSent,
    }) {
      return _host(
        Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () => showScheduledMessagesSheet(
              context,
              conversationId: 'conversation-1',
              onSent: onSent,
            ),
            child: const Text('Open'),
          ),
        ),
        repository,
        push: push,
      );
    }

    testWidgets('shows queued and failed messages', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!', after: const Duration(hours: 18)),
        _scheduled(
          'b',
          'Standup notes',
          after: const Duration(minutes: -10),
          status: ScheduledMessageStatus.failed,
          error: 'automod:Spam',
        ),
      ]);
      await tester.pumpWidget(sheetHost(repository));
      await _openSheet(tester);

      expect(find.text('Scheduled messages'), findsOneWidget);
      expect(find.text('Happy birthday!'), findsOneWidget);
      expect(find.text('Standup notes'), findsOneWidget);
      expect(find.text('AutoMod blocked it: Spam'), findsOneWidget);
      expect(find.byKey(const ValueKey('scheduled-send-b')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('says when there are none', (tester) async {
      await tester.pumpWidget(sheetHost(FakeScheduledMessagesRepository()));
      await _openSheet(tester);
      expect(find.text('No scheduled messages'), findsOneWidget);
    });

    testWidgets('deletes a message', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!'),
        _scheduled('b', 'Other one', after: const Duration(hours: 5)),
      ]);
      await tester.pumpWidget(sheetHost(repository));
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('scheduled-delete-a')));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['a']);
      expect(find.text('Happy birthday!'), findsNothing);
      expect(find.text('Other one'), findsOneWidget);
    });

    testWidgets('sends now, asks for the push and reloads the chat', (
      tester,
    ) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!'),
      ]);
      final push = RecordingPushRepository();
      var reloads = 0;
      await tester.pumpWidget(
        sheetHost(repository, push: push, onSent: () => reloads++),
      );
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('scheduled-send-a')));
      await tester.pumpAndSettle();

      expect(repository.sentNow, ['a']);
      expect(push.notified, ['sent-a']);
      expect(reloads, 1);
      expect(find.text('Happy birthday!'), findsNothing);
    });

    testWidgets('explains a refused send', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!'),
      ])..failWith = const PostgrestException(message: 'nope', code: '53400');
      await tester.pumpWidget(sheetHost(repository));
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('scheduled-send-a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('scheduled-error')), findsOneWidget);
      expect(find.text('You have too many scheduled messages.'), findsOneWidget);
      expect(find.text('Happy birthday!'), findsOneWidget);
    });

    testWidgets('edits the text and time', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!'),
      ]);
      await tester.pumpWidget(sheetHost(repository));
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('scheduled-edit-a')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scheduled-edit-field')),
        'Happy birthday, Ada!',
      );
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('when-tomorrowMorning')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-save')));
      await tester.pumpAndSettle();

      final edited = repository.messages.single;
      expect(edited.body, 'Happy birthday, Ada!');
      expect(edited.sendAt.toLocal().hour, 9);
      expect(find.text('Happy birthday, Ada!'), findsOneWidget);
    });

    testWidgets('an empty edit is not saved', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'Happy birthday!'),
      ]);
      await tester.pumpWidget(sheetHost(repository));
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('scheduled-edit-a')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scheduled-edit-field')),
        '   ',
      );
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('scheduled-edit-error')), findsOneWidget);
      expect(repository.messages.single.body, 'Happy birthday!');
    });
  });

  group('banner', () {
    Widget bannerHost(
      FakeScheduledMessagesRepository repository,
      VoidCallback onOpen,
    ) {
      return _host(
        ScheduledMessagesBanner(
          conversationId: 'conversation-1',
          onOpen: onOpen,
        ),
        repository,
      );
    }

    testWidgets('counts what is waiting and when the next goes', (
      tester,
    ) async {
      var opened = 0;
      final repository = FakeScheduledMessagesRepository([
        _scheduled('a', 'One', after: const Duration(days: 1)),
        _scheduled('b', 'Two', after: const Duration(days: 3)),
      ]);
      await tester.pumpWidget(bannerHost(repository, () => opened++));
      await tester.pumpAndSettle();

      expect(find.text('2 scheduled messages'), findsOneWidget);
      expect(find.textContaining('Next: '), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scheduled-banner')));
      expect(opened, 1);
    });

    testWidgets('counts failures apart', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        _scheduled(
          'a',
          'One',
          status: ScheduledMessageStatus.failed,
          error: 'x',
        ),
      ]);
      await tester.pumpWidget(bannerHost(repository, () {}));
      await tester.pumpAndSettle();
      expect(find.text('1 not sent'), findsOneWidget);
    });

    testWidgets('is not there without scheduled messages', (tester) async {
      await tester.pumpWidget(
        bannerHost(FakeScheduledMessagesRepository(), () {}),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scheduled-banner')), findsNothing);
    });
  });
}
