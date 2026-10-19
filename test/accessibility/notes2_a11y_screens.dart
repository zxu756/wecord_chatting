// Notes 2.0, for the accessibility guard (guidelines_test.dart) and the
// screenshot tool: a note with a table, its comments, the new comment box,
// the publish sheet (off and on), the templates, the AI in the editor, the
// published page and the comment notification.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/note_assist/note_assist_sheet.dart';
import 'package:wecord/features/notes/note_comments_panel.dart';
import 'package:wecord/features/notes/note_editor_extras.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_publish_sheet.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_templates.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/features/notes/public/public_note_screen.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';

import '../features/notes/notes2_fakes.dart';
import '../features/workspace/workspace_world.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

final _token = List.filled(48, 'b').join();

NoteTable _trip() => const NoteTable(
  columns: ['c1', 'c2', 'c3'],
  rows: [
    NoteTableRow(id: 'r1', cells: {'c1': 'Day', 'c2': 'Plan', 'c3': 'Notes'}),
    NoteTableRow(
      id: 'r2',
      cells: {'c1': 'Saturday', 'c2': 'North lot at 7', 'c3': 'Bring layers'},
    ),
    NoteTableRow(id: 'r3', cells: {'c1': 'Sunday'}),
  ],
);

FakeNotes2Repository _repository() {
  final repository = FakeNotes2Repository();
  repository.comments
    ..add(
      sampleComment(
        'c1',
        body: 'Is the north lot still where we park?',
        blockId: 'blk-2',
        start: 0,
        end: 8,
        quote: 'Leave at',
        canEdit: true,
        canDelete: true,
      ),
    )
    ..add(
      sampleComment(
        'r1',
        parentId: 'c1',
        author: 'Bart Simpson',
        body: 'Yes, but it closes at 6pm.',
        at: DateTime(2026, 10, 24, 9, 30),
      ),
    )
    ..add(sampleComment('c2', body: 'Can someone book the permit?'))
    ..add(
      sampleComment(
        'c3',
        body: 'The hut list is done.',
        resolvedAt: DateTime(2026, 10, 24, 12),
      ),
    );
  return repository;
}

WorkspaceWorld _world(PhoneWorld world, FakeNotes2Repository repository) {
  final workspace = WorkspaceWorld(world: world);
  workspace.notes.server.blocks['blk-5'] = NoteBlock(
    id: 'blk-5',
    pos: 'e',
    kind: NoteBlockKind.table,
    props: _trip().toProps(),
    rev: 1,
  );
  workspace.install();
  world.extraOverrides = [
    ...world.extraOverrides,
    ...repository.overrides,
    FakeNoteAssistRepository().overrides.first,
    FakeNoteFileExporter().overrides.first,
  ];
  return workspace;
}

