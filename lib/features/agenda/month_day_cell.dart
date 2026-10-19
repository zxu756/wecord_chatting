import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One day of a month grid: its number (ringed today, filled when picked)
/// and up to three dots for what is on it, red when something is overdue.
/// Shared by the agenda and the calendar view of a task list.
class MonthDayCell extends StatelessWidget {
  const MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.count,
    required this.overdue,
    required this.countLabel,
    required this.onPressed,
    this.keyPrefix = 'agenda-day',
    super.key,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final bool selected;

  /// How many things are on the day.
  final int count;

  /// Whether one of them is overdue.
  final bool overdue;

  /// What a screen reader says of [count] things ("3 on the agenda").
  final String Function(int count) countLabel;
  final VoidCallback onPressed;

  /// The key of the cell is `'<prefix>-<year>-<month>-<day>'`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final label = [
      localizations.formatFullDate(day),
      if (today) tr('Today'),
      if (count > 0) countLabel(count),
      if (overdue) tr('Overdue'),
    ].join(', ');
    final numberColor = selected
        ? c.onInk
        : inMonth
        ? c.ink
        : c.faint;
    return WeCordPressable(
      key: ValueKey('$keyPrefix-${day.year}-${day.month}-${day.day}'),
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: today || selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: numberColor,
                    ),
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
                    else if (count > 0)
                      _Dot(color: inMonth ? c.accent : c.faint),
                    if (count > 1) _Dot(color: inMonth ? c.accent : c.faint),
                    if (count > 2) _Dot(color: inMonth ? c.accent : c.faint),
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
