import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_item_sheet.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/features/notes/note_block_views.dart' show NoteCheckBox;
import 'package:wecord/features/notes/note_models.dart' show NoteMeta;
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart' show EmojiTile;
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a shared note, task or list card in a chat points at.
enum WorkspaceCardKind { note, task, list }

class WorkspaceCard {
  const WorkspaceCard({
    required this.kind,
    required this.id,
    required this.title,
    required this.icon,
    this.listId,
  });

  final WorkspaceCardKind kind;

  /// The note, task or list.
  final String id;
  final String title;
  final String icon;

  /// A task's list.
  final String? listId;

  static WorkspaceCard? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null) {
      return null;
    }
    switch (attachment['kind']) {
      case 'note':
        final id = attachment['note_id'];
        if (id is String) {
          return WorkspaceCard(
            kind: WorkspaceCardKind.note,
            id: id,
            title: attachment['title'] as String? ?? '',
            icon: attachment['icon'] as String? ?? '\u{1F4DD}',
          );
        }
      case 'task':
        final id = attachment['item_id'];
        if (id is String) {
          return WorkspaceCard(
            kind: WorkspaceCardKind.task,
            id: id,
            title: attachment['title'] as String? ?? '',
            icon: '☑',
            listId: attachment['list_id'] as String?,
          );
        }
      case 'list':
        final id = attachment['list_id'];
        if (id is String) {
          return WorkspaceCard(
            kind: WorkspaceCardKind.list,
            id: id,
            title: attachment['title'] as String? ?? '',
            icon: attachment['icon'] as String? ?? TaskList.defaultIcon,
          );
        }
    }
    return null;
  }
}

extension WorkspaceMessageCard on ChatMessage {
  /// The note, task or list this message shares, or null.
  WorkspaceCard? get workspaceCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return WorkspaceCard.maybeFromAttachment(attachment);
  }
}

final _taskCardProvider = FutureProvider.autoDispose
    .family<TaskSnapshot, String>((ref, itemId) {
      return ref.watch(listsRepositoryProvider).getItem(itemId);
    });

/// A shared note, task or list in a chat: tap to open it beside the chat.
/// A task's check box works from here.
class WorkspaceCardView extends ConsumerWidget {
  const WorkspaceCardView({
    required this.card,
    required this.conversationId,
    this.textColor,
    this.onDark = false,
    super.key,
  });

  final WorkspaceCard card;
  final String conversationId;
  final Color? textColor;

  /// On an ink (own) bubble: colors flip.
  final bool onDark;

