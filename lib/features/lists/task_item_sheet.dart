import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a task for reading and editing in a sheet.
Future<void> showTaskItemSheet(
  BuildContext context, {
  required TaskListController controller,
  required String itemId,
  required String conversationId,
  required List<GroupMember> members,
  required bool canEdit,
  VoidCallback? onShowMessage,
}) {
  return showWeCordSheet<void>(
    context,
    detents: const [0.6, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) => TaskItemSheet(
      controller: controller,
      itemId: itemId,
      conversationId: conversationId,
      members: members,
      canEdit: canEdit,
      scrollController: scrollController,
    ),
  );
}

/// The date a task is due, as stored: all-day dates end at 23:59 so a task
/// due "Oct 20" is only overdue after that day.
DateTime endOfDay(DateTime day) =>
    DateTime(day.year, day.month, day.day, 23, 59);

class TaskItemSheet extends ConsumerStatefulWidget {
  const TaskItemSheet({
    required this.controller,
    required this.itemId,
    required this.conversationId,
    required this.members,
    required this.canEdit,
    this.scrollController,
    super.key,
  });

  final TaskListController controller;
  final String itemId;
  final String conversationId;
  final List<GroupMember> members;
  final bool canEdit;
  final ScrollController? scrollController;

  @override
  ConsumerState<TaskItemSheet> createState() => _TaskItemSheetState();
}

