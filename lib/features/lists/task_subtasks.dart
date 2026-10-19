import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/notes/note_block_views.dart' show NoteCheckBox;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The most subtasks a task can have.
const maxSubtasks = 50;

/// The steps of a task in its sheet: a progress line, the subtasks with
/// check boxes, and a field to add one. Subtasks have no subtasks.
class TaskSubtasksSection extends StatefulWidget {
  const TaskSubtasksSection({
    required this.controller,
    required this.parent,
    required this.canEdit,
    required this.onOpen,
    super.key,
  });

  final TaskListController controller;
  final TaskItem parent;
  final bool canEdit;
  final void Function(TaskItem subtask) onOpen;

  @override
  State<TaskSubtasksSection> createState() => _TaskSubtasksSectionState();
}

class _TaskSubtasksSectionState extends State<TaskSubtasksSection> {
  final _add = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final title = text.trim();
    if (title.isEmpty) {
      return;
    }
    if (widget.controller.subtasksOf(widget.parent.id).length >= maxSubtasks) {
      return;
    }
    widget.controller.createItem(
      title.length > 300 ? title.substring(0, 300) : title,
      parentId: widget.parent.id,
    );
    _add.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtasks = widget.controller.subtasksOf(widget.parent.id);
    final progress = widget.controller.subtaskProgress(widget.parent.id);
    final canAdd = widget.canEdit && subtasks.length < maxSubtasks;
    if (subtasks.isEmpty && !widget.canEdit) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('task-subtasks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(Icons.checklist_rounded, size: 20, color: c.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    tr('Subtasks'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
              if (subtasks.isNotEmpty)
                Text(
                  tr('{done} of {total} done', {
                    'done': progress.done,
                    'total': progress.total,
                  }),
                  key: const ValueKey('task-subtasks-progress'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: progress.done == progress.total
                        ? c.successText
                        : c.subtle,
                  ),
                ),
            ],
          ),
        ),
        for (final subtask in subtasks)
          WeCordPressable(
            key: ValueKey('subtask-${subtask.id}'),
            onPressed: () => widget.onOpen(subtask),
            semanticLabel: subtask.title,
            hint: tr('Opens the subtask'),
            mergeSemantics: false,
            pressedScale: 0.99,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            builder: (context, states) => Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.raised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Row(
                children: [
                  NoteCheckBox(
                    checked: subtask.isDone,
                    onChanged: widget.canEdit
                        ? () => widget.controller.setDone(
                            subtask.id,
                            !subtask.isDone,
                          )
                        : null,
                    label: subtask.isDone
                        ? tr('Mark "{title}" as not done', {
                            'title': subtask.title,
                          })
                        : tr('Mark "{title}" as done', {
                            'title': subtask.title,
                          }),
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      subtask.title,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: subtask.isDone ? c.muted : c.ink,
                        decoration: subtask.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: c.muted,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
                ],
              ),
            ),
          ),
        if (canAdd)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: TextField(
              key: const ValueKey('subtask-add-field'),
              controller: _add,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                hintText: tr('Add a subtask'),
                prefixIcon: Icon(Icons.add_rounded, color: c.subtle),
                filled: true,
                fillColor: c.raised,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: WeCordFieldBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.pill),
                ),
              ),
              onSubmitted: _submit,
            ),
          ),
      ],
    );
  }
}
