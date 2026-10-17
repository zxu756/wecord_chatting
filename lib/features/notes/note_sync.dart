import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/models/fractional_key.dart';

/// Sends changes to the server.
abstract interface class NoteRemote {
  /// note_apply_ops: results come back in the order of [ops].
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  );
}

/// How the local copy relates to the server.
enum NoteSyncStatus {
  /// Everything typed is stored.
  saved,

  /// Changes are on their way.
  saving,

  /// The server could not be reached; changes are kept here and sent when
  /// it can.
  offline,
}

/// The unsent edits of a note, kept on this device so they survive closing
/// the app: the blocks as the server last had them ([base]) and as they are
/// now ([local]). Opening the note again merges the server's newer state
/// into them the same way live changes are merged.
@immutable
class NoteDraft {
  const NoteDraft({
    required this.noteId,
    required this.base,
    required this.local,
  });

  factory NoteDraft.fromJson(Map<String, dynamic> json) {
    List<NoteBlock> blocks(String key) => [
      for (final block in (json[key] as List<dynamic>? ?? const []))
        NoteBlock.fromJson(Map<String, dynamic>.from(block as Map)),
    ];
    return NoteDraft(
      noteId: json['note_id'] as String,
      base: blocks('base'),
      local: blocks('local'),
    );
  }

  final String noteId;
  final List<NoteBlock> base;
  final List<NoteBlock> local;

  Map<String, Object?> toJson() => {
    'note_id': noteId,
    'base': [for (final block in base) block.toJson()],
    'local': [for (final block in local) block.toJson()],
  };
}

/// Where unsent edits are kept; tests use memory.
abstract interface class NoteDraftStore {
  Future<NoteDraft?> load(String noteId);
  Future<void> save(NoteDraft draft);
  Future<void> clear(String noteId);
}

class SharedPreferencesNoteDraftStore implements NoteDraftStore {
  const SharedPreferencesNoteDraftStore();

  static String _key(String noteId) => 'wecord.notes.draft.$noteId';

  @override
  Future<NoteDraft?> load(String noteId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(noteId));
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? NoteDraft.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(NoteDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(draft.noteId), jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear(String noteId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(noteId));
  }
}

class InMemoryNoteDraftStore implements NoteDraftStore {
  final drafts = <String, NoteDraft>{};

  @override
  Future<NoteDraft?> load(String noteId) async => drafts[noteId];

  @override
  Future<void> save(NoteDraft draft) async => drafts[draft.noteId] = draft;

  @override
  Future<void> clear(String noteId) async => drafts.remove(noteId);
}

/// The local copy of one note and how it stays in step with the server.
///
/// People edit [local]; [base] is what the server is known to have. A block
/// whose local content differs from its base is dirty, and [flush] sends it
/// as a put based on the revision of its base. If the server's block moved
/// on, it answers with a conflict carrying the current block; so does a
/// change that arrives by realtime. Either way [receiveRemote] merges: the
/// block's text and formatting three-way (base, mine, theirs), the rest
/// field by field, and the result is sent again on the new revision. Blocks
/// that are only changed on one side just take the change. Edits made
/// offline simply stay dirty until [flush] gets through, and [toDraft] keeps
/// them across restarts.
class NoteSyncEngine extends ChangeNotifier {
  NoteSyncEngine({
    required this.noteId,
    required this.remote,
    required this.newId,
    this.maxAttempts = 8,
  });

  final String noteId;
  final NoteRemote remote;
  final String Function() newId;

  /// Rounds of send and merge one [flush] makes at most.
  final int maxAttempts;

  final _base = <String, NoteBlock>{};
  final _local = <String, NoteBlock>{};

  /// Blocks being sent, as sent: a realtime copy of the same content is the
  /// acknowledgement, not somebody else's change.
  final _inflight = <String, NoteBlock>{};

  var _status = NoteSyncStatus.saved;
  var _flushing = false;
  var _flushAgain = false;
  var _disposed = false;

