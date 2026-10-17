import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Times for scheduling and reminders, worked out in the time zone of the
/// [DateTime] they start from (the device's zone for `DateTime.now()`).
/// Wall-clock picks such as "tomorrow 9 am" are built from calendar fields,
/// so they stay right across daylight saving changes; instants are sent to
/// the server in UTC.

/// What a quick pick is.
enum QuickWhenKind {
  inTwentyMinutes,
  inOneHour,
  inThreeHours,
  tonight,
  tomorrowMorning,
}

/// A ready-made time to choose.
class QuickWhen {
  const QuickWhen(this.kind, this.at);

  final QuickWhenKind kind;
  final DateTime at;

  String get label => switch (kind) {
    QuickWhenKind.inTwentyMinutes => tr('In 20 minutes'),
    QuickWhenKind.inOneHour => tr('In 1 hour'),
    QuickWhenKind.inThreeHours => tr('In 3 hours'),
    QuickWhenKind.tonight => tr('Tonight at 8 pm'),
    QuickWhenKind.tomorrowMorning => tr('Tomorrow at 9 am'),
  };

  IconData get icon => switch (kind) {
    QuickWhenKind.inTwentyMinutes ||
    QuickWhenKind.inOneHour ||
    QuickWhenKind.inThreeHours => Icons.schedule_rounded,
    QuickWhenKind.tonight => Icons.nights_stay_outlined,
    QuickWhenKind.tomorrowMorning => Icons.wb_sunny_outlined,
  };
}

/// [now] with its seconds dropped: "in 1 hour" lands on a whole minute.
DateTime _wholeMinute(DateTime now) {
  return now.isUtc
      ? DateTime.utc(now.year, now.month, now.day, now.hour, now.minute)
      : DateTime(now.year, now.month, now.day, now.hour, now.minute);
}

/// The wall-clock time [hour]:00 on the day [dayOffset] days after [now],
/// in [now]'s zone.
DateTime wallClockTime(DateTime now, {int dayOffset = 0, required int hour}) {
  return now.isUtc
      ? DateTime.utc(now.year, now.month, now.day + dayOffset, hour)
      : DateTime(now.year, now.month, now.day + dayOffset, hour);
}

/// The earliest time a pick may be in the future: picks closer than this
/// are not offered.
const minimumLead = Duration(minutes: 5);

/// Quick picks for scheduling a message: in 1 hour, tonight at 8 pm (only
/// while it is at least [minimumLead] away) and tomorrow at 9 am.
List<QuickWhen> schedulePicks(DateTime now) {
  final tonight = wallClockTime(now, hour: 20);
  return [
    QuickWhen(
      QuickWhenKind.inOneHour,
      _wholeMinute(now).add(const Duration(hours: 1)),
    ),
    if (tonight.difference(now) >= minimumLead)
      QuickWhen(QuickWhenKind.tonight, tonight),
    QuickWhen(
      QuickWhenKind.tomorrowMorning,
      wallClockTime(now, dayOffset: 1, hour: 9),
    ),
  ];
}

/// Quick picks for a reminder: in 20 minutes, 1 hour, 3 hours and tomorrow
/// at 9 am.
List<QuickWhen> remindPicks(DateTime now) {
  final start = _wholeMinute(now);
  return [
    QuickWhen(
      QuickWhenKind.inTwentyMinutes,
      start.add(const Duration(minutes: 20)),
    ),
    QuickWhen(QuickWhenKind.inOneHour, start.add(const Duration(hours: 1))),
    QuickWhen(QuickWhenKind.inThreeHours, start.add(const Duration(hours: 3))),
    QuickWhen(
      QuickWhenKind.tomorrowMorning,
      wallClockTime(now, dayOffset: 1, hour: 9),
    ),
  ];
}

/// Whether [picked] is far enough ahead of [now] to be used.
bool isUsableFuture(DateTime picked, DateTime now) {
  return picked.difference(now) >= const Duration(minutes: 1);
}

/// A date and a time picked separately, as one instant in [zoneOf]'s zone.
DateTime combineDateAndTime(DateTime date, TimeOfDay time, DateTime zoneOf) {
  return zoneOf.isUtc
      ? DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
      : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// "UTC+8", "UTC-5:30": the zone [now] is in, for the custom time row.
String utcOffsetLabel(DateTime now) {
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final value = rest == 0
      ? '$hours'
      : '$hours:${rest.toString().padLeft(2, '0')}';
  return 'UTC$sign$value';
}

/// How a time reads in lists: "Today 8:00 PM", "Tomorrow 9:00 AM", or the
/// date for anything later ("Mon, Oct 19 9:00 AM"), in the zone of [when]
/// (convert it with `toLocal()` first).
String describeWhen(
  MaterialLocalizations localizations,
  DateTime when,
  DateTime now, {
  bool alwaysUse24HourFormat = false,
}) {
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(when),
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  // Calendar days apart, counted on UTC dates so a daylight saving change
  // (a 23 or 25 hour day) cannot shift the count.
  final days = DateTime.utc(
    when.year,
    when.month,
    when.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (days == 0) {
    return tr('Today {time}', {'time': time});
  }
  if (days == 1) {
    return tr('Tomorrow {time}', {'time': time});
  }
  final date = when.year == now.year
      ? localizations.formatMediumDate(when)
      : localizations.formatShortDate(when);
  return tr('{date} {time}', {'date': date, 'time': time});
}
