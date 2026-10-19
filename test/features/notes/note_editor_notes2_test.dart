import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';
import 'package:wecord/features/notes/note_editor.dart';
import 'package:wecord/features/notes/note_editor_controller.dart';
import 'package:wecord/features/notes/note_editor_extras.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_table_view.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../workspace/workspace_fakes.dart';
import 'notes2_fakes.dart';

var _ids = 0;

NoteEditorController newController(
  FakeNotesRepository repository, {
  bool canEdit = true,
}) {
  repository.meta = NoteMeta(
    id: 'note-1',
    conversationId: 'conv-general',
    title: 'Trip plan',
    icon: '\u{1F5FA}',
    canEdit: canEdit,
    canManage: canEdit,
  );
  return NoteEditorController(
    repository: repository,
    noteId: 'note-1',
    userId: 'user-1',
    userName: 'Ada Lovelace',
    newId: () => 'gen-${_ids++}-abcdefgh',
    drafts: InMemoryNoteDraftStore(),
    saveDelay: const Duration(milliseconds: 50),
    retryDelay: const Duration(milliseconds: 200),
  );
}

void main() {
  late FakeNotesRepository repository;
  late FakeNotes2Repository notes2;

  setUp(() {
    repository = FakeNotesRepository();
    repository.server.blocks['b1'] = const NoteBlock(
      id: 'b1',
      pos: 'a',
      text: 'Pack the tent and the stove',
      rev: 1,
    );
    repository.server.blocks['b2'] = const NoteBlock(
      id: 'b2',
      pos: 'b',
      text: '',
      rev: 1,
    );
    notes2 = FakeNotes2Repository();
  });

  void editorTest(
    String name,
    Future<void> Function(
      WidgetTester tester,
      NoteEditorController controller,
      GlobalKey<NoteEditorState> key,
      List<Object> events,
    )
    body, {
    bool canEdit = true,
    bool canComment = true,
    bool withAi = true,
  }) {
    testWidgets(name, (tester) async {
      final controller = newController(repository, canEdit: canEdit);
      await controller.open();
      final comments = NoteCommentsController(
        repository: notes2,
        noteId: 'note-1',
        newId: () => 'c-${_ids++}',
        reloadDelay: const Duration(milliseconds: 5),
      );
      await tester.runAsync(comments.open);
      final events = <Object>[];
      final key = GlobalKey<NoteEditorState>();
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(
              body: NoteEditor(
                key: key,
                controller: controller,
                extras: NoteEditorExtras(
                  comments: comments,
                  canComment: canComment,
                  onComment: events.add,
                  onOpenComments: events.add,
                  onAssist: withAi ? events.add : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      try {
        await body(tester, controller, key, events);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        comments.dispose();
        controller.dispose();
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }

  editorTest('"/" then Table puts a table in place of the empty line', (
    tester,
    controller,
    key,
    events,
  ) async {
    await tester.enterText(find.byType(TextField).at(1), '/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('AI…'), findsOneWidget);
    await tester.tap(find.text('Table'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final block = controller.engine.blockById('b2')!;
    expect(block.kind, NoteBlockKind.table);
    expect(block.text, '');
    final table = NoteTable.fromProps(block.props);
    expect(table.rows, hasLength(3));
    expect(table.columns, hasLength(3));
    // A paragraph follows, so typing can go on under the table.
    expect(controller.engine.blocks.last.kind, NoteBlockKind.paragraph);
    expect(find.byType(NoteTableEditor), findsOneWidget);
  });

  editorTest('typing in a cell is stored in the block', (
    tester,
    controller,
    key,
    events,
  ) async {
    controller.engine.updateBlock(
      'b2',
      kind: NoteBlockKind.table,
      props: NoteTable.empty(newId: () => 'g${_ids++}').toProps(),
    );
    await tester.pump();
    final cell = find.descendant(
      of: find.byType(NoteTableEditor),
      matching: find.byType(TextField),
    );
    await tester.enterText(cell.first, 'Name');
    await tester.pump();
    expect(
      NoteTable.fromProps(controller.engine.blockById('b2')!.props).cell(0, 0),
      'Name',
    );
    // Saved like any other edit.
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      NoteTable.fromProps(repository.server.blocks['b2']!.props).cell(0, 0),
      'Name',
    );
  });

  editorTest('the format bar comments on the selected words', (
    tester,
    controller,
    key,
    events,
  ) async {
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).at(0));
    field.controller!.selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 13,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Comment on the selection'));
    await tester.pump();
    final target = events.single as NoteCommentTarget;
    expect(target.blockId, 'b1');
    expect(target.start, 5);
    expect(target.end, 13);
    expect(target.quote, 'the tent');
  });

  editorTest('with nothing selected the comment is on the block', (
    tester,
    controller,
    key,
    events,
  ) async {
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    await tester.tap(find.byTooltip('Comment on the selection'));
    await tester.pump();
    final target = events.single as NoteCommentTarget;
    expect(target.blockId, 'b1');
    expect(target.start, isNull);
    expect(target.quote, isNull);
  });

  editorTest('open comments are highlighted and counted on their block', (
    tester,
    controller,
    key,
    events,
  ) async {
    notes2.comments.add(
      sampleComment('c1', blockId: 'b1', start: 5, end: 13, quote: 'the tent'),
    );
    notes2.changes.add(null);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('note-comment-chip')), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).at(0));
    final span = field.controller!.buildTextSpan(
      context: tester.element(find.byType(NoteEditor)),
      withComposing: false,
    );
    final highlighted = [
      for (final child in span.children ?? const <InlineSpan>[])
        if (child is TextSpan && child.style?.backgroundColor != null)
          child.text,
    ];
    expect(highlighted, ['the tent']);
    await tester.tap(find.byKey(const ValueKey('note-comment-chip')));
    await tester.pump();
    expect(events.single, 'b1');
    // The highlight is not part of the note: nothing to save.
    expect(controller.engine.hasPendingChanges, isFalse);
    expect(controller.engine.blockById('b1')!.marks, isEmpty);
  });

  editorTest('a reader who may comment gets a comment button only', (
    tester,
    controller,
    key,
    events,
  ) async {
    expect(find.byTooltip('Comment on the selection'), findsOneWidget);
    expect(find.byTooltip('Bold (Ctrl+B)'), findsNothing);
    expect(find.byTooltip('Ask the AI'), findsNothing);
  }, canEdit: false);

  editorTest(
    'a reader who may not comment gets no bar',
    (tester, controller, key, events) async {
      expect(find.byTooltip('Comment on the selection'), findsNothing);
    },
    canEdit: false,
    canComment: false,
  );

  editorTest('the AI button asks about the selection', (
    tester,
    controller,
    key,
    events,
  ) async {
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    tester
        .widget<TextField>(find.byType(TextField).at(0))
        .controller!
        .selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Ask the AI'));
    await tester.pump();
    final target = events.single as NoteAssistTarget;
    expect(target.blockId, 'b1');
    expect(target.selectedText, 'Pack');
    expect(target.hasSelection, isTrue);
  });

  editorTest('without the AI there is no AI button or menu entry', (
    tester,
    controller,
    key,
    events,
  ) async {
    expect(find.byTooltip('Ask the AI'), findsNothing);
    await tester.enterText(find.byType(TextField).at(1), '/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI…'), findsNothing);
  }, withAi: false);

  editorTest('an answer is added as blocks under the chosen one', (
    tester,
    controller,
    key,
    events,
  ) async {
    key.currentState!.insertBlocksAfter('b1', [
      (kind: NoteBlockKind.heading2, text: 'Summary', props: const {}),
      (kind: NoteBlockKind.todo, text: 'Book', props: const {'checked': false}),
    ]);
    await tester.pump();
    final kinds = controller.engine.blocks.map((b) => b.kind).toList();
    expect(kinds, [
      NoteBlockKind.paragraph,
      NoteBlockKind.heading2,
      NoteBlockKind.todo,
      NoteBlockKind.paragraph,
    ]);
    expect(controller.engine.blocks[1].text, 'Summary');
    // It saves like typing does.
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      repository.server.blocks.values.where((b) => b.text == 'Summary'),
      hasLength(1),
    );
  });

  editorTest(
    'an answer takes the place of the empty line the menu was opened on',
    (tester, controller, key, events) async {
      key.currentState!.insertBlocksAfter('b2', [
        (kind: NoteBlockKind.bullet, text: 'Point', props: const {}),
      ], removeBlockId: 'b2');
      await tester.pump();
      expect(controller.engine.blockById('b2'), isNull);
      expect(controller.engine.blocks.last.text, 'Point');
      // A line with words in it is never removed.
      key.currentState!.insertBlocksAfter('b1', [
        (kind: NoteBlockKind.bullet, text: 'Other', props: const {}),
      ], removeBlockId: 'b1');
      await tester.pump();
      expect(controller.engine.blockById('b1'), isNotNull);
    },
  );

  editorTest('an answer replaces just the selected words', (
    tester,
    controller,
    key,
    events,
  ) async {
    controller.engine.updateBlock(
      'b1',
      marks: const [NoteMark(0, 4, 'b'), NoteMark(14, 27, 'i')],
    );
    await tester.pump();
    key.currentState!.replaceRange('b1', 5, 13, 'the big tent');
    await tester.pump();
    final block = controller.engine.blockById('b1')!;
    expect(block.text, 'Pack the big tent and the stove');
    // Formatting outside the words is kept, in step with the new text.
    expect(block.marks.map((m) => (m.start, m.end, m.type)), [
      (0, 4, 'b'),
      (18, 31, 'i'),
    ]);
  });

  editorTest('a reader cannot be given an answer', (
    tester,
    controller,
    key,
    events,
  ) async {
    key.currentState!.insertBlocksAfter('b1', [
      (kind: NoteBlockKind.bullet, text: 'x', props: const {}),
    ]);
    key.currentState!.replaceRange('b1', 0, 4, 'Zzz');
    await tester.pump();
    expect(controller.engine.blocks, hasLength(2));
    expect(
      controller.engine.blockById('b1')!.text,
      'Pack the tent and the stove',
    );
  }, canEdit: false);
}
