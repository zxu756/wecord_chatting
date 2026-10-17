import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/features/notes/notes_repository.dart';

/// One open note: the local copy ([engine]), the title and settings, who
/// else is in it, and the plumbing that keeps them in step with the server
/// (realtime in, debounced saves out, retries while offline, a draft on
/// this device for edits that have not been stored).
class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.repository,
    required this.noteId,
    required this.userId,
    required this.userName,
    required this.newId,
    this.userAvatarUrl,
    this.seed,
    NoteDraftStore? drafts,
    this.saveDelay = const Duration(milliseconds: 700),
    this.retryDelay = const Duration(seconds: 6),
  }) : drafts = drafts ?? const SharedPreferencesNoteDraftStore() {
    engine = NoteSyncEngine(noteId: noteId, remote: repository, newId: newId);
    engine.addListener(_engineChanged);
  }

  final NotesRepository repository;
  final String noteId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String Function() newId;

  /// What is known of the note before it is fetched (from the list).
  final NoteMeta? seed;
  final NoteDraftStore drafts;
  final Duration saveDelay;
  final Duration retryDelay;

  late final NoteSyncEngine engine;
  NoteMeta? meta;
  var loading = true;
  Object? error;
  List<NotePeer> peers = const [];

  /// The note was deleted by someone, or I lost access.
  var unavailable = false;

  StreamSubscription<NoteBlock>? _blocks;
  StreamSubscription<NoteMetaChange>? _metaChanges;
  StreamSubscription<List<NotePeer>>? _peerChanges;
  NotePresence? _presence;
  Timer? _saveTimer;
  Timer? _retryTimer;
  Timer? _draftTimer;
  Timer? _titleTimer;
  String? _pendingTitle;
  var _disposed = false;
  var _wasOffline = false;

  bool get canEdit => meta?.canEdit ?? false;
  NoteSyncStatus get status => engine.status;

  /// Everything but the last stored blocks is the person's own, and not
  /// sent yet.
  bool get hasUnsentChanges =>
      engine.hasPendingChanges || _pendingTitle != null;

  // -------------------------------------------------------------- opening --

  /// Fetches the note and starts listening. Without a connection a note
  /// with unsent edits opens from the device.
  Future<void> open() async {
    final draft = await drafts.load(noteId);
    try {
      final snapshot = await repository.getNote(noteId);
      meta = snapshot.note;
      engine.load(snapshot, draft: draft);
      error = null;
    } on Object catch (e) {
      if (draft != null) {
        // Offline with edits kept: work from them.
        meta =
            seed ??
            NoteMeta(
              id: noteId,
              conversationId: '',
              title: '',
              icon: NoteMeta.defaultIcon,
              canEdit: true,
            );
        engine.load(
          NoteSnapshot(
            note: meta!,
            blocks: [
              for (final block in draft.base)
                if (!block.deleted && block.rev > 0) block,
            ],
          ),
          draft: draft,
        );
        _wasOffline = true;
        _scheduleRetry();
      } else {
        error = e;
        unavailable = _looksUnavailable(e);
      }
    }
    loading = false;
    if (error == null) {
      _listen();
      if (engine.hasPendingChanges) {
        unawaited(flush());
      }
    }
    _notify();
  }

  bool _looksUnavailable(Object error) {
    final text = '$error';
    return text.contains('P0002') || text.contains('Note not found');
  }

  void _listen() {
    _blocks = repository.blockChanges(noteId).listen(engine.receiveRemote);
    _metaChanges = repository.metaChanges(noteId).listen((change) {
      final current = meta;
      if (change.deleted) {
        unavailable = true;
        _notify();
        return;
      }
      if (current != null) {
        // Don't undo a title being typed here.
        meta = current.copyWith(
          title: _pendingTitle ?? change.title,
          icon: change.icon,
          managersOnly: change.managersOnly,
          pinned: change.pinned,
        );
        // Permissions depend on the lock: ask again.
        unawaited(_refreshPermissions());
        _notify();
      }
    });
    _presence = repository.openPresence(
      noteId,
      userId: userId,
      name: userName,
      avatarUrl: userAvatarUrl,
    );
    _peerChanges = _presence!.peers.listen((peers) {
      this.peers = peers;
      _notify();
    });
  }

  Future<void> _refreshPermissions() async {
    try {
      final snapshot = await repository.getNote(noteId);
      meta = snapshot.note.copyWith(
        title: _pendingTitle ?? snapshot.note.title,
      );
      _notify();
    } on Object {
      // Keep what is shown.
    }
  }

  // --------------------------------------------------------------- saving --

  void _engineChanged() {
    if (_disposed) {
      return;
    }
    _scheduleSave();
    _scheduleDraft();
    notifyListeners();
  }

  void _scheduleSave() {
    if (!engine.hasPendingChanges) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _writeDraft);
  }

  Future<void> _writeDraft() async {
    try {
      if (engine.hasPendingChanges) {
        await drafts.save(engine.toDraft());
      } else {
        await drafts.clear(noteId);
      }
    } on Object {
      // A draft is a convenience; saving to the server is what counts.
    }
  }

  /// Sends what is waiting, now.
  Future<void> flush() async {
    _saveTimer?.cancel();
    if (!engine.hasPendingChanges) {
      return;
    }
    final reached = await engine.flush();
    if (_disposed) {
      return;
    }
    if (reached) {
      if (_wasOffline) {
        _wasOffline = false;
        await _resync();
      }
      await _writeDraft();
    } else {
      _wasOffline = true;
      await _writeDraft();
      _scheduleRetry();
    }
    await _flushTitle();
    _notify();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () => unawaited(_retry()));
  }

  Future<void> _retry() async {
    if (_disposed) {
      return;
    }
    if (engine.hasPendingChanges) {
      await flush();
    } else if (_wasOffline) {
      await _resync();
    }
  }

  /// Takes the server's note again and merges everything missed while the
  /// connection was gone.
  Future<void> _resync() async {
    try {
      final snapshot = await repository.getNote(noteId);
      meta = snapshot.note.copyWith(
        title: _pendingTitle ?? snapshot.note.title,
      );
      engine.load(snapshot, draft: engine.toDraft());
      _wasOffline = false;
      if (engine.hasPendingChanges) {
        unawaited(flush());
      }
    } on Object {
      _wasOffline = true;
      _scheduleRetry();
    }
  }

  /// Call when the app comes back to the front or the network returns.
  Future<void> reconnect() async {
    if (_wasOffline || engine.status == NoteSyncStatus.offline) {
      await _retry();
    }
  }

  // ----------------------------------------------------------- title etc. --

  void setTitle(String title) {
    final current = meta;
    if (current == null || title == current.title) {
      return;
    }
    meta = current.copyWith(title: title);
    _pendingTitle = title;
    _titleTimer?.cancel();
    _titleTimer = Timer(saveDelay, () => unawaited(_flushTitle()));
    notifyListeners();
  }

  Future<void> _flushTitle() async {
    final title = _pendingTitle;
    if (title == null) {
      return;
    }
    try {
      await repository.updateMeta(noteId, {'title': title});
      if (_pendingTitle == title) {
        _pendingTitle = null;
      }
    } on Object {
      _scheduleRetry();
    }
  }

  Future<void> setIcon(String icon) async {
    final current = meta;
    if (current == null) {
      return;
    }
    meta = current.copyWith(icon: icon);
    notifyListeners();
    try {
      await repository.updateMeta(noteId, {'icon': icon});
    } on Object {
      meta = current;
      _notify();
      rethrow;
    }
  }

  Future<void> setManagersOnly(bool value) async {
    final current = meta;
    if (current == null) {
      return;
    }
    meta = await repository.updateMeta(noteId, {'managers_only': value});
    _notify();
  }

  Future<void> setPinned(bool value) async {
    final current = meta;
    if (current == null) {
      return;
    }
    meta = await repository.updateMeta(noteId, {'pinned': value});
    _notify();
  }

  /// Takes the server's note again after a restore.
  Future<void> reload() async {
    final snapshot = await repository.getNote(noteId);
    meta = snapshot.note;
    engine.load(snapshot, draft: engine.toDraft());
    _notify();
  }

  // ------------------------------------------------------------- presence --

  /// Tells the others where the caret is.
  void setCursor({String? blockId, int? offset}) {
    _presence?.update(blockId: blockId, offset: offset);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _draftTimer?.cancel();
    _titleTimer?.cancel();
    unawaited(_blocks?.cancel());
    unawaited(_metaChanges?.cancel());
    unawaited(_peerChanges?.cancel());
    unawaited(_presence?.close());
    // Last chance to store what was typed.
    engine.removeListener(_engineChanged);
    if (engine.hasPendingChanges) {
      unawaited(
        drafts
            .save(engine.toDraft())
            .catchError((Object _) {})
            .then((_) => engine.flush())
            .whenComplete(engine.dispose),
      );
    } else {
      engine.dispose();
    }
    super.dispose();
  }
}
