import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

/// What one person's action did to one element: [before] is null when the
/// action made it, [after] is null when the action rubbed it out.
class ElementChange {
  const ElementChange({required this.id, this.before, this.after})
    : assert(before != null || after != null, 'a change needs a side');

  final String id;
  final WhiteboardElement? before;
  final WhiteboardElement? after;

  bool get isCreation => before == null;
  bool get isRemoval => after == null;
}

/// Undo and redo of the person's own actions only. Other people's changes
/// are never undone, and undoing an edit puts back only the keys that action
/// changed (so a color somebody else picked meanwhile stays). The stacks are
/// local and reset when the board is closed.
class WhiteboardHistory {
  WhiteboardHistory({this.limit = 100});

  final int limit;
  final _undo = <List<ElementChange>>[];
  final _redo = <List<ElementChange>>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  /// Notes one action (all its changes undo together). Changes that did
  /// nothing are dropped.
  void record(Iterable<ElementChange> changes) {
    final kept = [
      for (final change in changes)
        if (!_isNoop(change)) change,
    ];
    if (kept.isEmpty) {
      return;
    }
    _undo.add(kept);
    if (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  bool _isNoop(ElementChange change) {
    final before = change.before;
    final after = change.after;
    return before != null && after != null && before.sameContent(after);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  /// Takes back the last action on [engine]. Returns the ids it touched
  /// (empty when there was nothing to undo).
  List<String> undo(WhiteboardSyncEngine engine) {
    if (_undo.isEmpty) {
      return const [];
    }
    final action = _undo.removeLast();
    _redo.add(action);
    return _apply(engine, action, forward: false);
  }

  List<String> redo(WhiteboardSyncEngine engine) {
    if (_redo.isEmpty) {
      return const [];
    }
    final action = _redo.removeLast();
    _undo.add(action);
    return _apply(engine, action, forward: true);
  }

  List<String> _apply(
    WhiteboardSyncEngine engine,
    List<ElementChange> action, {
    required bool forward,
  }) {
    final touched = <String>[];
    final puts = <WhiteboardElement>[];
    final removes = <String>[];
    final ordered = forward ? action : action.reversed;
    for (final change in ordered) {
      final from = forward ? change.before : change.after;
      final to = forward ? change.after : change.before;
      if (to == null) {
        // Going back to "does not exist".
        removes.add(change.id);
        touched.add(change.id);
      } else if (from == null) {
        // Going back to "exists": put it as it was, whole.
        puts.add(to);
        touched.add(change.id);
      } else {
        final current = engine.elementById(change.id);
        if (current == null) {
          // Somebody rubbed it out since: leave it so.
          continue;
        }
        final patched = _patchKeys(current, from: from, to: to);
        if (patched != null) {
          puts.add(patched);
          touched.add(change.id);
        }
      }
    }
    engine
      ..removeAll(removes)
      ..upsertAll(puts);
    return touched;
  }

  /// [current] with the keys that differ between [from] and [to] set to
  /// [to]'s values; null when nothing needs to change.
  WhiteboardElement? _patchKeys(
    WhiteboardElement current, {
    required WhiteboardElement from,
    required WhiteboardElement to,
  }) {
    final changes = <String, Object?>{};
    final keys = {...from.data.keys, ...to.data.keys};
    for (final key in keys) {
      if (!deepEquals(from.data[key], to.data[key])) {
        changes[key] = to.data[key];
      }
    }
    final zChanged = from.z != to.z && current.z != to.z;
    if (changes.isEmpty && !zChanged) {
      return null;
    }
    final next = current.withData(changes, z: zChanged ? to.z : null);
    return next.sameContent(current) ? null : next;
  }
}
