import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes_repository.dart';

import '../../mobile/phone_test_support.dart';
import 'workspace_fakes.dart';

/// The phone test world with notes and lists in it: three notes (one
/// pinned, one locked to managers) and two lists.
class WorkspaceWorld {
  WorkspaceWorld({PhoneWorld? world}) : world = world ?? PhoneWorld() {
    SharedPreferences.setMockInitialValues({});
    notes
      ..notes = [
        NoteSummary(
          id: 'note-plan',
          conversationId: conversationId,
          title: 'Trip plan',
          icon: '\u{1F5FA}',
          managersOnly: false,
          pinned: true,
          canEdit: true,
          updatedByName: 'Grace',
          preview: 'Leave at 7. Meet at the north lot. Bring layers and water.',
        ),
        NoteSummary(
          id: 'note-rules',
          conversationId: conversationId,
          title: 'Trailhead rules',
          icon: '\u{1F4DC}',
          managersOnly: true,
          pinned: false,
          canEdit: false,
          updatedByName: 'Bart',
          preview: 'No fires. Pack out what you pack in.',
        ),
        NoteSummary(
          id: 'note-gear',
          conversationId: conversationId,
          title: '',
          icon: '\u{1F392}',
          managersOnly: false,
          pinned: false,
          canEdit: true,
          preview: '',
        ),
      ]
      ..pinned = const NoteMeta(
        id: 'note-plan',
        conversationId: conversationId,
        title: 'Trip plan',
        icon: '\u{1F5FA}',
        pinned: true,
        canEdit: true,
      )
      ..meta = const NoteMeta(
        id: 'note-plan',
        conversationId: conversationId,
        title: 'Trip plan',
        icon: '\u{1F5FA}',
        pinned: true,
        canEdit: true,
        canManage: true,
      );
    notes.server.blocks.addAll({
      'blk-1': const NoteBlock(
        id: 'blk-1',
        pos: 'a',
        kind: NoteBlockKind.heading2,
        text: 'Saturday',
        rev: 1,
      ),
      'blk-2': const NoteBlock(
        id: 'blk-2',
        pos: 'b',
        text: 'Leave at 7 and meet at the north lot.',
        marks: [NoteMark(0, 8, 'b')],
        rev: 1,
      ),
      'blk-3': const NoteBlock(
        id: 'blk-3',
        pos: 'c',
        kind: NoteBlockKind.todo,
        text: 'Book the permit',
        props: {'checked': true},
        rev: 1,
      ),
      'blk-4': const NoteBlock(
        id: 'blk-4',
        pos: 'd',
        kind: NoteBlockKind.todo,
        text: 'Rent a bear canister',
        rev: 1,
      ),
    });

    final launch = TaskList(
      id: 'list-launch',
      conversationId: conversationId,
      title: 'Launch checklist',
      icon: '\u{1F680}',
      statuses: TaskStatus.defaults,
      canEdit: true,
      canManage: true,
    );
    lists
      ..lists = {'list-launch': launch}
      ..items = {for (final item in launchItems) item.id: item}
      ..summaries = [
        TaskListSummary(
          id: 'list-launch',
          conversationId: conversationId,
          title: 'Launch checklist',
          icon: '\u{1F680}',
          defaultView: TaskListView.list,
          openCount: 3,
          doneCount: 1,
          mineCount: 2,
          overdueCount: 1,
          canEdit: true,
        ),
      ];
  }

  static const conversationId = 'conv-general';

  final PhoneWorld world;
  final notes = FakeNotesRepository();
  final lists = FakeListsRepository();

  /// Tasks of the launch list: one overdue and mine, one in progress
  /// assigned to someone else, one without anything, one done.
  List<TaskItem> get launchItems => [
    TaskItem(
      id: 'item-copy',
      listId: 'list-launch',
      title: 'Write the launch copy',
      status: 'todo',
      pos: 'a',
      assignees: const ['user-1'],
      dueAt: DateTime.now().subtract(const Duration(days: 2)),
      priority: TaskPriority.high,
      createdAt: DateTime(2026, 10, 1),
      sourceMessageId: 'm1',
    ),
    TaskItem(
      id: 'item-design',
      listId: 'list-launch',
      title: 'Design the banner',
      status: 'doing',
      pos: 'a',
      assignees: const ['user-2', 'user-3'],
      dueAt: DateTime.now().add(const Duration(days: 3)),
      details: 'Square and wide versions.',
      createdAt: DateTime(2026, 10, 2),
    ),
    TaskItem(
      id: 'item-qa',
      listId: 'list-launch',
      title: 'Test on every phone',
      status: 'todo',
      pos: 'b',
      createdAt: DateTime(2026, 10, 3),
    ),
    TaskItem(
      id: 'item-plan',
      listId: 'list-launch',
      title: 'Plan the schedule',
      status: 'done',
      pos: 'a',
      assignees: const ['user-1'],
      completedAt: DateTime(2026, 10, 10),
      createdAt: DateTime(2026, 9, 28),
    ),
  ];

  List<Override> get overrides => [
    notesRepositoryProvider.overrideWithValue(notes),
    listsRepositoryProvider.overrideWithValue(lists),
  ];

  /// Applies the overrides to [world] (call before opening anything).
  void install() {
    world.extraOverrides = [...world.extraOverrides, ...overrides];
  }
}
