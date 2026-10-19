import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_repository.dart';
import 'package:wecord/features/notes/export/note_file_exporter.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/features/notes/public/public_note_repository.dart';

NoteComment sampleComment(
  String id, {
  String body = 'Looks good to me',
  String author = 'Grace Hopper',
  String? parentId,
  String? blockId,
  int? start,
  int? end,
  String? quote,
  DateTime? at,
  DateTime? resolvedAt,
  bool canEdit = false,
  bool canDelete = false,
  bool canResolve = true,
}) {
  return NoteComment(
    id: id,
    noteId: 'note-plan',
    parentId: parentId,
    blockId: blockId,
    anchorStart: start,
    anchorEnd: end,
    anchorText: quote,
    authorId: 'user-x',
    authorName: author,
    body: body,
    createdAt: at ?? DateTime(2026, 10, 24, 9),
    resolvedAt: resolvedAt,
    resolvedByName: resolvedAt == null ? null : 'Ada Lovelace',
    canEdit: canEdit,
    canDelete: canDelete,
    canResolve: canResolve && parentId == null,
  );
}

/// The server side of notes 2.0 as the app sees it: comments in a list,
/// personal templates, one publication.
class FakeNotes2Repository implements Notes2Repository {
  final comments = <NoteComment>[];
  final changes = StreamController<void>.broadcast();
  var canCommentValue = true;
  var failComments = false;
  var failWrites = false;
  var _next = 0;

  /// What was asked, in order.
  final calls = <String>[];
  final mentionsSent = <List<String>>[];

  var templates = <NoteTemplateSummary>[];
  final templateContents = <String, NoteTemplate>{};
  final createdFromBlocks = <NoteTemplate>[];
  final savedTemplates = <String>[];

  NotePublication publication = const NotePublication(
    canPublish: true,
    canWithdraw: true,
  );
  var publishedIndexing = <bool>[];

  var notifications = <NoteCommentNotification>[];
  final markedRead = <List<String>?>[];

  void _check() {
    if (failWrites) {
      throw StateError('offline');
    }
  }

  @override
  Future<List<NoteComment>> listComments(String noteId) async {
    calls.add('list');
    if (failComments) {
      throw StateError('offline');
    }
    return [...comments];
  }

  @override
  Future<bool> canComment(String noteId) async => canCommentValue;

  @override
  Future<NoteComment> addComment(
    String noteId, {
    required String body,
    String? blockId,
    int? anchorStart,
    int? anchorEnd,
    String? anchorText,
    String? parentId,
    List<String> mentions = const [],
    String? id,
  }) async {
    _check();
    calls.add('add');
    mentionsSent.add(mentions);
    final comment = NoteComment(
      id: id ?? 'comment-${_next++}',
      noteId: noteId,
      parentId: parentId,
      blockId: parentId == null ? blockId : null,
      anchorStart: parentId == null ? anchorStart : null,
      anchorEnd: parentId == null ? anchorEnd : null,
      anchorText: parentId == null ? anchorText : null,
      authorId: 'user-1',
      authorName: 'Ada Lovelace',
      body: body,
      mentions: mentions,
      createdAt: DateTime(2026, 10, 24, 10, _next),
      canEdit: true,
      canDelete: true,
      canResolve: parentId == null,
    );
    comments.add(comment);
    return comment;
  }

  @override
  Future<NoteComment> editComment(String commentId, String body) async {
    _check();
    calls.add('edit');
    final index = comments.indexWhere((c) => c.id == commentId);
    final old = comments[index];
    final next = NoteComment(
      id: old.id,
      noteId: old.noteId,
      parentId: old.parentId,
      blockId: old.blockId,
      anchorStart: old.anchorStart,
      anchorEnd: old.anchorEnd,
      anchorText: old.anchorText,
      authorId: old.authorId,
      authorName: old.authorName,
      body: body,
      createdAt: old.createdAt,
      editedAt: DateTime(2026, 10, 24, 11),
      canEdit: old.canEdit,
      canDelete: old.canDelete,
      canResolve: old.canResolve,
    );
    comments[index] = next;
    return next;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    _check();
    calls.add('delete');
    comments.removeWhere((c) => c.id == commentId || c.parentId == commentId);
  }

  @override
  Future<NoteComment> resolveComment(
    String commentId, {
    bool resolved = true,
  }) async {
    _check();
    calls.add(resolved ? 'resolve' : 'reopen');
    final index = comments.indexWhere((c) => c.id == commentId);
    final old = comments[index];
    final next = NoteComment(
      id: old.id,
      noteId: old.noteId,
      blockId: old.blockId,
      anchorStart: old.anchorStart,
      anchorEnd: old.anchorEnd,
      anchorText: old.anchorText,
      authorId: old.authorId,
      authorName: old.authorName,
      body: old.body,
      createdAt: old.createdAt,
      resolvedAt: resolved ? DateTime(2026, 10, 24, 12) : null,
      resolvedByName: resolved ? 'Ada Lovelace' : null,
      canEdit: old.canEdit,
      canDelete: old.canDelete,
      canResolve: true,
    );
    comments[index] = next;
    return next;
  }

  @override
  Stream<void> commentChanges(String noteId) => changes.stream;

