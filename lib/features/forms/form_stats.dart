import 'package:flutter/foundation.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// One bar of a chart: a choice, a date, a person or a range of numbers.
@immutable
class FormStatBar {
  const FormStatBar({
    required this.label,
    required this.count,
    required this.fraction,
  });

  final String label;
  final int count;

  /// [count] over the largest count of the chart, for the bar's length.
  final double fraction;
}

/// min / average / median / max of a number question.
@immutable
class FormNumberSummary {
  const FormNumberSummary({
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
  });

  final double min;
  final double max;
  final double mean;
  final double median;
}

/// What the answers to one question add up to.
@immutable
class FormFieldStats {
  const FormFieldStats({
    required this.field,
    required this.answered,
    required this.total,
    this.bars = const [],
    this.texts = const [],
    this.images = const [],
    this.number,
  });

  final FormFieldDef field;

  /// How many sheets answered this question, of [total].
  final int answered;
  final int total;

  /// Choice, date, member and number-range questions.
  final List<FormStatBar> bars;

  /// Short and long text answers.
  final List<String> texts;

  /// Picture answers.
  final List<FormImageAnswer> images;
  final FormNumberSummary? number;
}

List<FormStatBar> _bars(
  Iterable<MapEntry<String, int>> counts, {
  bool sort = false,
}) {
  final entries = counts.toList();
  if (sort) {
    entries.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  }
  final top = entries.fold<int>(0, (m, e) => e.value > m ? e.value : m);
  return [
    for (final e in entries)
      FormStatBar(
        label: e.key,
        count: e.value,
        fraction: top == 0 ? 0 : e.value / top,
      ),
  ];
}

/// Adds up each question of [form] over [results].
List<FormFieldStats> formStats(FormSnapshot form, FormResults results) {
  final rows = results.responses;
  return [for (final field in form.fields) _statsFor(field, rows, results)];
}

FormFieldStats _statsFor(
  FormFieldDef field,
  List<FormResponseRow> rows,
  FormResults results,
) {
  final values = [
    for (final row in rows)
      if (isAnswered(field, row.answers[field.id])) row.answers[field.id],
  ];
  FormFieldStats make({
    List<FormStatBar> bars = const [],
    List<String> texts = const [],
    List<FormImageAnswer> images = const [],
    FormNumberSummary? number,
  }) => FormFieldStats(
    field: field,
    answered: values.length,
    total: rows.length,
    bars: bars,
    texts: texts,
    images: images,
    number: number,
  );

  switch (field.type) {
    case FormFieldType.shortText:
    case FormFieldType.longText:
      return make(texts: [for (final v in values) (v! as String).trim()]);
    case FormFieldType.image:
      return make(
        images: [
          for (final v in values)
            if (v is FormImageAnswer) v,
        ],
      );
    case FormFieldType.singleChoice:
    case FormFieldType.multipleChoice:
      final counts = {for (final o in field.options) o.id: 0};
      for (final v in values) {
        final picked = v is List ? v : [v];
        for (final id in picked) {
          if (counts.containsKey('$id')) {
            counts['$id'] = counts['$id']! + 1;
          }
        }
      }
      return make(
        bars: _bars([
          for (final o in field.options) MapEntry(o.label, counts[o.id]!),
        ]),
      );
    case FormFieldType.date:
      final counts = <String, int>{};
      for (final v in values) {
        counts['$v'] = (counts['$v'] ?? 0) + 1;
      }
      final ordered = Map.fromEntries(
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      return make(bars: _bars(ordered.entries));
    case FormFieldType.member:
      final counts = <String, int>{};
      for (final v in values) {
        final name = results.personById('$v')?.displayName ?? tr('Someone');
        counts[name] = (counts[name] ?? 0) + 1;
      }
      return make(bars: _bars(counts.entries, sort: true));
    case FormFieldType.number:
      final numbers = <double>[
        for (final v in values)
          if (v is num) v.toDouble(),
      ]..sort();
      if (numbers.isEmpty) {
        return make();
      }
      final mean = numbers.reduce((a, b) => a + b) / numbers.length;
      final middle = numbers.length ~/ 2;
      final median = numbers.length.isOdd
          ? numbers[middle]
          : (numbers[middle - 1] + numbers[middle]) / 2;
      return make(
        bars: _numberBars(numbers),
        number: FormNumberSummary(
          min: numbers.first,
          max: numbers.last,
          mean: mean,
          median: median,
        ),
      );
  }
}

/// A histogram: whole numbers with few distinct values get a bar each,
/// otherwise five equal ranges.
List<FormStatBar> _numberBars(List<double> sorted) {
  final distinct = sorted.toSet();
  if (distinct.length <= 6) {
    final counts = <String, int>{};
    for (final v in sorted) {
      final key = formatNumber(v);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return _bars(counts.entries);
  }
  final low = sorted.first;
  final high = sorted.last;
  const buckets = 5;
  final width = (high - low) / buckets;
  final counts = List.filled(buckets, 0);
  for (final v in sorted) {
    final index = ((v - low) / width).floor().clamp(0, buckets - 1);
    counts[index]++;
  }
  return _bars(
    {
      for (var i = 0; i < buckets; i++)
        '${formatNumber(double.parse((low + width * i).toStringAsFixed(2)))} – '
                '${formatNumber(double.parse((low + width * (i + 1)).toStringAsFixed(2)))}':
            counts[i],
    }.entries,
  );
}
