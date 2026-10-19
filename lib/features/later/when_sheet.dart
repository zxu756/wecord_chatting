import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/later/schedule_repeat.dart';
import 'package:wecord/features/notifications/device_time_zone.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Picks a date and then a time of day, in the device's time zone. Null
/// when either picker was dismissed.
Future<DateTime?> pickDateAndTime(
  BuildContext context, {
  required DateTime now,
  DateTime? initial,
}) async {
  final start = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: DateUtils.dateOnly(now),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
  );
  if (time == null) {
    return null;
  }
  return combineDateAndTime(date, time, now);
}

/// Opens the "when" sheet: quick [picks] and a custom date and time.
/// Returns the chosen time, or null when dismissed.
Future<DateTime?> showWhenSheet(
  BuildContext context, {
  required String title,
  required List<QuickWhen> Function(DateTime now) picks,
  DateTime? initial,
  String? subtitle,
  ValueNotifier<ScheduleRepeat?>? repeat,
}) {
  return showWeCordSheet<DateTime>(
    context,
    title: title,
    builder: (context, _) => WhenSheet(
      picks: picks,
      initial: initial,
      subtitle: subtitle,
      repeat: repeat,
    ),
  );
}

/// The content of the "when" sheet. Pops the chosen [DateTime].
class WhenSheet extends StatefulWidget {
  const WhenSheet({
    required this.picks,
    this.initial,
    this.subtitle,
    this.customPicker,
    this.repeat,
    super.key,
  });

  final List<QuickWhen> Function(DateTime now) picks;

  /// When given, the sheet has a "Repeat" row; what the user picks there is
  /// put in this notifier (the time is still what the sheet returns).
  final ValueNotifier<ScheduleRepeat?>? repeat;

  /// The time a custom pick starts from (when editing).
  final DateTime? initial;

  /// A line under the title, such as who a reminder is about.
  final String? subtitle;

  /// Replaces the date and time pickers (tests).
  final Future<DateTime?> Function(BuildContext context, DateTime now)?
  customPicker;

  @override
  State<WhenSheet> createState() => _WhenSheetState();
}

class _WhenSheetState extends State<WhenSheet> {
  String? _error;

  Future<void> _pickCustom(DateTime now) async {
    final picked = await (widget.customPicker != null
        ? widget.customPicker!(context, now)
        : pickDateAndTime(context, now: now, initial: widget.initial));
    if (picked == null || !mounted) {
      return;
    }
    if (!isUsableFuture(picked, clock.now())) {
      setState(() => _error = tr('Pick a time in the future.'));
      return;
    }
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final now = clock.now();
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final picks = widget.picks(now);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle case final subtitle?)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.muted, height: 1.35),
                ),
              ),
            SettingsGroup(
              color: c.well,
              children: [
                for (final pick in picks)
                  SettingsRow(
                    key: ValueKey('when-${pick.kind.name}'),
                    icon: pick.icon,
                    title: pick.label,
                    value: describeWhen(
                      localizations,
                      pick.at,
                      now,
                      alwaysUse24HourFormat: use24,
                    ),
                    showChevron: false,
                    onTap: () => Navigator.of(context).pop(pick.at),
                  ),
                SettingsRow(
                  key: const ValueKey('when-custom'),
                  icon: Icons.edit_calendar_outlined,
                  tone: SettingsTone.accent,
                  title: tr('Pick date and time'),
                  subtitle: tr('Your time zone: {zone}', {
                    'zone': '${now.timeZoneName} (${utcOffsetLabel(now)})',
                  }),
                  onTap: () => _pickCustom(now),
                ),
              ],
            ),
            if (widget.repeat case final repeat?) ...[
              const SizedBox(height: 12),
              SettingsGroup(
                color: c.well,
                children: [
                  ValueListenableBuilder<ScheduleRepeat?>(
                    valueListenable: repeat,
                    builder: (context, current, _) => SettingsRow(
                      key: const ValueKey('when-repeat'),
                      icon: Icons.repeat_rounded,
                      title: tr('Repeat'),
                      value: repeatKindLabel(current?.kind),
                      onTap: () async {
                        final choice = await showRepeatSheet(
                          context,
                          current: current,
                          zone: deviceTimeZone(),
                        );
                        if (choice != null) {
                          repeat.value = choice.repeat;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('when-error'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