class _TaskItemSheetState extends ConsumerState<TaskItemSheet> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  Timer? _titleTimer;
  Timer? _detailsTimer;
  var _filled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    // Whatever was typed last still counts.
    _commitTitle();
    _commitDetails();
    _titleTimer?.cancel();
    _detailsTimer?.cancel();
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _commitTitle() {
    _titleTimer?.cancel();
    final item = widget.controller.itemById(widget.itemId);
    final text = _title.text.trim();
    if (item != null && text.isNotEmpty && text != item.title) {
      widget.controller.patchItem(widget.itemId, {'title': text});
    }
  }

  void _commitDetails() {
    _detailsTimer?.cancel();
    final item = widget.controller.itemById(widget.itemId);
    if (item != null && _details.text != item.details) {
      widget.controller.patchItem(widget.itemId, {'details': _details.text});
    }
  }

  Future<void> _pickDue(TaskItem item) async {
    final result = await showTaskDueSheet(
      context,
      initial: item.dueAt,
      hasTime: item.dueHasTime,
    );
    if (result == null) {
      return;
    }
    widget.controller.patchItem(widget.itemId, {
      'due_at': result.due?.toUtc().toIso8601String(),
      'due_has_time': result.hasTime,
    });
  }

  Future<void> _pickAssignees(TaskItem item) async {
    final picked = await showAssigneePicker(
      context,
      members: widget.members,
      selected: item.assignees,
    );
    if (picked != null) {
      widget.controller.patchItem(widget.itemId, {'assignees': picked});
    }
  }

  Future<void> _share(TaskItem item) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(listsRepositoryProvider)
          .shareItem(item.id, widget.conversationId);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Shared in the chat.'))),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not share the task.'))),
      );
    }
  }

  void _showMessage(TaskItem item) {
    final messageId = item.sourceMessageId;
    if (messageId == null) {
      return;
    }
    final conversations = ref.read(conversationsProvider).value ?? const [];
    final conversation = conversations
        .where((conversation) => conversation.id == widget.conversationId)
        .firstOrNull;
    Navigator.of(context).pop();
    if (conversation != null) {
      openConversationAtMessage(
        context,
        ref,
        conversation: conversation,
        messageId: messageId,
      );
    } else {
      ref.read(pendingMessageJumpProvider.notifier).state = MessageJump(
        conversationId: widget.conversationId,
        messageId: messageId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final item = widget.controller.itemById(widget.itemId);
    final list = widget.controller.list;
    if (item == null || list == null) {
      return Center(
        child: Text(tr('This task is gone.'), style: TextStyle(color: c.muted)),
      );
    }
    if (!_filled) {
      _filled = true;
      _title.text = item.title;
      _details.text = item.details;
    }
    final canEdit = widget.canEdit;
    final byId = {for (final m in widget.members) m.profile.id: m};
    final assigneeNames = [
      for (final id in item.assignees)
        byId[id]?.profile.displayName ?? tr('Someone'),
    ];
    final selfId = ref.watch(authRepositoryProvider).currentUser?.id;

    Widget row({
      required IconData icon,
      required String label,
      required Widget value,
      VoidCallback? onTap,
    }) {
      return WeCordPressable(
        onPressed: canEdit ? onTap : null,
        semanticLabel: label,
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered) && canEdit
                ? c.raised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.muted),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: value),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _BigCheck(
                done: item.isDone,
                title: item.title,
                onChanged: canEdit
                    ? () => widget.controller.setDone(item.id, !item.isDone)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('task-title'),
                controller: _title,
                readOnly: !canEdit,
                maxLines: null,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.ink,
                  decoration: item.isDone ? TextDecoration.lineThrough : null,
                  decorationColor: c.muted,
                ),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  hintText: tr('Task title'),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (_) {
                  _titleTimer?.cancel();
                  _titleTimer = Timer(
                    const Duration(milliseconds: 600),
                    _commitTitle,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in list.statuses)
                WeCordChip(
                  key: ValueKey('task-status-${status.id}'),
                  label: status.label,
                  selected: item.status == status.id,
                  onPressed: canEdit && item.status != status.id
                      ? () => widget.controller.moveItem(
                          item.id,
                          status.id,
                          widget.controller
                              .itemsIn(status.id, manualOrder: true)
                              .length,
                        )
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        row(
          icon: Icons.person_add_alt_1_outlined,
          label: tr('Assigned to'),
          onTap: () => unawaited(_pickAssignees(item)),
          value: item.assignees.isEmpty
              ? Text(
                  canEdit ? tr('Nobody yet') : tr('Nobody'),
                  style: TextStyle(fontSize: 15, color: c.subtle),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AssigneeStack(
                      userIds: item.assignees,
                      members: widget.members,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        assigneeNames.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        row(
          icon: Icons.event_outlined,
          label: tr('Due'),
          onTap: () => unawaited(_pickDue(item)),
          value: item.dueAt == null
              ? Text(
                  canEdit ? tr('No date') : tr('No due date'),
                  style: TextStyle(fontSize: 15, color: c.subtle),
                )
              : DueChip(item: item),
        ),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: WeCordSegmented<TaskPriority>(
              key: const ValueKey('task-priority'),
              semanticLabel: tr('Priority'),
              expand: true,
              height: 36,
              selected: item.priority,
              onChanged: (priority) => widget.controller.patchItem(item.id, {
                'priority': priority.value,
              }),
              segments: [
                WeCordSegment(value: TaskPriority.none, label: tr('None')),
                WeCordSegment(value: TaskPriority.low, label: tr('Low')),
                WeCordSegment(value: TaskPriority.medium, label: tr('Med')),
                WeCordSegment(value: TaskPriority.high, label: tr('High')),
              ],
            ),
          )
        else
          row(
            icon: Icons.flag_outlined,
            label: tr('Priority'),
            value: Text(
              item.priority.label,
              style: TextStyle(fontSize: 15, color: c.ink),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: WeCordTextField(
            controller: _details,
            label: tr('Notes'),
            hint: canEdit ? tr('Add details') : null,
            enabled: canEdit,
            maxLines: 6,
            minLines: 3,
            maxLength: 5000,
            onChanged: (_) {
              _detailsTimer?.cancel();
              _detailsTimer = Timer(
                const Duration(milliseconds: 700),
                _commitDetails,
              );
            },
          ),
        ),
        if (item.sourceMessageId != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: WeCordButton(
              label: tr('View the message'),
              icon: Icons.chat_bubble_outline_rounded,
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.small,
              onPressed: () => _showMessage(item),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                label: tr('Share in the chat'),
                icon: Icons.ios_share_rounded,
                variant: WeCordButtonVariant.secondary,
                expand: true,
                onPressed: () => unawaited(_share(item)),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 10),
              WeCordIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: tr('Delete task'),
                variant: WeCordButtonVariant.danger,
                size: 44,
                onPressed: () {
                  widget.controller.deleteItem(item.id);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ],
        ),
        if (selfId != null && item.isAssignedTo(selfId)) ...[
          const SizedBox(height: 10),
          Text(
            tr('This task is assigned to you.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.subtle),
          ),
        ],
      ],
    );
  }
}

class _BigCheck extends StatelessWidget {
  const _BigCheck({
    required this.done,
    required this.title,
    required this.onChanged,
  });

  final bool done;
  final String title;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onChanged,
      toggled: done,
      semanticLabel: done
          ? tr('Mark "{title}" as not done', {'title': title})
          : tr('Mark "{title}" as done', {'title': title}),
      shape: const CircleBorder(),
      builder: (context, states) => AnimatedContainer(
        duration: WeCordMotion.quick,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? c.success : Colors.transparent,
          border: Border.all(color: done ? c.success : c.faint, width: 2),
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Picks a due date: quick choices, a calendar and an optional time.
/// Returns null when dismissed; a null `due` clears the date.
Future<({DateTime? due, bool hasTime})?> showTaskDueSheet(
  BuildContext context, {
  DateTime? initial,
  bool hasTime = false,
}) {
  return showWeCordSheet<({DateTime? due, bool hasTime})>(
    context,
    title: tr('Due date'),
    builder: (context, _) => _DueSheet(initial: initial, hasTime: hasTime),
  );
}

class _DueSheet extends StatefulWidget {
  const _DueSheet({required this.initial, required this.hasTime});

  final DateTime? initial;
  final bool hasTime;

  @override
  State<_DueSheet> createState() => _DueSheetState();
}

class _DueSheetState extends State<_DueSheet> {
  late DateTime? _date = widget.initial;
  late bool _hasTime = widget.hasTime;

  void _finish() {
    final date = _date;
    Navigator.of(context).pop((
      due: date == null
          ? null
          : _hasTime
          ? date
          : endOfDay(date),
      hasTime: date != null && _hasTime,
    ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        final time = _date;
        _date = _hasTime && time != null
            ? DateTime(
                picked.year,
                picked.month,
                picked.day,
                time.hour,
                time.minute,
              )
            : endOfDay(picked);
      });
    }
  }

  Future<void> _pickTime() async {
    final current = _date ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _hasTime
          ? TimeOfDay.fromDateTime(current)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() {
        final day = _date ?? DateTime.now();
        _date = DateTime(
          day.year,
          day.month,
          day.day,
          picked.hour,
          picked.minute,
        );
        _hasTime = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final now = DateTime.now();
    Widget quick(String label, DateTime day) {
      final selected =
          _date != null &&
          _date!.year == day.year &&
          _date!.month == day.month &&
          _date!.day == day.day;
      return WeCordChip(
        label: label,
        selected: selected,
        onPressed: () => setState(() {
          _date = _hasTime && _date != null
              ? DateTime(
                  day.year,
                  day.month,
                  day.day,
                  _date!.hour,
                  _date!.minute,
                )
              : endOfDay(day);
        }),
      );
    }

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
              quick(tr('Today'), now),
              quick(tr('Tomorrow'), now.add(const Duration(days: 1))),
              quick(tr('Next week'), now.add(const Duration(days: 7))),
            ],
          ),
          const SizedBox(height: 14),
          WeCordButton(
            label: _date == null
                ? tr('Pick a date')
                : formatDue(context, _date!, hasTime: false),
            icon: Icons.calendar_month_outlined,
            variant: WeCordButtonVariant.secondary,
            expand: true,
            onPressed: () => unawaited(_pickDate()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Add a time'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              if (_hasTime && _date != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: WeCordButton(
                    label: MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(_date!)),
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: () => unawaited(_pickTime()),
                  ),
                ),
              WeCordSwitch(
                value: _hasTime,
                semanticLabel: tr('Add a time'),
                onChanged: (value) {
                  if (value) {
                    unawaited(_pickTime());
                  } else {
                    setState(() {
                      _hasTime = false;
                      if (_date != null) {
                        _date = endOfDay(_date!);
                      }
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  label: tr('No date'),
                  variant: WeCordButtonVariant.secondary,
                  expand: true,
                  onPressed: () {
                    setState(() => _date = null);
                    _finish();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  label: tr('Done'),
                  expand: true,
                  onPressed: _finish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Picks who a task is for from the people of the conversation. Returns the
/// chosen user ids, or null when dismissed.
Future<List<String>?> showAssigneePicker(
  BuildContext context, {
  required List<GroupMember> members,
  required List<String> selected,
}) {
  return showWeCordSheet<List<String>>(
    context,
    title: tr('Assign to'),
    detents: const [0.55, 0.92],
    initialDetent: 0.7,
    builder: (context, scrollController) => _AssigneePicker(
      members: members,
      selected: selected,
      scrollController: scrollController,
    ),
  );
}

class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker({
    required this.members,
    required this.selected,
    this.scrollController,
  });

  final List<GroupMember> members;
  final List<String> selected;
  final ScrollController? scrollController;

  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  late final Set<String> _selected = {...widget.selected};
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final needle = _query.trim().toLowerCase();
    final members = [
      for (final member in widget.members)
        if (needle.isEmpty ||
            member.profile.displayName.toLowerCase().contains(needle) ||
            member.profile.username.toLowerCase().contains(needle))
          member,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: WeCordTextField(
            hint: tr('Search people'),
            prefixIcon: Icons.search_rounded,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              final id = member.profile.id;
              final on = _selected.contains(id);
              return WeCordPressable(
                key: ValueKey('assignee-$id'),
                onPressed: () => setState(() {
                  if (on) {
                    _selected.remove(id);
                  } else if (_selected.length < 10) {
                    _selected.add(id);
                  }
                }),
                selected: on,
                toggled: on,
                semanticLabel: member.profile.displayName,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                pressedScale: 0.99,
                builder: (context, states) => Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: on
                        ? c.accentSoft
                        : states.contains(WidgetState.hovered)
                        ? c.raised
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  ),
                  child: Row(
                    children: [
                      PersonAvatar(name: member.profile.displayName, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          member.profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Icon(
                        on
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: on ? c.accent : c.faint,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: WeCordButton(
            label: tr('Done'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
          ),
        ),
      ],
    );
  }
}
