import 'dart:async';

import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';

/// A chain server in memory: one chain, the lines people added, and the
/// rules the real server enforces (closed, full, one line per person).
class FakeChainRepository implements ChainRepository {
  FakeChainRepository({
    this.chainId = 'chain-1',
    this.conversationId = 'conversation-1',
    this.title = 'Saturday hike sign-up',
    this.description = '',
    this.example = '',
    this.deadline,
    this.maxEntries,
    this.closed = false,
    this.canManage = false,
    this.me = 'user-1',
    this.creatorId = 'user-2',
    List<ChainEntry>? entries,
  }) : entries = entries ?? [];

  final String chainId;
  final String conversationId;
  String title;
  String description;
  String example;
  DateTime? deadline;
  int? maxEntries;
  bool closed;
  bool canManage;
  final String me;
  final String creatorId;
  final List<ChainEntry> entries;

  /// Note the server drops for the caller (the AI guard of new members).
  bool holdNotes = false;

  /// Makes the next [get] fail.
  Object? getError;

  final created = <(String, ChainDraft)>[];
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 1;

  /// Somebody else changed the chain: Realtime tells the clients.
  void touch() => _changes.add(null);

  ChainEntry person(String userId, String name, [String note = '']) {
    return ChainEntry(
      id: 'entry-${_next++}',
      userId: userId,
      name: name,
      note: note,
    );
  }

  void add(String userId, String name, [String note = '']) {
    entries.add(person(userId, name, note));
  }

  @override
  Future<String> create(String conversationId, ChainDraft draft) async {
    created.add((conversationId, draft));
    return 'message-1';
  }

  @override
  Future<ChainSnapshot> get(String chainId) async {
    calls.add('get');
    if (getError case final error?) {
      getError = null;
      throw error;
    }
    return ChainSnapshot(
      id: this.chainId,
      conversationId: conversationId,
      title: title,
      description: description,
      example: example,
      deadline: deadline,
      maxEntries: maxEntries,
      closedByServer: closed,
      createdBy: creatorId,
      creatorName: 'Ada',
      canManage: canManage || me == creatorId,
      myEntryId: entries.where((e) => e.userId == me).firstOrNull?.id,
      entries: List.of(entries),
    );
  }

  bool get _isClosed =>
      closed || (deadline != null && !deadline!.isAfter(DateTime.now()));

  @override
  Future<ChainWriteResult> join(String chainId, String note) async {
    calls.add('join:$note');
    if (_isClosed) {
      throw const ChainException(ChainFailureKind.closed);
    }
    if (entries.any((e) => e.userId == me)) {
      throw const ChainException(ChainFailureKind.alreadyJoined);
    }
    if (maxEntries != null && entries.length >= maxEntries!) {
      throw const ChainException(ChainFailureKind.full);
    }
    add(me, 'Me', holdNotes ? '' : note.trim());
    return ChainWriteResult(noteHeld: holdNotes && note.trim().isNotEmpty);
  }

  @override
  Future<ChainWriteResult> updateNote(String chainId, String note) async {
    calls.add('update:$note');
    if (_isClosed) {
      throw const ChainException(ChainFailureKind.closed);
    }
    final index = entries.indexWhere((e) => e.userId == me);
    if (index < 0) {
      throw const ChainException(ChainFailureKind.notJoined);
    }
    final old = entries[index];
    entries[index] = ChainEntry(
      id: old.id,
      userId: old.userId,
      name: old.name,
      note: holdNotes ? '' : note.trim(),
    );
    return ChainWriteResult(noteHeld: holdNotes && note.trim().isNotEmpty);
  }

  @override
  Future<void> leave(String chainId) async {
    calls.add('leave');
    if (_isClosed) {
      throw const ChainException(ChainFailureKind.closed);
    }
    entries.removeWhere((e) => e.userId == me);
  }

  @override
  Future<void> removeEntry(String entryId) async {
    calls.add('remove:$entryId');
    entries.removeWhere((e) => e.id == entryId);
  }

  @override
  Future<void> setClosed(String chainId, {required bool closed}) async {
    calls.add('closed:$closed');
    this.closed = closed;
    if (!closed && deadline != null && !deadline!.isAfter(DateTime.now())) {
      deadline = null;
    }
  }

  @override
  Stream<void> changes(String chainId) => _changes.stream;
}
