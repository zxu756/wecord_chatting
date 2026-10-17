import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_editor.dart';
import 'package:wecord/features/notes/note_editor_controller.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import '../workspace/workspace_fakes.dart';

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
    newId: () => 'gen-${_ids++}',
    drafts: InMemoryNoteDraftStore(),
    saveDelay: const Duration(milliseconds: 50),
    retryDelay: const Duration(milliseconds: 200),
  );
}

Future<void> pumpEditor(
  WidgetTester tester,
  NoteEditorController controller, {
  List<GroupMember> members = const [],
  Size size = const Size(900, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(
          body: NoteEditor(controller: controller, members: members),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder blockField(int index) => find.byType(TextField).at(index);

TextEditingController fieldController(WidgetTester tester, int index) =>
    tester.widget<TextField>(blockField(index)).controller!;

Future<void> pressWithControl(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  late FakeNotesRepository repository;

  setUp(() {
    repository = FakeNotesRepository();
    repository.server.blocks['b1'] = const NoteBlock(
      id: 'b1',
      pos: 'a',
      text: 'Pack the tent',
      rev: 1,
    );
    repository.server.blocks['b2'] = const NoteBlock(
      id: 'b2',
      pos: 'b',
      text: '',
      rev: 1,
    );
  });

  /// A test with an open note; the controller is disposed before the test
  /// ends so that none of its timers is left.
  void editorTest(
    String name,
    Future<void> Function(WidgetTester tester, NoteEditorController controller)
    body, {
    bool canEdit = true,
    List<GroupMember> members = const [],
  }) {
    testWidgets(name, (tester) async {
      final controller = newController(repository, canEdit: canEdit);
      await controller.open();
      await pumpEditor(tester, controller, members: members);
      try {
        await body(tester, controller);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }

  editorTest('typing "- " makes a bullet and Enter continues the list', (
    tester,
    controller,
  ) async {
    await tester.enterText(blockField(1), '- ');
    await tester.pump();
    expect(controller.engine.blocks[1].kind, NoteBlockKind.bullet);
    expect(controller.engine.blocks[1].text, '');

    await tester.enterText(blockField(1), 'Sleeping bags');
    await tester.pump();
    expect(controller.engine.blocks[1].text, 'Sleeping bags');

    await tester.enterText(blockField(1), 'Sleeping bags\n');
    await tester.pump();
    expect(controller.engine.blocks.length, 3);
    expect(controller.engine.blocks[2].kind, NoteBlockKind.bullet);
    expect(controller.engine.blocks[1].text, 'Sleeping bags');

    // Enter on the empty item ends the list.
    await tester.enterText(blockField(2), '\n');
    await tester.pump();
    expect(controller.engine.blocks[2].kind, NoteBlockKind.paragraph);
    expect(controller.engine.blocks.length, 3);
  });

  editorTest('markdown shortcuts: headings, to-dos, quotes, lists, code', (
    tester,
    controller,
  ) async {
    final cases = <String, NoteBlockKind>{
      '# ': NoteBlockKind.heading1,
      '## ': NoteBlockKind.heading2,
      '### ': NoteBlockKind.heading3,
      '[] ': NoteBlockKind.todo,
      '[ ] ': NoteBlockKind.todo,
      '> ': NoteBlockKind.quote,
      '1. ': NoteBlockKind.numbered,
      '* ': NoteBlockKind.bullet,
      '```': NoteBlockKind.code,
    };
    for (final entry in cases.entries) {
      controller.engine.updateBlock(
        'b2',
        kind: NoteBlockKind.paragraph,
        text: '',
      );
      await tester.pump();
      await tester.enterText(blockField(1), entry.key);
      await tester.pump();
      expect(
        controller.engine.blockById('b2')!.kind,
        entry.value,
        reason: entry.key,
      );
    }
  });

  editorTest('"[x] " makes a checked to-do and the box toggles', (
    tester,
    controller,
  ) async {
    await tester.enterText(blockField(1), '[x] ');
    await tester.pump();
    final block = controller.engine.blockById('b2')!;
    expect(block.kind, NoteBlockKind.todo);
    expect(block.checked, isTrue);
    await tester.tap(find.bySemanticsLabel(RegExp('To-do')).first);
    await tester.pump();
    expect(controller.engine.blockById('b2')!.checked, isFalse);
  });

  editorTest('Enter splits a block at the caret', (tester, controller) async {
    await tester.tap(blockField(0));
    await tester.pump();
    // The platform inserts the newline at the caret.
    fieldController(tester, 0).value = const TextEditingValue(
      text: 'Pack\nthe tent',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    final texts = controller.engine.blocks.map((b) => b.text).toList();
    expect(texts.sublist(0, 2), ['Pack', 'the tent']);
  });

  editorTest('pasting several lines makes several blocks', (
    tester,
    controller,
  ) async {
    await tester.enterText(
      blockField(1),
      'Gear\n- tent\n- stove\n## Food\nPasta',
    );
    await tester.pump();
    final kinds = controller.engine.blocks.map((b) => b.kind).toList();
    expect(kinds, [
      NoteBlockKind.paragraph,
      NoteBlockKind.paragraph,
      NoteBlockKind.bullet,
      NoteBlockKind.bullet,
      NoteBlockKind.heading2,
      NoteBlockKind.paragraph,
    ]);
    expect(controller.engine.blocks[1].text, 'Gear');
  });

  editorTest('Backspace at the start turns a heading back into text', (
    tester,
    controller,
  ) async {
    controller.engine.updateBlock('b1', kind: NoteBlockKind.heading1);
    await tester.pump();
    await tester.tap(blockField(0));
    await tester.pump();
    fieldController(tester, 0).selection = const TextSelection.collapsed(
      offset: 0,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.engine.blockById('b1')!.kind, NoteBlockKind.paragraph);
  });

  editorTest('Backspace at the start of a paragraph joins the previous', (
    tester,
    controller,
  ) async {
    controller.engine.updateBlock('b2', text: 'Stove');
    await tester.pump();
    await tester.tap(blockField(1));
    await tester.pump();
    fieldController(tester, 1).selection = const TextSelection.collapsed(
      offset: 0,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.engine.blocks.length, 1);
    expect(controller.engine.blocks.single.text, 'Pack the tentStove');
  });

  editorTest(
    'Ctrl+B bolds the selection and again unbolds; Ctrl+I italicises',
    (tester, controller) async {
      await tester.tap(blockField(0));
      await tester.pump();
      fieldController(tester, 0).selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await pressWithControl(tester, LogicalKeyboardKey.keyB);
      expect(controller.engine.blockById('b1')!.marks, [
        const NoteMark(0, 4, 'b'),
      ]);
      await pressWithControl(tester, LogicalKeyboardKey.keyB);
      expect(controller.engine.blockById('b1')!.marks, isEmpty);
      await pressWithControl(tester, LogicalKeyboardKey.keyI);
      expect(controller.engine.blockById('b1')!.marks, [
        const NoteMark(0, 4, 'i'),
      ]);
    },
  );

  editorTest('typing after a bold word continues the bold', (
    tester,
    controller,
  ) async {
    controller.engine.updateBlock('b1', marks: const [NoteMark(0, 4, 'b')]);
    await tester.pump();
    await tester.tap(blockField(0));
    await tester.pump();
    final field = fieldController(tester, 0);
    field.value = field.value.copyWith(
      text: 'PackX the tent',
      selection: const TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    expect(controller.engine.blockById('b1')!.marks, [
      const NoteMark(0, 5, 'b'),
    ]);
  });

  editorTest('the format bar toggles bold on the selection', (
    tester,
    controller,
  ) async {
    await tester.tap(blockField(0));
    await tester.pump();
    fieldController(tester, 0).selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 8,
    );
    await tester.pump();
    await tester.tap(find.byTooltip(RegExp(r'^Bold')));
    await tester.pump();
    expect(controller.engine.blockById('b1')!.marks, [
      const NoteMark(5, 8, 'b'),
    ]);
  });

  editorTest('a note I can only read has no bar and read-only fields', (
    tester,
    controller,
  ) async {
    expect(find.byKey(const ValueKey('note-format-bar')), findsNothing);
    expect(tester.widget<TextField>(blockField(0)).readOnly, isTrue);
    expect(controller.canEdit, isFalse);
  }, canEdit: false);

  editorTest('somebody else\'s edit shows up while I am in the note', (
    tester,
    controller,
  ) async {
    repository.server.apply([
      const NoteBlock(id: 'b1', pos: 'a', text: 'Pack the big tent').toPutOp(1),
    ]);
    await tester.pump();
    expect(fieldController(tester, 0).text, 'Pack the big tent');
    expect(controller.engine.pendingCount, 0);
  });

  editorTest('my edit and theirs in the same block merge', (
    tester,
    controller,
  ) async {
    await tester.enterText(blockField(0), 'Pack the tent today');
    await tester.pump();
    // Before mine is sent, they change the start.
    repository.server.apply([
      const NoteBlock(
        id: 'b1',
        pos: 'a',
        text: 'Please pack the tent',
      ).toPutOp(1),
    ]);
    await tester.pump();
    expect(fieldController(tester, 0).text.contains('today'), isTrue);
    await controller.flush();
    await tester.pump();
    expect(repository.server.blocks['b1']!.text.contains('today'), isTrue);
    expect(controller.engine.pendingCount, 0);
  });

  editorTest('edits are saved after a moment and survive going offline', (
    tester,
    controller,
  ) async {
    await tester.enterText(blockField(0), 'Pack the tent!');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(repository.server.blocks['b1']!.text, 'Pack the tent!');

    repository.failOps = true;
    await tester.enterText(blockField(0), 'Pack the tent!!');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(controller.status, NoteSyncStatus.offline);
    expect(controller.engine.pendingCount, 1);
    expect(repository.server.blocks['b1']!.text, 'Pack the tent!');

    repository.failOps = false;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(repository.server.blocks['b1']!.text, 'Pack the tent!!');
    expect(controller.status, NoteSyncStatus.saved);
  });

  editorTest('other people\'s carets are drawn with their names', (
    tester,
    controller,
  ) async {
    repository.presence.controller.add(const [
      NotePeer(userId: 'user-2', name: 'Bart', blockId: 'b1', offset: 4),
    ]);
    await tester.pump();
    await tester.pump();
    expect(controller.peers.single.name, 'Bart');
    expect(find.text('Bart'), findsOneWidget);
  });

  editorTest('my own caret is shared with the others', (
    tester,
    controller,
  ) async {
    await tester.tap(blockField(0));
    await tester.pump();
    expect(repository.presence.lastBlock, 'b1');
  });

  editorTest(
    '@ offers the people of the conversation',
    (tester, controller) async {
      await tester.enterText(blockField(1), 'Ask @gr');
      await tester.pump();
      expect(find.byKey(const ValueKey('note-mention-user-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-mention-user-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('note-mention-user-3')));
      await tester.pump();
      final block = controller.engine.blockById('b2')!;
      expect(block.text, 'Ask @Grace ');
      expect(block.marks.single.type, 'm:user-3');
      expect(block.marks.single.start, 4);
      expect(block.marks.single.end, 10);
    },
    members: [
      GroupMember(
        profile: phoneProfile('user-2', 'bart', 'Bart'),
        role: 'member',
      ),
      GroupMember(
        profile: phoneProfile('user-3', 'grace', 'Grace'),
        role: 'member',
      ),
    ],
  );
}
