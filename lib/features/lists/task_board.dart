import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/task_list_controller.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a dragged card carries.
class TaskDragData {
  const TaskDragData(this.itemId, this.fromStatus);

  final String itemId;
  final String fromStatus;
}

/// The index at which a card dragged to [pointerY] (global) would be put
/// among cards whose vertical centres are [centers] (in order, the dragged
/// card left out).
int boardInsertIndex(List<double> centers, double pointerY) {
  for (var i = 0; i < centers.length; i++) {
    if (pointerY < centers[i]) {
      return i;
    }
  }
  return centers.length;
}

/// A kanban board: one column per status, cards you drag between and within
/// columns. Dragging near an edge scrolls the board, or the column. The
/// same moves are offered as "Move to…" for screen readers and keyboards.
class TaskBoardView extends StatefulWidget {
  const TaskBoardView({
    required this.controller,
    required this.members,
    required this.onOpen,
    required this.onAdd,
    this.canEdit = true,
    super.key,
  });

  final TaskListController controller;
  final List<GroupMember> members;
  final void Function(TaskItem item) onOpen;

  /// Adds a task with [title] to a column.
  final void Function(String statusId, String title) onAdd;
  final bool canEdit;

  @override
  State<TaskBoardView> createState() => _TaskBoardViewState();
}

class _TaskBoardViewState extends State<TaskBoardView> {
  final _horizontal = ScrollController();
  final _boardKey = GlobalKey();
  final _columnScrollers =
      <String, ({ScrollController controller, GlobalKey key})>{};
  Timer? _autoScroll;
  Offset? _point;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _horizontal.dispose();
    for (final entry in _columnScrollers.values) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  ({ScrollController controller, GlobalKey key}) _scrollerFor(String statusId) {
    return _columnScrollers.putIfAbsent(
      statusId,
      () => (controller: ScrollController(), key: GlobalKey()),
    );
  }

