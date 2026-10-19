import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_table_view.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

NoteTable sample() => const NoteTable(
  columns: ['c1', 'c2'],
  rows: [
    NoteTableRow(id: 'r1', cells: {'c1': 'Name', 'c2': 'Day'}),
    NoteTableRow(id: 'r2', cells: {'c1': 'Ada'}),
  ],
);

Future<void> pumpTable(
  WidgetTester tester,
  NoteTable table, {
  bool readOnly = false,
  required ValueChanged<NoteTable> onChanged,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var ids = 0;
  var current = table;
  await tester.pumpWidget(
    MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: NoteTableEditor(
              table: current,
              readOnly: readOnly,
              onChanged: (next) {
                onChanged(next);
                setState(() => current = next);
              },
              newId: () => 'new${ids++}',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('every cell is a field, and typing reports the new table', (
    tester,
  ) async {
    NoteTable? changed;
    await pumpTable(tester, sample(), onChanged: (t) => changed = t);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Name'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(3), 'Tue');
    await tester.pump();
    expect(changed, isNotNull);
    expect(changed!.cell(1, 1), 'Tue');
    expect(changed!.cell(1, 0), 'Ada');
  });

  testWidgets('the buttons add and remove rows and columns', (tester) async {
    var table = sample();
    await pumpTable(tester, table, onChanged: (t) => table = t);
    await tester.tap(find.byTooltip('Add a row below'));
    await tester.pump();
    expect(table.rows, hasLength(3));
    expect(table.rows[1].id, 'new0');
    await tester.tap(find.byTooltip('Add a column to the right'));
    await tester.pump();
    expect(table.columns, hasLength(3));
    await tester.tap(find.byTooltip('Delete this column'));
    await tester.pump();
    expect(table.columns, hasLength(2));
    await tester.tap(find.byTooltip('Delete this row'));
    await tester.pump();
    expect(table.rows, hasLength(2));
    await tester.tap(find.byTooltip('Turn off the heading row'));
    await tester.pump();
    expect(table.header, isFalse);
  });

  testWidgets('changes from elsewhere reach the fields', (tester) async {
    var table = sample();
    await pumpTable(tester, table, onChanged: (t) => table = t);
    await pumpTable(
      tester,
      sample().setCell(1, 0, 'Ada Lovelace'),
      onChanged: (t) => table = t,
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    // A row somebody removed takes its fields away.
    await pumpTable(tester, sample().removeRow(1), onChanged: (t) => table = t);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('a reader sees the cells and no tools', (tester) async {
    await pumpTable(tester, sample(), readOnly: true, onChanged: (_) {});
    expect(find.byTooltip('Add a row below'), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.readOnly, isTrue);
    }
  });

  testWidgets('the cells are named for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTable(tester, sample(), onChanged: (_) {});
    expect(find.bySemanticsLabel('Row 2, column 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Table, 2 rows, 2 columns'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the read only table draws its text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(body: NoteTableReadOnly(table: sample())),
      ),
    );
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
