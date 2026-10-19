import 'package:flutter/material.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How a scheduled message repeats (D4). The server keeps the rule and writes
/// the next send after each one (migration 202610240450); this is the
/// app's side of it: the choice, the same calendar arithmetic for showing the
/// first send, and the words.

/// What the repeat is.
enum RepeatKind {
  daily('daily'),
  weekdays('weekdays'),
  weekly('weekly'),
  monthly('monthly');

  const RepeatKind(this.wire);

  /// The value of `scheduled_messages.recurrence`.
  final String wire;

  static RepeatKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }
}

/// A repeat rule. When the user makes one only [kind], [until] and [zone] are
/// set; the server works out the weekday, day of the month and time of day
/// from the first send. A rule that came back from the server has them all.
class ScheduleRepeat {
  const ScheduleRepeat({
    required this.kind,
    this.until,
    this.zone,
    this.day,
    this.hour,
    this.minute,
  });

  /// From a `scheduled_messages` row; null when the row does not repeat.
  static ScheduleRepeat? fromRow(Map<String, dynamic> row) {
    final kind = RepeatKind.fromWire(row['recurrence'] as String?);
    if (kind == null) {
      return null;
    }
    final time = (row['recurrence_time'] as String?)?.split(':');
    final until = row['recurrence_until'] as String?;
    return ScheduleRepeat(
      kind: kind,
      zone: row['recurrence_tz'] as String?,
      day: (row['recurrence_day'] as num?)?.toInt(),
      hour: time == null ? null : int.tryParse(time[0]),
      minute: time == null || time.length < 2 ? null : int.tryParse(time[1]),
      until: until == null ? null : DateTime.tryParse(until),
    );
  }

  final RepeatKind kind;

  /// The last day a send may fall on (the date counts, not the time).
  final DateTime? until;

  /// The IANA zone of the wall clock; the device's.
  final String? zone;

  /// Weekly: 1 (Monday) to 7 (Sunday); monthly: 1 to 31.
  final int? day;
  final int? hour;
  final int? minute;

  /// The same rule with another end ([clearUntil] removes it).
  ScheduleRepeat copyWith({
    RepeatKind? kind,
    DateTime? until,
    bool clearUntil = false,
    String? zone,
  }) {
    return ScheduleRepeat(
      kind: kind ?? this.kind,
      until: clearUntil ? null : until ?? this.until,
      zone: zone ?? this.zone,
      day: day,
      hour: hour,
      minute: minute,
    );
  }

  /// The columns to write: the server derives the rest.
  Map<String, dynamic> toColumns() => {
    'recurrence': kind.wire,
    'recurrence_tz': zone,
    'recurrence_until': until == null ? null : _dateText(until!),
  };

  /// This rule with the weekday, day and time of [firstSend], which is what
  /// the server makes of it.
  ScheduleRepeat startingAt(DateTime firstSend) {
    return ScheduleRepeat(
      kind: kind,
      until: until,
      zone: zone,
      day: switch (kind) {
        RepeatKind.weekly => firstSend.weekday,
        RepeatKind.monthly => firstSend.day,
        _ => null,
      },
      hour: firstSend.hour,
      minute: firstSend.minute,
    );
  }

  /// Whether a send falls on [date] (only its calendar day counts).
  bool matchesDate(DateTime date) {
    switch (kind) {
      case RepeatKind.daily:
        return true;
      case RepeatKind.weekdays:
        return date.weekday <= DateTime.friday;
      case RepeatKind.weekly:
        return date.weekday == day;
      case RepeatKind.monthly:
        // A month without the day sends on its last day.
        final lastDay = _isUtc(date)
            ? DateTime.utc(date.year, date.month + 1, 0).day
            : DateTime(date.year, date.month + 1, 0).day;
        return date.day == (day! < lastDay ? day! : lastDay);
    }
  }

  /// The first send strictly after [after], on the wall clock of [after]'s
  /// zone (the device's for `DateTime.now()`): each candidate is built from
  /// calendar fields, so 9:00 stays 9:00 across daylight saving changes (a
  /// time inside the skipped hour lands after the gap, as on the server).
  /// Null when the end date has passed or the rule is incomplete.
  DateTime? nextAfter(DateTime after) {
    final at = hour;
    final minutes = minute;
    if (at == null || minutes == null) {
      return null;
    }
    if ((kind == RepeatKind.weekly || kind == RepeatKind.monthly) &&
        day == null) {
      return null;
    }
    final utc = _isUtc(after);
    for (var offset = 0; offset <= 62; offset++) {
      final date = utc
          ? DateTime.utc(after.year, after.month, after.day + offset)
          : DateTime(after.year, after.month, after.day + offset);
      if (!matchesDate(date)) {
        continue;
      }
      if (until != null && _dayNumber(date) > _dayNumber(until!)) {
        return null;
      }
      final candidate = utc
          ? DateTime.utc(date.year, date.month, date.day, at, minutes)
          : DateTime(date.year, date.month, date.day, at, minutes);
      if (candidate.isAfter(after)) {
        return candidate;
      }
    }
    return null;
  }

