import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

const _columnWidth = 156.0;

/// A table block of a note, as a grid of text fields. Every cell is stored
/// on its own (see [NoteTable]), so two people can type in different cells
/// at once. Under the grid: add or remove a row or column next to the cell
/// last used, and switch the heading row.
class NoteTableEditor extends StatefulWidget {
  const NoteTableEditor({
    required this.table,
    required this.readOnly,
    required this.onChanged,
    required this.newId,
    super.key,
  });

  final NoteTable table;
  final bool readOnly;
  final ValueChanged<NoteTable> onChanged;

  /// Ids for new rows and columns.
  final String Function() newId;

  @override
  State<NoteTableEditor> createState() => _NoteTableEditorState();
}

class _NoteTableEditorState extends State<NoteTableEditor> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  var _row = 0;
  var _column = 0;
  final _scroll = ScrollController();

  String _key(String row, String column) => '$row|$column';

  TextEditingController _controllerFor(String row, String column, String text) {
    final key = _key(row, column);
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: text),
    );
  }

  FocusNode _focusFor(String row, String column, int r, int c) {
    return _focusNodes.putIfAbsent(_key(row, column), () {
      final node = FocusNode(debugLabel: 'table cell $row $column');
      node.addListener(() {
        if (node.hasFocus && mounted) {
          setState(() {
            _row = r;
            _column = c;
          });
        }
      });
      return node;
    });
  }

  @override
  void didUpdateWidget(NoteTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final table = widget.table;
    // Cells that changed elsewhere (a merge, somebody else typing) flow into
    // their fields; the caret stays with the words around it.
    for (final (r, row) in table.rows.indexed) {
      for (final (c, column) in table.columns.indexed) {
        final controller = _controllers[_key(row.id, column)];
        final text = table.cell(r, c);
        if (controller != null && controller.text != text) {
          final edit = diffText(controller.text, text);
          final old = controller.selection;
          controller.value = TextEditingValue(
            text: text,
            selection: old.isValid
                ? TextSelection(
                    baseOffset: transformOffset(
                      old.baseOffset,
                      edit,
                    ).clamp(0, text.length),
                    extentOffset: transformOffset(
                      old.extentOffset,
                      edit,
                    ).clamp(0, text.length),
                  )
                : TextSelection.collapsed(offset: text.length),
          );
        }
      }
    }
    // Fields of rows and columns that are gone.
    final live = {
      for (final row in table.rows)
        for (final column in table.columns) _key(row.id, column),
    };
    for (final key in _controllers.keys.toList()) {
      if (!live.contains(key)) {
        _controllers.remove(key)?.dispose();
        _focusNodes.remove(key)?.dispose();
      }
    }
    _row = _row.clamp(0, table.rows.length - 1);
    _column = _column.clamp(0, table.columns.length - 1);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _apply(NoteTable next, {int? focusRow, int? focusColumn}) {
    widget.onChanged(next);
    if (focusRow != null && focusColumn != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final table = widget.table;
        if (focusRow >= table.rows.length ||
            focusColumn >= table.columns.length) {
          return;
        }
        _focusNodes[_key(table.rows[focusRow].id, table.columns[focusColumn])]
            ?.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final table = widget.table;
    final touch = usesTouchInput(context);
    final minHeight = math.max(40.0, context.touchTargetSize - 4);
    final border = BorderSide(color: c.line);

    Widget cell(int r, int col) {
      final row = table.rows[r];
      final column = table.columns[col];
      final isHeader = table.header && r == 0;
      final style = TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
        color: c.ink,
      );
      return Container(
        key: ValueKey('note-table-cell-${row.id}-$column'),
        width: _columnWidth,
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          color: isHeader ? c.raised : null,
          border: Border(right: border, bottom: border),
        ),
        child: Semantics(
          label: tr('Row {row}, column {column}', {
            'row': '${r + 1}',
            'column': '${col + 1}',
          }),
          textField: true,
          child: TextField(
            controller: _controllerFor(row.id, column, table.cell(r, col)),
            focusNode: _focusFor(row.id, column, r, col),
            readOnly: widget.readOnly,
            maxLines: null,
            minLines: 1,
            maxLength: maxTableCellChars,
            style: style,
            cursorColor: c.accent,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            decoration: const InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            onChanged: (value) => _apply(widget.table.setCell(r, col, value)),
          ),
        ),
      );
    }

    final grid = Container(
      decoration: BoxDecoration(
        border: Border(top: border, left: border),
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in List.generate(table.rows.length, (i) => i))
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final col in List.generate(
                    table.columns.length,
                    (i) => i,
                  ))
                    cell(r, col),
                ],
              ),
            ),
        ],
      ),
    );

    Widget tool(IconData icon, String label, VoidCallback? onPressed) {
      return WeCordIconButton(
        icon: icon,
        tooltip: label,
        size: 32,
        iconSize: 18,
        variant: WeCordButtonVariant.ghost,
        onPressed: onPressed,
      );
    }

    return Semantics(
      container: true,
      label: tr('Table, {rows} rows, {columns} columns', {
        'rows': '${table.rows.length}',
        'columns': '${table.columns.length}',
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              primary: false,
              child: grid,
            ),
          ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 2,
                children: [
                  tool(
                    Icons.table_rows_outlined,
                    tr('Add a row below'),
                    table.canAddRow
                        ? () => _apply(
                            table.addRow(widget.newId(), after: _row),
                            focusRow: _row + 1,
                            focusColumn: _column,
                          )
                        : null,
                  ),
                  tool(
                    Icons.view_column_outlined,
                    tr('Add a column to the right'),
                    table.canAddColumn
                        ? () => _apply(
                            table.addColumn(widget.newId(), after: _column),
                            focusRow: _row,
                            focusColumn: _column + 1,
                          )
                        : null,
                  ),
                  tool(
                    Icons.horizontal_rule_rounded,
                    tr('Delete this row'),
                    table.canRemoveRow
                        ? () => _apply(
                            table.removeRow(_row),
                            focusRow: math.max(0, _row - 1),
                            focusColumn: _column,
                          )
                        : null,
                  ),
                  tool(
                    Icons.remove_rounded,
                    tr('Delete this column'),
                    table.canRemoveColumn
                        ? () => _apply(
                            table.removeColumn(_column),
                            focusRow: _row,
                            focusColumn: math.max(0, _column - 1),
                          )
                        : null,
                  ),
                  WeCordIconButton(
                    icon: Icons.title_rounded,
                    tooltip: table.header
                        ? tr('Turn off the heading row')
                        : tr('Make the first row a heading'),
                    size: 32,
                    iconSize: 18,
                    variant: WeCordButtonVariant.ghost,
                    selected: table.header,
                    onPressed: () => _apply(table.withHeader(!table.header)),
                  ),
                ],
              ),
            ),
          if (touch) const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// A table drawn read only: version history, the page on the web, exports.
class NoteTableReadOnly extends StatelessWidget {
  const NoteTableReadOnly({required this.table, super.key});

  final NoteTable table;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final border = BorderSide(color: c.line);
    return Semantics(
      container: true,
      label: tr('Table, {rows} rows, {columns} columns', {
        'rows': '${table.rows.length}',
        'columns': '${table.columns.length}',
      }),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: border, left: border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < table.rows.length; r++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (col, _) in table.columns.indexed)
                        Container(
                          width: _columnWidth,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: table.header && r == 0 ? c.raised : null,
                            border: Border(right: border, bottom: border),
                          ),
                          child: Text(
                            table.cell(r, col),
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: table.header && r == 0
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: c.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
