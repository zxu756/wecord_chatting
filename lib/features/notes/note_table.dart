import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_merge.dart';

/// The most columns, rows and characters in a cell the server accepts
/// (note_table_props_valid).
const maxTableColumns = 12;
const maxTableRows = 200;
const maxTableCellChars = 1000;

/// A table block: columns and rows with ids of their own, and the text of
/// each cell. The ids are what make a table merge cell by cell: two people
/// typing in different cells never touch each other, and adding a row in one
/// place and a column in another keeps both.
///
/// Stored in the block's props as
/// `{header, cols: [colId...], rows: [{id, c: {colId: text}}...]}`.
@immutable
class NoteTable {
  const NoteTable({
    required this.columns,
    required this.rows,
    this.header = true,
  });

  /// A table of [rowCount] rows and [columnCount] empty columns, with ids
  /// from [newId].
  factory NoteTable.empty({
    required String Function() newId,
    int rowCount = 3,
    int columnCount = 3,
  }) {
    return NoteTable(
      columns: [for (var i = 0; i < columnCount; i++) newId()],
      rows: [for (var i = 0; i < rowCount; i++) NoteTableRow(id: newId())],
    );
  }

  /// Reads a block's props; anything that is not a table is an empty one
  /// column, one row table, so a damaged block is still editable.
  factory NoteTable.fromProps(Map<String, Object?> props) {
    final columns = <String>[
      if (props['cols'] case final List<dynamic> cols)
        for (final col in cols)
          if (col is String && col.isNotEmpty) col,
    ];
    final rows = <NoteTableRow>[
      if (props['rows'] case final List<dynamic> list)
        for (final row in list)
          if (row is Map && row['id'] is String)
            NoteTableRow(
              id: row['id'] as String,
              cells: {
                if (row['c'] case final Map<dynamic, dynamic> cells)
                  for (final entry in cells.entries)
                    if (entry.key is String && entry.value is String)
                      entry.key as String: entry.value as String,
              },
            ),
    ];
    return NoteTable(
      columns: columns.isEmpty ? const ['c1'] : columns,
      rows: rows.isEmpty ? const [NoteTableRow(id: 'r1')] : rows,
      header: props['header'] != false,
    );
  }

  final List<String> columns;
  final List<NoteTableRow> rows;

  /// Whether the first row is a heading.
  final bool header;

  Map<String, Object?> toProps() => {
    'header': header,
    'cols': columns,
    'rows': [
      for (final row in rows)
        {
          'id': row.id,
          'c': {
            for (final column in columns)
              if ((row.cells[column] ?? '').isNotEmpty)
                column: row.cells[column],
          },
        },
    ],
  };

  bool get canAddRow => rows.length < maxTableRows;
  bool get canAddColumn => columns.length < maxTableColumns;
  bool get canRemoveRow => rows.length > 1;
  bool get canRemoveColumn => columns.length > 1;

  String cell(int row, int column) => rows[row].cells[columns[column]] ?? '';

  NoteTable setCell(int row, int column, String text) {
    final clipped = text.length > maxTableCellChars
        ? text.substring(0, maxTableCellChars)
        : text;
    return NoteTable(
      columns: columns,
      header: header,
      rows: [
        for (final (index, r) in rows.indexed)
          index == row ? r.withCell(columns[column], clipped) : r,
      ],
    );
  }

  /// A new row under row [after] (at the end when null).
  NoteTable addRow(String id, {int? after}) {
    if (!canAddRow) {
      return this;
    }
    final at = after == null ? rows.length : (after + 1).clamp(0, rows.length);
    return NoteTable(
      columns: columns,
      header: header,
      rows: [
        ...rows.sublist(0, at),
        NoteTableRow(id: id),
        ...rows.sublist(at),
      ],
    );
  }

  /// A new column to the right of column [after] (at the end when null).
  NoteTable addColumn(String id, {int? after}) {
    if (!canAddColumn) {
      return this;
    }
    final at = after == null
        ? columns.length
        : (after + 1).clamp(0, columns.length);
    return NoteTable(
      columns: [...columns.sublist(0, at), id, ...columns.sublist(at)],
      header: header,
      rows: rows,
    );
  }

  NoteTable removeRow(int index) {
    if (!canRemoveRow || index < 0 || index >= rows.length) {
      return this;
    }
    return NoteTable(
      columns: columns,
      header: header,
      rows: [...rows.sublist(0, index), ...rows.sublist(index + 1)],
    );
  }

  NoteTable removeColumn(int index) {
    if (!canRemoveColumn || index < 0 || index >= columns.length) {
      return this;
    }
    final gone = columns[index];
    return NoteTable(
      columns: [...columns.sublist(0, index), ...columns.sublist(index + 1)],
      header: header,
      rows: [
        for (final row in rows)
          NoteTableRow(
            id: row.id,
            cells: {
              for (final entry in row.cells.entries)
                if (entry.key != gone) entry.key: entry.value,
            },
          ),
      ],
    );
  }

  NoteTable withHeader(bool value) =>
      NoteTable(columns: columns, rows: rows, header: value);

  /// The table as lines of text cells, for exports and the AI.
  List<List<String>> get textRows => [
    for (final row in rows)
      [for (final column in columns) row.cells[column] ?? ''],
  ];
}

