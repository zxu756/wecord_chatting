import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/time_tokens/time_phrase_parser.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/shared/calendar/calendar_file_saver.dart';
import 'package:wecord/shared/calendar/ics.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether time chips refresh their "in 2 hours" hints by themselves every
/// minute. Widget tests turn it off, so no timer outlives them.
final timeTokenFollowsClockProvider = Provider<bool>((ref) => true);

/// The current time, ticking each minute while a time chip is on screen.
final timeTokenClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());
  if (ref.watch(timeTokenFollowsClockProvider)) {
    final timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => controller.add(DateTime.now()),
    );
    ref.onDispose(timer.cancel);
  }
  ref.onDispose(controller.close);
  return controller.stream;
});

/// Within this distance of now a chip adds "in 2 hours" next to the date.
const _hintWindow = Duration(days: 7);

/// The words a chip shows: the time in the reader's zone, and for the
/// styles that are not already relative, how far away it is.
({String text, String? hint}) timeTokenLabel(
  TimeToken token, {
  required DateTime now,
  required bool use24Hour,
}) {
  final text = formatTimeToken(token, now: now, use24Hour: use24Hour);
  if (token.style == TimeTokenStyle.relative) {
    return (text: text, hint: null);
  }
  final distance = token.time.difference(now).abs();
  return (
    text: text,
    hint: distance <= _hintWindow ? relativeTimeText(token.time, now) : null,
  );
}

