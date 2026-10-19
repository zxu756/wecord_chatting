import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/agenda/agenda_models.dart'
    show dateOnly, monthGrid, weekdayFromFirstDayIndex;
import 'package:wecord/features/agenda/month_day_cell.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A task list as a month: each day shows a dot for what is due on it (red
/// when something there is overdue); the picked day's tasks are listed
/// below, with a field to add one on that day, and the tasks with no date
/// at the end. The same month grid as My agenda.
class TaskCalendarView extends StatefulWidget {
  const TaskCalendarView({
    required this.controller,
    required this.members,
    required this.onOpen,
    required this.onAddOnDay,
    this.canEdit = true,
    super.key,
  });

  final TaskListController controller;
  final List<GroupMember> members;
  final void Function(TaskItem item) onOpen;

  /// Adds a task with [title] due on [day].
  final void Function(DateTime day, String title) onAddOnDay;
  final bool canEdit;

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  late DateTime _month = DateTime(clock.now().year, clock.now().month);
  late DateTime _selected = dateOnly(clock.now());
  final _add = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      final today = dateOnly(clock.now());
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

  void _submit(String text) {
    final title = text.trim();
    if (title.isEmpty) {
      return;
    }
    widget.onAddOnDay(_selected, title);
    _add.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final now = clock.now();
    final controller = widget.controller;
    final firstDay = weekdayFromFirstDayIndex(
      localizations.firstDayOfWeekIndex,
    );
    final byDay = controller.dueByDay();
    final weeks = monthGrid(_month, firstDayOfWeek: firstDay);
    final todayIsHere =
        now.year == _month.year &&
        now.month == _month.month &&
        _selected == dateOnly(now);
    final dayItems = controller.itemsDueOn(_selected);
    final undated = controller.undated;
    final fields = controller.list?.fieldDefs ?? const <TaskFieldDef>[];
    final weekdayNames = localizations.narrowWeekdays;
    final headers = [
      for (var i = 0; i < 7; i++) weekdayNames[(firstDay + i) % 7],
    ];

    Widget row(TaskItem item) => TaskRow(
      key: ValueKey('task-${item.id}'),
      item: item,
      members: widget.members,
      fields: fields,
      canEdit: widget.canEdit,
      onOpen: () => widget.onOpen(item),
      onToggleDone: () => controller.setDone(item.id, !item.isDone),
      now: now,
    );

    return ListView(
      key: const ValueKey('task-calendar'),
      // The grid takes nearly the full width so a day stays a 48 point target
      // on a narrow phone; the rest keeps the page margin.
      padding: EdgeInsets.fromLTRB(
        4,
        4,
        4,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Column(
            children: [
              Row(
                children: [
                  WeCordIconButton(
                    key: const ValueKey('task-calendar-previous'),
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
                        key: const ValueKey('task-calendar-title'),
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
                    key: const ValueKey('task-calendar-next'),
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
                        child: MonthDayCell(
                          keyPrefix: 'task-day',
                          day: day,
                          inMonth: day.month == _month.month,
                          today: day == dateOnly(now),
                          selected: day == _selected,
                          count: (byDay[day] ?? const []).length,
                          overdue: (byDay[day] ?? const []).any(
                            (item) => item.isOverdue(now),
                          ),
                          countLabel: (count) =>
                              tr('{count} tasks due', {'count': count}),
                          onPressed: () => setState(() => _selected = day),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          localizations.formatFullDate(_selected),
                          key: const ValueKey('task-calendar-selected-day'),
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
                        key: const ValueKey('task-calendar-today'),
                        label: tr('Today'),
                        size: WeCordButtonSize.small,
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: _today,
                      ),
                  ],
                ),
              ),
              if (dayItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    tr('No tasks due'),
                    key: const ValueKey('task-calendar-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                )
              else
                Column(
                  key: const ValueKey('task-calendar-day-list'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final item in dayItems) row(item)],
                ),
              if (widget.canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    key: const ValueKey('task-calendar-add-field'),
                    controller: _add,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 15.5, color: c.ink),
                    decoration: InputDecoration(
                      hintText: tr('Add a task for this day'),
                      prefixIcon: Icon(Icons.add_rounded, color: c.subtle),
                      filled: true,
                      fillColor: c.raised,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: WeCordFieldBorder(
                        borderRadius: BorderRadius.circular(WeCordRadii.pill),
                      ),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
              if (undated.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      tr('No date ({count})', {'count': undated.length}),
                      key: const ValueKey('task-calendar-undated'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.subtle,
                      ),
                    ),
                  ),
                ),
                for (final item in undated) row(item),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
