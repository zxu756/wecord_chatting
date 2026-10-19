import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/later/schedule_repeat.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_sheet.dart';
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'later_fakes.dart';

/// Repeating scheduled messages (D4): the rule the app shows, the same
/// calendar arithmetic as the server, the repeat choice in the sheets.
/// The suite runs in the machine's zone, and with `TZ=America/New_York` and
/// the like in CI; the UTC cases stand for a zone of their own.
void main() {
  final localizations = DefaultMaterialLocalizations();

  group('the next send', () {
    DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
        DateTime.utc(y, m, d, h, min);

    ScheduleRepeat rule(
      RepeatKind kind, {
      int? day,
      int hour = 9,
      int minute = 0,
      DateTime? until,
    }) => ScheduleRepeat(
      kind: kind,
      day: day,
      hour: hour,
      minute: minute,
      until: until,
    );

    test('daily is the next 9:00, tomorrow once it has passed', () {
      final daily = rule(RepeatKind.daily);
      expect(daily.nextAfter(utc(2030, 5, 6, 8)), utc(2030, 5, 6, 9));
      expect(daily.nextAfter(utc(2030, 5, 6, 9)), utc(2030, 5, 7, 9));
      expect(
        daily.nextAfter(utc(2030, 5, 6, 9, 0).add(const Duration(seconds: 40))),
        utc(2030, 5, 7, 9),
      );
    });

    test('weekdays skip the weekend', () {
      final weekdays = rule(RepeatKind.weekdays);
      // 2030-05-10 is a Friday.
      expect(weekdays.nextAfter(utc(2030, 5, 10, 9)), utc(2030, 5, 13, 9));
      expect(weekdays.nextAfter(utc(2030, 5, 11, 12)), utc(2030, 5, 13, 9));
      expect(weekdays.nextAfter(utc(2030, 5, 13, 8)), utc(2030, 5, 13, 9));
    });

    test('weekly is the chosen weekday', () {
      final wednesdays = rule(RepeatKind.weekly, day: DateTime.wednesday);
      expect(wednesdays.nextAfter(utc(2030, 5, 10)), utc(2030, 5, 15, 9));
      expect(wednesdays.nextAfter(utc(2030, 5, 15, 9)), utc(2030, 5, 22, 9));
    });

    test('monthly goes to the last day of a month without the day', () {
      final thirtyFirst = rule(RepeatKind.monthly, day: 31, hour: 10);
      expect(thirtyFirst.nextAfter(utc(2030, 1, 31, 10)), utc(2030, 2, 28, 10));
      expect(thirtyFirst.nextAfter(utc(2030, 2, 28, 10)), utc(2030, 3, 31, 10));
      expect(thirtyFirst.nextAfter(utc(2030, 3, 31, 10)), utc(2030, 4, 30, 10));
      expect(thirtyFirst.nextAfter(utc(2030, 4, 30, 10)), utc(2030, 5, 31, 10));
      // A leap year has a 29th of February.
      expect(thirtyFirst.nextAfter(utc(2032, 1, 31, 10)), utc(2032, 2, 29, 10));
      expect(
        rule(
          RepeatKind.monthly,
          day: 29,
          hour: 10,
        ).nextAfter(utc(2030, 1, 29, 10)),
        utc(2030, 2, 28, 10),
      );
      expect(
        rule(
          RepeatKind.monthly,
          day: 1,
          hour: 10,
        ).nextAfter(utc(2030, 12, 1, 10)),
        utc(2031, 1, 1, 10),
      );
    });

    test('the end date is the last day, and counts', () {
      final until = DateTime(2030, 5, 7);
      final daily = rule(RepeatKind.daily, until: until);
      expect(daily.nextAfter(utc(2030, 5, 6, 9)), utc(2030, 5, 7, 9));
      expect(daily.nextAfter(utc(2030, 5, 7, 9)), isNull);
    });

    test('a rule without its day or time has no next send', () {
      expect(
        const ScheduleRepeat(kind: RepeatKind.daily).nextAfter(utc(2030, 5, 6)),
        isNull,
      );
      expect(rule(RepeatKind.weekly).nextAfter(utc(2030, 5, 6)), isNull);
    });

    test('9:00 stays 9:00 on the clock, whatever the zone does', () {
      final daily = rule(RepeatKind.daily);
      var at = DateTime(2030, 3, 1, 8);
      for (var i = 0; i < 400; i++) {
        final next = daily.nextAfter(at)!;
        expect(next.hour, 9, reason: '$next');
        expect(next.minute, 0);
        at = next;
      }
    });

    test(
      'a time in the skipped hour lands after the gap, as on the server',
      () {
        final night = rule(RepeatKind.daily, hour: 2, minute: 30);
        final gap = DateTime(2030, 3, 10, 2, 30);
        final next = night.nextAfter(DateTime(2030, 3, 9, 2, 30))!;
        if (gap.hour == 3) {
          // This machine's zone skips 02:30 that night (New York).
          expect(next.hour, 3);
          expect(next.minute, 30);
        } else {
          expect(next, gap);
        }
      },
    );
  });

  group('the first send', () {
    test('weekdays set for a Saturday go out on Monday', () {
      const weekdays = ScheduleRepeat(kind: RepeatKind.weekdays);
      // 2030-05-11 is a Saturday.
      final first = weekdays.firstSend(DateTime(2030, 5, 11, 10));
      expect(first, DateTime(2030, 5, 13, 10));
    });

    test('a fitting time is kept as it is', () {
      const daily = ScheduleRepeat(kind: RepeatKind.daily);
      expect(
        daily.firstSend(DateTime(2030, 5, 11, 10, 15)),
        DateTime(2030, 5, 11, 10, 15),
      );
      const monthly = ScheduleRepeat(kind: RepeatKind.monthly);
      expect(
        monthly.firstSend(DateTime(2030, 5, 31, 8)),
        DateTime(2030, 5, 31, 8),
      );
    });

    test('startingAt takes the weekday, day and time of the first send', () {
      final rule = const ScheduleRepeat(
        kind: RepeatKind.weekly,
      ).startingAt(DateTime(2030, 5, 13, 9, 30));
      expect(rule.day, DateTime.monday);
      expect(rule.hour, 9);
      expect(rule.minute, 30);
      expect(
        const ScheduleRepeat(
          kind: RepeatKind.monthly,
        ).startingAt(DateTime(2030, 5, 31, 9)).day,
        31,
      );
    });
  });

  group('the server row', () {
    test('a row without a repeat has none', () {
      expect(ScheduleRepeat.fromRow({'recurrence': null}), isNull);
      expect(ScheduleRepeat.fromRow({}), isNull);
    });

    test('a repeating row is read with its rule', () {
      final rule = ScheduleRepeat.fromRow({
        'recurrence': 'weekly',
        'recurrence_day': 1,
        'recurrence_time': '09:00:00',
        'recurrence_tz': 'Asia/Shanghai',
        'recurrence_until': '2031-01-31',
      })!;
      expect(rule.kind, RepeatKind.weekly);
      expect(rule.day, 1);
      expect(rule.hour, 9);
      expect(rule.minute, 0);
      expect(rule.zone, 'Asia/Shanghai');
      expect(rule.until, DateTime(2031, 1, 31));
    });

    test('the columns written are the kind, the zone and the end date', () {
      final columns = ScheduleRepeat(
        kind: RepeatKind.monthly,
        zone: 'Europe/Berlin',
        until: DateTime(2031, 1, 5),
      ).toColumns();
      expect(columns, {
        'recurrence': 'monthly',
        'recurrence_tz': 'Europe/Berlin',
        'recurrence_until': '2031-01-05',
      });
      expect(
        const ScheduleRepeat(
          kind: RepeatKind.daily,
        ).toColumns()['recurrence_until'],
        isNull,
      );
    });

    test('a scheduled message carries its repeat', () {
      final message = ScheduledMessage.fromJson({
        'id': 's1',
        'conversation_id': 'c1',
        'body': 'Weekly report',
        'send_at': '2030-05-13T01:00:00+00:00',
        'recurrence': 'weekly',
        'recurrence_day': 1,
        'recurrence_time': '09:00:00',
        'recurrence_tz': 'Asia/Shanghai',
      });
      expect(message.isRepeating, isTrue);
      expect(message.repeat!.kind, RepeatKind.weekly);
      expect(
        ScheduledMessage.fromJson({
          'id': 's2',
          'conversation_id': 'c1',
          'send_at': '2030-05-13T01:00:00+00:00',
        }).isRepeating,
        isFalse,
      );
    });
  });

  group('the words', () {
    tearDown(() => AppStrings.isChinese = false);

    ScheduleRepeat rule(RepeatKind kind, {int? day, DateTime? until}) =>
        ScheduleRepeat(kind: kind, day: day, hour: 9, minute: 0, until: until);

    test('read as a rule in English', () {
      expect(
        describeRepeat(rule(RepeatKind.weekly, day: 1), localizations),
        'Every Monday 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.daily), localizations),
        'Every day 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.weekdays), localizations),
        'Weekdays 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.monthly, day: 31), localizations),
        'Every month on day 31 9:00 AM',
      );
      expect(
        describeRepeat(
          rule(RepeatKind.weekly, day: 7, until: DateTime(2030, 12, 31)),
          localizations,
          alwaysUse24HourFormat: true,
        ),
        'Every Sunday 09:00 · until Tue, Dec 31',
      );
    });

    test('read as a rule in Chinese', () {
      AppStrings.isChinese = true;
      expect(
        describeRepeat(rule(RepeatKind.weekly, day: 1), localizations),
        '每周一 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.daily), localizations),
        '每天 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.weekdays), localizations),
        '工作日 9:00 AM',
      );
      expect(
        describeRepeat(rule(RepeatKind.monthly, day: 31), localizations),
        '每月31号 9:00 AM',
      );
      expect(repeatKindLabel(null), '不重复');
    });
  });

  group('the sheets', () {
    final now = DateTime(2026, 10, 17, 15, 30);

    Widget host(Widget child, FakeScheduledMessagesRepository repository) {
      return ProviderScope(
        overrides: [
          scheduledMessagesRepositoryProvider.overrideWithValue(repository),
          pushRepositoryProvider.overrideWithValue(RecordingPushRepository()),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      );
    }

    testWidgets('the when sheet has a Repeat row and keeps the choice', (
      tester,
    ) async {
      final repeat = ValueNotifier<ScheduleRepeat?>(null);
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
                    repeat: repeat,
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
      expect(find.text('Does not repeat'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('when-repeat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('repeat-end')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('option-RepeatKind.weekly')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('repeat-end')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await tester.pumpAndSettle();

      expect(repeat.value?.kind, RepeatKind.weekly);
      expect(find.text('Every week'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('when-tomorrowMorning')));
      await tester.pumpAndSettle();
      expect(picked, isNotNull);
    });

    testWidgets('a sheet without a notifier has no Repeat row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: WhenSheet(picks: schedulePicks)),
        ),
      );
      expect(find.byKey(const ValueKey('when-repeat')), findsNothing);
    });

    testWidgets('choosing "Does not repeat" clears it', (tester) async {
      final repeat = ValueNotifier<ScheduleRepeat?>(
        const ScheduleRepeat(kind: RepeatKind.daily),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: WhenSheet(picks: schedulePicks, repeat: repeat),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('when-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('option-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await tester.pumpAndSettle();
      expect(repeat.value, isNull);
    });

    testWidgets('the list shows the rule, and stopping deletes the next send', (
      tester,
    ) async {
      final repository = FakeScheduledMessagesRepository([
        ScheduledMessage(
          id: 'r1',
          conversationId: 'conversation-1',
          body: 'Weekly report',
          sendAt: now.add(const Duration(days: 2)).toUtc(),
          repeat: const ScheduleRepeat(
            kind: RepeatKind.weekly,
            day: 1,
            hour: 9,
            minute: 0,
          ),
        ),
        ScheduledMessage(
          id: 'o1',
          conversationId: 'conversation-1',
          body: 'Once',
          sendAt: now.add(const Duration(days: 3)).toUtc(),
        ),
      ]);
      await withClock(Clock.fixed(now), () async {
        await tester.pumpWidget(
          host(
            const ScheduledMessagesSheet(conversationId: 'conversation-1'),
            repository,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(find.text('Every Monday 9:00 AM'), findsOneWidget);
      expect(find.byKey(const ValueKey('scheduled-repeat-o1')), findsNothing);
      expect(find.byTooltip('Stop repeating'), findsOneWidget);
      expect(find.byTooltip('Delete scheduled message'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop repeating'));
      await tester.pumpAndSettle();
      expect(repository.deleted, ['r1']);
    });

    testWidgets('editing changes the repeat', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        ScheduledMessage(
          id: 'r1',
          conversationId: 'conversation-1',
          body: 'Weekly report',
          sendAt: now.add(const Duration(days: 2)).toUtc(),
          repeat: const ScheduleRepeat(
            kind: RepeatKind.weekly,
            day: 1,
            hour: 9,
            minute: 0,
          ),
        ),
      ]);
      await withClock(Clock.fixed(now), () async {
        await tester.pumpWidget(
          host(
            ScheduledEditSheet(message: repository.messages.single),
            repository,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(find.text('Every week'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('option-RepeatKind.weekdays')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await tester.pumpAndSettle();
      expect(find.text('Weekdays'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scheduled-edit-save')));
      await tester.pumpAndSettle();
      expect(repository.messages.single.repeat?.kind, RepeatKind.weekdays);
    });

    testWidgets('editing to "Does not repeat" saves a one-off', (tester) async {
      final repository = FakeScheduledMessagesRepository([
        ScheduledMessage(
          id: 'r1',
          conversationId: 'conversation-1',
          body: 'Weekly report',
          sendAt: now.add(const Duration(days: 2)).toUtc(),
          repeat: const ScheduleRepeat(
            kind: RepeatKind.daily,
            hour: 9,
            minute: 0,
          ),
        ),
      ]);
      await withClock(Clock.fixed(now), () async {
        await tester.pumpWidget(
          host(
            ScheduledEditSheet(message: repository.messages.single),
            repository,
          ),
        );
        await tester.pumpAndSettle();
      });
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('option-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scheduled-edit-save')));
      await tester.pumpAndSettle();
      expect(repository.messages.single.repeat, isNull);
    });
  });
}
