import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/notification_settings.dart';

// The cases of supabase/functions/push/quiet_hours_test.ts and
// test/supabase/quiet_hours_behaviour.sql, as the wall clock the person sees
// (the app's rule works on the device's own clock, so daylight saving is
// the clock's business). 2026-10-19 is a Monday.
void main() {
  const everyDay = NotificationSettings.allDays;

  NotificationSettings window(
    String start,
    String end, {
    Set<int> days = everyDay,
    bool enabled = true,
  }) => NotificationSettings(
    quietEnabled: enabled,
    quietDays: days,
    quietStart: QuietTime.tryParse(start)!,
    quietEnd: QuietTime.tryParse(end)!,
  );

  group('isQuietAt', () {
    final cases =
        <
          ({
            String label,
            NotificationSettings settings,
            DateTime wall,
            bool expected,
          })
        >[
          // Shanghai wall clock, every day 23:00-07:00.
          (
            label: 'across midnight: start is in',
            settings: window('23:00', '07:00'),
            wall: DateTime(2026, 10, 20, 23),
            expected: true,
          ),
          (
            label: 'across midnight: a minute before',
            settings: window('23:00', '07:00'),
            wall: DateTime(2026, 10, 20, 22, 59),
            expected: false,
          ),
          (
            label: 'across midnight: after midnight',
            settings: window('23:00', '07:00'),
            wall: DateTime(2026, 10, 21, 2),
            expected: true,
          ),
          (
            label: 'across midnight: last minute',
            settings: window('23:00', '07:00'),
            wall: DateTime(2026, 10, 21, 6, 59),
            expected: true,
          ),
          (
            label: 'across midnight: end is out',
            settings: window('23:00', '07:00'),
            wall: DateTime(2026, 10, 21, 7),
            expected: false,
          ),
          // The days a window starts on.
          (
            label: 'monday night',
            settings: window('23:00', '07:00', days: {1}),
            wall: DateTime(2026, 10, 19, 23, 30),
            expected: true,
          ),
          (
            label: 'tuesday early morning belongs to monday',
            settings: window('23:00', '07:00', days: {1}),
            wall: DateTime(2026, 10, 20, 3),
            expected: true,
          ),
          (
            label: 'monday early morning belongs to sunday',
            settings: window('23:00', '07:00', days: {1}),
            wall: DateTime(2026, 10, 19, 3),
            expected: false,
          ),
          (
            label: 'tuesday night is not picked',
            settings: window('23:00', '07:00', days: {1}),
            wall: DateTime(2026, 10, 20, 23, 30),
            expected: false,
          ),
          (
            label: 'sunday night runs into monday',
            settings: window('23:00', '07:00', days: {7}),
            wall: DateTime(2026, 10, 19, 3),
            expected: true,
          ),
          // Same-day window on weekdays.
          (
            label: 'workday morning',
            settings: window('09:00', '17:00', days: {1, 2, 3, 4, 5}),
            wall: DateTime(2026, 10, 23, 10),
            expected: true,
          ),
          (
            label: 'workday evening',
            settings: window('09:00', '17:00', days: {1, 2, 3, 4, 5}),
            wall: DateTime(2026, 10, 23, 17),
            expected: false,
          ),
          (
            label: 'saturday',
            settings: window('09:00', '17:00', days: {1, 2, 3, 4, 5}),
            wall: DateTime(2026, 10, 24, 10),
            expected: false,
          ),
          // Odd settings.
          (
            label: 'equal start and end is empty',
            settings: window('08:00', '08:00'),
            wall: DateTime(2026, 10, 20, 8),
            expected: false,
          ),
          (
            label: 'no days is never quiet',
            settings: window('22:00', '07:00', days: {}),
            wall: DateTime(2026, 10, 20, 23),
            expected: false,
          ),
          (
            label: 'switched off is never quiet',
            settings: window('22:00', '07:00', enabled: false),
            wall: DateTime(2026, 10, 20, 23),
            expected: false,
          ),
          (
            label: 'midnight start',
            settings: window('00:00', '06:00'),
            wall: DateTime(2026, 10, 20),
            expected: true,
          ),
          (
            label: 'ends at midnight',
            settings: window('18:00', '00:00'),
            wall: DateTime(2026, 10, 20, 23, 59),
            expected: true,
          ),
          (
            label: 'ends at midnight: midnight is out',
            settings: window('18:00', '00:00'),
            wall: DateTime(2026, 10, 21),
            expected: false,
          ),
        ];
    for (final c in cases) {
      test(c.label, () {
        expect(c.settings.isQuietAt(c.wall), c.expected);
      });
    }
  });

  group('nextBoundaryAfter', () {
    test('is the next time the window opens or closes', () {
      final settings = window('23:00', '07:00');
      expect(
        settings.nextBoundaryAfter(DateTime(2026, 10, 20, 12)),
        DateTime(2026, 10, 20, 23),
      );
      expect(
        settings.nextBoundaryAfter(DateTime(2026, 10, 20, 23)),
        DateTime(2026, 10, 21, 7),
      );
      expect(
        settings.nextBoundaryAfter(DateTime(2026, 10, 20, 23, 30)),
        DateTime(2026, 10, 21, 7),
      );
      expect(
        settings.nextBoundaryAfter(DateTime(2026, 10, 21, 7)),
        DateTime(2026, 10, 21, 23),
      );
    });
  });

  group('breaksThrough', () {
    const settings = NotificationSettings(vipUserIds: {'cy'});

    test('ordinary messages do not', () {
      expect(
        settings.breaksThrough(const QuietMessage(senderId: 'dee')),
        isFalse,
      );
      expect(settings.breaksThrough(const QuietMessage()), isFalse);
    });

    test('calls, mentions, important contacts and starred friends do', () {
      expect(settings.breaksThrough(const QuietMessage(isCall: true)), isTrue);
      expect(
        settings.breaksThrough(const QuietMessage(mentionsMe: true)),
        isTrue,
      );
      expect(
        settings.breaksThrough(const QuietMessage(senderId: 'cy')),
        isTrue,
      );
      expect(
        settings.breaksThrough(
          const QuietMessage(senderId: 'bob'),
          starredFriendIds: {'bob'},
        ),
        isTrue,
      );
    });

    test('each exception follows its switch', () {
      final off = settings.copyWith(
        allowCalls: false,
        allowMentions: false,
        allowStarred: false,
      );
      expect(off.breaksThrough(const QuietMessage(isCall: true)), isFalse);
      expect(off.breaksThrough(const QuietMessage(mentionsMe: true)), isFalse);
      expect(
        off.breaksThrough(
          const QuietMessage(senderId: 'bob'),
          starredFriendIds: {'bob'},
        ),
        isFalse,
      );
      // Important contacts have no switch: choosing them is the switch.
      expect(off.breaksThrough(const QuietMessage(senderId: 'cy')), isTrue);
    });
  });

  group('rows', () {
    test('a row from the server', () {
      final settings = NotificationSettings.fromRow({
        'user_id': 'u1',
        'timezone': 'Asia/Shanghai',
        'quiet_enabled': true,
        'quiet_days': [1, 2, 3, 9],
        'quiet_start': '23:30:00',
        'quiet_end': '06:45:00',
        'allow_starred': false,
        'allow_mentions': true,
        'allow_calls': false,
        'vip_user_ids': ['a', 'b'],
        'show_previews': false,
      });
      expect(settings.timezone, 'Asia/Shanghai');
      expect(settings.quietEnabled, isTrue);
      expect(settings.quietDays, {1, 2, 3});
      expect(settings.quietStart, const QuietTime(23, 30));
      expect(settings.quietEnd, const QuietTime(6, 45));
      expect(settings.allowStarred, isFalse);
      expect(settings.allowCalls, isFalse);
      expect(settings.vipUserIds, {'a', 'b'});
      expect(settings.showPreviews, isFalse);
    });

    test('missing columns fall back to the defaults', () {
      final settings = NotificationSettings.fromRow({'user_id': 'u1'});
      expect(settings, NotificationSettings.defaults);
      expect(settings.showPreviews, isNull);
    });

    test('the quiet columns to save leave out the rest', () {
      final columns = window('22:00', '07:30', days: {3, 1}).quietColumns();
      expect(columns, {
        'quiet_enabled': true,
        'quiet_days': [1, 3],
        'quiet_start': '22:00:00',
        'quiet_end': '07:30:00',
        'allow_starred': true,
        'allow_mentions': true,
        'allow_calls': true,
      });
    });

    test('times parse from Postgres and print for the database', () {
      expect(QuietTime.tryParse('07:05:00'), const QuietTime(7, 5));
      expect(QuietTime.tryParse('7:05'), const QuietTime(7, 5));
      expect(QuietTime.tryParse('24:00'), isNull);
      expect(QuietTime.tryParse('late'), isNull);
      expect(QuietTime.tryParse(null), isNull);
      expect(const QuietTime(7, 5).toSql(), '07:05:00');
      expect(const QuietTime(7, 5).toString(), '07:05');
    });
  });
}
