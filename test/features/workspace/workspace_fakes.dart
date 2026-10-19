import 'dart:async';
import 'dart:typed_data';

import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes_repository.dart';

import '../notes/note_fakes.dart';

class FakeNotePresence implements NotePresence {
  final controller = StreamController<List<NotePeer>>.broadcast();
  String? lastBlock;
  int? lastOffset;
  var closed = false;

  @override
  Stream<List<NotePeer>> get peers => controller.stream;

  @override
  void update({String? blockId, int? offset}) {
    lastBlock = blockId;
    lastOffset = offset;
  }

  @override
  Future<void> close() async => closed = true;
}

/// Notes in memory, with the server rules of 202610170060_notes.sql for
/// blocks (through [FakeNoteServer]).
class FakeNotesRepository implements NotesRepository {
  FakeNotesRepository() {
    server.listen((block) {
      if (!blocks.isClosed) {
        blocks.add(block);
      }
    });
  }

  final server = FakeNoteServer();
  final blocks = StreamController<NoteBlock>.broadcast();
  final metas = StreamController<NoteMetaChange>.broadcast();
  final changes = StreamController<void>.broadcast();
  final presence = FakeNotePresence();

  var notes = <NoteSummary>[];
  NoteMeta? meta;
  NoteMeta? pinned;
  var canCreate = true;
  var versions = <NoteVersionSummary>[];
  final versionContents = <String, NoteVersion>{};
  final shared = <(String, String)>[];
  final created = <String>[];
  final uploaded = <String>[];
  var failOps = false;

  @override
  Future<ConversationWorkspace> getWorkspace(String conversationId) async {
    return ConversationWorkspace(
      notes: notes.length,
      pinnedNote: pinned,
      canCreate: canCreate,
    );
  }

  @override
  Future<List<NoteSummary>> listNotes(String conversationId) async => notes;

  @override
  Future<NoteMeta> createNote(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
  }) async {
    final note = NoteMeta(
      id: id ?? 'note-new',
      conversationId: conversationId,
      title: title,
      icon: icon ?? NoteMeta.defaultIcon,
      canEdit: true,
      canManage: true,
    );
    created.add(note.id);
    meta = note;
    server.blocks['first-block'] = const NoteBlock(
      id: 'first-block',
      pos: 'V',
      rev: 1,
    );
    notes = [
      NoteSummary(
        id: note.id,
        conversationId: conversationId,
        title: title,
        icon: note.icon,
        managersOnly: false,
        pinned: false,
        canEdit: true,
      ),
      ...notes,
    ];
    return note;
  }

  @override
  Future<NoteSnapshot> getNote(String noteId) async {
    final current =
        meta ??
        NoteMeta(
          id: noteId,
          conversationId: 'conv-general',
          title: 'Trip plan',
          icon: '\u{1F5FA}',
          canEdit: true,
          canManage: true,
        );
    return NoteSnapshot(note: current, blocks: server.snapshot().blocks);
  }

  @override
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  ) async {
    if (failOps) {
      throw StateError('offline');
    }
    return server.apply(ops);
  }

  @override
  Future<NoteMeta> updateMeta(String noteId, Map<String, Object?> patch) async {
    final current = await getNote(noteId);
    meta = current.note.copyWith(
      title: patch['title'] as String?,
      icon: patch['icon'] as String?,
      managersOnly: patch['managers_only'] as bool?,
      pinned: patch['pinned'] as bool?,
    );
    return meta!;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes = [
      for (final note in notes)
        if (note.id != noteId) note,
    ];
  }

  @override
  Future<List<NoteVersionSummary>> listVersions(String noteId) async =>
      versions;

  @override
  Future<NoteVersion> getVersion(String versionId) async =>
      versionContents[versionId]!;

  @override
  Future<void> createVersion(String noteId, {String? label}) async {
    versions = [
      NoteVersionSummary(
        id: 'v-${versions.length + 1}',
        createdAt: DateTime.now(),
        kind: 'manual',
        title: label ?? '',
        blockCount: server.snapshot().blocks.length,
        label: label,
        createdByName: 'Ada Lovelace',
      ),
      ...versions,
    ];
  }

  @override
  Future<NoteMeta> restoreVersion(String versionId) async {
    final version = versionContents[versionId]!;
    server.blocks
      ..clear()
      ..addAll({for (final block in version.blocks) block.id: block});
    return (await getNote('n')).note;
  }

  @override
  Future<String> shareNote(String noteId, String conversationId) async {
    shared.add((noteId, conversationId));
    return 'message-shared';
  }

  @override
  Future<List<NoteSearchHit>> searchNotes(String query) async {
    return [
      for (final note in notes)
        if (note.title.toLowerCase().contains(query.toLowerCase()))
          NoteSearchHit(
            id: note.id,
            conversationId: note.conversationId,
            title: note.title,
            icon: note.icon,
            conversationType: 'channel',
            conversationTitle: 'general',
            circleName: 'Hikers',
          ),
    ];
  }

  @override
  Future<String> uploadImage(
    String noteId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final path = '$noteId/$fileName';
    uploaded.add(path);
    return path;
  }

  @override
  Future<String> imageUrl(String path) async => 'https://example.com/$path';

  @override
  Stream<NoteBlock> blockChanges(String noteId) => blocks.stream;

  @override
  Stream<NoteMetaChange> metaChanges(String noteId) => metas.stream;

  @override
  Stream<void> listChanges(String conversationId) => changes.stream;

  @override
  NotePresence openPresence(
    String noteId, {
    required String userId,
    required String name,
    String? avatarUrl,
  }) => presence;
}

