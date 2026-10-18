import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/agenda/agenda_models.dart';

import 'agenda_fakes.dart';

void main() {
  // Wednesday 21 October 2026, 10:00 local.
  final now = DateTime(2026, 10, 21, 10);

  AgendaItem item(
    AgendaKind kind,
    String id,
    DateTime startsAt, {
    bool allDay = false,
    DateTime? endsAt,
  }) => agendaItem(
    kind,
    id,
    startsAt: startsAt.toUtc(),
    endsAt: endsAt?.toUtc(),
    allDay: allDay,
  );

  group('parsing', () {
    test('reads a server row', () {
      final parsed = AgendaItem.tryParse({
        'kind': 'chat_event',
        'title': '  Bouldering night ',
        'starts_at': '2026-10-22T18:00:00+00:00',
        'ends_at': '2026-10-22T20:00:00+00:00',
        'all_day': false,
        'conversation_id': 'c1',
        'circle_id': null,
        'target_id': 'e1',
        'parent_id': null,
        'place_name': 'Climbing crew',
        'subtitle': 'The gym',
        'meta': {'status': 'maybe'},
      })!;
      expect(parsed.kind, AgendaKind.chatEvent);
      expect(parsed.title, 'Bouldering night');
      expect(parsed.startsAt, DateTime.utc(2026, 10, 22, 18));
      expect(parsed.endsAt, DateTime.utc(2026, 10, 22, 20));
      expect(parsed.rsvp, 'maybe');
      expect(parsed.placeName, 'Climbing crew');
      expect(parsed.key, 'chat_event:e1');
    });

    test('a reminder about a hidden message has no title', () {
      final parsed = AgendaItem.tryParse({
        'kind': 'reminder',
        'title': null,
        'starts_at': '2026-10-22T18:00:00+00:00',
        'target_id': 'r1',
        'conversation_id': 'c1',
        'meta': {'message_type': null, 'fired': false},
      })!;
      expect(parsed.title, isNull);
      expect(parsed.messageType, isNull);
    });

    test('rows of an unknown kind or without a time are skipped', () {
      expect(
        AgendaItem.tryParse({
          'kind': 'hologram',
          'starts_at': '2026-10-22T18:00:00+00:00',
          'target_id': 'x',
        }),
        isNull,
      );
      expect(
        AgendaItem.tryParse({
          'kind': 'task',
          'starts_at': 'soon',
          'target_id': 'x',
        }),
        isNull,
      );
    });
  });

  group('overdue', () {
    test('tasks and reminders past their time need me; events do not', () {
      final past = now.subtract(const Duration(hours: 1));
      expect(item(AgendaKind.task, 't', past).isOverdue(now), isTrue);
      expect(item(AgendaKind.reminder, 'r', past).isOverdue(now), isTrue);
      expect(item(AgendaKind.chatEvent, 'e', past).isOverdue(now), isFalse);
      expect(
        item(AgendaKind.scheduledMessage, 's', past).isOverdue(now),
        isFalse,
      );
      expect(
        item(
          AgendaKind.task,
          't2',
          now.add(const Duration(hours: 1)),
        ).isOverdue(now),
        isFalse,
      );
    });

    test('an all-day task is not overdue until its day is over', () {
      final dueToday = item(
        AgendaKind.task,
        't',
        DateTime(2026, 10, 21, 23, 59),
        allDay: true,
      );
      expect(dueToday.isOverdue(now), isFalse);
      expect(dueToday.isOverdue(DateTime(2026, 10, 22, 0, 1)), isTrue);
    });
  });

  group('buckets', () {
    AgendaBucket bucket(
      DateTime at, {
      int firstDay = DateTime.monday,
      AgendaKind kind = AgendaKind.chatEvent,
    }) => agendaBucketOf(item(kind, 'x', at), now, firstDayOfWeek: firstDay);

    test('overdue, today, tomorrow, this week, later', () {
      expect(
        bucket(DateTime(2026, 10, 20, 9), kind: AgendaKind.task),
        AgendaBucket.overdue,
      );
      expect(bucket(DateTime(2026, 10, 21, 8)), AgendaBucket.today);
      expect(bucket(DateTime(2026, 10, 21, 23, 30)), AgendaBucket.today);
      expect(bucket(DateTime(2026, 10, 22, 0, 30)), AgendaBucket.tomorrow);
      expect(bucket(DateTime(2026, 10, 23, 12)), AgendaBucket.thisWeek);
      // Sunday 25 October is the last day of a Monday-first week.
      expect(bucket(DateTime(2026, 10, 25, 20)), AgendaBucket.thisWeek);
      expect(bucket(DateTime(2026, 10, 26, 9)), AgendaBucket.later);
      expect(bucket(DateTime(2027, 1, 5)), AgendaBucket.later);
    });

    test('the week starts where the locale says', () {
      // Sunday-first: the week of Wed 21 ends Saturday 24.
      expect(
        bucket(DateTime(2026, 10, 24, 9), firstDay: DateTime.sunday),
        AgendaBucket.thisWeek,
      );
      expect(
        bucket(DateTime(2026, 10, 25, 9), firstDay: DateTime.sunday),
        AgendaBucket.later,
      );
      // Saturday-first: the week runs Sat 17 to Fri 23.
      expect(
        bucket(DateTime(2026, 10, 23, 9), firstDay: DateTime.saturday),
        AgendaBucket.thisWeek,
      );
      expect(
        bucket(DateTime(2026, 10, 24, 9), firstDay: DateTime.saturday),
        AgendaBucket.later,
      );
    });

    test('a task due tomorrow is not overdue and is filed under tomorrow', () {
      expect(
        bucket(DateTime(2026, 10, 22, 9), kind: AgendaKind.task),
        AgendaBucket.tomorrow,
      );
    });

    test('days are local days across a daylight saving change', () {
      // 25 October 2026 is when Europe leaves summer time; whatever zone the
      // tests run in, the day count is calendar days.
      final late = DateTime(2026, 10, 25, 23, 30);
      final early = DateTime(2026, 10, 26, 0, 30);
      final sunday = DateTime(2026, 10, 25, 12);
      expect(
        agendaBucketOf(item(AgendaKind.chatEvent, 'a', late), sunday),
        AgendaBucket.today,
      );
      expect(
        agendaBucketOf(item(AgendaKind.chatEvent, 'b', early), sunday),
        AgendaBucket.tomorrow,
      );
    });
  });

  group('grouping', () {
    test('groups in order, leaves empty buckets out and sorts by time', () {
      final groups = groupAgenda([
        item(AgendaKind.chatEvent, 'later', DateTime(2026, 12, 1, 9)),
        item(AgendaKind.chatEvent, 'today-b', DateTime(2026, 10, 21, 20)),
        item(AgendaKind.chatEvent, 'today-a', DateTime(2026, 10, 21, 12)),
        item(AgendaKind.task, 'overdue-b', DateTime(2026, 10, 20, 9)),
        item(AgendaKind.task, 'overdue-a', DateTime(2026, 10, 18, 9)),
      ], now);
      expect(groups.keys, [
        AgendaBucket.overdue,
        AgendaBucket.today,
        AgendaBucket.later,
      ]);
      expect(groups[AgendaBucket.overdue]!.map((i) => i.targetId), [
        'overdue-a',
        'overdue-b',
      ]);
      expect(groups[AgendaBucket.today]!.map((i) => i.targetId), [
        'today-a',
        'today-b',
      ]);
    });

    test('events that ended before today are not listed', () {
      final groups = groupAgenda([
        item(
          AgendaKind.chatEvent,
          'old',
          DateTime(2026, 10, 19, 9),
          endsAt: DateTime(2026, 10, 19, 11),
        ),
        item(
          AgendaKind.chatEvent,
          'still-on',
          DateTime(2026, 10, 20, 22),
          endsAt: DateTime(2026, 10, 21, 1),
        ),
        item(AgendaKind.scheduledMessage, 'missed', DateTime(2026, 10, 20, 9)),
      ], now);
      expect(groups.values.expand((items) => items).map((i) => i.targetId), [
        'still-on',
      ]);
    });

    test('counts what is overdue', () {
      expect(agendaOverdueCount(sampleAgenda(now), now), 2);
      expect(agendaOverdueCount(const [], now), 0);
    });
  });

  group('month grid', () {
    test('October 2026 starts on a Thursday', () {
      final monday = monthGrid(DateTime(2026, 10));
      expect(monday.length, 5);
      expect(monday.every((week) => week.length == 7), isTrue);
      expect(monday.first.first, DateTime(2026, 9, 28));
      expect(monday.first[3], DateTime(2026, 10));
      expect(monday.last.last, DateTime(2026, 11, 1));

      final sunday = monthGrid(DateTime(2026, 10), firstDayOfWeek: 7);
      expect(sunday.first.first, DateTime(2026, 9, 27));
      expect(sunday.first[4], DateTime(2026, 10));
      expect(sunday.last.last, DateTime(2026, 10, 31));
    });

    test('a month can need six weeks, or four', () {
      expect(monthGrid(DateTime(2026, 8)).length, 6);
      expect(monthGrid(DateTime(2027, 2)).length, 4);
    });

    test('days of a year turn over cleanly', () {
      final grid = monthGrid(DateTime(2026, 12));
      expect(grid.last.last.isAfter(DateTime(2026, 12, 31)), isTrue);
      expect(grid.last.last.year, 2027);
    });

    test('items are found by their local day', () {
      final items = [
        item(AgendaKind.chatEvent, 'a', DateTime(2026, 10, 22, 23, 30)),
        item(AgendaKind.chatEvent, 'b', DateTime(2026, 10, 23, 0, 30)),
        item(AgendaKind.chatEvent, 'c', DateTime(2026, 10, 22, 8)),
      ];
      expect(
        agendaOnDay(items, DateTime(2026, 10, 22, 15)).map((i) => i.targetId),
        ['c', 'a'],
      );
      expect(agendaByDay(items).keys, {
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 23),
      });
    });
  });
}