  void _dragMoved(Offset globalPoint) {
    _point = globalPoint;
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickAutoScroll(),
    );
  }

  void stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _point = null;
  }

  void _tickAutoScroll() {
    final point = _point;
    final box = _boardKey.currentContext?.findRenderObject();
    if (point == null || box is! RenderBox || !box.hasSize) {
      return;
    }
    const edge = 56.0;
    const step = 14.0;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (_horizontal.hasClients) {
      if (point.dx < rect.left + edge) {
        _horizontal.jumpTo(
          (_horizontal.offset - step).clamp(
            0.0,
            _horizontal.position.maxScrollExtent,
          ),
        );
      } else if (point.dx > rect.right - edge) {
        _horizontal.jumpTo(
          (_horizontal.offset + step).clamp(
            0.0,
            _horizontal.position.maxScrollExtent,
          ),
        );
      }
    }
    for (final entry in _columnScrollers.values) {
      final columnBox = entry.key.currentContext?.findRenderObject();
      if (columnBox is! RenderBox ||
          !columnBox.hasSize ||
          !entry.controller.hasClients) {
        continue;
      }
      final columnRect = columnBox.localToGlobal(Offset.zero) & columnBox.size;
      if (!columnRect.contains(point)) {
        continue;
      }
      final position = entry.controller.position;
      if (point.dy < columnRect.top + edge) {
        entry.controller.jumpTo(
          (position.pixels - step).clamp(0.0, position.maxScrollExtent),
        );
      } else if (point.dy > columnRect.bottom - edge) {
        entry.controller.jumpTo(
          (position.pixels + step).clamp(0.0, position.maxScrollExtent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.controller.list;
    if (list == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth =
            isWideLayout(MediaQuery.sizeOf(context).width) ||
                constraints.maxWidth > 600
            ? 288.0
            : (constraints.maxWidth * 0.8).clamp(240.0, 320.0);
        return ListView.separated(
          key: _boardKey,
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: list.statuses.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final status = list.statuses[index];
            final scroller = _scrollerFor(status.id);
            return SizedBox(
              width: columnWidth,
              child: _BoardColumn(
                key: ValueKey('board-column-${status.id}'),
                status: status,
                statuses: list.statuses,
                controller: widget.controller,
                members: widget.members,
                scroller: scroller.controller,
                columnKey: scroller.key,
                cardWidth: columnWidth - 24,
                canEdit: widget.canEdit,
                onOpen: widget.onOpen,
                onAdd: (title) => widget.onAdd(status.id, title),
                onDragMoved: _dragMoved,
                onDragEnded: stopAutoScroll,
              ),
            );
          },
        );
      },
    );
  }
}

class _BoardColumn extends StatefulWidget {
  const _BoardColumn({
    required this.status,
    required this.statuses,
    required this.controller,
    required this.members,
    required this.scroller,
    required this.columnKey,
    required this.cardWidth,
    required this.canEdit,
    required this.onOpen,
    required this.onAdd,
    required this.onDragMoved,
    required this.onDragEnded,
    super.key,
  });

  final TaskStatus status;
  final List<TaskStatus> statuses;
  final TaskListController controller;
  final List<GroupMember> members;
  final ScrollController scroller;
  final GlobalKey columnKey;
  final double cardWidth;
  final bool canEdit;
  final void Function(TaskItem item) onOpen;
  final void Function(String title) onAdd;
  final void Function(Offset globalPoint) onDragMoved;
  final VoidCallback onDragEnded;

  @override
  State<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends State<_BoardColumn> {
  final _cardKeys = <String, GlobalKey>{};
  int? _hoverIndex;
  String? _draggingId;
  var _adding = false;
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  List<TaskItem> _cards() =>
      widget.controller.itemsIn(widget.status.id, manualOrder: true);

  int _indexFor(Offset point, List<TaskItem> cards) {
    final centers = <double>[];
    for (final card in cards) {
      if (card.id == _draggingId) {
        continue;
      }
      final box = _cardKeys[card.id]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        centers.add(box.localToGlobal(Offset(0, box.size.height / 2)).dy);
      }
    }
    return boardInsertIndex(centers, point.dy);
  }

  void _submitAdd() {
    final title = _addController.text.trim();
    if (title.isNotEmpty) {
      widget.onAdd(title);
    }
    _addController.clear();
    // Stay in the field for the next one.
    _addFocus.requestFocus();
  }

  Color _dot(WeCordPalette c) => switch (widget.status.kind) {
    TaskStatusKind.todo => c.faint,
    TaskStatusKind.active => c.accent,
    TaskStatusKind.done => c.success,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final cards = _cards();
    final touch = usesTouchInput(context);
    final shownCount = cards.where((card) => card.id != _draggingId).length;

    final children = <Widget>[];
    var position = 0;
    for (final item in cards) {
      final dragging = item.id == _draggingId;
      if (!dragging && _hoverIndex == position) {
        children.add(const _InsertMarker());
      }
      if (!dragging) {
        position++;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _DraggableCard(
            key: _cardKeys.putIfAbsent(item.id, GlobalKey.new),
            item: item,
            statuses: widget.statuses,
            members: widget.members,
            width: widget.cardWidth,
            canEdit: widget.canEdit,
            touch: touch,
            onOpen: () => widget.onOpen(item),
            onToggleDone: () =>
                widget.controller.setDone(item.id, !item.isDone),
            onMoveTo: (statusId) => widget.controller.moveItem(
              item.id,
              statusId,
              widget.controller.itemsIn(statusId, manualOrder: true).length,
            ),
            onDragStarted: () => setState(() => _draggingId = item.id),
            onDragEnd: () {
              widget.onDragEnded();
              if (mounted) {
                setState(() {
                  _draggingId = null;
                  _hoverIndex = null;
                });
              }
            },
          ),
        ),
      );
    }
    if (_hoverIndex != null && _hoverIndex! >= shownCount) {
      children.add(const _InsertMarker());
    }

    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (details) => widget.canEdit,
      onMove: (details) {
        widget.onDragMoved(details.offset + const Offset(24, 24));
        final index = _indexFor(details.offset + const Offset(24, 24), cards);
        if (index != _hoverIndex) {
          setState(() => _hoverIndex = index);
        }
      },
      onLeave: (_) => setState(() => _hoverIndex = null),
      onAcceptWithDetails: (details) {
        final index = _hoverIndex ?? shownCount;
        setState(() => _hoverIndex = null);
        widget.controller.moveItem(
          details.data.itemId,
          widget.status.id,
          index,
        );
      },
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          key: widget.columnKey,
          duration: WeCordMotion.quick,
          decoration: BoxDecoration(
            color: highlighted ? c.accentSoft : c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
            border: Border.all(
              color: highlighted ? c.accent : c.lineSoft,
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                child: Semantics(
                  header: true,
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _dot(c),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${cards.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.subtle,
                        ),
                      ),
                      const Spacer(),
                      if (widget.canEdit)
                        WeCordIconButton(
                          icon: Icons.add_rounded,
                          iconSize: 20,
                          size: 32,
                          tooltip: tr('Add a task to {status}', {
                            'status': widget.status.label,
                          }),
                          variant: WeCordButtonVariant.ghost,
                          onPressed: () {
                            setState(() => _adding = true);
                            _addFocus.requestFocus();
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: widget.scroller,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    ...children,
                    if (cards.isEmpty && !_adding && _hoverIndex == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          widget.canEdit
                              ? tr('Drop tasks here')
                              : tr('Nothing here'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: c.subtle),
                        ),
                      ),
                    if (_adding && widget.canEdit)
                      TextField(
                        controller: _addController,
                        focusNode: _addFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: 14.5, color: c.ink),
                        decoration: InputDecoration(
                          hintText: tr('Task title'),
                          filled: true,
                          fillColor: c.panel,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: WeCordFieldBorder(
                            borderRadius: BorderRadius.circular(WeCordRadii.lg),
                          ),
                        ),
                        onSubmitted: (_) => _submitAdd(),
                        onTapOutside: (_) {
                          if (_addController.text.trim().isEmpty) {
                            setState(() => _adding = false);
                          }
                        },
                      ),
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

class _InsertMarker extends StatelessWidget {
  const _InsertMarker();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      height: 4,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _DraggableCard extends StatelessWidget {
  const _DraggableCard({
    required this.item,
    required this.statuses,
    required this.members,
    required this.width,
    required this.canEdit,
    required this.touch,
    required this.onOpen,
    required this.onToggleDone,
    required this.onMoveTo,
    required this.onDragStarted,
    required this.onDragEnd,
    super.key,
  });

  final TaskItem item;
  final List<TaskStatus> statuses;
  final List<GroupMember> members;
  final double width;
  final bool canEdit;
  final bool touch;
  final VoidCallback onOpen;
  final VoidCallback onToggleDone;
  final void Function(String statusId) onMoveTo;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final card = TaskCard(
      item: item,
      members: members,
      canEdit: canEdit,
      onOpen: onOpen,
      onToggleDone: onToggleDone,
    );
    // For screen readers: moves as actions, since dragging is not possible.
    final actions = <CustomSemanticsAction, VoidCallback>{
      if (canEdit)
        for (final status in statuses)
          if (status.id != item.status)
            CustomSemanticsAction(
              label: tr('Move to {status}', {'status': status.label}),
            ): () =>
                onMoveTo(status.id),
    };
    final semantic = Semantics(customSemanticsActions: actions, child: card);
    if (!canEdit) {
      return semantic;
    }
    final feedback = SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Transform.rotate(
          angle: 0.02,
          child: TaskCard(
            item: item,
            members: members,
            lifted: true,
            onOpen: null,
            onToggleDone: null,
          ),
        ),
      ),
    );
    final ghost = Opacity(opacity: 0.35, child: card);
    if (touch) {
      return LongPressDraggable<TaskDragData>(
        data: TaskDragData(item.id, item.status),
        feedback: feedback,
        childWhenDragging: ghost,
        delay: const Duration(milliseconds: 220),
        hapticFeedbackOnStart: true,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd(),
        onDraggableCanceled: (velocity, offset) => onDragEnd(),
        child: semantic,
      );
    }
    return Draggable<TaskDragData>(
      data: TaskDragData(item.id, item.status),
      feedback: feedback,
      childWhenDragging: ghost,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (velocity, offset) => onDragEnd(),
      child: semantic,
    );
  }
}
