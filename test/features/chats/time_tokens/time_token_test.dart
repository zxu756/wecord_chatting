import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/shared/calendar/ics.dart';
import 'package:wecord/shared/l10n/l10n.dart';

// Saturday 17 October 2026, 14:00 local time.
final _now = DateTime(2026, 10, 17, 14);

TimeToken _at(DateTime time, [TimeTokenStyle? style]) =>
    TimeToken.fromDateTime(time, style ?? TimeTokenStyle.shortDateTime);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('markup', () {
    test('round trips with every style', () {
      for (final style in TimeTokenStyle.values) {
        final token = TimeToken(1790000000, style);
        final parsed = timeTokenAt(token.markup, 0);
        expect(parsed, isNotNull);
        expect(parsed!.token, token);
        expect(parsed.end, token.markup.length);
      }
    });

    test('default style and rejects nonsense', () {
      expect(
        timeTokenAt('<t:1790000000>', 0)!.token.style,
        TimeTokenStyle.shortDateTime,
      );
      expect(timeTokenAt('<t:1790000000:x>', 0), isNull);
      expect(timeTokenAt('<t:99999999999999>', 0), isNull);
      expect(timeTokenAt('x<t:1790000000>', 0), isNull);
      expect(timeTokenAt('x<t:1790000000>', 1), isNotNull);
    });

    test('is the same instant for readers anywhere', () {
      final utc = DateTime.utc(2026, 10, 20, 7);
      final token = TimeToken.fromDateTime(utc);
      expect(token.unix, utc.millisecondsSinceEpoch ~/ 1000);
      expect(token.time.toUtc(), utc);
    });
  });

  group('formatting', () {
    test('English styles', () {
      final time = DateTime(2026, 10, 20, 15, 5, 9);
      String format(TimeTokenStyle style, {bool use24Hour = false}) =>
          formatTimeToken(_at(time, style), now: _now, use24Hour: use24Hour);
      expect(format(TimeTokenStyle.shortTime), '3:05 PM');
      expect(format(TimeTokenStyle.shortTime, use24Hour: true), '15:05');
      expect(format(TimeTokenStyle.longTime), '3:05:09 PM');
      expect(format(TimeTokenStyle.shortDate), 'Oct 20');
      expect(format(TimeTokenStyle.longDate), 'October 20, 2026');
      expect(format(TimeTokenStyle.shortDateTime), 'Tue, Oct 20, 3:05 PM');
      expect(
        format(TimeTokenStyle.longDateTime),
        'Tuesday, October 20, 2026 at 3:05 PM',
      );
      expect(format(TimeTokenStyle.relative), 'in 3 days');
    });

    test('midnight and noon', () {
      expect(formatClock(DateTime(2026, 1, 1, 0, 0)), '12:00 AM');
      expect(formatClock(DateTime(2026, 1, 1, 12, 30)), '12:30 PM');
    });

    test('other years show the year', () {
      expect(
        formatTimeToken(
          _at(DateTime(2027, 1, 5, 9), TimeTokenStyle.shortDate),
          now: _now,
        ),
        'Jan 5, 2027',
      );
    });

    test('Chinese', () {
      AppStrings.isChinese = true;
      final time = DateTime(2026, 10, 20, 15, 5);
      expect(formatTimeToken(_at(time), now: _now), '10月20日 周二 下午3:05');
      expect(
        formatTimeToken(_at(time, TimeTokenStyle.longDateTime), now: _now),
        '2026年10月20日 星期二 下午3:05',
      );
      expect(
        formatTimeToken(
          _at(time, TimeTokenStyle.shortTime),
          now: _now,
          use24Hour: true,
        ),
        '15:05',
      );
    });
  });

  group('relative hints', () {
    String hint(Duration offset) => relativeTimeText(_now.add(offset), _now);

    test('minutes, hours and days ahead', () {
      expect(hint(const Duration(seconds: 10)), 'in a moment');
      expect(hint(const Duration(minutes: 1)), 'in 1 minute');
      expect(hint(const Duration(minutes: 45)), 'in 45 minutes');
      expect(hint(const Duration(hours: 1)), 'in 1 hour');
      expect(hint(const Duration(hours: 2)), 'in 2 hours');
      expect(hint(const Duration(days: 1)), 'tomorrow');
      expect(hint(const Duration(days: 3)), 'in 3 days');
      expect(hint(const Duration(days: 60)), 'in 2 months');
      expect(hint(const Duration(days: 800)), 'in 2 years');
    });

    test('and in the past', () {
      expect(hint(const Duration(seconds: -10)), 'just now');
      expect(hint(const Duration(minutes: -5)), '5 minutes ago');
      expect(hint(const Duration(hours: -3)), '3 hours ago');
      expect(hint(const Duration(days: -1)), 'yesterday');
      expect(hint(const Duration(days: -4)), '4 days ago');
    });

    test('tomorrow is a calendar day, not 24 hours', () {
      final lateTonight = DateTime(2026, 10, 17, 23, 30);
      final earlyTomorrow = DateTime(2026, 10, 18, 0, 30);
      // An hour apart, but a different day: still just "in 1 hour".
      expect(relativeTimeText(earlyTomorrow, lateTonight), 'in 1 hour');
      final tomorrowNoon = DateTime(2026, 10, 18, 12);
      expect(
        relativeTimeText(tomorrowNoon, DateTime(2026, 10, 17, 9)),
        'tomorrow',
      );
    });
  });

  test('replaceTimeTokensWithText leaves ordinary text alone', () {
    expect(
      replaceTimeTokensWithText('no tokens <b> here'),
      'no tokens <b> here',
    );
    final replaced = replaceTimeTokensWithText(
      'see <t:1790000000:d> and <t:1790090000:t>',
      now: _now,
    );
    expect(replaced, isNot(contains('<t:')));
  });

  group('calendar file', () {
    test('has the event, UTC times and a reminder', () {
      final ics = buildIcsCalendar(
        uid: 'abc@wecord',
        title: 'Team, sync; weekly',
        start: DateTime.utc(2026, 10, 20, 7),
        end: DateTime.utc(2026, 10, 20, 8, 30),
        description: 'Line one\nLine two',
        location: 'Room 4',
        remindMinutesBefore: 15,
        now: DateTime.utc(2026, 10, 17, 14),
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, contains('UID:abc@wecord\r\n'));
      expect(ics, contains('DTSTART:20261020T070000Z\r\n'));
      expect(ics, contains('DTEND:20261020T083000Z\r\n'));
      expect(ics, contains(r'SUMMARY:Team\, sync\; weekly'));
      expect(ics, contains(r'DESCRIPTION:Line one\nLine two'));
      expect(ics, contains('LOCATION:Room 4'));
      expect(ics, contains('TRIGGER:-PT15M'));
    });

    test('folds long lines at 75 bytes without splitting characters', () {
      final ics = buildIcsCalendar(
        uid: 'x@wecord',
        title: '会' * 60,
        start: DateTime.utc(2026, 10, 20, 7),
      );
      for (final line in ics.split('\r\n')) {
        expect(line.codeUnits.length < 80, isTrue, reason: line);
      }
      expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:${'会' * 60}'));
    });

    test('file names keep Chinese and drop punctuation', () {
      expect(calendarFileName('Team sync!'), 'team-sync.ics');
      expect(calendarFileName('明天开会'), '明天开会.ics');
      expect(calendarFileName('???'), 'event.ics');
    });
  });
}
