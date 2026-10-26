import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/whiteboard/whiteboard_merge.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';

/// Sends changes to the server.
abstract interface class WhiteboardRemote {
  /// whiteboard_apply_ops: results come back in the order of [ops].
  Future<List<WhiteboardOpResult>> applyOps(
    String boardId,
    List<Map<String, Object?>> ops,
  );
}

/// How the local copy relates to the server.
enum WhiteboardSyncStatus {
  /// Everything drawn is stored.
  saved,

  /// Changes are on their way.
  saving,

  /// The server could not be reached; changes are kept here and sent when
  /// it can.
  offline,
}

/// The unsent changes of a board, kept on this device so they survive
/// closing the app: the elements that differ from the server's, as the
/// server last had them ([base]) and as they are now ([local]). Opening the
/// board again merges the server's newer state into them the same way live
/// changes are merged.
@immutable
class WhiteboardDraft {
  const WhiteboardDraft({
    required this.boardId,
    required this.base,
    required this.local,
  });

  factory WhiteboardDraft.fromJson(Map<String, dynamic> json) {
    List<WhiteboardElement> elements(String key) => [
      for (final element in (json[key] as List<dynamic>? ?? const []))
        WhiteboardElement.fromJson(Map<String, dynamic>.from(element as Map)),
    ];
    return WhiteboardDraft(
      boardId: json['board_id'] as String,
      base: elements('base'),
      local: elements('local'),
    );
  }

  final String boardId;
  final List<WhiteboardElement> base;
  final List<WhiteboardElement> local;

  bool get isEmpty => local.isEmpty;

  Map<String, Object?> toJson() => {
    'board_id': boardId,
    'base': [for (final element in base) element.toJson()],
    'local': [for (final element in local) element.toJson()],
  };
}

/// Where unsent changes are kept; tests use memory.
abstract interface class WhiteboardDraftStore {
  Future<WhiteboardDraft?> load(String boardId);
  Future<void> save(WhiteboardDraft draft);
  Future<void> clear(String boardId);
}

class SharedPreferencesWhiteboardDraftStore implements WhiteboardDraftStore {
  const SharedPreferencesWhiteboardDraftStore();

  static String _key(String boardId) => 'wecord.whiteboard.draft.$boardId';

  @override
  Future<WhiteboardDraft?> load(String boardId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(boardId));
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? WhiteboardDraft.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(WhiteboardDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(draft.boardId),
      jsonEncode(draft.toJson()),
    );
  }

  @override
  Future<void> clear(String boardId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(boardId));
  }
}

class InMemoryWhiteboardDraftStore implements WhiteboardDraftStore {
  final drafts = <String, WhiteboardDraft>{};

  @override
  Future<WhiteboardDraft?> load(String boardId) async => drafts[boardId];

  @override
  Future<void> save(WhiteboardDraft draft) async => drafts[draft.boardId] = draft;

  @override
  Future<void> clear(String boardId) async => drafts.remove(boardId);
}

/// The local copy of one board and how it stays in step with the server.
///
/// People draw on [local]; [base] is what the server is known to have. An
/// element whose local content differs from its base is dirty, and [flush]
/// sends it as a put based on the revision of its base (or a delete). If the
/// server's element moved on, it answers with a conflict carrying the
/// current element; so does a change that arrives by realtime. Either way
/// [receiveRemote] merges: key by key (see whiteboard_merge.dart), and the
/// result is sent again on the new revision. Elements only changed on one
/// side just take the change. A rub-out beats an edit; "undo" of a rub-out
/// is sent as a revive on the revision of the tombstone. Changes made
/// offline simply stay dirty until [flush] gets through, and [toDraft] keeps
/// them across restarts.
class WhiteboardSyncEngine extends ChangeNotifier {
  WhiteboardSyncEngine({
    required this.boardId,
    required this.remote,
    this.maxAttempts = 8,
  });

  final String boardId;
  final WhiteboardRemote remote;

  /// Rounds of send and merge one [flush] makes at most.
  final int maxAttempts;

  final _base = <String, WhiteboardElement>{};
  final _local = <String, WhiteboardElement>{};

  /// Elements being sent, as sent: a realtime copy of the same content is the
  /// acknowledgement, not somebody else's change.
  final _inflight = <String, WhiteboardElement>{};

  var _status = WhiteboardSyncStatus.saved;
  var _flushing = false;
  var _flushAgain = false;
  var _disposed = false;
  var _version = 0;
  List<WhiteboardElement>? _ordered;

  /// Set when the server refused a change (for example a board that is full);
  /// the local element went back to the server's.
  String? lastRejection;

  WhiteboardSyncStatus get status => _status;

  /// Goes up with every change to what is on the board, for caches.
  int get version => _version;

  /// Live elements in drawing order.
  List<WhiteboardElement> get elements {
    return _ordered ??= (<WhiteboardElement>[
      for (final element in _local.values)
        if (!element.deleted) element,
    ]..sort(compareElements));
  }

  int get liveCount => elements.length;

  WhiteboardElement? elementById(String id) {
    final element = _local[id];
    return element == null || element.deleted ? null : element;
  }

