import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/csv_table.dart';
import 'package:wecord/features/file_preview/viewers/text_preview.dart';

void main() {
  test('quoted fields keep separators, quotes and line breaks', () {
    final rows = parseDelimited(
      'name,note\r\n"Ada, L.","said ""hi""\nthen left"\nBob,\n',
    );
    expect(rows, [
      ['name', 'note'],
      ['Ada, L.', 'said "hi"\nthen left'],
      ['Bob', ''],
    ]);
  });

  test('the separator follows the extension, else the first line', () {
    expect(guessSeparator('a\tb', extension: 'tsv'), '\t');
    expect(guessSeparator('a;b;c\n1;2;3', extension: 'csv'), ';');
    expect(guessSeparator('a,b\n1,2', extension: 'csv'), ',');
  });

  test('rows are padded to the widest row and a BOM is skipped', () {
    final table = DelimitedTable.parse('﻿a,b,c\n1\n1,2,3,4', extension: 'csv');
    expect(table.columnCount, 4);
    expect(table.header, ['a', 'b', 'c', '']);
    expect(table.rows.first, ['1', '', '', '']);
    final widths = table.columnWidths();
    expect(widths, hasLength(4));
    expect(widths.every((w) => w >= 64 && w <= 320), isTrue);
  });

  test('JSON is indented unless it was cut off or is broken', () {
    expect(prettyJson('{"a":[1]}'), '{\n  "a": [\n    1\n  ]\n}');
    expect(prettyJson('{"a":', truncated: true), '{"a":');
    expect(prettyJson('not json'), 'not json');
  });
}
