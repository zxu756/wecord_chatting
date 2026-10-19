import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_patch_store.dart';
import 'package:wecord/shared/models/fractional_key.dart';

/// Which items a list shows.
enum TaskFilter {
  all,

  /// Assigned to the current user.
  mine,

  /// Not done and past their date.
  overdue,

  /// Not done.
  open,
}

enum TaskSort { manual, dueDate, priority, newest }

/// A list's items on this device: shown at once when changed, sent to the
/// server in the background, kept and retried while offline.
///
/// Every change is a patch of a few fields of one item ([patchItem]); the
/// server applies a patch field by field, so two people changing different
/// fields never overwrite each other. While patches are waiting, changes
/// that arrive from the server are shown with the waiting patches on top,
/// so a local drag or edit is not undone by a late echo.
///
/// With a [store] the waiting patches are also kept on the device (and the
/// items made here and not stored yet with them), so they survive closing
/// the app: [load] puts a stored [TaskListDraft] back on top of the server's
/// state, the same way, and sends it. A patch the server refuses is dropped
/// for good; one it could not be asked about stays stored.
class TaskListController extends ChangeNotifier {
  TaskListController({
    required this.repository,
    required this.currentUserId,
    required this.newId,
    this.store,
    DateTime Function()? clock,
    this.retryAfter = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now;

  final ListsRepository repository;
  final String? currentUserId;
  final String Function() newId;
  final Duration retryAfter;
  final DateTime Function() _clock;

  /// Where waiting patches are kept across restarts; null keeps them in
  /// memory only.
  final TaskPatchStore? store;

  /// The lists with a controller on screen, so the background retry
  /// ([TaskPatchSync]) leaves their patches to it.
  static final _open = <String, int>{};
  static bool isListOpen(String listId) => (_open[listId] ?? 0) > 0;
  String? _openListId;

  /// Writes to [store] one after another, in the order they were asked for.
  Future<void> _writes = Future<void>.value();

  TaskList? _list;
  final _items = <String, TaskItem>{};

  /// Patches waiting to be sent, by item. A new item's first patch holds
  /// its title.
  final _pending = <String, Map<String, Object?>>{};
  final _creating = <String>{};
  var _sending = false;
  var _offline = false;
  Timer? _retry;
  Timer? _flushTimer;
  var _disposed = false;

  TaskFilter filter = TaskFilter.all;
  TaskSort sort = TaskSort.manual;

  /// The last error the server gave for a change, for a message.
  Object? lastError;

  TaskList? get list => _list;
  bool get isOffline => _offline;
  bool get hasPending => _pending.isNotEmpty;

  /// All items that are not deleted.
  List<TaskItem> get items => [
    for (final item in _items.values)
      if (!item.deleted) item,
  ];

  TaskItem? itemById(String id) {
    final item = _items[id];
    return item == null || item.deleted ? null : item;
  }

  /// Takes the list as the server has it. Patches kept in [draft] (from a
  /// previous run) are put back first, so they show on top of the server's
  /// state and are sent like any others.
  void load(TaskSnapshot snapshot, {TaskListDraft? draft}) {
    _list = snapshot.list;
    if (_openListId != snapshot.list.id) {
      _forgetOpen();
      _openListId = snapshot.list.id;
      _open[_openListId!] = (_open[_openListId!] ?? 0) + 1;
    }
    final fresh = <String, TaskItem>{
      for (final item in snapshot.items) item.id: item,
    };
    if (draft != null) {
      _restore(draft, fresh);
    }
    // Items made here and not stored yet stay.
    for (final id in _creating) {
      final local = _items[id];
      if (local != null && !fresh.containsKey(id)) {
        fresh[id] = local;
      }
    }
    _items
      ..clear()
      ..addAll({
        for (final entry in fresh.entries) entry.key: _overlay(entry.value),
      });
    notifyListeners();
    if (draft != null && _pending.isNotEmpty) {
      _scheduleFlush();
    }
  }

  /// Puts the patches of [draft] back: on the server's items when they are
  /// still there, and as new items when they were made here and never
  /// stored. A patch for an item that is gone is dropped.
  void _restore(TaskListDraft draft, Map<String, TaskItem> fresh) {
    var dropped = false;
    for (final entry in draft.patches.entries) {
      final id = entry.key;
      final known = fresh[id];
      if (known == null) {
        final createdAt = draft.created[id];
        if (createdAt == null) {
          dropped = true;
          continue;
        }
        fresh[id] = _restoredItem(id, entry.value, createdAt);
        _creating.add(id);
      } else if (known.deleted) {
        dropped = true;
        continue;
      }
      _pending[id] = mergeTaskPatch(entry.value, _pending[id] ?? const {});
    }
    if (dropped) {
      _persist();
    }
  }

  /// An item made on this device and not stored yet, from its first patch.
  TaskItem _restoredItem(
    String id,
    Map<String, Object?> patch,
    DateTime createdAt,
  ) {
    final list = _list!;
    return TaskItem(
      id: id,
      listId: list.id,
      title: '${patch['title'] ?? ''}',
      status: '${patch['status'] ?? list.statuses.first.id}',
      pos: '${patch['pos'] ?? 'V'}',
      createdBy: currentUserId,
      createdAt: createdAt,
    );
  }

  void setFilter(TaskFilter value) {
    filter = value;
    notifyListeners();
  }

  void setSort(TaskSort value) {
    sort = value;
    notifyListeners();
  }

  void updateList(TaskList list) {
    _list = list;
    notifyListeners();
  }

  // -------------------------------------------------------------- views --

  bool _matches(TaskItem item) {
    return switch (filter) {
      TaskFilter.all => true,
      TaskFilter.mine => item.isAssignedTo(currentUserId),
      TaskFilter.overdue => item.isOverdue(_clock()),
      TaskFilter.open => !item.isDone,
    };
  }

  int _compare(TaskItem a, TaskItem b) {
    int byManual() {
      final byPos = a.pos.compareTo(b.pos);
      return byPos != 0 ? byPos : a.id.compareTo(b.id);
    }

    switch (sort) {
      case TaskSort.manual:
        return byManual();
      case TaskSort.dueDate:
        final left = a.dueAt;
        final right = b.dueAt;
        if (left == null && right == null) {
          return byManual();
        }
        if (left == null) {
          return 1;
        }
        if (right == null) {
          return -1;
        }
        final byDue = left.compareTo(right);
        return byDue != 0 ? byDue : byManual();
      case TaskSort.priority:
        final byPriority = b.priority.value.compareTo(a.priority.value);
        return byPriority != 0 ? byPriority : byManual();
      case TaskSort.newest:
        final left = a.createdAt;
        final right = b.createdAt;
        if (left != null && right != null) {
          final byDate = right.compareTo(left);
          if (byDate != 0) {
            return byDate;
          }
        }
        return byManual();
    }
  }

  /// The items of a status after the filter and sort ([manualOrder]: in
  /// the order they were put in, as boards show them).
  List<TaskItem> itemsIn(String statusId, {bool manualOrder = false}) {
    final sorted = [
      for (final item in items)
        if (item.status == statusId && _matches(item)) item,
    ];
    if (manualOrder) {
      return sorted..sort((a, b) {
        final byPos = a.pos.compareTo(b.pos);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
    }
    return sorted..sort(_compare);
  }

  /// Whether [item] is shown as a subtask under a task of this list (its
  /// task may have been deleted meanwhile; then it stands on its own).
  bool isNested(TaskItem item) {
    final parent = item.parentId;
    return parent != null && itemById(parent) != null;
  }

  /// The subtasks of [parentId], in the order they were put in.
  List<TaskItem> subtasksOf(String parentId) {
    return [
      for (final item in items)
        if (item.parentId == parentId) item,
    ]..sort((a, b) {
      final byPos = a.pos.compareTo(b.pos);
      return byPos != 0 ? byPos : a.id.compareTo(b.id);
    });
  }

  /// How many of [parentId]'s subtasks are done, and how many there are.
  ({int done, int total}) subtaskProgress(String parentId) {
    final subtasks = subtasksOf(parentId);
    return (
      done: subtasks.where((item) => item.isDone).length,
      total: subtasks.length,
    );
  }

  /// The subtasks of [parentId] the filter shows: all of them when the task
  /// itself matches, else the ones that do.
  List<TaskItem> visibleSubtasks(TaskItem parent) {
    final subtasks = subtasksOf(parent.id);
    if (filter == TaskFilter.all || _matches(parent)) {
      return subtasks;
    }
    return [
      for (final item in subtasks)
        if (_matches(item)) item,
    ];
  }

  /// The tasks of a status that stand on their own (not subtasks), after
  /// the filter and sort: those that match, and those with a subtask that
  /// does. For the list and the board, which show subtasks under their task.
  List<TaskItem> rootsIn(String statusId, {bool manualOrder = false}) {
    final sorted = [
      for (final item in items)
        if (item.status == statusId &&
            !isNested(item) &&
            (_matches(item) ||
                subtasksOf(item.id).any((child) => _matches(child))))
          item,
    ];
    if (manualOrder) {
      return sorted..sort((a, b) {
        final byPos = a.pos.compareTo(b.pos);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
    }
    return sorted..sort(_compare);
  }

  /// The tasks with a date on [day] (local), after the filter, by time.
  List<TaskItem> itemsDueOn(DateTime day) {
    return [
      for (final item in items)
        if (_matches(item) &&
            item.dueAt != null &&
            item.dueAt!.year == day.year &&
            item.dueAt!.month == day.month &&
            item.dueAt!.day == day.day)
          item,
    ]..sort(_compare);
  }

  /// The tasks with a date, by local day: for the dots of the calendar.
  Map<DateTime, List<TaskItem>> dueByDay() {
    final byDay = <DateTime, List<TaskItem>>{};
    for (final item in items) {
      final due = item.dueAt;
      if (due == null || !_matches(item)) {
        continue;
      }
      byDay
          .putIfAbsent(DateTime(due.year, due.month, due.day), () => [])
          .add(item);
    }
    return byDay;
  }

  /// The tasks without a date, after the filter.
  List<TaskItem> get undated => [
    for (final item in items)
      if (item.dueAt == null && _matches(item)) item,
  ]..sort(_compare);

  /// How many items a filter would show, for the chips.
  int count(TaskFilter which) {
    final saved = filter;
    filter = which;
    final total = items.where(_matches).length;
    filter = saved;
    return total;
  }

  // ------------------------------------------------------------ changes --

  /// Adds an item to the end of [statusId] (the first status by default).
  TaskItem createItem(
    String title, {
    String? statusId,
    List<String> assignees = const [],
    DateTime? dueAt,
    bool dueHasTime = false,
    TaskPriority priority = TaskPriority.none,
    String? details,
    String? parentId,
    TaskRecurrence? recurrence,
  }) {
    final list = _list!;
    final status = statusId ?? list.statuses.first.id;
    final column =
        items
            .where((item) => item.status == status && item.parentId == parentId)
            .toList()
          ..sort((a, b) => a.pos.compareTo(b.pos));
    final item = TaskItem(
      id: newId(),
      listId: list.id,
      title: title.trim(),
      status: status,
      details: details ?? '',
      priority: priority,
      dueAt: dueAt,
      dueHasTime: dueHasTime,
      pos: keyBetween(column.isEmpty ? null : column.last.pos, null),
      createdBy: currentUserId,
      createdAt: _clock(),
      assignees: assignees,
      parentId: parentId,
      recurrence: dueAt == null || parentId != null ? null : recurrence,
    );
    _items[item.id] = item;
    _creating.add(item.id);
    _pending[item.id] = {
      'title': item.title,
      'status': status,
      'pos': item.pos,
      if (assignees.isNotEmpty) 'assignees': assignees,
      if (dueAt != null) ...{
        'due_at': dueAt.toUtc().toIso8601String(),
        'due_has_time': dueHasTime,
      },
      if (priority != TaskPriority.none) 'priority': priority.value,
      if (details != null && details.isNotEmpty) 'details': details,
      'parent_id': ?parentId,
      'recurrence': ?item.recurrence?.toJson(),
    };
    _persist();
    notifyListeners();
    _scheduleFlush();
    return item;
  }

  /// Changes some fields of an item: `title`, `details`, `status`,
  /// `priority`, `due_at` (a UTC ISO string or null), `due_has_time`, `pos`,
  /// `assignees` (user ids), `custom` (the list's own fields: `{field id:
  /// value}`, null clears one value), `parent_id` (null makes it a task
  /// again) and `recurrence` (a repeat rule's JSON, or null).
  void patchItem(String id, Map<String, Object?> fields) {
    final item = _items[id];
    if (item == null || fields.isEmpty) {
      return;
    }
    _items[id] = _apply(item, fields);
    _pending[id] = mergeTaskPatch(_pending[id], fields);
    _persist();
    notifyListeners();
    _scheduleFlush();
  }

  /// Checks an item off, or back on.
  void setDone(String id, bool done) {
    final list = _list;
    final item = _items[id];
    if (list == null || item == null) {
      return;
    }
    final target = done ? list.doneStatus : list.todoStatus;
    if (target == null || target.id == item.status) {
      return;
    }
    final column = items.where((other) => other.status == target.id).toList()
      ..sort((a, b) => a.pos.compareTo(b.pos));
    patchItem(id, {
      'status': target.id,
      'pos': keyBetween(column.isEmpty ? null : column.last.pos, null),
    });
  }

  /// Puts an item at [index] among the items of [statusId] (as drawn, with
  /// the item itself taken out first). Moves between columns and within
  /// one; the other columns' items keep their order.
  void moveItem(String id, String statusId, int index) {
    final item = _items[id];
    if (item == null) {
      return;
    }
    // A task moves among tasks, a subtask among subtasks.
    final nested = isNested(item);
    final column =
        [
          for (final other in items)
            if (other.status == statusId &&
                other.id != id &&
                isNested(other) == nested)
              other,
        ]..sort((a, b) {
          final byPos = a.pos.compareTo(b.pos);
          return byPos != 0 ? byPos : a.id.compareTo(b.id);
        });
    final at = index.clamp(0, column.length);
    var before = at > 0 ? column[at - 1].pos : null;
    var after = at < column.length ? column[at].pos : null;
    if (before != null && after != null && before.compareTo(after) >= 0) {
      after = null;
    }
    if (before != null && before.length > 40) {
      // Gaps split too often: renumber the column, then place the item.
      final keys = keysBetween(null, null, column.length);
      for (var i = 0; i < column.length; i++) {
        patchItem(column[i].id, {'pos': keys[i]});
      }
      before = at > 0 ? keys[at - 1] : null;
      after = at < column.length ? keys[at] : null;
    }
    final fields = <String, Object?>{
      if (item.status != statusId) 'status': statusId,
      'pos': keyBetween(before, after),
    };
    patchItem(id, fields);
  }

  void deleteItem(String id) {
    final item = _items[id];
    if (item == null) {
      return;
    }
    _items[id] = item.copyWith(deleted: true);
    _pending.remove(id);
    final wasCreating = _creating.remove(id);
    _persist();
    notifyListeners();
    if (wasCreating) {
      return;
    }
    unawaited(() async {
      try {
        await repository.deleteItem(id);
      } on Object catch (error) {
        lastError = error;
        _items[id] = item;
        if (!_disposed) {
          notifyListeners();
        }
      }
    }());
  }

  // ------------------------------------------------------------- remote --

  /// An item row changed on the server (assignees are not part of it).
  void receiveItem(TaskItem remote) {
    final known = _items[remote.id];
    final merged = remote.copyWith(assignees: known?.assignees);
    _items[remote.id] = _overlay(merged);
    notifyListeners();
  }

  /// Takes the full list again (settings or assignees changed).
  void refresh(TaskSnapshot snapshot) => load(snapshot);

  // ------------------------------------------------------------ sending --

  TaskItem _overlay(TaskItem item) {
    final fields = _pending[item.id];
    return fields == null ? item : _apply(item, fields);
  }

  TaskItem _apply(TaskItem item, Map<String, Object?> fields) {
    final list = _list;
    var next = item;
    for (final entry in fields.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'title':
          next = next.copyWith(title: '$value');
        case 'details':
          next = next.copyWith(details: '$value');
        case 'status':
          final kind = list?.statusById('$value')?.kind;
          next = next.copyWith(
            status: '$value',
            completedAt: kind == TaskStatusKind.done
                ? (next.completedAt ?? _clock())
                : null,
          );
        case 'priority':
          next = next.copyWith(priority: TaskPriority.fromValue(value));
        case 'due_at':
          next = next.copyWith(
            dueAt: value == null ? null : DateTime.parse('$value').toLocal(),
          );
        case 'due_has_time':
          next = next.copyWith(dueHasTime: value == true);
        case 'pos':
          next = next.copyWith(pos: '$value');
        case 'assignees':
          next = next.copyWith(
            assignees: [for (final id in value! as List) '$id'],
          );
        case 'custom':
          final merged = {...next.custom};
          for (final field in (value! as Map).entries) {
            if (field.value == null) {
              merged.remove('${field.key}');
            } else {
              merged['${field.key}'] = field.value;
            }
          }
          next = next.copyWith(custom: merged);
        case 'parent_id':
          next = next.copyWith(parentId: value, recurrence: null);
        case 'recurrence':
          next = next.copyWith(
            recurrence: next.parentId != null
                ? null
                : value is TaskRecurrence
                ? value
                : TaskRecurrence.tryFromJson(value),
          );
      }
    }
    return next;
  }

  /// Sends the waiting patches, one item after another. A failure because
  /// the connection is gone keeps them for later; a refusal drops that
  /// item's patch and goes back to the server's version.
  Future<void> flush() async {
    _flushTimer?.cancel();
    if (_sending) {
      return;
    }
    _sending = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final id = _pending.keys.first;
        final fields = {...?_pending[id], 'id': id};
        if (fields['custom'] is Map) {
          fields['custom'] = {...fields['custom']! as Map};
        }
        final list = _list;
        if (list == null) {
          break;
        }
        try {
          final saved = await repository.upsertItem(list.id, fields);
          _offline = false;
          _creating.remove(id);
          // Fields changed while this was in flight stay waiting.
          final current = _pending[id];
          if (current != null) {
            removeSentFromTaskPatch(current, fields);
            if (current.isEmpty) {
              _pending.remove(id);
            }
          }
          _items[id] = _overlay(saved);
          if (fields.containsKey('assignees') &&
              (fields['assignees']! as List).isNotEmpty) {
            unawaited(repository.notifyAssignments(id));
          }
        } on Object catch (error) {
          if (_isRefusal(error)) {
            lastError = error;
            _pending.remove(id);
            _creating.remove(id);
            _items.remove(id);
            // Fetch the server's version again.
            unawaited(_reload());
          } else {
            _offline = true;
            _scheduleRetry();
            break;
          }
        }
        _persist();
        if (!_disposed) {
          notifyListeners();
        }
      }
    } finally {
      _sending = false;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _isRefusal(Object error) => isTaskPatchRefusal(error);

  /// Keeps the waiting patches on the device (or forgets them when none
  /// are left).
  void _persist() {
    final store = this.store;
    final userId = currentUserId;
    final list = _list;
    if (store == null || userId == null || list == null) {
      return;
    }
    final draft = TaskListDraft(
      userId: userId,
      listId: list.id,
      patches: {
        for (final entry in _pending.entries) entry.key: {...entry.value},
      },
      created: {
        for (final id in _creating)
          if (_pending.containsKey(id)) id: _items[id]?.createdAt ?? _clock(),
      },
    );
    _writes = _writes.then((_) => store.save(draft)).catchError((Object _) {});
  }

  void _forgetOpen() {
    final id = _openListId;
    if (id == null) {
      return;
    }
    final count = (_open[id] ?? 1) - 1;
    if (count <= 0) {
      _open.remove(id);
    } else {
      _open[id] = count;
    }
    _openListId = null;
  }

  Future<void> _reload() async {
    final list = _list;
    if (list == null) {
      return;
    }
    try {
      load(await repository.getList(list.id));
    } on Object {
      // Offline; the next refresh will do.
    }
  }

  /// Patches made in quick succession (typing, a drag and a drop) go out
  /// together.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(
      const Duration(milliseconds: 40),
      () => unawaited(flush()),
    );
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(retryAfter, () => unawaited(flush()));
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _flushTimer?.cancel();
    _forgetOpen();
    // Changes still waiting get one last try. What cannot be sent stays in
    // the store, for the next time the list is opened or the background
    // retry.
    final list = _list;
    if (list != null && _pending.isNotEmpty) {
      final leftovers = {
        for (final entry in _pending.entries)
          entry.key: {...entry.value, 'id': entry.key},
      };
      unawaited(() async {
        for (final entry in leftovers.entries) {
          try {
            await repository.upsertItem(list.id, entry.value);
            _pending.remove(entry.key);
            _creating.remove(entry.key);
            _persist();
          } on Object catch (error) {
            if (_isRefusal(error)) {
              _pending.remove(entry.key);
              _creating.remove(entry.key);
              _persist();
            }
            // Otherwise offline: kept in the store.
          }
        }
      }());
    }
    super.dispose();
  }
}

/// [older] with [newer] on top, field by field. The list's own fields
/// (`custom`) merge value by value, so two changes to different fields made
/// before the first was sent both go out.
Map<String, Object?> mergeTaskPatch(
  Map<String, Object?>? older,
  Map<String, Object?> newer,
) {
  final merged = {...?older, ...newer};
  final before = older?['custom'];
  final after = newer['custom'];
  if (before is Map && after is Map) {
    merged['custom'] = <String, Object?>{
      for (final entry in before.entries) '${entry.key}': entry.value,
      for (final entry in after.entries) '${entry.key}': entry.value,
    };
  }
  return merged;
}

bool _sameValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return mapEquals(a, b);
  }
  if (a is List && b is List) {
    return listEquals(a, b);
  }
  return a == b;
}

/// Takes out of [pending] what was sent in [sent] and has not been changed
/// since (a field changed while the request was on its way stays).
void removeSentFromTaskPatch(
  Map<String, Object?> pending,
  Map<String, Object?> sent,
) {
  for (final key in sent.keys) {
    if (key == 'custom' && pending['custom'] is Map && sent['custom'] is Map) {
      final waiting = pending['custom']! as Map;
      for (final entry in (sent['custom']! as Map).entries.toList()) {
        if (waiting.containsKey(entry.key) &&
            _sameValue(waiting[entry.key], entry.value)) {
          waiting.remove(entry.key);
        }
      }
      if (waiting.isEmpty) {
        pending.remove('custom');
      }
    } else if (_sameValue(pending[key], sent[key])) {
      pending.remove(key);
    }
  }
}

/// Whether [error] is the server refusing a change (not allowed, not valid,
/// item gone) rather than the connection failing. PostgREST errors carry the
/// SQLSTATE; connection problems do not.
bool isTaskPatchRefusal(Object error) {
  final text = '$error';
  return text.contains('42501') ||
      text.contains('22023') ||
      text.contains('P0002');
}