  /// What the server is known to have of an element (for tests and merges).
  WhiteboardElement? baseOf(String id) => _base[id];

  /// How many elements have changes the server has not confirmed.
  int get pendingCount => _dirtyIds().length;

  bool get hasPendingChanges => pendingCount > 0;

  /// The approximate size of everything on the board.
  int get approximateSize {
    var size = 0;
    for (final element in elements) {
      size += element.approximateSize;
    }
    return size;
  }

  // ------------------------------------------------------------- loading --

  /// Takes the elements the server sent when the board was opened. Unsent
  /// changes kept in [draft] are put back and merged with the server's state
  /// like any other remote change.
  void load(WhiteboardSnapshot snapshot, {WhiteboardDraft? draft}) {
    _base.clear();
    _local.clear();
    _inflight.clear();
    for (final element in snapshot.elements) {
      _base[element.id] = element;
      _local[element.id] = element;
    }
    if (draft != null) {
      final draftBase = {for (final e in draft.base) e.id: e};
      for (final mine in draft.local) {
        final theirs = _base[mine.id];
        final known = draftBase[mine.id];
        if (theirs == null) {
          // The server has nothing of it: new here, or rubbed out there.
          if (known == null || known.rev == 0) {
            _local[mine.id] = mine;
          } else if (!mine.deleted && known.deleted) {
            // An undo that never got through: bring it back.
            _base[mine.id] = known;
            _local[mine.id] = mine;
          }
        } else if (known != null && known.rev == theirs.rev) {
          _local[mine.id] = mine;
        } else if (mine.deleted) {
          _local[mine.id] = mine;
        } else {
          _local[mine.id] = mergeElements(
            base: known,
            mine: mine,
            theirs: theirs,
          );
        }
      }
    }
    _changed(notify: false);
    _refreshStatus();
    notifyListeners();
  }

  /// The changes to keep across a restart: only the elements that differ
  /// from the server's.
  WhiteboardDraft toDraft() {
    final ids = _dirtyIds();
    return WhiteboardDraft(
      boardId: boardId,
      base: [
        for (final id in ids)
          if (_base[id] != null) _base[id]!,
      ],
      local: [for (final id in ids) _local[id]!],
    );
  }

  // ------------------------------------------------------- local changes --

  /// Puts [element] on the board, new or in place of the one with its id.
  void upsert(WhiteboardElement element) {
    final current = _local[element.id];
    if (current != null && !current.deleted && current.sameContent(element)) {
      return;
    }
    _local[element.id] = element.copyWith(
      rev: current?.rev ?? _base[element.id]?.rev ?? element.rev,
      deleted: false,
    );
    _changed();
  }

  /// Puts several at once (one change for listeners).
  void upsertAll(Iterable<WhiteboardElement> elements) {
    var changed = false;
    for (final element in elements) {
      final current = _local[element.id];
      if (current != null && !current.deleted && current.sameContent(element)) {
        continue;
      }
      _local[element.id] = element.copyWith(
        rev: current?.rev ?? _base[element.id]?.rev ?? element.rev,
        deleted: false,
      );
      changed = true;
    }
    if (changed) {
      _changed();
    }
  }

  /// Rubs [id] out.
  void remove(String id) {
    final element = _local[id];
    if (element == null || element.deleted) {
      return;
    }
    final base = _base[id];
    if (base == null || base.rev == 0) {
      // Never stored: nothing to tell the server.
      _local.remove(id);
    } else {
      _local[id] = element.copyWith(deleted: true);
    }
    _changed();
  }

