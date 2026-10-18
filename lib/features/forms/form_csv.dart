import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The answers of a form as a CSV file (RFC 4180, CRLF lines, a byte order
/// mark so that Excel reads Chinese), one row per sheet.
///
/// A form that is not anonymous starts each row with the person and the
/// time. An ANONYMOUS form has no such columns, and the server does not send
/// the people in the first place: the file carries the answers and nothing
/// that could say who gave them (the sheets come in an order that does not
/// follow the order of arrival).
String buildFormCsv(
  FormSnapshot form,
  FormResults results, {
  String Function(DateTime)? formatTime,
}) {
  final anonymous = results.anonymous || form.settings.anonymous;
  String time(DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    return formatTime != null ? formatTime(local) : _defaultTime(local);
  }

  final rows = <List<String>>[
    [
      if (!anonymous) ...[tr('Name'), tr('Submitted'), tr('Updated')],
      for (final field in form.fields) field.label,
    ],
    for (final response in results.responses)
      [
        if (!anonymous) ...[
          results.personById(response.userId)?.displayName ?? tr('Someone'),
          time(response.submittedAt),
          time(response.updatedAt),
        ],
        for (final field in form.fields)
          csvAnswer(field, response.answers[field.id], results),
      ],
  ];
  final body = [
    for (final row in rows) row.map(csvCell).join(','),
  ].join('\r\n');
  return '﻿$body\r\n';
}

String _defaultTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// One answer as a cell's text.
String csvAnswer(FormFieldDef field, Object? value, FormResults results) {
  if (!isAnswered(field, value)) {
    return '';
  }
  switch (field.type) {
    case FormFieldType.shortText:
    case FormFieldType.longText:
    case FormFieldType.date:
      return '$value';
    case FormFieldType.number:
      return value is num ? formatNumber(value) : '$value';
    case FormFieldType.singleChoice:
      return field.optionLabel('$value') ?? '';
    case FormFieldType.multipleChoice:
      return [
        for (final id in value! as List) ?field.optionLabel('$id'),
      ].join('; ');
    case FormFieldType.image:
      return value is FormImageAnswer ? value.path.split('/').last : '';
    case FormFieldType.member:
      return results.personById('$value')?.displayName ?? tr('Someone');
  }
}

/// A cell, quoted when it needs to be. A cell that a spreadsheet would run
/// as a formula (it starts with = + - @ or a control character) gets a
/// leading apostrophe, so that what someone typed into a form cannot do
/// anything on the creator's computer.
String csvCell(String text) {
  var cell = text;
  if (cell.isNotEmpty && '=+-@\t\r'.contains(cell[0])) {
    // A plain negative number is a number, not a formula.
    if (!(cell.startsWith('-') && num.tryParse(cell) != null)) {
      cell = "'$cell";
    }
  }
  if (cell.contains(RegExp('[",\r\n]')) || cell != cell.trim()) {
    return '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}

/// A file name for the export: "Hike sign-up" becomes "Hike sign-up.csv",
/// without characters a file system refuses.
String formCsvFileName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final base = cleaned.isEmpty ? 'form' : cleaned;
  return '${base.length > 60 ? base.substring(0, 60).trim() : base}.csv';
}