  @override
  Future<List<NoteTemplateSummary>> listTemplates() async => templates;

  @override
  Future<NoteTemplate> getTemplate(String templateId) async {
    final template = templateContents[templateId];
    if (template == null) {
      throw StateError('no such template');
    }
    return template;
  }

  @override
  Future<NoteTemplateSummary> saveTemplate(String noteId, String name) async {
    _check();
    savedTemplates.add(name);
    final summary = NoteTemplateSummary(
      id: 'template-${templates.length + 1}',
      name: name,
      icon: NoteMeta.defaultIcon,
      title: name,
      blockCount: 3,
    );
    templates = [summary, ...templates];
    return summary;
  }

  @override
  Future<void> deleteTemplate(String templateId) async {
    calls.add('delete-template');
    templates = [
      for (final template in templates)
        if (template.id != templateId) template,
    ];
  }

  @override
  Future<NoteMeta> createNoteFromBlocks(
    String conversationId, {
    required String title,
    required String icon,
    required List<NoteTemplateBlock> blocks,
    String? id,
  }) async {
    createdFromBlocks.add(
      NoteTemplate(name: title, icon: icon, title: title, blocks: blocks),
    );
    return NoteMeta(
      id: id ?? 'note-from-template',
      conversationId: conversationId,
      title: title,
      icon: icon,
      canEdit: true,
      canManage: true,
    );
  }

  @override
  Future<NotePublication> getPublication(String noteId) async => publication;

  @override
  Future<NotePublication> publish(
    String noteId, {
    bool allowIndexing = false,
  }) async {
    _check();
    calls.add('publish');
    publishedIndexing.add(allowIndexing);
    publication = NotePublication(
      published: true,
      canPublish: true,
      canWithdraw: true,
      token: List.filled(48, 'a').join(),
      allowIndexing: allowIndexing,
      publishedAt: DateTime(2026, 10, 24, 10),
      publishedByName: 'Ada Lovelace',
    );
    return publication;
  }

  @override
  Future<void> unpublish(String noteId) async {
    _check();
    calls.add('unpublish');
    publication = const NotePublication(canPublish: true, canWithdraw: true);
  }

  @override
  Future<List<NoteCommentNotification>> listCommentNotifications({
    int limit = 50,
  }) async => notifications;

  @override
  Future<void> markCommentNotificationsRead([List<String>? ids]) async {
    markedRead.add(ids);
    notifications = [
      for (final n in notifications)
        if (ids != null && !ids.contains(n.id))
          n
        else
          NoteCommentNotification(
            id: n.id,
            kind: n.kind,
            commentId: n.commentId,
            noteId: n.noteId,
            conversationId: n.conversationId,
            noteTitle: n.noteTitle,
            noteIcon: n.noteIcon,
            actorName: n.actorName,
            snippet: n.snippet,
            createdAt: n.createdAt,
            isUnread: false,
          ),
    ];
  }

  List<Override> get overrides => [
    notes2RepositoryProvider.overrideWithValue(this),
  ];
}

/// The AI in the notes editor, answering what a test tells it to.
class FakeNoteAssistRepository implements NoteAssistRepository {
  /// What it answers, or throws when [error] is set.
  NoteAssistResult result = const NoteAssistResult(
    blocks: [
      NoteAssistBlock(kind: NoteBlockKind.bullet, text: 'First point'),
      NoteAssistBlock(kind: NoteBlockKind.bullet, text: 'Second point'),
    ],
    text: 'First point\nSecond point',
  );
  Object? error;
  Completer<void>? hold;

  final requests =
      <
        ({
          String noteId,
          NoteAssistMode mode,
          String? text,
          NoteAssistTone? tone,
          AiLanguage? target,
        })
      >[];

  @override
  Future<NoteAssistResult> assist({
    required String noteId,
    required NoteAssistMode mode,
    String? text,
    NoteAssistTone? tone,
    AiLanguage? target,
    AiLanguage? language,
  }) async {
    requests.add((
      noteId: noteId,
      mode: mode,
      text: text,
      tone: tone,
      target: target,
    ));
    await hold?.future;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }

  List<Override> get overrides => [
    noteAssistRepositoryProvider.overrideWithValue(this),
  ];
}

/// Keeps the files a note export would hand over.
class FakeNoteFileExporter implements NoteFileExporter {
  final files = <({String name, Uint8List bytes, String mime})>[];
  var outcome = NoteExportOutcome.downloadStarted;

  @override
  Future<NoteExportOutcome> export({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? origin,
  }) async {
    files.add((name: fileName, bytes: bytes, mime: mimeType));
    return outcome;
  }

  List<Override> get overrides => [
    noteFileExporterProvider.overrideWithValue(this),
  ];
}

/// Published notes by token.
class FakePublicNoteRepository implements PublicNoteRepository {
  final notes = <String, PublicNote>{};
  Object? error;
  final loaded = <String>[];

  @override
  Future<PublicNote> load(String token) async {
    loaded.add(token);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    final note = notes[token];
    if (note == null) {
      throw const PublicNoteGoneException();
    }
    return note;
  }

  List<Override> get overrides => [
    publicNoteRepositoryProvider.overrideWithValue(this),
  ];
}