/// Lists in memory with the same rules as the SQL: patches apply field by
/// field, done statuses set completion.
class FakeListsRepository implements ListsRepository {
  var lists = <String, TaskList>{};
  var items = <String, TaskItem>{};
  var summaries = <TaskListSummary>[];
  var notificationList = <TaskNotification>[];
  var messageTaskList = <MessageTask>[];
  final upserts = <Map<String, Object?>>[];
  final shared = <String>[];
  final pushed = <String>[];
  final createdFromMessage = <String>[];
  final itemEvents = StreamController<TaskItem>.broadcast();
  final structure = StreamController<void>.broadcast();
  final conversation = StreamController<void>.broadcast();
  var failUpserts = false;

  /// The server answers every change with a refusal (SQLSTATE 42501).
  var refuseUpserts = false;

  @override
  Future<List<TaskListSummary>> listLists(String conversationId) async =>
      summaries;

  @override
  Future<TaskList> createList(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
    List<TaskStatus>? statuses,
    TaskListView view = TaskListView.list,
  }) async {
    final list = TaskList(
      id: id ?? 'list-new',
      conversationId: conversationId,
      title: title,
      icon: icon ?? TaskList.defaultIcon,
      statuses: statuses ?? TaskStatus.defaults,
      defaultView: view,
      canEdit: true,
      canManage: true,
    );
    lists[list.id] = list;
    summaries = [
      ...summaries,
      TaskListSummary(
        id: list.id,
        conversationId: conversationId,
        title: title,
        icon: list.icon,
        defaultView: view,
        openCount: 0,
        doneCount: 0,
        mineCount: 0,
        overdueCount: 0,
        canEdit: true,
      ),
    ];
    return list;
  }

  @override
  Future<TaskSnapshot> getList(String listId) async {
    return TaskSnapshot(
      list: lists[listId]!,
      items: [
        for (final item in items.values)
          if (item.listId == listId && !item.deleted) item,
      ],
    );
  }

  @override
  Future<TaskSnapshot> getItem(String itemId) async {
    final item = items[itemId]!;
    return TaskSnapshot(list: lists[item.listId]!, items: [item]);
  }

  @override
  Future<TaskList> updateList(
    String listId, {
    String? title,
    String? icon,
    TaskListView? view,
    List<TaskStatus>? statuses,
    Map<String, String>? statusMoves,
  }) async {
    final updated = lists[listId]!.copyWith(
      title: title,
      icon: icon,
      defaultView: view,
      statuses: statuses,
    );
    lists[listId] = updated;
    return updated;
  }

  @override
  Future<void> deleteList(String listId) async {
    lists.remove(listId);
  }

  @override
  Future<TaskList> setListFields(
    String listId,
    List<TaskFieldDef> fields,
  ) async {
    final updated = lists[listId]!.copyWith(fieldDefs: fields);
    lists[listId] = updated;
    return updated;
  }

  @override
  Future<TaskItem> upsertItem(
    String listId,
    Map<String, Object?> fields,
  ) async {
    if (failUpserts) {
      throw StateError('offline');
    }
    if (refuseUpserts) {
      throw StateError('42501 You cannot edit this list');
    }
    upserts.add({...fields, 'list_id': listId});
    final id = fields['id']! as String;
    final list = lists[listId]!;
    var item =
        items[id] ??
        TaskItem(
          id: id,
          listId: listId,
          title: '',
          status: list.statuses.first.id,
          createdAt: DateTime.now(),
        );
    for (final entry in fields.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'title':
          item = item.copyWith(title: '$value');
        case 'details':
          item = item.copyWith(details: '$value');
        case 'status':
          final kind = list.statusById('$value')?.kind;
          item = item.copyWith(
            status: '$value',
            completedAt: kind == TaskStatusKind.done
                ? (item.completedAt ?? DateTime.now())
                : null,
          );
        case 'priority':
          item = item.copyWith(priority: TaskPriority.fromValue(value));
        case 'due_at':
          item = item.copyWith(
            dueAt: value == null ? null : DateTime.parse('$value').toLocal(),
          );
        case 'due_has_time':
          item = item.copyWith(dueHasTime: value == true);
        case 'pos':
          item = item.copyWith(pos: '$value');
        case 'assignees':
          item = item.copyWith(
            assignees: [for (final a in value! as List) '$a'],
          );
        case 'custom':
          final merged = {...item.custom};
          for (final field in (value! as Map).entries) {
            if (list.fieldById('${field.key}') == null) {
              continue;
            }
            if (field.value == null) {
              merged.remove('${field.key}');
            } else {
              merged['${field.key}'] = field.value;
            }
          }
          item = item.copyWith(custom: merged);
        case 'parent_id':
          item = item.copyWith(parentId: value);
        case 'recurrence':
          item = item.copyWith(
            recurrence: value == null
                ? null
                : TaskRecurrence.tryFromJson(value),
          );
      }
    }
    items[id] = item;
    return item;
  }

  @override
  Future<TaskItem> setItemDone(String itemId, bool done) async {
    final item = items[itemId]!;
    final list = lists[item.listId]!;
    final target = done ? list.doneStatus! : list.todoStatus!;
    return upsertItem(item.listId, {'id': itemId, 'status': target.id});
  }

  @override
  Future<void> deleteItem(String itemId) async {
    items[itemId] = items[itemId]!.copyWith(deleted: true);
  }

  @override
  Future<TaskItem> createFromMessage(
    String messageId, {
    String? listId,
    String? title,
    String? itemId,
  }) async {
    createdFromMessage.add(messageId);
    final target = listId ?? lists.keys.first;
    final item = await upsertItem(target, {
      'id': itemId ?? 'item-from-message',
      'title': title ?? 'From message',
    });
    final linked = TaskItem(
      id: item.id,
      listId: item.listId,
      title: item.title,
      status: item.status,
      sourceMessageId: messageId,
      createdAt: item.createdAt,
    );
    items[item.id] = linked;
    return linked;
  }

  @override
  Future<List<MessageTask>> messageTasks(String conversationId) async =>
      messageTaskList;

  @override
  Future<String> shareItem(String itemId, String conversationId) async {
    shared.add('item:$itemId');
    return 'message-task';
  }

  @override
  Future<String> shareList(String listId, String conversationId) async {
    shared.add('list:$listId');
    return 'message-list';
  }

  @override
  Future<List<TaskNotification>> notifications({int limit = 50}) async =>
      notificationList;

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {
    notificationList = [
      for (final n in notificationList)
        if (ids == null || ids.contains(n.id))
          TaskNotification(
            id: n.id,
            kind: n.kind,
            itemId: n.itemId,
            listId: n.listId,
            conversationId: n.conversationId,
            title: n.title,
            createdAt: n.createdAt,
            isUnread: false,
            isDone: n.isDone,
            actorName: n.actorName,
            listTitle: n.listTitle,
            dueAt: n.dueAt,
          )
        else
          n,
    ];
  }

  @override
  Future<void> notifyAssignments(String itemId) async => pushed.add(itemId);

  @override
  Stream<TaskItemChange> itemChanges(String listId) => itemEvents.stream;

  @override
  Stream<void> listStructureChanges(String listId) => structure.stream;

  @override
  Stream<void> conversationChanges(String conversationId) =>
      conversation.stream;

  @override
  Stream<void> notificationChanges() => const Stream.empty();
}
