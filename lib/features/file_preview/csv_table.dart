/// Parses comma (or tab) separated values per RFC 4180: quoted fields may
/// hold separators, line breaks and doubled quotes. Accepts \n, \r\n and
/// \r line endings. A trailing empty line is dropped.
List<List<String>> parseDelimited(String text, {String separator = ','}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var index = 0;
  // Skip a byte order mark.
  if (text.startsWith('﻿')) {
    index = 1;
  }
  final sep = separator.codeUnitAt(0);
  const quote = 0x22, cr = 0x0D, lf = 0x0A;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (index < text.length) {
    final char = text.codeUnitAt(index);
    if (inQuotes) {
      if (char == quote) {
        if (index + 1 < text.length && text.codeUnitAt(index + 1) == quote) {
          field.writeCharCode(quote);
          index += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.writeCharCode(char);
      }
      index++;
      continue;
    }
    if (char == quote && field.isEmpty) {
      inQuotes = true;
    } else if (char == sep) {
      endField();
    } else if (char == cr) {
      endRow();
      if (index + 1 < text.length && text.codeUnitAt(index + 1) == lf) {
        index++;
      }
    } else if (char == lf) {
      endRow();
    } else {
      field.writeCharCode(char);
    }
    index++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows;
}

/// Tab for .tsv/.tab files, else whichever of comma, semicolon and tab
/// appears most in the first line (European spreadsheets export with ;).
String guessSeparator(String text, {required String extension}) {
  if (extension == 'tsv' || extension == 'tab') {
    return '\t';
  }
  final newline = text.indexOf('\n');
  final firstLine = newline < 0 ? text : text.substring(0, newline);
  var best = ',';
  var bestCount = 0;
  for (final candidate in const [',', ';', '\t']) {
    final count = candidate.allMatches(firstLine).length;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/// A table ready to show: a header row and body rows, every row padded to
/// the same number of columns.
class DelimitedTable {
  DelimitedTable._(this.header, this.rows, this.columnCount);

  factory DelimitedTable.parse(String text, {required String extension}) {
    final parsed = parseDelimited(
      text,
      separator: guessSeparator(text, extension: extension),
    );
    var columns = 0;
    for (final row in parsed) {
      if (row.length > columns) {
        columns = row.length;
      }
    }
    List<String> pad(List<String> row) => row.length >= columns
        ? row
        : [...row, for (var i = row.length; i < columns; i++) ''];
    if (parsed.isEmpty) {
      return DelimitedTable._(const [], const [], 0);
    }
    return DelimitedTable._(pad(parsed.first), [
      for (final row in parsed.skip(1)) pad(row),
    ], columns);
  }

  final List<String> header;
  final List<List<String>> rows;
  final int columnCount;

  /// A width for each column from the longest value in it (of the first
  /// rows), between [min] and [max].
  List<double> columnWidths({
    double charWidth = 7.8,
    double padding = 28,
    double min = 64,
    double max = 320,
    int sampleRows = 300,
  }) {
    final widths = List<double>.filled(columnCount, min);
    void measure(List<String> row) {
      for (var i = 0; i < row.length; i++) {
        final longest = row[i]
            .split('\n')
            .fold<int>(0, (a, line) => line.length > a ? line.length : a);
        final width = (longest * charWidth + padding).clamp(min, max);
        if (width > widths[i]) {
          widths[i] = width;
        }
      }
    }

    measure(header);
    rows.take(sampleRows).forEach(measure);
    return widths;
  }
}
