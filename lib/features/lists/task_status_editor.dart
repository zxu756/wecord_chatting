import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The result of editing statuses: the new list, and where the items of a
/// removed status go.
typedef StatusEdit = ({List<TaskStatus> statuses, Map<String, String> moves});

/// Edits a list's statuses (the columns of its board): rename, change what
/// each means (to do, active, done), reorder, add and remove. At least one
/// to-do and one done status are kept.
Future<StatusEdit?> showTaskStatusEditor(
  BuildContext context,
  List<TaskStatus> statuses,
) {
  return showWeCordSheet<StatusEdit>(
    context,
    title: tr('Statuses'),
    detents: const [0.6, 0.92],
    initialDetent: 0.8,
    builder: (context, scrollController) =>
        _StatusEditor(statuses: statuses, scrollController: scrollController),
  );
}

/// An id for a new status named [name] that is not in [taken].
String newStatusId(String name, Set<String> taken) {
  var base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) {
    base = 'status';
  }
  if (base.length > 24) {
    base = base.substring(0, 24);
  }
  var candidate = base;
  var n = 2;
  while (taken.contains(candidate)) {
    candidate = '$base-$n';
    n++;
  }
  return candidate;
}

/// Whether [statuses] can be saved: names filled in, at least one to-do and
/// one done status.
bool validStatuses(List<TaskStatus> statuses) {
  return statuses.isNotEmpty &&
      statuses.length <= 12 &&
      statuses.every((status) => status.name.trim().isNotEmpty) &&
      statuses.any((status) => status.kind == TaskStatusKind.todo) &&
      statuses.any((status) => status.kind == TaskStatusKind.done);
}

class _StatusEditor extends StatefulWidget {
  const _StatusEditor({required this.statuses, this.scrollController});

  final List<TaskStatus> statuses;
  final ScrollController? scrollController;

  @override
  State<_StatusEditor> createState() => _StatusEditorState();
}

class _StatusEditorState extends State<_StatusEditor> {
  late final List<TaskStatus> _statuses = [...widget.statuses];
  final _controllers = <String, TextEditingController>{};

  TextEditingController _controllerFor(TaskStatus status) {
    return _controllers.putIfAbsent(
      status.id,
      () => TextEditingController(text: status.label),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _rename(int index, String name) {
    setState(() {
      _statuses[index] = _statuses[index].copyWith(name: name);
    });
  }

  void _setKind(int index, TaskStatusKind kind) {
    setState(() => _statuses[index] = _statuses[index].copyWith(kind: kind));
  }

  void _move(int index, int by) {
    final target = index + by;
    if (target < 0 || target >= _statuses.length) {
      return;
    }
    setState(() {
      final status = _statuses.removeAt(index);
      _statuses.insert(target, status);
    });
  }

  void _add() {
    final id = newStatusId('status', {for (final s in _statuses) s.id});
    setState(() {
      _statuses.add(
        TaskStatus(id: id, name: tr('New status'), kind: TaskStatusKind.active),
      );
    });
  }

  void _remove(int index) {
    setState(() {
      final removed = _statuses.removeAt(index);
      _controllers.remove(removed.id)?.dispose();
    });
  }

  void _save() {
    // Items of a removed status go to the first status of the same kind.
    final kept = {for (final s in _statuses) s.id};
    final moves = <String, String>{};
    for (final old in widget.statuses) {
      if (kept.contains(old.id)) {
        continue;
      }
      final target =
          _statuses.where((s) => s.kind == old.kind).firstOrNull ??
          _statuses.first;
      moves[old.id] = target.id;
    }
    Navigator.of(context).pop((
      statuses: [
        for (final status in _statuses)
          status.copyWith(name: status.name.trim()),
      ],
      moves: moves,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final valid = validStatuses(_statuses);
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  tr(
                    'Each status is a column on the board. Mark which are not '
                    'started, in progress, or finished.',
                  ),
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
                ),
              ),
              for (final (index, status) in _statuses.indexed)
                Container(
                  key: ValueKey('status-${status.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: WeCordTextField(
                              controller: _controllerFor(status),
                              hint: tr('Status name'),
                              maxLength: 40,
                              onChanged: (value) => _rename(index, value),
                            ),
                          ),
                          WeCordIconButton(
                            icon: Icons.arrow_upward_rounded,
                            tooltip: tr('Move up'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: index > 0
                                ? () => _move(index, -1)
                                : null,
                          ),
                          WeCordIconButton(
                            icon: Icons.arrow_downward_rounded,
                            tooltip: tr('Move down'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: index < _statuses.length - 1
                                ? () => _move(index, 1)
                                : null,
                          ),
                          WeCordIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: tr('Remove status'),
                            size: 36,
                            variant: WeCordButtonVariant.ghost,
                            onPressed: _statuses.length > 1
                                ? () => _remove(index)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      WeCordSegmented<TaskStatusKind>(
                        expand: true,
                        height: 34,
                        semanticLabel: tr('What this status means'),
                        selected: status.kind,
                        onChanged: (kind) => _setKind(index, kind),
                        segments: [
                          WeCordSegment(
                            value: TaskStatusKind.todo,
                            label: tr('Not started'),
                          ),
                          WeCordSegment(
                            value: TaskStatusKind.active,
                            label: tr('In progress'),
                          ),
                          WeCordSegment(
                            value: TaskStatusKind.done,
                            label: tr('Finished'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_statuses.length < 12)
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    label: tr('Add a status'),
                    icon: Icons.add_rounded,
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _add,
                  ),
                ),
              if (!valid)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr(
                      'Keep a name on every status, and at least one "Not started" and one "Finished".',
                    ),
                    style: TextStyle(fontSize: 13, color: c.dangerText),
                  ),
                ),
            ],
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
            label: tr('Save'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: valid ? _save : null,
          ),
        ),
      ],
    );
  }
}
