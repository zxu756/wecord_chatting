import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_list_page.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_page.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A conversation's notes and lists: the list of both with a switch between
/// them, and the note or list that is open. It is the right-hand panel on
/// desktop ([pageMode] false) and the body of the full page otherwise.
class WorkspacePanel extends ConsumerStatefulWidget {
  const WorkspacePanel({
    required this.conversationId,
    this.title,
    this.initialTab = WorkspaceTab.notes,
    this.initialNoteId,
    this.initialListId,
    this.initialItemId,
    this.onClose,
    this.onOpenPage,
    this.pageMode = false,
    super.key,
  });

  final String conversationId;

  /// The conversation's name, for the header.
  final String? title;
  final WorkspaceTab initialTab;
  final String? initialNoteId;
  final String? initialListId;
  final String? initialItemId;

  /// Closes the panel (the X), or leaves the page (the back button).
  final VoidCallback? onClose;

  /// Opens the same view as a page.
  final VoidCallback? onOpenPage;
  final bool pageMode;

  @override
  ConsumerState<WorkspacePanel> createState() => WorkspacePanelState();
}

class WorkspacePanelState extends ConsumerState<WorkspacePanel> {
  late WorkspaceTab _tab = widget.initialTab;
  String? _noteId;
  String? _listId;
  String? _itemId;
  NoteMeta? _noteSeed;
  var _autofocusNote = false;
  var _creating = false;

  @override
  void initState() {
    super.initState();
    _noteId = widget.initialNoteId;
    _listId = widget.initialListId;
    _itemId = widget.initialItemId;
    if (_noteId != null) {
      _tab = WorkspaceTab.notes;
    } else if (_listId != null) {
      _tab = WorkspaceTab.lists;
    }
  }

  /// Opens what a request asks for (a note, a list, a task).
  void show(WorkspaceRequest request) {
    setState(() {
      _tab = request.tab;
      _noteId = request.noteId;
      _listId = request.listId;
      _itemId = request.itemId;
      _noteSeed = null;
      _autofocusNote = false;
    });
  }

  void _closeItem() {
    setState(() {
      _noteId = null;
      _listId = null;
      _itemId = null;
      _noteSeed = null;
    });
  }

