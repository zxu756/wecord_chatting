import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/actions/apply_extracted_actions.dart';
import 'package:wecord/features/ai/actions/extract_actions_repository.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId, newClientId;
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_item_sheet.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The most messages one extraction reads (the `ai` function's limit).
const maxExtractMessages = 50;

/// Whether [message] can be read for to-dos: written text that is still
/// there.
bool canExtractFrom(ChatMessage message) =>
    message.type == MessageType.text &&
    message.recalledAt == null &&
    message.reviewState == null &&
    message.body.trim().isNotEmpty &&
    !isPendingMessageId(message.id);

/// Opens the sheet that turns messages into tasks and events: [messages] are
/// sent to the `ai` function and its findings listed for the person to tick,
/// edit and confirm. With [preset] the items are already known (a to-do list
/// WeCord AI wrote in the chat) and nothing is asked of the AI. Resolves to
/// true when something was created.
Future<bool?> showExtractActionsSheet(
  BuildContext context, {
  required String conversationId,
  List<ChatMessage> messages = const [],
  List<ExtractedAction>? preset,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('To-dos from the chat'),
    detents: const [0.6, 0.92],
    initialDetent: 0.8,
    builder: (sheetContext, scrollController) => ExtractActionsSheet(
      conversationId: conversationId,
      messages: messages,
      preset: preset,
      scrollController: scrollController,
    ),
  );
}

class _Row {
  _Row(this.action)
    : title = TextEditingController(text: action.title),
      id = newClientId();

  ExtractedAction action;
  bool included = true;
  final TextEditingController title;

  /// The task's id, kept across tries so a lost answer cannot duplicate it.
  final String id;

  ExtractedAction get edited => action.copyWith(title: title.text.trim());
}

/// The review sheet. Its pieces carry keys for tests: `extract-item-N`,
/// `extract-item-title-N`, `extract-item-tick-N`, `extract-create`.
class ExtractActionsSheet extends ConsumerStatefulWidget {
  const ExtractActionsSheet({
    required this.conversationId,
    this.messages = const [],
    this.preset,
    this.scrollController,
    super.key,
  });

  final String conversationId;
  final List<ChatMessage> messages;
  final List<ExtractedAction>? preset;
  final ScrollController? scrollController;

  @override
  ConsumerState<ExtractActionsSheet> createState() =>
      _ExtractActionsSheetState();
}

class _ExtractActionsSheetState extends ConsumerState<ExtractActionsSheet> {
  var _rows = <_Row>[];
  var _loading = true;
  Object? _error;
  var _saving = false;
  var _read = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.title.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    try {
      final List<ExtractedAction> found;
      var read = 0;
      final preset = widget.preset;
      if (preset != null) {
        found = preset;
        read = 0;
      } else {
        final result = await ref
            .read(extractActionsRepositoryProvider)
            .extract(
              conversationId: widget.conversationId,
              messageIds: [
                for (final message in widget.messages.take(maxExtractMessages))
                  message.id,
              ],
              now: now,
            );
        found = result.items;
        read = result.messageCount;
      }
      if (!mounted) {
        return;
      }
      for (final row in _rows) {
        row.title.dispose();
      }
      setState(() {
        _rows = [for (final item in found) _Row(item.refined(now))];
        _read = read;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  int get _chosen => _rows
      .where((row) => row.included && row.title.text.trim().isNotEmpty)
      .length;

  Future<void> _create() async {
    final chosen = [
      for (final row in _rows)
        if (row.included && row.title.text.trim().isNotEmpty) row,
    ];
    if (chosen.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    final outcomes = await applyExtractedActions(
      lists: ref.read(listsRepositoryProvider),
      events: ref.read(chatEventsRepositoryProvider),
      conversationId: widget.conversationId,
      actions: [for (final row in chosen) row.edited],
      newId: newClientId,
      taskIds: [for (final row in chosen) row.id],
    );
    if (!mounted) {
      return;
    }
    var tasks = 0;
    var events = 0;
    final failed = <_Row>[];
    for (final (index, outcome) in outcomes.indexed) {
      switch (outcome) {
        case TaskCreated():
          tasks++;
        case EventCreated():
          events++;
        case ApplyFailed():
          failed.add(chosen[index]);
      }
    }
    ref
      ..invalidate(messageTasksProvider(widget.conversationId))
      ..invalidate(taskListsProvider(widget.conversationId));
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (failed.isEmpty) {
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(content: Text(_doneText(tasks, events))),
      );
      return;
    }
    // Keep only what could not be made, so trying again cannot repeat the rest.
    setState(() {
      _saving = false;
      for (final row in _rows.toList()) {
        if (chosen.contains(row) && !failed.contains(row)) {
          _rows.remove(row);
          row.title.dispose();
        }
      }
    });
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tasks + events > 0
              ? tr(
                  '{done} created. {failed} could not be created. Try again.',
                  {'done': tasks + events, 'failed': failed.length},
                )
              : tr('Could not create them. Try again.'),
        ),
      ),
    );
  }

  String _doneText(int tasks, int events) {
    String taskPart() =>
        tasks == 1 ? tr('1 task') : tr('{count} tasks', {'count': tasks});
    String eventPart() =>
        events == 1 ? tr('1 event') : tr('{count} events', {'count': events});
    if (tasks > 0 && events > 0) {
      return tr('{tasks} and {events} created.', {
        'tasks': taskPart(),
        'events': eventPart(),
      });
    }
    if (events > 0) {
      return events == 1
          ? tr('Event created.')
          : tr('{count} events created.', {'count': events});
    }
    return tasks == 1
        ? tr('Task created.')
        : tr('{count} tasks created.', {'count': tasks});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final members =
        ref.watch(conversationMembersProvider(widget.conversationId)).value ??
        const <GroupMember>[];
    final Widget body;
    if (_loading) {
      body = _Status(
        key: const ValueKey('extract-loading'),
        icon: Icons.auto_awesome_rounded,
        text: widget.messages.length > 1
            ? tr('Reading {count} messages…', {'count': widget.messages.length})
            : tr('Reading the message…'),
        progress: true,
      );
    } else if (_error != null) {
      body = _Status(
        key: const ValueKey('extract-error'),
        icon: Icons.error_outline_rounded,
        text: aiErrorMessage(_error!),
        action:
            _error is AiNotConfiguredException ||
                _error is AiDisabledInCircleException ||
                _error is AiTurnedOffException
            ? null
            : WeCordButton(
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => unawaited(_load()),
              ),
      );
    } else if (_rows.isEmpty) {
      body = _Status(
        key: const ValueKey('extract-empty'),
        icon: Icons.checklist_rounded,
        text: tr('No to-dos or events found in these messages.'),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              tr(
                'WeCord AI suggests these. Change anything and untick what you do not want; nothing is created until you confirm.',
              ),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
            ),
          ),
          for (final (index, row) in _rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ItemCard(
                key: ValueKey('extract-item-$index'),
                index: index,
                row: row,
                members: members,
                onChanged: () => setState(() {}),
              ),
            ),
          const SizedBox(height: 6),
          WeCordButton(
            key: const ValueKey('extract-create'),
            label: _chosen == 0
                ? tr('Nothing selected')
                : _chosen == 1
                ? tr('Create 1 item')
                : tr('Create {count} items', {'count': _chosen}),
            icon: Icons.add_task_rounded,
            expand: true,
            size: WeCordButtonSize.large,
            loading: _saving,
            onPressed: _chosen == 0 ? null : () => unawaited(_create()),
          ),
          if (_read > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                tr('Read {count} messages.', {'count': _read}),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.subtle),
              ),
            ),
        ],
      );
    }
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: widget.scrollController == null,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [body],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.text,
    this.progress = false,
    this.action,
    super.key,
  });

  final IconData icon;
  final String text;
  final bool progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          if (progress)
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, size: 30, color: c.subtle),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.index,
    required this.row,
    required this.members,
    required this.onChanged,
    super.key,
  });

  final int index;
  final _Row row;
  final List<GroupMember> members;
  final VoidCallback onChanged;

  String _assigneeLabel() {
    final ids = row.action.assignees;
    if (ids.isEmpty) {
      return tr('Assign');
    }
    if (ids.length > 1) {
      return tr('{count} assigned', {'count': ids.length});
    }
    final member = members.where((m) => m.profile.id == ids.first).firstOrNull;
    return member == null
        ? tr('1 assigned')
        : (member.nickname?.trim().isNotEmpty == true
              ? member.nickname!.trim()
              : member.profile.displayLabel);
  }

  Future<void> _pickAssignees(BuildContext context) async {
    final picked = await showAssigneePicker(
      context,
      members: members,
      selected: row.action.assignees,
    );
    if (picked != null) {
      row.action = row.action.copyWith(assignees: picked);
      onChanged();
    }
  }

  Future<void> _pickDue(BuildContext context, {bool needTime = false}) async {
    final action = row.action;
    final picked = await showTaskDueSheet(
      context,
      initial: action.due,
      hasTime: needTime || action.dueHasTime,
    );
    if (picked == null) {
      if (action.kind == ExtractedKind.event && !action.canBeEvent) {
        // No date and time were chosen: it stays a task.
        row.action = action.copyWith(kind: ExtractedKind.task);
        onChanged();
      }
      return;
    }
    var next = action.copyWith(due: picked.due, dueHasTime: picked.hasTime);
    if (next.kind == ExtractedKind.event && !next.canBeEvent) {
      next = next.copyWith(kind: ExtractedKind.task);
    }
    row.action = next;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final action = row.action;
    final due = action.due;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      decoration: BoxDecoration(
        color: row.included ? c.raised : c.raised.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WeCordPressable(
            key: ValueKey('extract-item-tick-$index'),
            toggled: row.included,
            semanticLabel: row.title.text.trim().isEmpty
                ? tr('Include')
                : row.title.text.trim(),
            hint: tr('Include in the new items'),
            onPressed: () {
              row.included = !row.included;
              onChanged();
            },
            builder: (context, states) => SizedBox.square(
              dimension: 44,
              child: Icon(
                row.included
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: row.included ? c.accent : c.faint,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeCordTextField(
                  key: ValueKey('extract-item-title-$index'),
                  controller: row.title,
                  label: tr('Title'),
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 300,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    WeCordChip(
                      key: ValueKey('extract-item-assignee-$index'),
                      icon: Icons.person_outline_rounded,
                      label: _assigneeLabel(),
                      selected: action.assignees.isNotEmpty,
                      onPressed: members.isEmpty
                          ? null
                          : () => unawaited(_pickAssignees(context)),
                    ),
                    WeCordChip(
                      key: ValueKey('extract-item-due-$index'),
                      icon: Icons.event_outlined,
                      label: due == null
                          ? tr('Due date')
                          : formatDue(context, due, hasTime: action.dueHasTime),
                      selected: due != null,
                      onPressed: () => unawaited(_pickDue(context)),
                    ),
                    WeCordSegmented<ExtractedKind>(
                      key: ValueKey('extract-item-kind-$index'),
                      height: 32,
                      semanticLabel: tr('Make it a'),
                      segments: [
                        WeCordSegment(
                          value: ExtractedKind.task,
                          label: tr('Task'),
                          key: ValueKey('extract-item-task-$index'),
                        ),
                        WeCordSegment(
                          value: ExtractedKind.event,
                          label: tr('Event'),
                          key: ValueKey('extract-item-event-$index'),
                        ),
                      ],
                      selected: action.kind,
                      onChanged: (kind) {
                        if (kind == ExtractedKind.event && !action.canBeEvent) {
                          // An event needs a date and a time of day.
                          row.action = action.copyWith(kind: kind);
                          onChanged();
                          unawaited(_pickDue(context, needTime: true));
                          return;
                        }
                        row.action = action.copyWith(kind: kind);
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
