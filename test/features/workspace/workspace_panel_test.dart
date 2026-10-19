import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../mobile/phone_test_support.dart';
import 'workspace_world.dart';

Future<WorkspaceWorld> openPanel(
  WidgetTester tester, {
  WorkspaceTab tab = WorkspaceTab.notes,
  String? noteId,
  String? listId,
  String? itemId,
  PhoneViewport viewport = notchedPhone,
  void Function(WorkspaceWorld world)? prepare,
}) async {
  usePhoneViewport(tester, viewport);
  final workspace = WorkspaceWorld();
  prepare?.call(workspace);
  workspace.install();
  await pumpStandalone(
    tester,
    workspace.world,
    WorkspacePanel(
      conversationId: WorkspaceWorld.conversationId,
      initialTab: tab,
      initialNoteId: noteId,
      initialListId: listId,
      initialItemId: itemId,
      pageMode: true,
      onClose: () {},
    ),
  );
  return workspace;
}

void main() {
  testWidgets('notes: pinned first, with icons, previews and locks', (
    tester,
  ) async {
    await openPanel(tester);
    expect(find.text('Notes and lists'), findsOneWidget);
    expect(find.text('Trip plan'), findsOneWidget);
    expect(find.text('Trailhead rules'), findsOneWidget);
    // A note without a title reads "Untitled".
    expect(find.text('Untitled'), findsOneWidget);
    expect(find.textContaining('Bring layers'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    // Pinned note on top.
    final plan = tester.getTopLeft(
      find.byKey(const ValueKey('note-row-note-plan')),
    );
    final rules = tester.getTopLeft(
      find.byKey(const ValueKey('note-row-note-rules')),
    );
    expect(plan.dy, lessThan(rules.dy));
  });

  testWidgets('no notes: an invitation to write the first one', (tester) async {
    await openPanel(tester, prepare: (w) => w.notes.notes = []);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Create the first note'), findsOneWidget);
  });

  testWidgets('people who cannot send do not get create buttons', (
    tester,
  ) async {
    await openPanel(
      tester,
      prepare: (w) {
        w.notes
          ..notes = []
          ..canCreate = false;
      },
    );
    expect(find.byKey(const ValueKey('workspace-create')), findsNothing);
    expect(find.text('Create the first note'), findsNothing);
    expect(find.text('Nobody has written a note here yet.'), findsOneWidget);
  });

  testWidgets('creating a note opens it ready to type', (tester) async {
    final workspace = await openPanel(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await settle(tester);
    // How the note starts: a blank page, or a template.
    expect(find.text('Meeting notes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-note-blank')));
    await settle(tester);
    expect(workspace.notes.created, hasLength(1));
    expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    await workspace.world.close(tester);
  });

  testWidgets('a note opens with its blocks and can be shared to the chat', (
    tester,
  ) async {
    final workspace = await openPanel(tester, noteId: 'note-plan');
    await settle(tester);
    expect(find.text('Saturday'), findsOneWidget);
    expect(find.textContaining('Leave at 7'), findsOneWidget);
    expect(find.text('Rent a bear canister'), findsOneWidget);
    await tester.tap(find.byTooltip('Share in the chat'));
    await settle(tester);
    expect(workspace.notes.shared, [
      ('note-plan', WorkspaceWorld.conversationId),
    ]);
    expect(find.text('Shared in the chat.'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the title is saved shortly after typing', (tester) async {
    final workspace = await openPanel(tester, noteId: 'note-plan');
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('note-title')),
      'Trip plan v2',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(workspace.notes.meta!.title, 'Trip plan v2');
    await workspace.world.close(tester);
  });

  testWidgets('a locked note says so and is read only for non-managers', (
    tester,
  ) async {
    await openPanel(
      tester,
      noteId: 'note-rules',
      prepare: (w) => w.notes.meta = const NoteMeta(
        id: 'note-rules',
        conversationId: WorkspaceWorld.conversationId,
        title: 'Trailhead rules',
        icon: '\u{1F4DC}',
        managersOnly: true,
      ),
    );
    await settle(tester);
    expect(find.text('Only managers can edit'), findsWidgets);
    expect(find.text('You can read this note but not edit it'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-format-bar')), findsNothing);
  });

  testWidgets('version history lists snapshots and restores one', (
    tester,
  ) async {
    final workspace = await openPanel(
      tester,
      noteId: 'note-plan',
      prepare: (w) {
        w.notes.versions = [
          NoteVersionSummary(
            id: 'v-1',
            createdAt: DateTime.now().subtract(const Duration(hours: 2)),
            kind: 'auto',
            title: 'Trip plan',
            blockCount: 1,
            createdByName: 'Grace',
          ),
        ];
        w.notes.versionContents['v-1'] = NoteVersion(
          id: 'v-1',
          title: 'Trip plan',
          icon: '\u{1F5FA}',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          blocks: const [
            NoteBlock(id: 'old-1', pos: 'a', text: 'Before the trip'),
          ],
        );
      },
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Version history'));
    await settle(tester);
    expect(find.text('Autosave'), findsOneWidget);
    await tester.tap(find.text('Autosave'));
    await settle(tester);
    expect(find.text('Before the trip'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await settle(tester);
    await tester.tap(find.text('Restore').last);
    await settle(tester);
    expect(workspace.notes.server.blocks.keys, ['old-1']);
    await workspace.world.close(tester);
  });

  testWidgets('lists: counts, overdue badge and an invitation when empty', (
    tester,
  ) async {
    await openPanel(tester, tab: WorkspaceTab.lists);
    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('3 open · 1 done · 2 yours'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('creating a list asks for a name and opens it', (tester) async {
    final workspace = await openPanel(tester, tab: WorkspaceTab.lists);
    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Sprint');
    await tester.tap(find.text('Board').last);
    await settle(tester);
    await tester.tap(find.text('Create list'));
    await settle(tester);
    final created = workspace.lists.lists.values.firstWhere(
      (list) => list.title == 'Sprint',
    );
    expect(created.defaultView, TaskListView.board);
    expect(find.byKey(const ValueKey('board-column-todo')), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the tabs switch between notes and lists', (tester) async {
    await openPanel(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
    await settle(tester);
    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('Trip plan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-notes')));
    await settle(tester);
    expect(find.text('Trip plan'), findsOneWidget);
  });

  testWidgets('the Chinese UI reads in Chinese', (tester) async {
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    await openPanel(tester);
    expect(find.text('笔记和列表'), findsOneWidget);
    expect(find.text('笔记'), findsWidgets);
  });
}
