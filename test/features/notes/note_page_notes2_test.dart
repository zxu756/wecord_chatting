import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/export/note_file_exporter.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';

import '../workspace/workspace_panel_test.dart' show openPanel;
import '../workspace/workspace_world.dart';
import 'notes2_fakes.dart';

void main() {
  late FakeNotes2Repository notes2;
  late FakeNoteFileExporter exporter;
  late FakeNoteAssistRepository assist;

  Future<WorkspaceWorld> openNote(WidgetTester tester) async {
    notes2 = FakeNotes2Repository();
    exporter = FakeNoteFileExporter();
    assist = FakeNoteAssistRepository();
    final workspace = await openPanel(
      tester,
      noteId: 'note-plan',
      prepare: (w) {
        w.world.extraOverrides = [
          ...w.world.extraOverrides,
          ...notes2.overrides,
          ...exporter.overrides,
          ...assist.overrides,
        ];
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return workspace;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More').last);
    await tester.pumpAndSettle();
  }

  testWidgets('the menu publishes, exports and saves templates', (
    tester,
  ) async {
    final workspace = await openNote(tester);
    await openMenu(tester);
    for (final label in [
      'Publish to the web…',
      'Save as a template…',
      'Export as a Markdown file',
      'Export as a PDF',
      'Copy as Markdown',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await workspace.world.close(tester);
  });

  testWidgets('Markdown goes out as a file named after the note', (
    tester,
  ) async {
    final workspace = await openNote(tester);
    await openMenu(tester);
    await tester.tap(find.text('Export as a Markdown file'));
    await tester.pumpAndSettle();
    final file = exporter.files.single;
    expect(file.name, 'Trip plan.md');
    expect(file.mime, 'text/markdown');
    final markdown = utf8.decode(file.bytes);
    expect(markdown, contains('# Trip plan'));
    expect(markdown, contains('## Saturday'));
    expect(markdown, contains('- [x] Book the permit'));
    await workspace.world.close(tester);
  });

  testWidgets('the PDF goes out as a PDF', (tester) async {
    final workspace = await openNote(tester);
    await openMenu(tester);
    await tester.tap(find.text('Export as a PDF'));
    await tester.pump();
    for (var i = 0; i < 100 && exporter.files.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final file = exporter.files.single;
    expect(file.name, 'Trip plan.pdf');
    expect(file.mime, 'application/pdf');
    expect(latin1.decode(file.bytes.sublist(0, 8)), startsWith('%PDF-1.4'));
    await workspace.world.close(tester);
  });

  testWidgets('a failed export says so', (tester) async {
    final workspace = await openNote(tester);
    exporter.outcome = NoteExportOutcome.failed;
    await openMenu(tester);
    await tester.tap(find.text('Export as a Markdown file'));
    await tester.pumpAndSettle();
    expect(find.text('Could not export the note.'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the note can be saved as a template under a name', (
    tester,
  ) async {
    final workspace = await openNote(tester);
    await openMenu(tester);
    await tester.tap(find.text('Save as a template…'));
    await tester.pumpAndSettle();
    expect(find.text('Save as a template'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Weekend');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(notes2.savedTemplates, ['Weekend']);
    expect(find.text('Saved as a template.'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the menu opens the publish sheet', (tester) async {
    final workspace = await openNote(tester);
    await openMenu(tester);
    await tester.tap(find.text('Publish to the web…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('publish-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-button')));
    await tester.pumpAndSettle();
    expect(notes2.calls, contains('publish'));
    expect(find.byKey(const ValueKey('publish-link')), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the comments button shows the open threads', (tester) async {
    notes2 = FakeNotes2Repository();
    notes2.comments
      ..add(sampleComment('c1', body: 'First question'))
      ..add(
        sampleComment(
          'c2',
          body: 'Settled',
          resolvedAt: DateTime(2026, 10, 24, 12),
        ),
      );
    exporter = FakeNoteFileExporter();
    assist = FakeNoteAssistRepository();
    final workspace = await openPanel(
      tester,
      noteId: 'note-plan',
      prepare: (w) {
        w.world.extraOverrides = [
          ...w.world.extraOverrides,
          ...notes2.overrides,
          ...exporter.overrides,
          ...assist.overrides,
        ];
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.byKey(const ValueKey('note-comments-button'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('First question'), findsOneWidget);
    expect(find.text('Settled'), findsNothing);
    await workspace.world.close(tester);
  });

  testWidgets('a comment on a whole note is added from the panel', (
    tester,
  ) async {
    final workspace = await openNote(tester);
    await tester.tap(find.byKey(const ValueKey('note-comments-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('note-comment-field')),
      'Who brings the stove?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('note-comment-send')));
    await tester.pumpAndSettle();
    expect(notes2.comments.single.body, 'Who brings the stove?');
    expect(find.text('Who brings the stove?'), findsOneWidget);
    await workspace.world.close(tester);
  });

  testWidgets('the AI adds its answer under the text, after a bookmark', (
    tester,
  ) async {
    final workspace = await openNote(tester);
    await tester.tap(find.byTooltip('Ask the AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assist-mode-summarize')));
    await tester.pumpAndSettle();
    expect(assist.requests.single.noteId, 'note-plan');
    await tester.tap(find.byKey(const ValueKey('assist-insert')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    final texts = [
      for (final block in workspace.notes.server.blocks.values) block.text,
    ];
    expect(texts, containsAll(['First point', 'Second point']));
    // A version was kept to go back to.
    expect(
      workspace.notes.versions.map((v) => v.label),
      contains('Before the AI'),
    );
    await workspace.world.close(tester);
  });

  test('a note keeps the kinds the server knows', () {
    expect(NoteBlockKind.values.map((k) => k.value), contains('table'));
    expect(NotePublication().published, isFalse);
  });
}