  void removeAll(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      final element = _local[id];
      if (element == null || element.deleted) {
        continue;
      }
      final base = _base[id];
      if (base == null || base.rev == 0) {
        _local.remove(id);
      } else {
        _local[id] = element.copyWith(deleted: true);
      }
      changed = true;
    }
    if (changed) {
      _changed();
    }
  }

  void _changed({bool notify = true}) {
    _ordered = null;
    _version++;
    if (!notify) {
      return;
    }
    _refreshStatus();
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _refreshStatus() {
    if (!hasPendingChanges) {
      _status = WhiteboardSyncStatus.saved;
    } else if (_status == WhiteboardSyncStatus.saved) {
      _status = WhiteboardSyncStatus.saving;
    }
  }

  // ------------------------------------------------------ remote changes --

  /// Takes an element as the server has it (from realtime, a conflict answer
  /// or a fresh load) and merges it with local changes to the same element.
  void receiveRemote(WhiteboardElement theirs, {bool notify = true}) {
    final prior = _base[theirs.id];
    if (prior != null && theirs.rev <= prior.rev) {
      return;
    }
    // Our own change coming back before the answer does.
    final sent = _inflight[theirs.id];
    if (sent != null &&
        !sent.deleted &&
        !theirs.deleted &&
        sent.sameContent(theirs)) {
      _base[theirs.id] = sent.copyWith(rev: theirs.rev);
      _inflight.remove(theirs.id);
      if (notify) {
        _changed();
      }
      return;
    }
    final mine = _local[theirs.id];
    _base[theirs.id] = theirs;
    final dirty =
        mine != null &&
        (prior == null ? !mine.deleted : !mine.sameContent(prior));
    if (!dirty) {
      _local[theirs.id] = theirs;
    } else if (theirs.deleted) {
      if (prior != null && prior.deleted && !mine.deleted) {
        // An undo of a rub-out, meeting a newer rub-out: it was meant to
        // bring the element back, so it is sent again on the new revision.
        _local[theirs.id] = mine;
      } else {
        // Changed here, rubbed out there: the eraser wins.
        _local[theirs.id] = theirs;
      }
    } else if (mine.deleted) {
      // Rubbed out here, changed there: the rub-out stands (it is sent next).
      _local[theirs.id] = mine;
    } else if (prior == null) {
      // Made here, and the server has a copy (an earlier send whose answer
      // was lost): the newer content is sent over it.
      _local[theirs.id] = mine;
    } else if (prior.deleted) {
      // We held it rubbed out and somebody brought it back meanwhile.
      _local[theirs.id] = theirs;
    } else {
      _local[theirs.id] = mergeElements(base: prior, mine: mine, theirs: theirs);
    }
    if (notify) {
      _changed();
    } else {
      _ordered = null;
      _version++;
    }
  }

  // --------------------------------------------------------------- sending --

  Set<String> _dirtyIds() {
    final ids = <String>{};
    for (final entry in _local.entries) {
      final local = entry.value;
      final base = _base[entry.key];
      if (local.deleted) {
        if (base != null && !base.deleted && base.rev > 0) {
          ids.add(entry.key);
        }
      } else if (base == null ||
          base.rev == 0 ||
          base.deleted ||
          !local.sameContent(base)) {
        ids.add(entry.key);
      }
    }
    return ids;
  }

  /// Sends what the server does not have yet and merges what it answers,
  /// until nothing is left to send or [maxAttempts] rounds passed. Returns
  /// false when the server could not be reached (the changes stay queued).
  Future<bool> flush() async {
    if (_flushing) {
      _flushAgain = true;
      return true;
    }
    _flushing = true;
    try {
      var attempts = 0;
      do {
        _flushAgain = false;
        final ids = _dirtyIds().toList()..sort();
        if (ids.isEmpty) {
          break;
        }
        for (var i = 0; i < ids.length; i += WhiteboardLimits.opsPerCall) {
          final end = i + WhiteboardLimits.opsPerCall > ids.length
              ? ids.length
              : i + WhiteboardLimits.opsPerCall;
          final chunk = ids.sublist(i, end);
          final sentElements = <String, WhiteboardElement>{};
          final ops = <Map<String, Object?>>[];
          for (final id in chunk) {
            final local = _local[id]!;
            final base = _base[id];
            if (local.deleted) {
              ops.add({'op': 'del', 'id': id});
            } else {
              ops.add(
                local.toPutOp(
                  base == null || base.rev == 0 ? null : base.rev,
                  revive: base?.deleted ?? false,
                ),
              );
              sentElements[id] = local;
              _inflight[id] = local;
            }
          }
          _status = WhiteboardSyncStatus.saving;
          if (!_disposed) {
            notifyListeners();
          }
          final List<WhiteboardOpResult> results;
          try {
            results = await remote.applyOps(boardId, ops);
          } on Object {
            _inflight.clear();
            _status = WhiteboardSyncStatus.offline;
            if (!_disposed) {
              notifyListeners();
            }
            return false;
          }
          for (var j = 0; j < chunk.length && j < results.length; j++) {
            _handleResult(chunk[j], results[j], sentElements[chunk[j]]);
          }
          for (final id in chunk) {
            _inflight.remove(id);
          }
          _ordered = null;
          _version++;
        }
        attempts++;
      } while ((_flushAgain || hasPendingChanges) && attempts < maxAttempts);
      _status = hasPendingChanges
          ? WhiteboardSyncStatus.saving
          : WhiteboardSyncStatus.saved;
      if (!_disposed) {
        notifyListeners();
      }
      return true;
    } finally {
      _flushing = false;
    }
  }

  void _handleResult(
    String id,
    WhiteboardOpResult result,
    WhiteboardElement? sent,
  ) {
    if (result.isOk) {
      final base = _base[id];
      if (sent == null) {
        // A delete went through.
        final known = base ?? _local[id];
        if (known != null) {
          _base[id] = known.copyWith(
            deleted: true,
            rev: result.rev ?? known.rev + 1,
          );
        }
        return;
      }
      final rev = result.rev ?? ((base?.rev ?? 0) + 1);
      if (base == null || base.rev < rev || base.deleted) {
        _base[id] = sent.copyWith(rev: rev, deleted: false);
      }
    } else if (result.isConflict && result.element != null) {
      receiveRemote(result.element!, notify: false);
    } else {
      // Refused: go back to what the server has.
      lastRejection = result.reason ?? 'rejected';
      final base = _base[id];
      if (base == null || base.rev == 0) {
        _local.remove(id);
        _base.remove(id);
      } else {
        _local[id] = base;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
