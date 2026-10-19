import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';

/// The comments of one open note: fetched, kept current while it is open
/// (Realtime says when something changed), and the actions on them. The
/// server decides who may do what; this only asks and shows.
class NoteCommentsController extends ChangeNotifier {
  NoteCommentsController({
    required this.repository,
    required this.noteId,
    required this.newId,
    this.reloadDelay = const Duration(milliseconds: 250),
  });

  final Notes2Repository repository;
  final String noteId;
  final String Function() newId;
  final Duration reloadDelay;

  var _comments = const <NoteComment>[];

  /// Whether the person may comment (the server decides).
  var canComment = false;
  var loading = true;
  Object? error;
  StreamSubscription<void>? _changes;
  Timer? _reload;
  var _disposed = false;

  /// Comments and replies, oldest first.
  List<NoteComment> get comments => _comments;

  List<NoteCommentThread> get threads => groupCommentThreads(_comments);

  List<NoteCommentThread> get openThreads => [
    for (final thread in threads)
      if (!thread.isResolved) thread,
  ];

  List<NoteCommentThread> get resolvedThreads => [
    for (final thread in threads)
      if (thread.isResolved) thread,
  ];

  /// The number of unresolved threads.
  int get openCount => openThreads.length;

  /// Unresolved threads on [blockId].
  List<NoteCommentThread> openThreadsOn(String blockId) => [
    for (final thread in openThreads)
      if (thread.root.blockId == blockId) thread,
  ];

  /// The stretches of [block] that open comments are about, for the
  /// highlight; a comment whose words moved or changed has none.
  List<NoteCommentAnchor> anchorsFor(NoteBlock block) {
    return [
      for (final thread in openThreadsOn(block.id))
        ?anchorIn(block, thread.root),
    ];
  }

  Future<void> open() async {
    await _load();
    if (_disposed) {
      return;
    }
    _changes = repository
        .commentChanges(noteId)
        .listen((_) => _scheduleReload());
  }

  Future<void> _load() async {
    try {
      _comments = await repository.listComments(noteId);
      error = null;
    } on Object catch (e) {
      error = e;
    }
    try {
      canComment = await repository.canComment(noteId);
    } on Object {
      // Keep what was known.
    }
    loading = false;
    _notify();
  }

  void _scheduleReload() {
    _reload?.cancel();
    _reload = Timer(reloadDelay, () => unawaited(_load()));
  }

  /// Takes the server's list again.
  Future<void> refresh() => _load();

  /// Adds a comment on the note, a block or a stretch of text.
  Future<NoteComment> add(
    String body, {
    String? blockId,
    int? anchorStart,
    int? anchorEnd,
    String? anchorText,
    List<String> mentions = const [],
  }) async {
    final comment = await repository.addComment(
      noteId,
      body: body,
      blockId: blockId,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      anchorText: anchorText,
      mentions: mentions,
      id: newId(),
    );
    _merge(comment);
    return comment;
  }

  Future<NoteComment> reply(
    NoteComment to,
    String body, {
    List<String> mentions = const [],
  }) async {
    final comment = await repository.addComment(
      noteId,
      body: body,
      parentId: to.parentId ?? to.id,
      mentions: mentions,
      id: newId(),
    );
    _merge(comment);
    return comment;
  }

  Future<void> edit(NoteComment comment, String body) async {
    _merge(await repository.editComment(comment.id, body));
  }

  Future<void> delete(NoteComment comment) async {
    await repository.deleteComment(comment.id);
    _comments = [
      for (final other in _comments)
        if (other.id != comment.id && other.parentId != comment.id) other,
    ];
    _notify();
  }

  Future<void> setResolved(NoteComment comment, bool resolved) async {
    _merge(await repository.resolveComment(comment.id, resolved: resolved));
  }

  /// Puts [comment] into the list (or replaces its older copy).
  void _merge(NoteComment comment) {
    final index = _comments.indexWhere((other) => other.id == comment.id);
    if (index >= 0) {
      _comments = [..._comments]..[index] = comment;
    } else {
      _comments = [..._comments, comment]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reload?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