  void _open(BuildContext context, WidgetRef ref) {
    switch (card.kind) {
      case WorkspaceCardKind.note:
        openWorkspace(context, conversationId: conversationId, noteId: card.id);
      case WorkspaceCardKind.list:
        openWorkspace(
          context,
          conversationId: conversationId,
          tab: WorkspaceTab.lists,
          listId: card.id,
        );
      case WorkspaceCardKind.task:
        openWorkspace(
          context,
          conversationId: conversationId,
          tab: WorkspaceTab.lists,
          listId: card.listId,
          itemId: card.id,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    TaskItem? item;
    TaskList? list;
    if (card.kind == WorkspaceCardKind.task) {
      final snapshot = ref.watch(_taskCardProvider(card.id)).value;
      item = snapshot?.items.firstOrNull;
      list = snapshot?.list;
    }
    final title = (item?.title ?? card.title).trim().isEmpty
        ? switch (card.kind) {
            WorkspaceCardKind.note => tr('Untitled'),
            WorkspaceCardKind.task => tr('Task'),
            WorkspaceCardKind.list => tr('Untitled list'),
          }
        : (item?.title ?? card.title);
    final kindLabel = switch (card.kind) {
      WorkspaceCardKind.note => tr('Note'),
      WorkspaceCardKind.task => tr('Task'),
      WorkspaceCardKind.list => tr('List'),
    };
    final done = item?.isDone ?? false;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 220),
      child: WeCordPressable(
        key: ValueKey('workspace-card-${card.id}'),
        onPressed: () => _open(context, ref),
        semanticLabel: '$kindLabel: $title',
        hint: tr('Opens it beside the chat'),
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(
              color: states.contains(WidgetState.hovered) ? c.line : c.lineSoft,
            ),
          ),
          child: Row(
            children: [
              if (card.kind == WorkspaceCardKind.task && item != null)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 10),
                  child: NoteCheckBox(
                    checked: done,
                    label: done
                        ? tr('Mark "{title}" as not done', {'title': title})
                        : tr('Mark "{title}" as done', {'title': title}),
                    onChanged: (list?.canEdit ?? false)
                        ? () => unawaited(_toggle(ref, item!))
                        : null,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: EmojiTile(emoji: card.icon, size: 40),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kindLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: c.subtle,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: done ? c.muted : c.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: c.muted,
                      ),
                    ),
                    if (item?.dueAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DueChip(item: item!),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, TaskItem item) async {
    try {
      await ref
          .read(listsRepositoryProvider)
          .setItemDone(item.id, !item.isDone);
    } on Object {
      // The card shows the server's state again below.
    }
    ref
      ..invalidate(_taskCardProvider(card.id))
      ..invalidate(messageTasksProvider(conversationId));
  }
}

/// The note pinned to the top of a conversation, as a slim banner.
class PinnedNoteBanner extends StatelessWidget {
  const PinnedNoteBanner({
    required this.conversationId,
    required this.note,
    super.key,
  });

  final String conversationId;
  final NoteMeta note;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = note.title.trim().isEmpty ? tr('Untitled') : note.title;
    return WeCordPressable(
      key: const ValueKey('pinned-note-banner'),
      onPressed: () => openWorkspace(
        context,
        conversationId: conversationId,
        noteId: note.id,
      ),
      semanticLabel: tr('Pinned note: {title}', {'title': title}),
      hint: tr('Opens the note'),
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_rounded, size: 16, color: c.accentText),
            const SizedBox(width: 8),
            Text(note.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.accentText),
          ],
        ),
      ),
    );
  }
}

/// Under a message that became a task: its title with a check box.
class MessageTaskChip extends ConsumerWidget {
  const MessageTaskChip({required this.message, this.textColor, super.key});

  final ChatMessage message;
  final Color? textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.recalledAt != null || message.type == MessageType.system) {
      return const SizedBox.shrink();
    }
    final tasks = ref.watch(messageTasksProvider(message.conversationId)).value;
    final task = tasks?[message.id];
    if (task == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: WeCordPressable(
        key: ValueKey('message-task-${task.itemId}'),
        onPressed: () => openWorkspace(
          context,
          conversationId: message.conversationId,
          tab: WorkspaceTab.lists,
          listId: task.listId,
          itemId: task.itemId,
        ),
        semanticLabel: tr('Task: {title}', {'title': task.title}),
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: const StadiumBorder(),
        builder: (context, states) => Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
          decoration: ShapeDecoration(
            color: c.well,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoteCheckBox(
                checked: task.isDone,
                size: 18,
                label: task.isDone
                    ? tr('Mark "{title}" as not done', {'title': task.title})
                    : tr('Mark "{title}" as done', {'title': task.title}),
                onChanged: () => unawaited(_toggle(ref, task)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: task.isDone ? c.muted : c.ink,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: c.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, MessageTask task) async {
    try {
      await ref
          .read(listsRepositoryProvider)
          .setItemDone(task.itemId, !task.isDone);
    } on Object {
      // Shown again from the server below.
    }
    ref.invalidate(messageTasksProvider(message.conversationId));
  }
}

/// The message menu's "Create task": a sheet with the title taken from the
/// message, the list to put it in and optionally who it is for and when it
/// is due. The task keeps a link to the message.
Future<void> showCreateTaskFromMessage(
  BuildContext context,
  ChatMessage message,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final created = await showWeCordSheet<TaskItem>(
    context,
    title: tr('Create task'),
    builder: (sheetContext, _) => _CreateTaskSheet(message: message),
  );
  if (created == null || !context.mounted) {
    return;
  }
  container
    ..invalidate(messageTasksProvider(message.conversationId))
    ..invalidate(taskListsProvider(message.conversationId));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(tr('Task created.')),
      action: SnackBarAction(
        label: tr('Open'),
        onPressed: () => openWorkspace(
          context,
          conversationId: message.conversationId,
          tab: WorkspaceTab.lists,
          listId: created.listId,
          itemId: created.id,
        ),
      ),
    ),
  );
}

/// A first line of [body] to use as a task title.
String taskTitleFromMessage(ChatMessage message) {
  final firstLine = message.body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isNotEmpty) {
    return firstLine.length > 300 ? firstLine.substring(0, 300) : firstLine;
  }
  return switch (message.type) {
    MessageType.image => tr('Picture'),
    MessageType.voice => tr('Voice message'),
    MessageType.file => (message.attachment?['name'] as String?) ?? tr('File'),
    _ => tr('Task from a message'),
  };
}