  /// The first send for a message the user set for [picked]: [picked] itself
  /// when it fits the rule, else the next send that does (a weekdays message
  /// set for a Saturday goes out on Monday).
  DateTime? firstSend(DateTime picked) {
    final rule = startingAt(picked);
    final moment = _isUtc(picked)
        ? DateTime.utc(
            picked.year,
            picked.month,
            picked.day,
            picked.hour,
            picked.minute,
          )
        : DateTime(
            picked.year,
            picked.month,
            picked.day,
            picked.hour,
            picked.minute,
          );
    return rule.nextAfter(moment.subtract(const Duration(seconds: 1)));
  }
}

bool _isUtc(DateTime value) => value.isUtc;

int _dayNumber(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// "Every Monday 9:00 AM", "Weekdays 8:30 AM", "Every day 9:00 AM", "Every
/// month on day 31 9:00 AM", with " · until Dec 31" when it ends.
String describeRepeat(
  ScheduleRepeat repeat,
  MaterialLocalizations localizations, {
  bool alwaysUse24HourFormat = false,
}) {
  final hour = repeat.hour;
  final minute = repeat.minute;
  final time = hour == null || minute == null
      ? ''
      : localizations.formatTimeOfDay(
          TimeOfDay(hour: hour, minute: minute),
          alwaysUse24HourFormat: alwaysUse24HourFormat,
        );
  final base = switch (repeat.kind) {
    RepeatKind.daily => tr('Every day {time}', {'time': time}),
    RepeatKind.weekdays => tr('Weekdays {time}', {'time': time}),
    RepeatKind.weekly => '${_everyWeekday(repeat.day ?? 1)} $time',
    RepeatKind.monthly => tr('Every month on day {day} {time}', {
      'day': repeat.day ?? 1,
      'time': time,
    }),
  }.trim();
  final until = repeat.until;
  if (until == null) {
    return base;
  }
  return '$base · ${tr('until {date}', {'date': localizations.formatMediumDate(until)})}';
}

String _everyWeekday(int isoWeekday) => switch (isoWeekday) {
  1 => tr('Every Monday'),
  2 => tr('Every Tuesday'),
  3 => tr('Every Wednesday'),
  4 => tr('Every Thursday'),
  5 => tr('Every Friday'),
  6 => tr('Every Saturday'),
  _ => tr('Every Sunday'),
};

/// The name of a choice in the repeat picker.
String repeatKindLabel(RepeatKind? kind) => switch (kind) {
  null => tr('Does not repeat'),
  RepeatKind.daily => tr('Every day'),
  RepeatKind.weekdays => tr('Weekdays'),
  RepeatKind.weekly => tr('Every week'),
  RepeatKind.monthly => tr('Every month'),
};

/// What the user picked in [showRepeatSheet]; [repeat] is null for "Does not
/// repeat". A dismissed sheet gives no choice at all.
class RepeatChoice {
  const RepeatChoice(this.repeat);

  final ScheduleRepeat? repeat;
}

/// Opens the repeat choices and the end date. [current] is the rule now.
Future<RepeatChoice?> showRepeatSheet(
  BuildContext context, {
  required ScheduleRepeat? current,
  required String? zone,
}) {
  return showWeCordSheet<RepeatChoice>(
    context,
    title: tr('Repeat'),
    builder: (context, _) => RepeatSheet(current: current, zone: zone),
  );
}

/// The content of the repeat sheet: pick how it repeats, then when it ends.
class RepeatSheet extends StatefulWidget {
  const RepeatSheet({required this.current, required this.zone, super.key});

  final ScheduleRepeat? current;
  final String? zone;

  @override
  State<RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<RepeatSheet> {
  late RepeatKind? _kind = widget.current?.kind;
  late DateTime? _until = widget.current?.until;

  ScheduleRepeat? get _repeat {
    final kind = _kind;
    return kind == null
        ? null
        : ScheduleRepeat(kind: kind, until: _until, zone: widget.zone);
  }

  Future<void> _pickEnd() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() => _until = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionPickerBody<RepeatKind?>(
              options: [
                for (final kind in <RepeatKind?>[null, ...RepeatKind.values])
                  PickerOption<RepeatKind?>(
                    value: kind,
                    title: repeatKindLabel(kind),
                    subtitle: switch (kind) {
                      RepeatKind.weekly => tr(
                        'On the weekday of the first send',
                      ),
                      RepeatKind.monthly => tr(
                        'On the day of the month of the first send',
                      ),
                      _ => null,
                    },
                  ),
              ],
              selected: _kind,
              onPick: (kind) => setState(() => _kind = kind),
              note: _kind == RepeatKind.monthly
                  ? tr(
                      'In a month without that day it goes out on the last day of the month.',
                    )
                  : null,
            ),
            if (_kind != null) ...[
              const SizedBox(height: 12),
              SettingsGroup(
                color: c.well,
                children: [
                  SettingsRow(
                    key: const ValueKey('repeat-end'),
                    icon: Icons.event_busy_outlined,
                    title: tr('Ends'),
                    value: _until == null
                        ? tr('Does not end')
                        : localizations.formatMediumDate(_until!),
                    onTap: _pickEnd,
                  ),
                  if (_until != null)
                    SettingsRow(
                      key: const ValueKey('repeat-end-clear'),
                      icon: Icons.all_inclusive_rounded,
                      title: tr('Never stop repeating'),
                      showChevron: false,
                      onTap: () => setState(() => _until = null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('repeat-done'),
              label: tr('Done'),
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () => Navigator.of(context).pop(RepeatChoice(_repeat)),
            ),
          ],
        ),
      ),
    );
  }
}