  /// Set when the server refused a change (for example text over the
  /// limit); the local block went back to the server's.
  String? lastRejection;

  NoteSyncStatus get status => _status;

  /// Blocks in document order, without deleted ones.
  List<NoteBlock> get blocks {
    final result = [
      for (final block in _local.values)
        if (!block.deleted) block,
    ]..sort(compareBlocks);
    return result;
  }

  NoteBlock? blockById(String id) {
    final block = _local[id];
    return block == null || block.deleted ? null : block;
  }

  /// What the server is known to have of a block (for tests and merges).
  NoteBlock? baseOf(String id) => _base[id];

  /// How many blocks have changes the server has not confirmed.
  int get pendingCount => _dirtyIds().length;

  bool get hasPendingChanges => pendingCount > 0;

  // ------------------------------------------------------------- loading --

  /// Takes the blocks the server sent when the note was opened. Unsent
  /// edits kept in [draft] are put back first and then merged with the
  /// server's state like any other remote change.
  void load(NoteSnapshot snapshot, {NoteDraft? draft}) {
    _base.clear();
    _local.clear();
    _inflight.clear();
    if (draft != null) {
      for (final block in draft.base) {
        _base[block.id] = block;
      }
      for (final block in draft.local) {
        _local[block.id] = block;
      }
      final seen = <String>{};
      for (final block in snapshot.blocks) {
        seen.add(block.id);
        receiveRemote(block, notify: false);
      }
      // Blocks the draft knew that the server no longer has were deleted.
      for (final id in _base.keys.toList()) {
        final known = _base[id]!;
        if (!seen.contains(id) && !known.deleted) {
          receiveRemote(
            known.copyWith(deleted: true, rev: known.rev + 1),
            notify: false,
          );
        }
      }
    } else {
      for (final block in snapshot.blocks) {
        _base[block.id] = block;
        _local[block.id] = block;
      }
    }
    _ensureOneBlock();
    _refreshStatus();
    notifyListeners();
  }

  /// An empty note still has a block to type into.
  void _ensureOneBlock() {
    if (blocks.isEmpty) {
      final block = NoteBlock(id: newId(), pos: firstFractionalKey);
      _local[block.id] = block;
    }
  }

  NoteDraft toDraft() => NoteDraft(
    noteId: noteId,
    base: _base.values.toList(),
    local: _local.values.toList(),
  );

  // ------------------------------------------------------- local changes --

  /// Sets a block's content. Only the arguments given change.
  void updateBlock(
    String id, {
    String? text,
    List<NoteMark>? marks,
    NoteBlockKind? kind,
    Map<String, Object?>? props,
  }) {
    final block = blockById(id);
    if (block == null) {
      return;
    }
    final next = block.copyWith(
      text: text,
      marks: marks == null
          ? (text == null ? null : normalizeMarks(block.marks, text.length))
          : normalizeMarks(marks, (text ?? block.text).length),
      kind: kind,
      props: props,
    );
    if (next.sameContent(block)) {
      return;
    }
    _local[id] = next;
    _changed();
  }

  /// Keys get a character longer about every six inserts into the same gap;
  /// past this length all keys are renumbered (a rare change of every
  /// block's position).
  static const _maxKeyLength = 40;

  /// Gives every block a fresh, evenly spread key.
  void _rebalance() {
    final ordered = blocks;
    final keys = keysBetween(null, null, ordered.length);
    for (var i = 0; i < ordered.length; i++) {
      _local[ordered[i].id] = ordered[i].copyWith(pos: keys[i]);
    }
  }

