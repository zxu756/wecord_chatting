import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/later/later_time.dart';

/// Quick picks are wall-clock times in the zone of "now". The suite runs in
/// the machine's zone, and with `TZ=America/New_York`, `TZ=Asia/Kolkata`
/// and so on in CI; the UTC cases stand for a zone of their own.
void main() {
  group('schedule picks', () {
    test('offer 1 hour, tonight at 8 pm and tomorrow at 9 am', () {
      final now = DateTime(2026, 10, 17, 15, 42, 30);
      final picks = schedulePicks(now);
      expect(picks.map((pick) => pick.kind), [
        QuickWhenKind.inOneHour,
        QuickWhenKind.tonight,
        QuickWhenKind.tomorrowMorning,
      ]);
      // A whole minute, one hour on.
      expect(picks[0].at, DateTime(2026, 10, 17, 16, 42));
      expect(picks[1].at, DateTime(2026, 10, 17, 20));
      expect(picks[2].at, DateTime(2026, 10, 18, 9));
    });

    test('leave out tonight when 8 pm is less than 5 minutes away or past', () {
      for (final now in [
        DateTime(2026, 10, 17, 19, 56),
        DateTime(2026, 10, 17, 20),
        DateTime(2026, 10, 17, 23, 30),
      ]) {
        expect(
          schedulePicks(now).map((pick) => pick.kind),
          isNot(contains(QuickWhenKind.tonight)),
          reason: '$now',
        );
      }
      expect(
        schedulePicks(DateTime(2026, 10, 17, 19, 55)).map((pick) => pick.kind),
        contains(QuickWhenKind.tonight),
      );
    });

    test('tomorrow rolls over month and year ends', () {
      expect(
        schedulePicks(DateTime(2026, 12, 31, 22)).last.at,
        DateTime(2027, 1, 1, 9),
      );
      expect(
        schedulePicks(DateTime(2028, 2, 28, 22)).last.at,
        DateTime(2028, 2, 29, 9),
      );
    });

    test('are built in the zone of now', () {
      final utc = DateTime.utc(2026, 10, 17, 3, 15);
      final picks = schedulePicks(utc);
      expect(picks.every((pick) => pick.at.isUtc), isTrue);
      expect(picks[1].at, DateTime.utc(2026, 10, 17, 20));
      expect(picks[2].at, DateTime.utc(2026, 10, 18, 9));

      final local = DateTime(2026, 10, 17, 3, 15);
      expect(schedulePicks(local).every((pick) => !pick.at.isUtc), isTrue);
    });

    test('keep 9 am on the wall clock across daylight saving changes', () {
      // Whatever the machine's zone, tomorrow at 9 am reads 9:00 there,
      // also when the clocks change overnight (US: 2026-03-08 and
      // 2026-11-01; Europe: 2026-03-29 and 2026-10-25).
      for (final day in [
        DateTime(2026, 3, 7, 12),
        DateTime(2026, 3, 28, 12),
        DateTime(2026, 10, 24, 12),
        DateTime(2026, 10, 31, 12),
      ]) {
        final tomorrow = schedulePicks(day).last.at;
        expect(tomorrow.hour, 9, reason: '$day');
        expect(tomorrow.minute, 0);
        expect(tomorrow.day, day.add(const Duration(days: 1)).day);
      }
    });

    test('instants are sent as UTC', () {
      final pick = schedulePicks(DateTime(2026, 10, 17, 15)).last.at;
      expect(pick.toUtc().isUtc, isTrue);
      expect(pick.toUtc().toLocal(), pick);
    });
  });

  group('remind picks', () {
    test('are 20 minutes, 1 hour, 3 hours and tomorrow at 9 am', () {
      final now = DateTime(2026, 10, 17, 15, 42, 30);
      final picks = remindPicks(now);
      expect(picks.map((pick) => pick.kind), [
        QuickWhenKind.inTwentyMinutes,
        QuickWhenKind.inOneHour,
        QuickWhenKind.inThreeHours,
        QuickWhenKind.tomorrowMorning,
      ]);
      expect(picks[0].at, DateTime(2026, 10, 17, 16, 2));
      expect(picks[1].at, DateTime(2026, 10, 17, 16, 42));
      expect(picks[2].at, DateTime(2026, 10, 17, 18, 42));
      expect(picks[3].at, DateTime(2026, 10, 18, 9));
    });
  });

  group('custom times', () {
    test('combine a date and a time of day in the zone of now', () {
      final picked = combineDateAndTime(
        DateTime(2026, 11, 2),
        const TimeOfDay(hour: 7, minute: 30),
        DateTime(2026, 10, 17),
      );
      expect(picked, DateTime(2026, 11, 2, 7, 30));
      expect(picked.isUtc, isFalse);
      expect(
        combineDateAndTime(
          DateTime(2026, 11, 2),
          const TimeOfDay(hour: 7, minute: 30),
          DateTime.utc(2026, 10, 17),
        ),
        DateTime.utc(2026, 11, 2, 7, 30),
      );
    });

    test('must be at least a minute ahead', () {
      final now = DateTime(2026, 10, 17, 12);
      expect(isUsableFuture(DateTime(2026, 10, 17, 12, 1), now), isTrue);
      expect(isUsableFuture(DateTime(2026, 10, 17, 12, 0, 30), now), isFalse);
      expect(isUsableFuture(DateTime(2026, 10, 17, 11), now), isFalse);
    });

    test('name the zone by its UTC offset', () {
      expect(utcOffsetLabel(DateTime.utc(2026, 10, 17)), 'UTC+0');
      // DateTime has no way to build a zone; the sign and minutes are read
      // from the offset, which is checked on the local zone here.
      final local = DateTime(2026, 10, 17);
      final offset = local.timeZoneOffset;
      final label = utcOffsetLabel(local);
      expect(label.startsWith('UTC${offset.isNegative ? '-' : '+'}'), isTrue);
      expect(label, contains('${offset.inMinutes.abs() ~/ 60}'));
    });
  });

  group('describeWhen', () {
    const localizations = DefaultMaterialLocalizations();

    test('says today and tomorrow, then the date', () {
      final now = DateTime(2026, 10, 17, 15);
      expect(
        describeWhen(localizations, DateTime(2026, 10, 17, 20), now),
        'Today 8:00 PM',
      );
      expect(
        describeWhen(localizations, DateTime(2026, 10, 18, 9), now),
        'Tomorrow 9:00 AM',
      );
      expect(
        describeWhen(localizations, DateTime(2026, 10, 20, 9, 5), now),
        'Tue, Oct 20 9:05 AM',
      );
      expect(
        describeWhen(localizations, DateTime(2027, 1, 2, 18), now),
        'Jan 2, 2027 6:00 PM',
      );
    });

    test('follows the 24 hour clock', () {
      final now = DateTime(2026, 10, 17, 15);
      expect(
        describeWhen(
          localizations,
          DateTime(2026, 10, 17, 20),
          now,
          alwaysUse24HourFormat: true,
        ),
        'Today 20:00',
      );
    });

    test('counts calendar days across a daylight saving night', () {
      // 23 or 25 hours apart, still "tomorrow".
      final now = DateTime(2026, 11, 1, 0, 30);
      final when = DateTime(2026, 11, 2, 0, 15);
      expect(
        describeWhen(localizations, when, now),
        startsWith('Tomorrow'),
      );
      final late = DateTime(2026, 10, 31, 23, 50);
      expect(
        describeWhen(localizations, DateTime(2026, 11, 1, 0, 10), late),
        startsWith('Tomorrow'),
      );
    });
  });
}
