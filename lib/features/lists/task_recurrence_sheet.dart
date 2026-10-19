import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

String taskRepeatUnitName(TaskRepeatUnit unit, int interval) {
  final args = {'count': interval};
  return switch (unit) {
    TaskRepeatUnit.daily =>
      interval == 1 ? trIn('repeat-unit', 'Day') : tr('{count} days', args),
    TaskRepeatUnit.weekly =>
      interval == 1 ? trIn('repeat-unit', 'Week') : tr('{count} weeks', args),
    TaskRepeatUnit.monthly =>
      interval == 1 ? trIn('repeat-unit', 'Month') : tr('{count} months', args),
    TaskRepeatUnit.yearly =>
      interval == 1 ? trIn('repeat-unit', 'Year') : tr('{count} years', args),
  };
}

/// Picks how a task repeats. Returns null when dismissed; a result with a
/// null `rule` means "does not repeat".
Future<({TaskRecurrence? rule})?> showTaskRecurrenceSheet(
  BuildContext context, {
  TaskRecurrence? current,
}) {
  return showWeCordSheet<({TaskRecurrence? rule})>(
    context,
    title: tr('Repeat'),
    builder: (context, _) => _RecurrenceSheet(current: current),
  );
}

class _RecurrenceSheet extends StatefulWidget {
  const _RecurrenceSheet({required this.current});

  final TaskRecurrence? current;

  @override
  State<_RecurrenceSheet> createState() => _RecurrenceSheetState();
}

class _RecurrenceSheetState extends State<_RecurrenceSheet> {
  late TaskRepeatUnit? _unit = widget.current?.unit;
  late int _interval = widget.current?.interval ?? 1;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final unit = _unit;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
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
                key: const ValueKey('repeat-never'),
                label: tr('Does not repeat'),
                selected: unit == null,
                onPressed: () => setState(() => _unit = null),
              ),
              for (final option in TaskRepeatUnit.values)
                WeCordChip(
                  key: ValueKey('repeat-${option.value}'),
                  label: TaskRecurrence(unit: option).label,
                  selected: unit == option && _interval == 1,
                  onPressed: () => setState(() {
                    _unit = option;
                    _interval = 1;
                  }),
                ),
            ],
          ),
          if (unit != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Every'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                WeCordIconButton(
                  key: const ValueKey('repeat-less'),
                  icon: Icons.remove_rounded,
                  tooltip: tr('Less often'),
                  size: 40,
                  variant: WeCordButtonVariant.secondary,
                  onPressed: _interval > 1
                      ? () => setState(() => _interval--)
                      : null,
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 96),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    taskRepeatUnitName(unit, _interval),
                    key: const ValueKey('repeat-interval'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
                WeCordIconButton(
                  key: const ValueKey('repeat-more'),
                  icon: Icons.add_rounded,
                  tooltip: tr('More often'),
                  size: 40,
                  variant: WeCordButtonVariant.secondary,
                  onPressed: _interval < 99
                      ? () => setState(() => _interval++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'When you finish it, the next one is made, due on the next date.',
              ),
              style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
            ),
          ],
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('repeat-done'),
            label: tr('Done'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => Navigator.of(context).pop((
              rule: unit == null
                  ? null
                  : TaskRecurrence.here(unit, interval: _interval),
            )),
          ),
        ],
      ),
    );
  }
}