  /// A key for a block going between [before] and [after]; renumbers the
  /// note first when the gap has been split too often.
  String _keyFor(String? afterId, {String? skipId}) {
    String? before;
    String? after;
    for (var attempt = 0; attempt < 2; attempt++) {
      final ordered = [
        for (final block in blocks)
          if (block.id != skipId) block,
      ];
      before = null;
      after = null;
      if (afterId == null) {
        after = ordered.isEmpty ? null : ordered.first.pos;
      } else {
        final index = ordered.indexWhere((block) => block.id == afterId);
        if (index >= 0) {
          before = ordered[index].pos;
          after = index + 1 < ordered.length ? ordered[index + 1].pos : null;
        } else {
          before = ordered.isEmpty ? null : ordered.last.pos;
        }
      }
      // Neighbours with equal keys (two people inserting at the same spot)
      // leave no room between them; go just after the first one.
      if (before != null && after != null && before.compareTo(after) >= 0) {
        after = null;
      }
      final key = keyBetween(before, after);
      if (key.length <= _maxKeyLength || attempt == 1) {
        return key;
      }
      _rebalance();
    }
    return keyBetween(before, after);
  }

  /// Adds a block after [afterId] (at the start when null) and returns it.
  NoteBlock insertBlock({
    String? afterId,
    NoteBlockKind kind = NoteBlockKind.paragraph,
    String text = '',
    List<NoteMark> marks = const [],
    Map<String, Object?> props = const {},
  }) {
    final block = NoteBlock(
      id: newId(),
      pos: _keyFor(afterId),
      kind: kind,
      text: text,
      marks: normalizeMarks(marks, text.length),
      props: props,
    );
    _local[block.id] = block;
    _changed();
    return block;
  }

  /// Several blocks in a row after [afterId] (a paste), with keys spread
  /// between the neighbours.
  List<NoteBlock> insertBlocks(
    String? afterId,
    List<({NoteBlockKind kind, String text, Map<String, Object?> props})> items,
  ) {
    if (items.isEmpty) {
      return const [];
    }
    final ordered = blocks;
    String? before;
    String? after;
    if (afterId == null) {
      after = ordered.isEmpty ? null : ordered.first.pos;
    } else {
      final index = ordered.indexWhere((block) => block.id == afterId);
      before = index >= 0 ? ordered[index].pos : null;
      after = index >= 0 && index + 1 < ordered.length
          ? ordered[index + 1].pos
          : null;
    }
    if (before != null && after != null && before.compareTo(after) >= 0) {
      after = null;
    }
    final keys = keysBetween(before, after, items.length);
    final created = <NoteBlock>[];
    for (var i = 0; i < items.length; i++) {
      final block = NoteBlock(
        id: newId(),
        pos: keys[i],
        kind: items[i].kind,
        text: items[i].text,
        props: items[i].props,
      );
      _local[block.id] = block;
      created.add(block);
    }
    _changed();
    return created;
  }

  /// Removes a block. The last block of a note is emptied instead.
  void deleteBlock(String id) {
    final block = _local[id];
    if (block == null || block.deleted) {
      return;
    }
    if (blocks.length <= 1) {
      updateBlock(
        id,
        text: '',
        marks: const [],
        kind: NoteBlockKind.paragraph,
        props: const {},
      );
      return;
    }
    if (_base[id] == null || _base[id]!.rev == 0) {
      // Never stored: nothing to tell the server.
      _local.remove(id);
    } else {
      _local[id] = block.copyWith(deleted: true);
    }
    _changed();
  }

  /// Puts [id] after [afterId] (first when null).
  void moveBlock(String id, String? afterId) {
    final block = blockById(id);
    if (block == null || id == afterId) {
      return;
    }
    if (afterId != null && blockById(afterId) == null) {
      return;
    }
    final pos = _keyFor(afterId, skipId: id);
    // A renumbering may have changed this block's key as well.
    _local[id] = (blockById(id) ?? block).copyWith(pos: pos);
    _changed();
  }

  void _changed() {
    _refreshStatus();
    notifyListeners();
  }

  void _refreshStatus() {
    if (!hasPendingChanges) {
      _status = NoteSyncStatus.saved;
    } else if (_status == NoteSyncStatus.saved) {
      _status = NoteSyncStatus.saving;
    }
  }

  // ------------------------------------------------------ remote changes --

