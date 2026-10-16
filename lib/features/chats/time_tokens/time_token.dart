import 'package:wecord/shared/l10n/l10n.dart';

/// How a time token is shown, with the letter written in the markup
/// (`<t:1760000000:R>`). The default is [shortDateTime].
enum TimeTokenStyle {
  shortTime('t'),
  longTime('T'),
  shortDate('d'),
  longDate('D'),
  shortDateTime('f'),
  longDateTime('F'),
  relative('R');

  const TimeTokenStyle(this.code);

  /// The letter in the markup.
  final String code;

  static TimeTokenStyle fromCode(String? code) {
    for (final style in values) {
      if (style.code == code) {
        return style;
      }
    }
    return shortDateTime;
  }
}

/// A moment in time written into a message as `<t:unix>` or
/// `<t:unix:style>`. The instant is fixed; every reader sees it in their
/// own time zone.
class TimeToken {
  const TimeToken(this.unix, [this.style = TimeTokenStyle.shortDateTime]);

  factory TimeToken.fromDateTime(
    DateTime time, [
    TimeTokenStyle style = TimeTokenStyle.shortDateTime,
  ]) {
    return TimeToken(time.millisecondsSinceEpoch ~/ 1000, style);
  }

  /// Seconds since the epoch.
  final int unix;
  final TimeTokenStyle style;

  /// The instant in the reader's time zone.
  DateTime get time =>
      DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true).toLocal();

  /// What is stored in the message body.
  String get markup => '<t:$unix:${style.code}>';

  @override
  bool operator ==(Object other) =>
      other is TimeToken && other.unix == unix && other.style == style;

  @override
  int get hashCode => Object.hash(unix, style);

  @override
  String toString() => markup;
}

/// A time token in a message: `<t:1760000000>` or `<t:1760000000:R>`.
final timeTokenPattern = RegExp(r'<t:(-?\d{1,12})(?::([tTdDfFR]))?>');

/// The token starting at [index] in [source] and where it ends, or null.
({TimeToken token, int end})? timeTokenAt(String source, int index) {
  if (index >= source.length || source[index] != '<') {
    return null;
  }
  final match = timeTokenPattern.matchAsPrefix(source, index);
  if (match == null) {
    return null;
  }
  final unix = int.tryParse(match.group(1)!);
  // About year 1 to 9999, so DateTime never overflows.
  if (unix == null || unix.abs() > 253402300799) {
    return null;
  }
  return (
    token: TimeToken(unix, TimeTokenStyle.fromCode(match.group(2))),
    end: match.end,
  );
}

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _englishWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _chineseWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

String _two(int number) => number.toString().padLeft(2, '0');

/// [time] as a clock reading: `3:05 PM`, or `15:05` in 24-hour mode. In
/// Chinese the period of the day comes first (`下午3:05`).
String formatClock(
  DateTime time, {
  bool use24Hour = false,
  bool seconds = false,
}) {
  final tail = seconds ? ':${_two(time.second)}' : '';
  if (use24Hour) {
    return '${_two(time.hour)}:${_two(time.minute)}$tail';
  }
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final clock = '$hour12:${_two(time.minute)}$tail';
  if (AppStrings.isChinese) {
    return '${_chinesePeriod(time.hour)}$clock';
  }
  return '$clock ${time.hour < 12 ? 'AM' : 'PM'}';
}

String _chinesePeriod(int hour) {
  if (hour < 5) return '凌晨';
  if (hour < 12) return '上午';
  if (hour < 13) return '中午';
  if (hour < 18) return '下午';
  return '晚上';
}

/// `Oct 20` / `10月20日`, with the year when it is not [now]'s.
String formatDateShort(DateTime time, {required DateTime now}) {
  final sameYear = time.year == now.year;
  if (AppStrings.isChinese) {
    return sameYear
        ? '${time.month}月${time.day}日'
        : '${time.year}年${time.month}月${time.day}日';
  }
  final month = _englishMonths[time.month - 1].substring(0, 3);
  return sameYear ? '$month ${time.day}' : '$month ${time.day}, ${time.year}';
}

/// `October 20, 2026` / `2026年10月20日`.
String formatDateLong(DateTime time) {
  if (AppStrings.isChinese) {
    return '${time.year}年${time.month}月${time.day}日';
  }
  return '${_englishMonths[time.month - 1]} ${time.day}, ${time.year}';
}