  Future<void> _createNote() async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      final meta = await ref
          .read(notesRepositoryProvider)
          .createNote(widget.conversationId, id: newClientId());
      ref.invalidate(notesListProvider(widget.conversationId));
      if (mounted) {
        setState(() {
          _noteId = meta.id;
          _noteSeed = meta;
          _autofocusNote = true;
        });
      }
    } on Object {
      _toast(tr('Could not create the note.'));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _createList() async {
    final created = await showNewListSheet(context);
    if (created == null || !mounted) {
      return;
    }
    setState(() => _creating = true);
    try {
      final list = await ref
          .read(listsRepositoryProvider)
          .createList(
            widget.conversationId,
            title: created.title,
            icon: created.icon,
            id: newClientId(),
            view: created.view,
          );
      ref.invalidate(taskListsProvider(widget.conversationId));
      if (mounted) {
        setState(() {
          _listId = list.id;
          _itemId = null;
        });
      }
    } on Object {
      _toast(tr('Could not create the list.'));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteId = _noteId;
    if (noteId != null) {
      return NotePage(
        key: ValueKey('note-$noteId'),
        noteId: noteId,
        conversationId: widget.conversationId,
        seed: _noteSeed,
        embedded: !widget.pageMode,
        autofocus: _autofocusNote,
        onBack: _closeItem,
      );
    }
    final listId = _listId;
    if (listId != null) {
      return TaskListPage(
        key: ValueKey('list-$listId'),
        listId: listId,
        conversationId: widget.conversationId,
        initialItemId: _itemId,
        embedded: !widget.pageMode,
        onBack: _closeItem,
      );
    }
    return _buildIndex(context);
  }

  Widget _buildIndex(BuildContext context) {
    final c = context.tokens.colors;
    final workspace = ref.watch(
      conversationWorkspaceProvider(widget.conversationId),
    );
    final canCreate = workspace.value?.canCreate ?? true;
    final notes = ref.watch(notesListProvider(widget.conversationId));
    final lists = ref.watch(taskListsProvider(widget.conversationId));
    final isNotes = _tab == WorkspaceTab.notes;

    final header = widget.pageMode
        ? Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 4),
            child: Row(
              children: [
                if (widget.onClose != null)
                  WeCordIconButton(
                    icon: Icons.chevron_left_rounded,
                    iconSize: 24,
                    size: 42,
                    tooltip: tr('Back'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: widget.onClose,
                  ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('Notes and lists'),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : Container(
            height: 58,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.lineSoft)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      tr('Notes and lists'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
                if (widget.onOpenPage != null)
                  WeCordIconButton(
                    icon: Icons.open_in_full_rounded,
                    iconSize: 17,
                    size: 36,
                    tooltip: tr('Open as a page'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: widget.onOpenPage,
                  ),
                if (widget.onClose != null)
                  WeCordIconButton(
                    icon: Icons.close_rounded,
                    iconSize: 19,
                    size: 36,
                    tooltip: tr('Close'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          );

    final createLabel = isNotes ? tr('New note') : tr('New list');
    return Material(
      color: widget.pageMode ? c.panel : c.sidebar,
      child: SafeArea(
        top: widget.pageMode,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: WeCordSegmented<WorkspaceTab>(
                      key: const ValueKey('workspace-tabs'),
                      expand: true,
                      semanticLabel: tr('Notes or lists'),
                      selected: _tab,
                      onChanged: (tab) => setState(() => _tab = tab),
                      segments: [
                        WeCordSegment(
                          value: WorkspaceTab.notes,
                          label: tr('Notes'),
                          icon: Icons.description_outlined,
                          key: const ValueKey('workspace-tab-notes'),
                        ),
                        WeCordSegment(
                          value: WorkspaceTab.lists,
                          label: tr('Lists'),
                          icon: Icons.checklist_rounded,
                          key: const ValueKey('workspace-tab-lists'),
                        ),
                      ],
                    ),
                  ),
                  if (canCreate) ...[
                    const SizedBox(width: 10),
                    WeCordIconButton(
                      key: const ValueKey('workspace-create'),
                      icon: Icons.add_rounded,
                      tooltip: createLabel,
                      variant: WeCordButtonVariant.accent,
                      onPressed: _creating
                          ? null
                          : () => unawaited(
                              isNotes ? _createNote() : _createList(),
                            ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: isNotes
                  ? _NotesIndex(
                      notes: notes,
                      canCreate: canCreate,
                      onCreate: () => unawaited(_createNote()),
                      onRetry: () => ref.invalidate(
                        notesListProvider(widget.conversationId),
                      ),
                      onOpen: (note) => setState(() {
                        _noteId = note.id;
                        _noteSeed = null;
                        _autofocusNote = false;
                      }),
                    )
                  : _ListsIndex(
                      lists: lists,
                      canCreate: canCreate,
                      onCreate: () => unawaited(_createList()),
                      onRetry: () => ref.invalidate(
                        taskListsProvider(widget.conversationId),
                      ),
                      onOpen: (list) => setState(() {
                        _listId = list.id;
                        _itemId = null;
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The emoji square in front of a note or list.
class EmojiTile extends StatelessWidget {
  const EmojiTile({required this.emoji, this.size = 44, super.key});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}

class _IndexRow extends StatelessWidget {
  const _IndexRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.semanticLabel,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      semanticLabel: semanticLabel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      pressedScale: 0.99,
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.panel
              : Colors.transparent,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          boxShadow: states.contains(WidgetState.hovered)
              ? context.tokens.shadows.hairline
              : null,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _EmptyIndex extends StatelessWidget {
  const _EmptyIndex({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.faint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              WeCordButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotesIndex extends StatelessWidget {
  const _NotesIndex({
    required this.notes,
    required this.canCreate,
    required this.onCreate,
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<NoteSummary>> notes;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onRetry;
  final void Function(NoteSummary note) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return notes.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      error: (error, stackTrace) => _EmptyIndex(
        icon: Icons.cloud_off_rounded,
        title: tr('Could not load the notes'),
        message: tr('Check your connection and try again.'),
        actionLabel: tr('Try again'),
        onAction: onRetry,
      ),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyIndex(
            icon: Icons.description_outlined,
            title: tr('No notes yet'),
            message: canCreate
                ? tr(
                    'Write things down together: plans, meeting notes, checklists. Everyone here can read them, and anyone who can chat can edit.',
                  )
                : tr('Nobody has written a note here yet.'),
            actionLabel: canCreate ? tr('Create the first note') : null,
            onAction: onCreate,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final note = items[index];
            final title = note.title.isEmpty ? tr('Untitled') : note.title;
            final edited = note.updatedByName == null
                ? ''
                : tr('Edited by {name}', {'name': note.updatedByName});
            return _IndexRow(
              key: ValueKey('note-row-${note.id}'),
              leading: EmojiTile(emoji: note.icon),
              title: title,
              subtitle: note.preview.isNotEmpty ? note.preview : edited,
              semanticLabel: [
                title,
                if (note.pinned) tr('Pinned'),
                if (note.managersOnly) tr('Only managers can edit'),
                if (note.preview.isNotEmpty) note.preview,
              ].join(', '),
              onTap: () => onOpen(note),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (note.managersOnly)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: c.faint,
                      ),
                    ),
                  if (note.pinned)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: c.accent,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ListsIndex extends StatelessWidget {
  const _ListsIndex({
    required this.lists,
    required this.canCreate,
    required this.onCreate,
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<TaskListSummary>> lists;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onRetry;
  final void Function(TaskListSummary list) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return lists.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      error: (error, stackTrace) => _EmptyIndex(
        icon: Icons.cloud_off_rounded,
        title: tr('Could not load the lists'),
        message: tr('Check your connection and try again.'),
        actionLabel: tr('Try again'),
        onAction: onRetry,
      ),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyIndex(
            icon: Icons.checklist_rounded,
            title: tr('No lists yet'),
            message: canCreate
                ? tr(
                    'Keep track of who does what: give tasks an owner and a date, and move them across a board.',
                  )
                : tr('Nobody has made a list here yet.'),
            actionLabel: canCreate ? tr('Create the first list') : null,
            onAction: onCreate,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final list = items[index];
            final title = list.title.isEmpty ? tr('Untitled list') : list.title;
            final parts = [
              tr('{count} open', {'count': list.openCount}),
              if (list.doneCount > 0)
                tr('{count} done', {'count': list.doneCount}),
              if (list.mineCount > 0)
                tr('{count} yours', {'count': list.mineCount}),
            ];
            return _IndexRow(
              key: ValueKey('list-row-${list.id}'),
              leading: EmojiTile(emoji: list.icon),
              title: title,
              subtitle: parts.join(' · '),
              semanticLabel: [
                title,
                ...parts,
                if (list.overdueCount > 0)
                  tr('{count} overdue', {'count': list.overdueCount}),
              ].join(', '),
              onTap: () => onOpen(list),
              trailing: list.overdueCount > 0
                  ? CountBadge(
                      count: list.overdueCount,
                      tone: BadgeTone.mention,
                    )
                  : Icon(
                      list.defaultView == TaskListView.board
                          ? Icons.view_kanban_outlined
                          : Icons.view_list_rounded,
                      size: 18,
                      color: c.faint,
                    ),
            );
          },
        );
      },
    );
  }
}

/// Asks for the name, icon and view of a new list.
Future<({String title, String icon, TaskListView view})?> showNewListSheet(
  BuildContext context,
) {
  return showWeCordSheet<({String title, String icon, TaskListView view})>(
    context,
    title: tr('New list'),
    builder: (context, _) => const _NewListSheet(),
  );
}

class _NewListSheet extends StatefulWidget {
  const _NewListSheet();

  @override
  State<_NewListSheet> createState() => _NewListSheetState();
}

class _NewListSheetState extends State<_NewListSheet> {
  final _title = TextEditingController();
  var _view = TaskListView.list;
  var _icon = TaskList.defaultIcon;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.of(
      context,
    ).pop((title: _title.text.trim(), icon: _icon, view: _view));
  }

  @override
  Widget build(BuildContext context) {
    const icons = [
      '✅',
      '\u{1F4CC}',
      '\u{1F680}',
      '\u{1F4C5}',
      '\u{1F6D2}',
      '\u{1F3AF}',
      '\u{1F4A1}',
      '\u{1F41B}',
    ];
    final c = context.tokens.colors;
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
            label: tr('Name'),
            hint: tr('Launch checklist'),
            autofocus: true,
            maxLength: 120,
            onSubmitted: (_) => _done(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in icons)
                WeCordPressable(
                  onPressed: () => setState(() => _icon = icon),
                  selected: _icon == icon,
                  semanticLabel: icon,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  builder: (context, states) => Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _icon == icon ? c.accentSoft : c.raised,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                      border: Border.all(
                        color: _icon == icon ? c.accent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(icon, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          WeCordSegmented<TaskListView>(
            expand: true,
            semanticLabel: tr('Opens as'),
            selected: _view,
            onChanged: (view) => setState(() => _view = view),
            segments: [
              WeCordSegment(
                value: TaskListView.list,
                label: tr('List'),
                icon: Icons.view_list_rounded,
              ),
              WeCordSegment(
                value: TaskListView.board,
                label: tr('Board'),
                icon: Icons.view_kanban_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          WeCordButton(
            label: tr('Create list'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: _done,
          ),
        ],
      ),
    );
  }
}