  /// Takes a block as the server has it (from realtime, a conflict answer
  /// or a fresh load) and merges it with local edits to the same block.
  void receiveRemote(NoteBlock theirs, {bool notify = true}) {
    final prior = _base[theirs.id];
    if (prior != null && theirs.rev <= prior.rev) {
      return;
    }
    // Our own change coming back before the answer does.
    final sent = _inflight[theirs.id];
    if (sent != null &&
        sent.sameContent(theirs.copyWith(deleted: sent.deleted))) {
      _base[theirs.id] = sent.copyWith(rev: theirs.rev);
      _inflight.remove(theirs.id);
      if (notify) {
        _changed();
      }
      return;
    }
    final mine = _local[theirs.id];
    _base[theirs.id] = theirs;
    // Whether this device has changes to the block the server lacks: edits
    // to a stored block, or a block created here that the server knows
    // nothing (or only an older copy) of.
    final dirty =
        mine != null &&
        (prior == null ? !mine.deleted : !_sameAsBase(mine, prior));
    if (!dirty) {
      _local[theirs.id] = theirs;
    } else if (theirs.deleted) {
      _local[theirs.id] = theirs;
      if (!mine.deleted) {
        // Edited here, deleted there: the text lives on in a block of its
        // own at the same place rather than vanishing.
        final copy = NoteBlock(
          id: newId(),
          pos: mine.pos,
          kind: mine.kind,
          text: mine.text,
          marks: mine.marks,
          props: mine.props,
        );
        _local[copy.id] = copy;
      }
    } else if (mine.deleted) {
      // Deleted here, edited there: the delete stands (it is sent next).
      _local[theirs.id] = mine;
    } else if (prior == null) {
      // Created here, and the server has an older copy (an earlier send
      // whose answer was lost): the newer text is sent over it.
      _local[theirs.id] = mine;
    } else {
      _local[theirs.id] = mergeBlocks(base: prior, mine: mine, theirs: theirs);
    }
    _ensureOneBlock();
    if (notify) {
      _changed();
    }
  }

  bool _sameAsBase(NoteBlock local, NoteBlock base) {
    return local.sameContent(base);
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
      } else if (base == null || base.rev == 0 || !local.sameContent(base)) {
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
        for (var i = 0; i < ids.length; i += 200) {
          final chunk = ids.sublist(
            i,
            i + 200 > ids.length ? ids.length : i + 200,
          );
          final sentBlocks = <String, NoteBlock>{};
          final ops = <Map<String, Object?>>[];
          for (final id in chunk) {
            final local = _local[id]!;
            final base = _base[id];
            if (local.deleted) {
              ops.add({'op': 'del', 'id': id});
            } else {
              ops.add(
                local.toPutOp(base == null || base.rev == 0 ? null : base.rev),
              );
              sentBlocks[id] = local;
              _inflight[id] = local;
            }
          }
          _status = NoteSyncStatus.saving;
          if (!_disposed) {
            notifyListeners();
          }
          final List<NoteOpResult> results;
          try {
            results = await remote.applyOps(noteId, ops);
          } on Object {
            _inflight.clear();
            _status = NoteSyncStatus.offline;
            if (!_disposed) {
              notifyListeners();
            }
            return false;
          }
          for (var j = 0; j < chunk.length && j < results.length; j++) {
            _handleResult(chunk[j], results[j], sentBlocks[chunk[j]]);
          }
          for (final id in chunk) {
            _inflight.remove(id);
          }
        }
        attempts++;
      } while ((_flushAgain || hasPendingChanges) && attempts < maxAttempts);
      _status = hasPendingChanges
          ? NoteSyncStatus.saving
          : NoteSyncStatus.saved;
      if (!_disposed) {
        notifyListeners();
      }
      return true;
    } finally {
      _flushing = false;
    }
  }

  void _handleResult(String id, NoteOpResult result, NoteBlock? sent) {
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
      if (base == null || base.rev < rev) {
        _base[id] = sent.copyWith(rev: rev);
      }
    } else if (result.isConflict && result.block != null) {
      receiveRemote(result.block!, notify: false);
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