/// A message's words without its time tokens, for naming a calendar entry.
String calendarTitleFromMessage(String body) {
  final stripped = body
      .replaceAll(timeTokenPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (stripped.isEmpty) {
    return tr('Reminder from WeCord');
  }
  return stripped.length > 80 ? '${stripped.substring(0, 79)}…' : stripped;
}

/// Saves [token]'s moment as an .ics file: downloaded in the browser, or
/// through the share sheet (which offers Calendar) on iOS and macOS.
Future<CalendarSaveResult> addTimeTokenToCalendar(
  WidgetRef ref,
  TimeToken token, {
  String? title,
}) {
  final name = title ?? tr('Reminder from WeCord');
  final start = token.time;
  return ref
      .read(calendarFileSaverProvider)
      .save(
        fileName: calendarFileName(name),
        contents: buildIcsCalendar(
          uid: '${token.unix}-${name.hashCode.abs()}@wecord',
          title: name,
          start: start,
          end: start.add(const Duration(hours: 1)),
          remindMinutesBefore: 15,
        ),
      );
}

Future<void> showTimeTokenSheet(
  BuildContext context, {
  required TimeToken token,
  String? eventTitle,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Time'),
    builder: (context, _) =>
        _TimeTokenDetails(token: token, eventTitle: eventTitle),
  );
}

class _TimeTokenDetails extends ConsumerWidget {
  const _TimeTokenDetails({required this.token, this.eventTitle});

  final TimeToken token;
  final String? eventTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = token.time;
    final full = formatTimeToken(
      TimeToken(token.unix, TimeTokenStyle.longDateTime),
      now: now,
      use24Hour: use24Hour,
    );
    final zone = '${utcOffsetLabel(time)} · ${time.timeZoneName}';
    final messenger = ScaffoldMessenger.maybeOf(context);

    Future<void> addToCalendar() async {
      final result = await addTimeTokenToCalendar(
        ref,
        token,
        title: eventTitle,
      );
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            CalendarSaveResult.downloaded => tr(
              'Calendar file downloaded. Open it to add the event.',
            ),
            CalendarSaveResult.shared => tr(
              'Choose Calendar to add the event.',
            ),
            CalendarSaveResult.failed => tr(
              'Could not create the calendar file.',
            ),
          }),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            full,
            key: const ValueKey('time-token-full'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: c.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            relativeTimeText(time, now),
            key: const ValueKey('time-token-relative'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.accentText,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.public_rounded, size: 20, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      'Shown in your time zone ({zone}). Everyone who reads this sees their own.',
                      {'zone': zone},
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: c.muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          WeCordButton(
            key: const ValueKey('time-token-add-to-calendar'),
            label: tr('Add to calendar'),
            icon: Icons.event_available_rounded,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: addToCalendar,
          ),
          const SizedBox(height: 10),
          WeCordButton(
            key: const ValueKey('time-token-copy'),
            label: tr('Copy time'),
            icon: Icons.copy_rounded,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: full));
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
              messenger?.showSnackBar(
                SnackBar(content: Text(tr('Time copied.'))),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Insert time

/// Which look the picked time gets in the message.
enum _InsertKind { dateTime, date, time, relative }

/// Lets the writer pick a date and time and returns the token to put in
/// the message, or null when they cancel.
Future<TimeToken?> showInsertTimeSheet(BuildContext context) {
  return showWeCordSheet<TimeToken>(
    context,
    title: tr('Insert time'),
    builder: (context, _) => const _InsertTimeBody(),
  );
}

class _InsertTimeBody extends StatefulWidget {
  const _InsertTimeBody();

  @override
  State<_InsertTimeBody> createState() => _InsertTimeBodyState();
}

class _InsertTimeBodyState extends State<_InsertTimeBody> {
  late DateTime _time;
  var _kind = _InsertKind.dateTime;

  @override
  void initState() {
    super.initState();
    final soon = DateTime.now().add(const Duration(minutes: 90));
    _time = DateTime(soon.year, soon.month, soon.day, soon.hour);
  }

  TimeToken get _token => TimeToken.fromDateTime(_time, switch (_kind) {
    _InsertKind.dateTime => TimeTokenStyle.shortDateTime,
    _InsertKind.date => TimeTokenStyle.longDate,
    _InsertKind.time => TimeTokenStyle.shortTime,
    _InsertKind.relative => TimeTokenStyle.relative,
  });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateUtils.dateOnly(_time.isBefore(now) ? _time : now),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) {
      setState(
        () => _time = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _time.hour,
          _time.minute,
        ),
      );
    }
  }

  Future<void> _pickClock() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked != null && mounted) {
      setState(
        () => _time = DateTime(
          _time.year,
          _time.month,
          _time.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  void _preset(DateTime time) => setState(() => _time = time);

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final now = DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final preview = formatTimeToken(
      TimeToken(_token.unix, TimeTokenStyle.longDateTime),
      now: now,
      use24Hour: use24Hour,
    );
    DateTime at(int dayOffset, int hour) =>
        DateTime(now.year, now.month, now.day + dayOffset, hour);
    final mondayOffset = (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WeCordChip(
                label: tr('In 1 hour'),
                onPressed: () {
                  final soon = now.add(const Duration(hours: 1));
                  _preset(
                    DateTime(
                      soon.year,
                      soon.month,
                      soon.day,
                      soon.hour,
                      soon.minute,
                    ),
                  );
                },
              ),
              WeCordChip(
                label: tr('Tonight 8 PM'),
                onPressed: () => _preset(at(0, 20)),
              ),
              WeCordChip(
                label: tr('Tomorrow 9 AM'),
                onPressed: () => _preset(at(1, 9)),
              ),
              WeCordChip(
                label: tr('Next Monday 9 AM'),
                onPressed: () => _preset(at(mondayOffset, 9)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SettingsGroup(
            separatorIndent: 14,
            color: c.well,
            children: [
              SettingsRow(
                key: const ValueKey('insert-time-date'),
                icon: Icons.calendar_today_rounded,
                title: tr('Date'),
                value: formatDateLong(_time),
                onTap: _pickDate,
              ),
              SettingsRow(
                key: const ValueKey('insert-time-clock'),
                icon: Icons.schedule_rounded,
                title: tr('Time'),
                value: formatClock(_time, use24Hour: use24Hour),
                onTap: _pickClock,
              ),
            ],
          ),
          const SizedBox(height: 14),
          WeCordSegmented<_InsertKind>(
            expand: true,
            semanticLabel: tr('How it looks'),
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
            segments: [
              WeCordSegment(
                value: _InsertKind.dateTime,
                label: tr('Date & time'),
              ),
              WeCordSegment(value: _InsertKind.date, label: tr('Date')),
              WeCordSegment(value: _InsertKind.time, label: tr('Time')),
              WeCordSegment(
                value: _InsertKind.relative,
                label: tr('Countdown'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.public_rounded, size: 20, color: c.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Readers see {time} in their own time zone.', {
                      'time': preview,
                    }),
                    key: const ValueKey('insert-time-preview'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.accentText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          WeCordButton(
            key: const ValueKey('insert-time-confirm'),
            label: tr('Insert'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_token),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------- Composer offer

/// Above the composer: when the text being written names a date and time,
/// offers to turn it into a time token every reader sees in their own zone.
class TimePhraseSuggestion extends StatefulWidget {
  const TimePhraseSuggestion({
    required this.controller,
    required this.onConverted,
    this.horizontalPadding = 16,
    this.clock,
    super.key,
  });

  final TextEditingController controller;

  /// Called after the text changed, so drafts and typing state follow.
  final VoidCallback onConverted;
  final double horizontalPadding;

  /// The current time; the real one by default (tests fix it).
  final DateTime Function()? clock;

  @override
  State<TimePhraseSuggestion> createState() => _TimePhraseSuggestionState();
}

class _TimePhraseSuggestionState extends State<TimePhraseSuggestion> {
  Timer? _debounce;
  TimePhrase? _phrase;
  String _phraseText = '';
  final _dismissed = <String>{};

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleScan);
    _scan();
  }

  @override
  void didUpdateWidget(covariant TimePhraseSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleScan);
      widget.controller.addListener(_scheduleScan);
      _scan();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_scheduleScan);
    super.dispose();
  }

  void _scheduleScan() {
    final text = widget.controller.text;
    final phrase = _phrase;
    // Still showing for the same words: nothing to do until they change.
    if (phrase != null &&
        phrase.end <= text.length &&
        phrase.textIn(text) == _phraseText) {
      return;
    }
    _debounce?.cancel();
    if (text.isEmpty) {
      _scan();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _scan);
  }

  void _scan() {
    if (!mounted) {
      return;
    }
    final text = widget.controller.text;
    final found = findTimePhrases(text, now: _now())
        .where(
          (phrase) => !_dismissed.contains(phrase.textIn(text).toLowerCase()),
        )
        .firstOrNull;
    if (found?.textIn(text) == (_phrase == null ? null : _phraseText) &&
        found?.start == _phrase?.start) {
      return;
    }
    setState(() {
      _phrase = found;
      _phraseText = found?.textIn(text) ?? '';
    });
  }

  void _convert() {
    final phrase = _phrase;
    if (phrase == null) {
      return;
    }
    final value = widget.controller.value;
    final text = value.text;
    if (phrase.end > text.length || phrase.textIn(text) != _phraseText) {
      _scan();
      return;
    }
    final token = TimeToken.fromDateTime(phrase.time).markup;
    final replaced = text.replaceRange(phrase.start, phrase.end, token);
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : text.length;
    final shift = token.length - (phrase.end - phrase.start);
    final nextCursor = cursor >= phrase.end
        ? cursor + shift
        : (cursor > phrase.start ? phrase.start + token.length : cursor);
    widget.controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(
        offset: nextCursor.clamp(0, replaced.length),
      ),
    );
    setState(() {
      _phrase = null;
      _phraseText = '';
    });
    widget.onConverted();
    _scan();
  }

  void _dismiss() {
    _dismissed.add(_phraseText.toLowerCase());
    setState(() {
      _phrase = null;
      _phraseText = '';
    });
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrase;
    if (phrase == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final when = formatTimeToken(
      TimeToken.fromDateTime(phrase.time),
      now: _now(),
      use24Hour: use24Hour,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        0,
        widget.horizontalPadding,
        8,
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: tr('Suggestion: make "{text}" a shared time', {
          'text': _phraseText,
        }),
        child: Container(
          key: const ValueKey('time-phrase-suggestion'),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
            border: Border.all(color: c.line),
            boxShadow: context.tokens.shadows.hairline,
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: c.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      when,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      tr('"{text}" as a time in each reader\'s zone', {
                        'text': _phraseText,
                      }),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              WeCordButton(
                key: const ValueKey('time-phrase-convert'),
                label: tr('Convert'),
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.accent,
                onPressed: _convert,
              ),
              WeCordIconButton(
                key: const ValueKey('time-phrase-dismiss'),
                tooltip: tr('Dismiss'),
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 18,
                onPressed: _dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