@immutable
class NoteTableRow {
  const NoteTableRow({required this.id, this.cells = const {}});

  final String id;

  /// Text by column id; a missing cell is empty.
  final Map<String, String> cells;

  NoteTableRow withCell(String column, String text) {
    final next = {...cells};
    if (text.isEmpty) {
      next.remove(column);
    } else {
      next[column] = text;
    }
    return NoteTableRow(id: id, cells: next);
  }
}

// ------------------------------------------------------------------ merge --

/// The ids of a three way merge of ordered lists of ids: [theirs] sets the
/// order, what [mine] added goes after the item that came before it in
/// [mine], what either side removed stays removed - unless the other side
/// changed it ([changedByMine] / [changedByTheirs] say so), because nothing
/// typed is thrown away.
List<String> mergeIdOrder({
  required List<String> base,
  required List<String> mine,
  required List<String> theirs,
  required bool Function(String id) changedByMine,
  required bool Function(String id) changedByTheirs,
}) {
  final baseSet = base.toSet();
  final mineSet = mine.toSet();
  final theirSet = theirs.toSet();
  // Start from theirs, without what I removed (unless they changed it).
  final result = <String>[
    for (final id in theirs)
      if (mineSet.contains(id) || !baseSet.contains(id) || changedByTheirs(id))
        id,
  ];
  // What I added, or removed from them but changed, goes back in after the
  // item before it in my list.
  for (var i = 0; i < mine.length; i++) {
    final id = mine[i];
    if (result.contains(id)) {
      continue;
    }
    final addedByMe = !baseSet.contains(id);
    final removedByThem = baseSet.contains(id) && !theirSet.contains(id);
    if (!addedByMe && !(removedByThem && changedByMine(id))) {
      continue;
    }
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final before = result.indexOf(mine[j]);
      if (before >= 0) {
        at = before + 1;
        break;
      }
    }
    result.insert(at, id);
  }
  return result;
}

/// Merges two people's changes to a table that both started from [base]:
/// row and column structure by id (see [mergeIdOrder]), then every cell on
/// its own - the side that changed it wins, and when both changed the same
/// cell their words are merged like any text, so nothing typed is lost.
NoteTable mergeTables({
  required NoteTable base,
  required NoteTable mine,
  required NoteTable theirs,
}) {
  Map<String, NoteTableRow> byId(NoteTable table) => {
    for (final row in table.rows) row.id: row,
  };
  final baseRows = byId(base);
  final mineRows = byId(mine);
  final theirRows = byId(theirs);

  String cellOf(Map<String, NoteTableRow> rows, String row, String column) =>
      rows[row]?.cells[column] ?? '';

  bool rowChanged(Map<String, NoteTableRow> side, String id) {
    final before = baseRows[id];
    final after = side[id];
    if (after == null) {
      return false;
    }
    if (before == null) {
      return true;
    }
    return !mapEquals(before.cells, after.cells);
  }

  bool columnChanged(Map<String, NoteTableRow> rows, String id) {
    for (final row in rows.values) {
      if (cellOf(rows, row.id, id) != cellOf(baseRows, row.id, id)) {
        return true;
      }
    }
    return false;
  }

  final columns = mergeIdOrder(
    base: base.columns,
    mine: mine.columns,
    theirs: theirs.columns,
    changedByMine: (id) => columnChanged(mineRows, id),
    changedByTheirs: (id) => columnChanged(theirRows, id),
  );
  final rowIds = mergeIdOrder(
    base: [for (final row in base.rows) row.id],
    mine: [for (final row in mine.rows) row.id],
    theirs: [for (final row in theirs.rows) row.id],
    changedByMine: (id) => rowChanged(mineRows, id),
    changedByTheirs: (id) => rowChanged(theirRows, id),
  );

  final rows = <NoteTableRow>[];
  for (final id in rowIds) {
    final cells = <String, String>{};
    for (final column in columns) {
      final b = cellOf(baseRows, id, column);
      final m = cellOf(mineRows, id, column);
      final t = cellOf(theirRows, id, column);
      final String value;
      if (m == t) {
        value = m;
      } else if (m == b) {
        value = t;
      } else if (t == b) {
        value = m;
      } else {
        value = mergeText(
          base: b,
          baseMarks: const [],
          mine: m,
          mineMarks: const [],
          theirs: t,
          theirsMarks: const [],
        ).text;
      }
      final clipped = value.length > maxTableCellChars
          ? value.substring(0, maxTableCellChars)
          : value;
      if (clipped.isNotEmpty) {
        cells[column] = clipped;
      }
    }
    rows.add(NoteTableRow(id: id, cells: cells));
  }

  bool pick(bool b, bool m, bool t) => m != b ? m : t;
  return NoteTable(
    columns: columns,
    rows: rows.isEmpty ? [NoteTableRow(id: base.rows.first.id)] : rows,
    header: pick(base.header, mine.header, theirs.header),
  );
}

/// [mergeTables] on block props, for [mergeBlocks].
Map<String, Object?> mergeTableProps({
  required Map<String, Object?> base,
  required Map<String, Object?> mine,
  required Map<String, Object?> theirs,
}) {
  return mergeTables(
    base: NoteTable.fromProps(base),
    mine: NoteTable.fromProps(mine),
    theirs: NoteTable.fromProps(theirs),
  ).toProps();
}
