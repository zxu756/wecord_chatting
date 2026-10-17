import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry, globalRectOf, showGlassMenu;
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_board.dart';
import 'package:wecord/features/lists/task_item_sheet.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_status_editor.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One task list: its tasks grouped by status (list view) or as columns
/// (board), with filters (all, mine, overdue, open), sorting, quick add, and
/// everything updating live as other people change it.
class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({
    required this.listId,
    required this.conversationId,
    this.initialItemId,
    this.onBack,
    this.embedded = false,
    this.onDeleted,
    super.key,
  });

  final String listId;
  final String conversationId;

  /// A task to open as soon as the list is loaded (from a notification).
  final String? initialItemId;
  final VoidCallback? onBack;
  final bool embedded;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  late final TaskListController _controller;
  StreamSubscription<TaskItem>? _items;
  StreamSubscription<void>? _structure;
  Timer? _refetch;
  TaskListView _view = TaskListView.list;
  var _loading = true;
  Object? _error;
  var _openedInitial = false;
  final _collapsed = <String>{};
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final repository = ref.read(listsRepositoryProvider);
    _controller = TaskListController(
      repository: repository,
      currentUserId: ref.read(authRepositoryProvider).currentUser?.id,
      newId: newClientId,
    )..addListener(_changed);
    unawaited(_load(first: true));
    _items = repository
        .itemChanges(widget.listId)
        .listen(_controller.receiveItem);
    _structure = repository.listStructureChanges(widget.listId).listen((_) {
      _refetch?.cancel();
      _refetch = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_load()),
      );
    });
  }

  Future<void> _load({bool first = false}) async {
    try {
      final snapshot = await ref
          .read(listsRepositoryProvider)
          .getList(widget.listId);
      if (!mounted) {
        return;
      }
      if (first) {
        _view = snapshot.list.defaultView;
      }
      _controller.load(snapshot);
      setState(() {
        _loading = false;
        _error = null;
      });
      _maybeOpenInitial();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _controller.list == null ? error : null;
        });
      }
    }
  }

  void _maybeOpenInitial() {
    final id = widget.initialItemId;
    if (_openedInitial || id == null || _controller.itemById(id) == null) {
      return;
    }
    _openedInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openItem(_controller.itemById(id)!));
      }
    });
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _refetch?.cancel();
    unawaited(_items?.cancel());
    unawaited(_structure?.cancel());
    _controller
      ..removeListener(_changed)
      ..dispose();
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _openItem(TaskItem item) {
    return showTaskItemSheet(
      context,
      controller: _controller,
      itemId: item.id,
      conversationId: widget.conversationId,
      members:
          ref.read(conversationMembersProvider(widget.conversationId)).value ??
          const [],
      canEdit: _controller.list?.canEdit ?? false,
    );
  }

  void _addTask(String title, {String? statusId}) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _controller.createItem(trimmed, statusId: statusId);
    ref.invalidate(taskListsProvider(widget.conversationId));
  }

  Future<void> _rename() async {
    final list = _controller.list;
    if (list == null) {
      return;
    }
    final result = await showRenameListDialog(
      context,
      title: list.title,
      icon: list.icon,
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      final updated = await ref
          .read(listsRepositoryProvider)
          .updateList(list.id, title: result.title, icon: result.icon);
      _controller.updateList(updated);
      ref.invalidate(taskListsProvider(widget.conversationId));
    } on Object {
      _toast(tr('Could not rename the list.'));
    }
  }

  Future<void> _editStatuses() async {
    final list = _controller.list;
    if (list == null) {
      return;
    }
    final edited = await showTaskStatusEditor(context, list.statuses);
    if (edited == null || !mounted) {
      return;
    }
    try {
      final updated = await ref
          .read(listsRepositoryProvider)
          .updateList(
            list.id,
            statuses: edited.statuses,
            statusMoves: edited.moves,
          );
      _controller.updateList(updated);
      await _load();
    } on Object {
      _toast(tr('Could not change the statuses.'));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this list?')),
        content: Text(tr('Its tasks are deleted for everyone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(listsRepositoryProvider).deleteList(widget.listId);
      ref.invalidate(taskListsProvider(widget.conversationId));
      if (mounted) {
        (widget.onDeleted ?? widget.onBack)?.call();
      }
    } on Object {
      _toast(tr('Could not delete the list.'));
    }
  }

  Future<void> _share() async {
    try {
      await ref
          .read(listsRepositoryProvider)
          .shareList(widget.listId, widget.conversationId);
      _toast(tr('Shared in the chat.'));
    } on Object {
      _toast(tr('Could not share the list.'));
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openMenu(BuildContext buttonContext) {
    final list = _controller.list;
    if (list == null) {
      return;
    }
    unawaited(
      showGlassMenu(
        buttonContext,
        anchor: globalRectOf(buttonContext),
        entries: [
          GlassMenuEntry(
            icon: Icons.ios_share_rounded,
            label: tr('Share in the chat'),
            onSelected: () => unawaited(_share()),
          ),
          if (list.canEdit)
            GlassMenuEntry(
              icon: Icons.edit_outlined,
              label: tr('Rename and change icon'),
              onSelected: () => unawaited(_rename()),
            ),
          if (list.canEdit)
            GlassMenuEntry(
              icon: Icons.view_column_outlined,
              label: tr('Edit statuses'),
              onSelected: () => unawaited(_editStatuses()),
            ),
          if (list.canManage)
            GlassMenuEntry(
              icon: Icons.delete_outline_rounded,
              label: tr('Delete list'),
              destructive: true,
              onSelected: () => unawaited(_delete()),
            ),
        ],
      ),
    );
  }

  void _openSortMenu(BuildContext buttonContext) {
    GlassMenuEntry entry(TaskSort sort, IconData icon, String label) {
      return GlassMenuEntry(
        icon: _controller.sort == sort ? Icons.check_rounded : icon,
        label: label,
        onSelected: () => _controller.setSort(sort),
      );
    }

    unawaited(
      showGlassMenu(
        buttonContext,
        anchor: globalRectOf(buttonContext),
        entries: [
          entry(TaskSort.manual, Icons.swap_vert_rounded, tr('Manual order')),
          entry(TaskSort.dueDate, Icons.event_outlined, tr('Due date')),
          entry(TaskSort.priority, Icons.flag_outlined, tr('Priority')),
          entry(TaskSort.newest, Icons.schedule_rounded, tr('Newest first')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final list = _controller.list;
    final members =
        ref.watch(conversationMembersProvider(widget.conversationId)).value ??
        const [];

    Widget body;
    if (_loading && list == null) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (list == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 36, color: c.faint),
              const SizedBox(height: 12),
              Text(
                _error == null
                    ? tr('This list is not available')
                    : tr('Could not open the list'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 12),
              WeCordButton(
                label: tr('Try again'),
                onPressed: () {
                  setState(() => _loading = true);
                  unawaited(_load());
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final canEdit = list.canEdit;
      body = Column(
        children: [
          _FilterBar(controller: _controller, onSort: _openSortMenu),
          if (_controller.isOffline)
            Container(
              key: const ValueKey('list-offline-banner'),
              width: double.infinity,
              color: c.warningSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                tr(
                  'You are offline. Changes are kept and sent when you are back.',
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.warningText,
                ),
              ),
            ),
          Expanded(
            child: _view == TaskListView.board
                ? TaskBoardView(
                    controller: _controller,
                    members: members,
                    canEdit: canEdit,
                    onOpen: (item) => unawaited(_openItem(item)),
                    onAdd: (statusId, title) =>
                        _addTask(title, statusId: statusId),
                  )
                : _GroupedListView(
                    controller: _controller,
                    members: members,
                    collapsed: _collapsed,
                    canEdit: canEdit,
                    onToggleSection: (id) => setState(() {
                      if (!_collapsed.remove(id)) {
                        _collapsed.add(id);
                      }
                    }),
                    onOpen: (item) => unawaited(_openItem(item)),
                  ),
          ),
          if (canEdit && _view == TaskListView.list)
            _AddBar(
              controller: _addController,
              focusNode: _addFocus,
              onSubmit: (title) {
                _addTask(title);
                _addController.clear();
                _addFocus.requestFocus();
              },
            ),
        ],
      );
    }

    final size = widget.embedded ? 36.0 : 40.0;
    return Scaffold(
      backgroundColor: c.panel,
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: EdgeInsets.fromLTRB(widget.embedded ? 8 : 6, 4, 8, 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  if (widget.onBack != null)
                    WeCordIconButton(
                      tooltip: widget.embedded
                          ? tr('Back to lists')
                          : tr('Back'),
                      icon: Icons.chevron_left_rounded,
                      iconSize: 24,
                      size: size,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: widget.onBack,
                    ),
                  if (list != null) ...[
                    Text(list.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        list == null
                            ? ''
                            : list.title.isEmpty
                            ? tr('Untitled list')
                            : list.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  if (list != null) ...[
                    WeCordIconButton(
                      key: const ValueKey('view-list'),
                      tooltip: tr('List view'),
                      icon: Icons.view_list_rounded,
                      iconSize: 21,
                      size: size,
                      variant: WeCordButtonVariant.ghost,
                      selected: _view == TaskListView.list,
                      onPressed: () =>
                          setState(() => _view = TaskListView.list),
                    ),
                    WeCordIconButton(
                      key: const ValueKey('view-board'),
                      tooltip: tr('Board view'),
                      icon: Icons.view_kanban_outlined,
                      iconSize: 21,
                      size: size,
                      variant: WeCordButtonVariant.ghost,
                      selected: _view == TaskListView.board,
                      onPressed: () =>
                          setState(() => _view = TaskListView.board),
                    ),
                    Builder(
                      builder: (buttonContext) => WeCordIconButton(
                        tooltip: tr('More'),
                        icon: Icons.more_horiz_rounded,
                        iconSize: 21,
                        size: size,
                        variant: WeCordButtonVariant.ghost,
                        onPressed: () => _openMenu(buttonContext),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller, required this.onSort});

  final TaskListController controller;
  final void Function(BuildContext buttonContext) onSort;

  @override
  Widget build(BuildContext context) {
    Widget chip(TaskFilter filter, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: WeCordChip(
          key: ValueKey('task-filter-${filter.name}'),
          label: label,
          count: filter == TaskFilter.all ? null : controller.count(filter),
          selected: controller.filter == filter,
          onPressed: () => controller.setFilter(filter),
        ),
      );
    }

    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              children: [
                chip(TaskFilter.all, tr('All')),
                chip(TaskFilter.mine, tr('Mine')),
                chip(TaskFilter.overdue, tr('Overdue')),
                chip(TaskFilter.open, tr('Open')),
              ],
            ),
          ),
          Builder(
            builder: (buttonContext) => WeCordIconButton(
              tooltip: tr('Sort'),
              icon: Icons.sort_rounded,
              size: 36,
              iconSize: 20,
              variant: WeCordButtonVariant.ghost,
              selected: controller.sort != TaskSort.manual,
              onPressed: () => onSort(buttonContext),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _GroupedListView extends StatelessWidget {
  const _GroupedListView({
    required this.controller,
    required this.members,
    required this.collapsed,
    required this.canEdit,
    required this.onToggleSection,
    required this.onOpen,
  });

  final TaskListController controller;
  final List<GroupMember> members;
  final Set<String> collapsed;
  final bool canEdit;
  final void Function(String statusId) onToggleSection;
  final void Function(TaskItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final list = controller.list!;
    final total = controller.items.length;
    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt_rounded, size: 40, color: c.faint),
              const SizedBox(height: 12),
              Text(
                tr('No tasks yet'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                canEdit
                    ? tr(
                        'Add the first one below. You can assign it, give it a date and drag it across the board.',
                      )
                    : tr('Nothing has been added to this list yet.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
              ),
            ],
          ),
        ),
      );
    }
    final sections = <Widget>[];
    for (final status in list.statuses) {
      final items = controller.itemsIn(status.id);
      final all = controller.items
          .where((item) => item.status == status.id)
          .length;
      if (items.isEmpty && controller.filter != TaskFilter.all) {
        continue;
      }
      final isCollapsed = collapsed.contains(status.id);
      sections.add(
        WeCordPressable(
          key: ValueKey('section-${status.id}'),
          onPressed: () => onToggleSection(status.id),
          toggled: !isCollapsed,
          semanticLabel: tr('{status}, {count} tasks', {
            'status': status.label,
            'count': items.length,
          }),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          pressedScale: 1,
          builder: (context, states) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Row(
              children: [
                Icon(
                  isCollapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: c.subtle,
                ),
                const SizedBox(width: 4),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: c.subtle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  controller.filter == TaskFilter.all
                      ? '$all'
                      : '${items.length}/$all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!isCollapsed) {
        for (final item in items) {
          sections.add(
            TaskRow(
              key: ValueKey('task-${item.id}'),
              item: item,
              members: members,
              canEdit: canEdit,
              onOpen: () => onOpen(item),
              onToggleDone: () => controller.setDone(item.id, !item.isDone),
            ),
          );
        }
        if (items.isEmpty) {
          sections.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 4, 12, 8),
              child: Text(
                tr('Nothing here'),
                style: TextStyle(fontSize: 13.5, color: c.subtle),
              ),
            ),
          );
        }
      }
    }
    if (sections.isEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr('No tasks match this filter.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: sections,
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String title) onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        10 + MediaQuery.paddingOf(context).bottom * 0,
      ),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('task-add-field'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15.5, color: c.ink),
              decoration: InputDecoration(
                hintText: tr('Add a task'),
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
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 8),
          WeCordIconButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: tr('Add task'),
            variant: WeCordButtonVariant.accent,
            onPressed: () => onSubmit(controller.text),
          ),
        ],
      ),
    );
  }
}

/// Asks for a list's name and icon.
Future<({String title, String icon})?> showRenameListDialog(
  BuildContext context, {
  required String title,
  required String icon,
}) {
  return showDialog<({String title, String icon})>(
    context: context,
    builder: (context) => _RenameListDialog(title: title, icon: icon),
  );
}

class _RenameListDialog extends StatefulWidget {
  const _RenameListDialog({required this.title, required this.icon});

  final String title;
  final String icon;

  @override
  State<_RenameListDialog> createState() => _RenameListDialogState();
}

class _RenameListDialogState extends State<_RenameListDialog> {
  late final _title = TextEditingController(text: widget.title);
  late String _icon = widget.icon;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AlertDialog(
      title: Text(tr('Rename list')),
      content: SizedBox(
        width: 380,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            WeCordPressable(
              onPressed: () async {
                final emoji = await showEmojiReactionPicker(
                  context,
                  title: tr('Choose an icon'),
                );
                if (emoji != null) {
                  setState(() => _icon = emoji);
                }
              },
              tooltip: tr('Change icon'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              builder: (context, states) => Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                child: Text(_icon, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WeCordTextField(
                controller: _title,
                label: tr('Name'),
                autofocus: true,
                maxLength: 120,
                onSubmitted: (_) => _done(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _done, child: Text(tr('Save'))),
      ],
    );
  }

  void _done() {
    Navigator.of(context).pop((title: _title.text.trim(), icon: _icon));
  }
}
