import 'dart:async';

import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';

/// The server side of note_apply_ops, as in 202610170060_notes.sql: puts
/// need the block's current revision, otherwise the current block comes
/// back as a conflict; deletes always win.
class FakeNoteServer {
  final blocks = <String, NoteBlock>{};
  final _listeners = <void Function(NoteBlock)>[];

  /// Every batch received, for assertions.
  final batches = <List<Map<String, Object?>>>[];

  /// While false, calls fail like a lost connection.
  var online = true;

  void listen(void Function(NoteBlock block) onBlock) =>
      _listeners.add(onBlock);

  NoteSnapshot snapshot() {
    return NoteSnapshot(
      note: const NoteMeta(
        id: 'note-1',
        conversationId: 'conv-1',
        title: 'Test',
        icon: 'x',
        canEdit: true,
      ),
      blocks: [
        for (final block in blocks.values)
          if (!block.deleted) block,
      ]..sort(compareBlocks),
    );
  }

  String text() =>
      [for (final block in snapshot().blocks) block.text].join('|');

  List<NoteOpResult> apply(List<Map<String, Object?>> ops) {
    batches.add(ops);
    final results = <NoteOpResult>[];
    for (final op in ops) {
      final id = op['id']! as String;
      final current = blocks[id];
      if (op['op'] == 'del') {
        if (current != null && !current.deleted) {
          final next = current.copyWith(deleted: true, rev: current.rev + 1);
          blocks[id] = next;
          _emit(next);
          results.add(NoteOpResult(id: id, status: 'ok', rev: next.rev));
        } else {
          results.add(NoteOpResult(id: id, status: 'ok'));
        }
        continue;
      }
      final incoming = NoteBlock.fromJson({...op, 'rev': 1, 'deleted': false});
      final baseRev = op['base_rev'] as int?;
      if (current == null) {
        blocks[id] = incoming;
        _emit(incoming);
        results.add(NoteOpResult(id: id, status: 'ok', rev: 1));
      } else if (!current.deleted && current.sameContent(incoming)) {
        results.add(NoteOpResult(id: id, status: 'ok', rev: current.rev));
      } else if (current.deleted || baseRev != current.rev) {
        results.add(NoteOpResult(id: id, status: 'conflict', block: current));
      } else {
        final next = incoming.copyWith(rev: current.rev + 1);
        blocks[id] = next;
        _emit(next);
        results.add(NoteOpResult(id: id, status: 'ok', rev: next.rev));
      }
    }
    return results;
  }

  void _emit(NoteBlock block) {
    for (final listener in _listeners) {
      listener(block);
    }
  }
}

/// A client's connection to a [FakeNoteServer].
class FakeNoteRemote implements NoteRemote {
  FakeNoteRemote(this.server);

  final FakeNoteServer server;

  /// This client has no connection.
  var offline = false;

  /// Runs before a call is answered (to let others write in between).
  void Function()? beforeAnswer;

  @override
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  ) async {
    if (offline || !server.online) {
      throw StateError('offline');
    }
    await Future<void>.delayed(Duration.zero);
    beforeAnswer?.call();
    return server.apply(ops);
  }
}