Future<void> _note(
  WidgetTester tester,
  PhoneWorld world, {
  FakeNotes2Repository? repository,
}) async {
  _world(world, repository ?? _repository());
  await pumpStandalone(
    tester,
    world,
    WorkspacePanel(
      conversationId: WorkspaceWorld.conversationId,
      initialTab: WorkspaceTab.notes,
      initialNoteId: 'note-plan',
      pageMode: true,
      onClose: () {},
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _standalone(
  WidgetTester tester,
  PhoneWorld world,
  Widget child, {
  FakeNotes2Repository? repository,
}) async {
  world.extraOverrides = [
    ...world.extraOverrides,
    ...(repository ?? _repository()).overrides,
    ...FakeNoteAssistRepository().overrides,
  ];
  await pumpStandalone(tester, world, Scaffold(body: child));
}

PublicNote _published() => PublicNote.fromJson({
  'title': 'Trip plan',
  'icon': '\u{1F5FA}',
  'updated_at': '2026-10-24T09:00:00Z',
  'blocks': [
    {'id': 'p1', 'kind': 'h2', 'text': 'Saturday'},
    {
      'id': 'p2',
      'kind': 'paragraph',
      'text': 'Leave at 7 and meet at the north lot. Details on the map.',
      'marks': [
        [0, 8, 'b'],
        [47, 55, 'l:https://example.com/map'],
      ],
    },
    {'id': 'p3', 'kind': 'table', 'props': _trip().toProps()},
    {
      'id': 'p4',
      'kind': 'todo',
      'text': 'Book the permit',
      'props': {'checked': true},
    },
  ],
});

final notes2A11yScreens = <A11yScreen>[
  A11yScreen('note-with-table', (tester, world) => _note(tester, world)),
  A11yScreen('note-comments', (tester, world) async {
    await _note(tester, world);
    await tester.tap(find.byKey(const ValueKey('note-comments-button')));
  }),
  A11yScreen('note-new-comment', (tester, world) async {
    await _standalone(
      tester,
      world,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showNewNoteComment(
              context,
              members: const [],
              quote: 'Leave at 7 and meet at the north lot.',
              onSubmit: (body, mentions) async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
  }),
  A11yScreen('note-publish-off', (tester, world) async {
    await _standalone(
      tester,
      world,
      const NotePublishSheet(noteId: 'note-plan', siteUrl: 'https://site.test'),
    );
  }),
  A11yScreen('note-publish-on', (tester, world) async {
    final repository = _repository()
      ..publication = NotePublication(
        published: true,
        canPublish: true,
        canWithdraw: true,
        token: _token,
        publishedByName: 'Ada Lovelace',
      );
    await _standalone(
      tester,
      world,
      const NotePublishSheet(noteId: 'note-plan', siteUrl: 'https://site.test'),
      repository: repository,
    );
  }),
  A11yScreen('note-new-from-template', (tester, world) async {
    final repository = _repository()
      ..templates = const [
        NoteTemplateSummary(
          id: 't1',
          name: 'Sprint retro',
          icon: '\u{1F501}',
          title: 'Sprint retro',
          blockCount: 9,
        ),
      ];
    await _standalone(
      tester,
      world,
      const NewNoteSheet(),
      repository: repository,
    );
  }),
  A11yScreen('note-ai-choose', (tester, world) async {
    await _standalone(
      tester,
      world,
      const NoteAssistSheet(noteId: 'note-plan', target: NoteAssistTarget()),
    );
  }),
  A11yScreen('note-ai-answer', (tester, world) async {
    await _standalone(
      tester,
      world,
      const NoteAssistSheet(
        noteId: 'note-plan',
        target: NoteAssistTarget(
          blockId: 'blk-2',
          start: 0,
          end: 8,
          selectedText: 'Leave at',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('assist-mode-summarize')));
  }),
  A11yScreen('public-note', (tester, world) async {
    final repository = FakePublicNoteRepository()..notes[_token] = _published();
    await pumpStandalone(
      tester,
      world,
      PublicNoteScreen(token: _token),
      extraOverrides: repository.overrides,
    );
  }),
  A11yScreen('public-note-gone', (tester, world) async {
    await pumpStandalone(
      tester,
      world,
      PublicNoteScreen(token: _token),
      extraOverrides: FakePublicNoteRepository().overrides,
    );
  }),
  A11yScreen('notifications-note-comment', (tester, world) async {
    final repository = _repository()
      ..notifications = [
        NoteCommentNotification(
          id: 'n1',
          kind: 'mention',
          commentId: 'c1',
          noteId: 'note-plan',
          conversationId: WorkspaceWorld.conversationId,
          noteTitle: 'Trip plan',
          noteIcon: '\u{1F5FA}',
          actorName: 'Bart Simpson',
          snippet: '@Ada can you check the north lot is open on Saturday?',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          isUnread: true,
        ),
        NoteCommentNotification(
          id: 'n2',
          kind: 'reply',
          commentId: 'r1',
          noteId: 'note-plan',
          conversationId: WorkspaceWorld.conversationId,
          noteTitle: '',
          noteIcon: '\u{1F4DD}',
          actorName: 'Grace Hopper',
          snippet: 'Yes, but it closes at 6pm.',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          isUnread: false,
        ),
      ];
    world.extraOverrides = [...world.extraOverrides, ...repository.overrides];
    await world.open(tester, '/notifications');
  }),
];