class _CreateTaskSheet extends ConsumerStatefulWidget {
  const _CreateTaskSheet({required this.message});

  final ChatMessage message;

  @override
  ConsumerState<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<_CreateTaskSheet> {
  late final _title = TextEditingController(
    text: taskTitleFromMessage(widget.message),
  );
  String? _listId;
  var _assignees = <String>[];
  DateTime? _due;
  var _dueHasTime = false;
  var _saving = false;
  final _itemId = newClientId();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    final repository = ref.read(listsRepositoryProvider);
    try {
      var item = await repository.createFromMessage(
        widget.message.id,
        listId: _listId,
        title: title,
        itemId: _itemId,
      );
      if (_assignees.isNotEmpty || _due != null) {
        item = await repository.upsertItem(item.listId, {
          'id': item.id,
          if (_assignees.isNotEmpty) 'assignees': _assignees,
          if (_due != null) ...{
            'due_at': _due!.toUtc().toIso8601String(),
            'due_has_time': _dueHasTime,
          },
        });
        if (_assignees.isNotEmpty) {
          unawaited(repository.notifyAssignments(item.id));
        }
      }
      if (mounted) {
        Navigator.of(context).pop(item);
      }
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not create the task.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final conversationId = widget.message.conversationId;
    final lists =
        ref.watch(taskListsProvider(conversationId)).value ?? const [];
    final members =
        ref.watch(conversationMembersProvider(conversationId)).value ??
        const [];
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
          WeCordTextField(
            controller: _title,
            label: tr('Task'),
            maxLines: 3,
            minLines: 1,
            maxLength: 300,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          if (lists.isNotEmpty) ...[
            Text(
              tr('List'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, list) in lists.indexed)
                  WeCordChip(
                    key: ValueKey('create-task-list-${list.id}'),
                    label:
                        '${list.icon} ${list.title.isEmpty ? tr('Untitled list') : list.title}',
                    selected: (_listId ?? lists.first.id) == list.id,
                    onPressed: list.canEdit
                        ? () => setState(
                            () => _listId = index == 0 ? null : list.id,
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  label: _assignees.isEmpty
                      ? tr('Assign')
                      : tr('{count} assigned', {'count': _assignees.length}),
                  icon: Icons.person_add_alt_1_outlined,
                  variant: WeCordButtonVariant.secondary,
                  expand: true,
                  onPressed: members.isEmpty
                      ? null
                      : () async {
                          final picked = await showAssigneePicker(
                            context,
                            members: members,
                            selected: _assignees,
                          );
                          if (picked != null) {
                            setState(() => _assignees = picked);
                          }
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  label: _due == null
                      ? tr('Due date')
                      : formatDue(context, _due!, hasTime: _dueHasTime),
                  icon: Icons.event_outlined,
                  variant: WeCordButtonVariant.secondary,
                  expand: true,
                  onPressed: () async {
                    final picked = await showTaskDueSheet(
                      context,
                      initial: _due,
                      hasTime: _dueHasTime,
                    );
                    if (picked != null) {
                      setState(() {
                        _due = picked.due;
                        _dueHasTime = picked.hasTime;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          WeCordButton(
            label: tr('Create task'),
            expand: true,
            size: WeCordButtonSize.large,
            loading: _saving,
            onPressed: _create,
          ),
        ],
      ),
    );
  }
}