/// `Tuesday` / `星期二` (`Tue` / `周二` when [abbreviated]).
String formatWeekday(DateTime time, {bool abbreviated = false}) {
  final index = time.weekday - 1;
  if (AppStrings.isChinese) {
    return '${abbreviated ? '周' : '星期'}${_chineseWeekdays[index]}';
  }
  final name = _englishWeekdays[index];
  return abbreviated ? name.substring(0, 3) : name;
}

/// The token's time in the reader's zone, in its style. [now] only matters
/// for [TimeTokenStyle.relative] and for leaving out the current year.
String formatTimeToken(
  TimeToken token, {
  required DateTime now,
  bool use24Hour = false,
}) {
  final time = token.time;
  String clock({bool seconds = false}) =>
      formatClock(time, use24Hour: use24Hour, seconds: seconds);
  switch (token.style) {
    case TimeTokenStyle.shortTime:
      return clock();
    case TimeTokenStyle.longTime:
      return clock(seconds: true);
    case TimeTokenStyle.shortDate:
      return formatDateShort(time, now: now);
    case TimeTokenStyle.longDate:
      return formatDateLong(time);
    case TimeTokenStyle.shortDateTime:
      final date = formatDateShort(time, now: now);
      final weekday = formatWeekday(time, abbreviated: true);
      return AppStrings.isChinese
          ? '$date $weekday ${clock()}'
          : '$weekday, $date, ${clock()}';
    case TimeTokenStyle.longDateTime:
      final date = formatDateLong(time);
      final weekday = formatWeekday(time);
      return AppStrings.isChinese
          ? '$date $weekday ${clock()}'
          : '$weekday, $date at ${clock()}';
    case TimeTokenStyle.relative:
      return relativeTimeText(time, now);
  }
}

/// How far [time] is from [now] in words: "in 2 hours", "3 days ago",
/// "tomorrow".
String relativeTimeText(DateTime time, DateTime now) {
  final difference = time.difference(now);
  final future = !difference.isNegative;
  final seconds = difference.inSeconds.abs();
  if (seconds < 45) {
    return future ? tr('in a moment') : tr('just now');
  }
  final minutes = (seconds / 60).round();
  if (minutes < 60) {
    if (future) {
      return minutes == 1
          ? tr('in 1 minute')
          : tr('in {count} minutes', {'count': minutes});
    }
    return minutes == 1
        ? tr('1 minute ago')
        : tr('{count} minutes ago', {'count': minutes});
  }
  final hours = (minutes / 60).round();
  if (hours < 24) {
    if (future) {
      return hours == 1
          ? tr('in 1 hour')
          : tr('in {count} hours', {'count': hours});
    }
    return hours == 1
        ? tr('1 hour ago')
        : tr('{count} hours ago', {'count': hours});
  }
  final days = DateTime(
    time.year,
    time.month,
    time.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 1) return tr('tomorrow');
  if (days == -1) return tr('yesterday');
  final count = days.abs();
  if (count < 30) {
    return days > 0
        ? tr('in {count} days', {'count': count})
        : tr('{count} days ago', {'count': count});
  }
  if (count < 365) {
    final months = (count / 30).round();
    if (days > 0) {
      return months == 1
          ? tr('in 1 month')
          : tr('in {count} months', {'count': months});
    }
    return months == 1
        ? tr('1 month ago')
        : tr('{count} months ago', {'count': months});
  }
  final years = (count / 365).round();
  if (days > 0) {
    return years == 1
        ? tr('in 1 year')
        : tr('in {count} years', {'count': years});
  }
  return years == 1
      ? tr('1 year ago')
      : tr('{count} years ago', {'count': years});
}

/// The reader's offset from UTC, like `UTC+8` or `UTC-7:30`.
String utcOffsetLabel(DateTime time) {
  final offset = time.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'UTC$sign$hours' : 'UTC$sign$hours:${_two(rest)}';
}

/// [text] with every time token turned into its time, for one-line
/// previews and notifications that have no widgets.
String replaceTimeTokensWithText(
  String text, {
  DateTime? now,
  bool use24Hour = false,
}) {
  if (!text.contains('<t:')) {
    return text;
  }
  final reference = now ?? DateTime.now();
  return text.replaceAllMapped(timeTokenPattern, (match) {
    final parsed = timeTokenAt(text, match.start);
    if (parsed == null) {
      return match.group(0)!;
    }
    return formatTimeToken(parsed.token, now: reference, use24Hour: use24Hour);
  });
}
