import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_text_ops.dart';

import 'note_fakes.dart';

NoteTable table(
  List<List<String>> rows, {
  List<String>? columns,
  bool header = true,
}) {
  final ids = columns ?? [for (var c = 0; c < rows.first.length; c++) 'c$c'];
  return NoteTable(
    columns: ids,
    header: header,
    rows: [
      for (final (r, row) in rows.indexed)
        NoteTableRow(
          id: 'r$r',
          cells: {
            for (final (c, cell) in row.indexed)
              if (cell.isNotEmpty) ids[c]: cell,
          },
        ),
    ],
  );
}

List<List<String>> textOf(NoteTable t) => t.textRows;

void main() {
  group('the table', () {
    test('survives being stored and read back', () {
      final original = table([
        ['Name', 'Day'],
        ['Ada', 'Mon'],
        ['', 'Tue'],
      ]);
      final props = original.toProps();
      expect(props['cols'], ['c0', 'c1']);
      expect(props['header'], isTrue);
      final back = NoteTable.fromProps(props);
      expect(textOf(back), textOf(original));
      expect(back.columns, original.columns);
      expect([for (final row in back.rows) row.id], ['r0', 'r1', 'r2']);
    });

    test('leaves empty cells out of what is stored', () {
      final props = table([
        ['a', ''],
        ['', ''],
      ]).toProps();
      final rows = props['rows']! as List<Object?>;
      expect((rows[0]! as Map)['c'], {'c0': 'a'});
      expect((rows[1]! as Map)['c'], <String, Object?>{});
    });

    test('reads damaged props as a table you can still type in', () {
      final empty = NoteTable.fromProps(const {});
      expect(empty.columns, hasLength(1));
      expect(empty.rows, hasLength(1));
      final odd = NoteTable.fromProps({
        'cols': ['a', 3, '', 'b'],
        'rows': [
          {
            'id': 'r1',
            'c': {'a': 'x', 'b': 5, 7: 'y'},
          },
          'bad',
          {'id': 3},
        ],
        'header': false,
      });
      expect(odd.columns, ['a', 'b']);
      expect(odd.rows, hasLength(1));
      expect(odd.rows.single.cells, {'a': 'x'});
      expect(odd.header, isFalse);
    });

    test('adds and removes rows and columns where the cursor is', () {
      var t = table([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      t = t.addRow('new-row', after: 0);
      expect(t.rows.map((r) => r.id), ['r0', 'new-row', 'r1']);
      t = t.addColumn('new-col', after: 0);
      expect(t.columns, ['c0', 'new-col', 'c1']);
      expect(textOf(t)[0], ['a', '', 'b']);
      t = t.removeColumn(1).removeRow(1);
      expect(textOf(t), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      // The last row and the last column stay.
      final one = table([
        ['x'],
      ]);
      expect(one.removeRow(0).rows, hasLength(1));
      expect(one.removeColumn(0).columns, hasLength(1));
      expect(one.canRemoveRow, isFalse);
      expect(one.canRemoveColumn, isFalse);
    });

    test('stops at 12 columns, 200 rows and 1000 characters a cell', () {
      var t = table([
        [for (var i = 0; i < 12; i++) 'x'],
      ]);
      expect(t.canAddColumn, isFalse);
      expect(t.addColumn('more').columns, hasLength(12));
      t = NoteTable(
        columns: const ['a'],
        rows: [for (var i = 0; i < 200; i++) NoteTableRow(id: 'r$i')],
      );
      expect(t.canAddRow, isFalse);
      expect(t.addRow('more').rows, hasLength(200));
      expect(
        table([
          [''],
        ]).setCell(0, 0, 'y' * 1500).cell(0, 0),
        hasLength(1000),
      );
    });

    test('toggles the heading row and edits one cell', () {
      final t = table([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(t.withHeader(false).header, isFalse);
      final edited = t.setCell(1, 1, 'D!');
      expect(textOf(edited), [
        ['a', 'b'],
        ['c', 'D!'],
      ]);
      expect(textOf(t)[1][1], 'd');
      // Clearing a cell removes it.
      expect(edited.setCell(1, 1, '').rows[1].cells.containsKey('c1'), isFalse);
    });

    test('is written to Markdown with a heading row', () {
      final md = tableToMarkdown(
        table([
          ['Name', 'Note'],
          ['Ada', 'a | b'],
          ['Bo', 'line\nbreak'],
        ]),
      );
      expect(md, '''
| Name | Note |
| --- | --- |
| Ada | a \\| b |
| Bo | line<br>break |
''');
      final headless = tableToMarkdown(
        table([
          ['x', 'y'],
        ], header: false),
      );
      expect(headless, '''
|  |  |
| --- | --- |
| x | y |
''');
    });

    test('is part of the note exported as Markdown', () {
      final md = noteToMarkdown('Trip', [
        const NoteBlock(id: 'a', pos: 'a', text: 'Intro'),
        NoteBlock(
          id: 'b',
          pos: 'b',
          kind: NoteBlockKind.table,
          props: table([
            ['Day', 'Plan'],
            ['1', 'Train'],
          ]).toProps(),
        ),
      ]);
      expect(md, contains('# Trip'));
      expect(md, contains('| Day | Plan |'));
      expect(md, contains('| 1 | Train |'));
    });
  });

  group('merging two people\'s tables', () {
    final base = table([
      ['Name', 'Day'],
      ['Ada', 'Mon'],
      ['Bo', 'Tue'],
    ]);

    test('keeps edits to different cells', () {
      final mine = base.setCell(1, 1, 'Wed');
      final theirs = base.setCell(2, 0, 'Bob');
      final merged = mergeTables(base: base, mine: mine, theirs: theirs);
      expect(textOf(merged), [
        ['Name', 'Day'],
        ['Ada', 'Wed'],
        ['Bob', 'Tue'],
      ]);
    });

    test('merges the words when both edit the same cell', () {
      final mine = base.setCell(1, 0, 'Ada L');
      final theirs = base.setCell(1, 0, 'Dr Ada');
      final merged = mergeTables(base: base, mine: mine, theirs: theirs);
      final cell = merged.cell(1, 0);
      // Nothing either of them typed is lost.
      expect(cell, contains('Dr'));
      expect(cell, contains('L'));
      expect(cell, contains('Ada'));
    });

    test('keeps a row added here and a column added there', () {
      final mine = base.addRow('mine', after: 2).setCell(3, 0, 'Cy');
      final theirs = base.addColumn('theirs', after: 1).setCell(0, 2, 'Where');
      final merged = mergeTables(base: base, mine: mine, theirs: theirs);
      expect(merged.columns, ['c0', 'c1', 'theirs']);
      expect(merged.rows.map((r) => r.id), ['r0', 'r1', 'r2', 'mine']);
      expect(textOf(merged), [
        ['Name', 'Day', 'Where'],
        ['Ada', 'Mon', ''],
        ['Bo', 'Tue', ''],
        ['Cy', '', ''],
      ]);
    });

    test('puts two rows added at once after their own neighbours', () {
      final mine = base.addRow('m', after: 0);
      final theirs = base.addRow('t', after: 1);
      final merged = mergeTables(base: base, mine: mine, theirs: theirs);
      expect(merged.rows.map((r) => r.id), ['r0', 'm', 'r1', 't', 'r2']);
    });

    test('lets a deletion stand unless the other side edited the row', () {
      final deleted = base.removeRow(1);
      final untouched = mergeTables(base: base, mine: deleted, theirs: base);
      expect(untouched.rows.map((r) => r.id), ['r0', 'r2']);
      final edited = base.setCell(1, 1, 'Fri');
      final saved = mergeTables(base: base, mine: deleted, theirs: edited);
      expect(saved.rows.map((r) => r.id), ['r0', 'r1', 'r2']);
      expect(saved.cell(1, 1), 'Fri');
      // The other way round: they deleted it, I edited it.
      final mineEdited = mergeTables(base: base, mine: edited, theirs: deleted);
      expect(mineEdited.rows.map((r) => r.id), ['r0', 'r1', 'r2']);
    });

    test('lets a deleted column go unless somebody typed in it', () {
      final gone = base.removeColumn(1);
      final plain = mergeTables(base: base, mine: gone, theirs: base);
      expect(plain.columns, ['c0']);
      final typed = mergeTables(
        base: base,
        mine: gone,
        theirs: base.setCell(1, 1, 'Fri'),
      );
      expect(typed.columns, ['c0', 'c1']);
      expect(typed.cell(1, 1), 'Fri');
    });

    test('takes the heading switch from whoever changed it', () {
      final merged = mergeTables(
        base: base,
        mine: base.withHeader(false),
        theirs: base.setCell(0, 0, 'Who'),
      );
      expect(merged.header, isFalse);
      expect(merged.cell(0, 0), 'Who');
    });

    test('never grows past the limits', () {
      final merged = mergeTables(
        base: table([
          ['a'],
        ]),
        mine: table([
          ['a'],
        ]).setCell(0, 0, 'x' * 1000),
        theirs: table([
          ['a'],
        ]).setCell(0, 0, 'y' * 1000),
      );
      expect(merged.cell(0, 0).length, lessThanOrEqualTo(1000));
    });
  });

  group('inside the sync engine', () {
    test(
      'two devices typing in different cells both keep their words',
      () async {
        final server = FakeNoteServer();
        final baseTable = table([
          ['Name', 'Day'],
          ['Ada', 'Mon'],
        ]);
        server.blocks['t'] = NoteBlock(
          id: 't',
          pos: 'a',
          kind: NoteBlockKind.table,
          props: baseTable.toProps(),
          rev: 1,
        );
        NoteSyncEngine device() {
          final engine = NoteSyncEngine(
            noteId: 'note-1',
            remote: FakeNoteRemote(server),
            newId: () => 'gen',
          );
          engine.load(server.snapshot());
          return engine;
        }

        final one = device();
        final two = device();
        one.updateBlock(
          't',
          props: NoteTable.fromProps(
            one.blockById('t')!.props,
          ).setCell(1, 1, 'Wed').toProps(),
        );
        two.updateBlock(
          't',
          props: NoteTable.fromProps(
            two.blockById('t')!.props,
          ).setCell(1, 0, 'Ada L').toProps(),
        );
        expect(await one.flush(), isTrue);
        expect(await two.flush(), isTrue);
        expect(await one.flush(), isTrue);
        final merged = NoteTable.fromProps(server.blocks['t']!.props);
        expect(textOf(merged)[1], ['Ada L', 'Wed']);
        // The first device learns of the merge like any remote change.
        one.receiveRemote(server.blocks['t']!);
        expect(
          NoteTable.fromProps(one.blockById('t')!.props).cell(1, 0),
          'Ada L',
        );
      },
    );
  });
}
