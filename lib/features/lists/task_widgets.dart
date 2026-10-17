import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/notes/note_block_views.dart' show NoteCheckBox;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Today", "Tomorrow", "Yesterday", "Oct 20" (and the time when the date
/// has one), for a task's due date.
String formatDue(
  BuildContext context,
  DateTime due, {
  required bool hasTime,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final localizations = MaterialLocalizations.of(context);
  final day = DateTime(due.year, due.month, due.day);
  final base = DateTime(today.year, today.month, today.day);
  final difference = day.difference(base).inDays;
  final date = switch (difference) {
    0 => tr('Today'),
    1 => tr('Tomorrow'),
    -1 => tr('Yesterday'),
    _ =>
      due.year == today.year
          ? localizations.formatShortMonthDay(due)
          : localizations.formatMediumDate(due),
  };
  if (!hasTime) {
    return date;
  }
  return '$date, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(due))}';
}

Color priorityColor(WeCordPalette c, TaskPriority priority) {
  return switch (priority) {
    TaskPriority.high => c.danger,
    TaskPriority.medium => c.warning,
    TaskPriority.low => c.accent,
    TaskPriority.none => c.faint,
  };
}

/// A small pill with an icon and a word: the due date, the priority.
class TaskChip extends StatelessWidget {
  const TaskChip({
    required this.label,
    this.icon,
    this.color,
    this.background,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: background ?? c.raised,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The due date of [item] as a chip: red once overdue, amber on its day.
class DueChip extends StatelessWidget {
  const DueChip({required this.item, this.now, super.key});

  final TaskItem item;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final due = item.dueAt;
    if (due == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final current = now ?? DateTime.now();
    final overdue = item.isOverdue(current);
    final today =
        !item.isDone &&
        !overdue &&
        due.year == current.year &&
        due.month == current.month &&
        due.day == current.day;
    return TaskChip(
      icon: overdue ? Icons.error_outline_rounded : Icons.event_outlined,
      label: formatDue(context, due, hasTime: item.dueHasTime, now: current),
      color: item.isDone
          ? c.muted
          : overdue
          ? c.dangerText
          : today
          ? c.warningText
          : c.muted,
      background: item.isDone
          ? c.raised
          : overdue
          ? c.dangerSoft
          : today
          ? c.warningSoft
          : c.raised,
    );
  }
}

/// Overlapped avatars of the people a task is assigned to.
class AssigneeStack extends StatelessWidget {
  const AssigneeStack({
    required this.userIds,
    required this.members,
    this.size = 24,
    this.max = 3,
    super.key,
  });

  final List<String> userIds;
  final List<GroupMember> members;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final byId = {for (final member in members) member.profile.id: member};
    final shown = userIds.take(max).toList();
    final names = [
      for (final id in userIds) byId[id]?.profile.displayName ?? tr('Someone'),
    ];
    final step = size * 0.7;
    return Semantics(
      label: tr('Assigned to {names}', {'names': names.join(', ')}),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + (shown.length - 1) * step,
            height: size,
            child: Stack(
              children: [
                for (final (index, id) in shown.indexed)
                  Positioned(
                    left: index * step,
                    child: PersonAvatar(
                      name: byId[id]?.profile.displayName ?? '?',
                      size: size,
                      ringColor: c.panel,
                    ),
                  ),
              ],
            ),
          ),
          if (userIds.length > max) ...[
            const SizedBox(width: 4),
            Text(
              '+${userIds.length - max}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a task row or card says about the task besides its title: due date,
/// priority, notes, a link to its message, and who it is for.
class TaskMeta extends StatelessWidget {
  const TaskMeta({
    required this.item,
    required this.members,
    this.now,
    super.key,
  });

  final TaskItem item;
  final List<GroupMember> members;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final hasAnything =
        item.dueAt != null ||
        item.priority != TaskPriority.none ||
        item.details.isNotEmpty ||
        item.sourceMessageId != null ||
        item.assignees.isNotEmpty;
    if (!hasAnything) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (item.dueAt != null) DueChip(item: item, now: now),
          if (item.priority != TaskPriority.none)
            TaskChip(
              icon: Icons.flag_rounded,
              label: item.priority.label,
              color: priorityColor(c, item.priority),
            ),
          if (item.details.isNotEmpty)
            Icon(Icons.notes_rounded, size: 15, color: c.faint),
          if (item.sourceMessageId != null)
            Icon(Icons.chat_bubble_outline_rounded, size: 14, color: c.faint),
          if (item.assignees.isNotEmpty)
            AssigneeStack(userIds: item.assignees, members: members),
        ],
      ),
    );
  }
}

/// A task in the list view: check box, title and what is known of it.
class TaskRow extends StatelessWidget {
  const TaskRow({
    required this.item,
    required this.members,
    required this.onOpen,
    required this.onToggleDone,
    this.canEdit = true,
    this.now,
    super.key,
  });

  final TaskItem item;
  final List<GroupMember> members;
  final VoidCallback onOpen;
  final VoidCallback? onToggleDone;
  final bool canEdit;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onOpen,
      semanticLabel: item.title,
      hint: tr('Opens the task'),
      mergeSemantics: false,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.raised
              : Colors.transparent,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.zero,
              child: NoteCheckBox(
                checked: item.isDone,
                onChanged: canEdit ? onToggleDone : null,
                label: item.isDone
                    ? tr('Mark "{title}" as not done', {'title': item.title})
                    : tr('Mark "{title}" as done', {'title': item.title}),
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: _checkInset(context, 22) + 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: item.isDone ? c.muted : c.ink,
                        decoration: item.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: c.muted,
                      ),
                    ),
                    TaskMeta(item: item, members: members, now: now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The space above a title so it lines up with a check box of [size] that
/// grew to the touch target.
double _checkInset(BuildContext context, double size) =>
    ((context.touchTargetSize - size) / 2).clamp(0, 24).toDouble();

/// A task as a card on a board.
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.item,
    required this.members,
    required this.onOpen,
    required this.onToggleDone,
    this.canEdit = true,
    this.lifted = false,
    this.now,
    super.key,
  });

  final TaskItem item;
  final List<GroupMember> members;
  final VoidCallback? onOpen;
  final VoidCallback? onToggleDone;
  final bool canEdit;

  /// Drawn as picked up (the drag feedback).
  final bool lifted;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return WeCordPressable(
      onPressed: onOpen,
      semanticLabel: item.title,
      hint: tr('Opens the task'),
      mergeSemantics: false,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) && !lifted
              ? c.well
              : c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: lifted ? c.accent : c.lineSoft),
          boxShadow: lifted ? tokens.shadows.menu : tokens.shadows.hairline,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.zero,
              child: NoteCheckBox(
                checked: item.isDone,
                onChanged: canEdit ? onToggleDone : null,
                label: item.isDone
                    ? tr('Mark "{title}" as not done', {'title': item.title})
                    : tr('Mark "{title}" as done', {'title': item.title}),
                size: 20,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: _checkInset(context, 20) + 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: item.isDone ? c.muted : c.ink,
                        decoration: item.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: c.muted,
                      ),
                    ),
                    TaskMeta(item: item, members: members, now: now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
