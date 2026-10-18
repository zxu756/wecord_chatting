import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_navigation.dart';
import 'package:wecord/features/agenda/agenda_repository.dart';
import 'package:wecord/features/agenda/agenda_row.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The agenda as a month: a grid of days with a dot for each kind of thing
/// on them (red for what is overdue), and the picked day's entries below.
class AgendaMonthView extends ConsumerStatefulWidget {
  const AgendaMonthView({required this.onRefresh, super.key});

  final Future<void> Function() onRefresh;

  @override
  ConsumerState<AgendaMonthView> createState() => _AgendaMonthViewState();
}

class _AgendaMonthViewState extends ConsumerState<AgendaMonthView> {
  late DateTime _month = DateTime(clock.now().year, clock.now().month);
  late DateTime _selected = dateOnly(clock.now());

  void _go(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      final today = dateOnly(clock.now());
      // Land on today when it is in the month, else on the 1st.
      _selected = today.year == _month.year && today.month == _month.month
          ? today
          : _month;
    });
  }

  void _today() {
    final now = clock.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = dateOnly(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final now = clock.now();
    final firstDay = weekdayFromFirstDayIndex(
      localizations.firstDayOfWeekIndex,
    );
    final month = ref.watch(agendaMonthProvider(_month));
    final items = month.value ?? const <AgendaItem>[];
    final byDay = agendaByDay(items);
    final weeks = monthGrid(_month, firstDayOfWeek: firstDay);
    final todayIsHere =
        now.year == _month.year &&
        now.month == _month.month &&
        _selected == dateOnly(now);
    final dayItems = agendaOnDay(items, _selected);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;

    final weekdayNames = localizations.narrowWeekdays;
    // narrowWeekdays starts on Sunday; DateTime.sunday is 7.
    final headers = [
      for (var i = 0; i < 7; i++) weekdayNames[(firstDay + i) % 7],
    ];

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const ValueKey('agenda-month'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(WeCordRadii.xl),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    WeCordIconButton(
                      key: const ValueKey('agenda-month-previous'),
                      icon: Icons.chevron_left_rounded,
                      tooltip: localizations.previousMonthTooltip,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: () => _go(-1),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          localizations.formatMonthYear(_month),
                          key: const ValueKey('agenda-month-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                    WeCordIconButton(
                      key: const ValueKey('agenda-month-next'),
                      icon: Icons.chevron_right_rounded,
                      tooltip: localizations.nextMonthTooltip,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: () => _go(1),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final name in headers)
                      Expanded(
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.subtle,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                for (final week in weeks)
                  Row(
                    children: [
                      for (final day in week)
                        Expanded(
                          child: _DayCell(
                            day: day,
                            inMonth: day.month == _month.month,
                            today: day == dateOnly(now),
                            selected: day == _selected,
                            items: byDay[day] ?? const [],
                            now: now,
                            onPressed: () => setState(() => _selected = day),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      localizations.formatFullDate(_selected),
                      key: const ValueKey('agenda-selected-day'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.subtle,
                      ),
                    ),
                  ),
                ),
                if (!todayIsHere)
                  WeCordButton(
                    key: const ValueKey('agenda-month-today'),
                    label: tr('Today'),
                    size: WeCordButtonSize.small,
                    variant: WeCordButtonVariant.onPaper,
                    onPressed: _today,
                  ),
              ],
            ),
          ),
          if (month.isLoading && !month.hasValue)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (month.hasError && !month.hasValue)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('Could not load your agenda.'),
                key: const ValueKey('agenda-month-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dangerText),
              ),
            )
          else if (dayItems.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('Nothing planned'),
                key: const ValueKey('agenda-day-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            )
          else
            Container(
              key: const ValueKey('agenda-day-list'),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.xl),
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in dayItems)
                    AgendaRow(
                      item: item,
                      now: now,
                      onPressed: () => openAgendaItem(context, ref, item),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.items,
    required this.now,
    required this.onPressed,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final bool selected;
  final List<AgendaItem> items;
  final DateTime now;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final overdue = items.any((item) => item.isOverdue(now));
    final label = [
      localizations.formatFullDate(day),
      if (today) tr('Today'),
      if (items.isNotEmpty)
        tr('{count} on the agenda', {'count': items.length}),
      if (overdue) tr('Overdue'),
    ].join(', ');
    final numberColor = selected
        ? c.onInk
        : inMonth
        ? c.ink
        : c.faint;
    return WeCordPressable(
      key: ValueKey('agenda-day-${day.year}-${day.month}-${day.day}'),
      onPressed: onPressed,
      selected: selected,
      semanticLabel: label,
      excludeSemantics: true,
      pressedScale: 0.94,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return SizedBox(
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected
                      ? c.ink
                      : hovered
                      ? c.raised
                      : Colors.transparent,
                  shape: CircleBorder(
                    side: today && !selected
                        ? BorderSide(color: c.accent, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: today || selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: numberColor,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overdue)
                      _Dot(color: c.badgeMention)
                    else if (items.isNotEmpty)
                      _Dot(color: inMonth ? c.accent : c.faint),
                    if (items.length > 1)
                      _Dot(color: inMonth ? c.accent : c.faint),
                    if (items.length > 2)
                      _Dot(color: inMonth ? c.accent : c.faint),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
