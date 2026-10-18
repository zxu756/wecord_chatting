import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wecord/features/circles/insights/insights_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

// The charts are drawn by hand with CustomPainter: three small charts do not
// need a charting package. Every color comes from the tokens (so light,
// dark and both high contrast sets work), and every count the server hid
// ("<5") is drawn as a hatched stub, never as a size: a hidden number must
// not be guessable from the picture.

/// The cell color of a count on the weekday by hour map.
Color heatColor(WeCordPalette c, int value, int peak) {
  if (value <= 0 || peak <= 0) {
    return c.raised;
  }
  final t = math.sqrt((value / peak).clamp(0.0, 1.0));
  return Color.lerp(c.accentSoft, c.accent, 0.25 + 0.75 * t)!;
}

/// Short date labels under a chart: the first and last day of the range.
String insightDayLabel(DateTime day) => '${day.month}/${day.day}';

/// A line of the circle's member count over the range. Days whose count the
/// server hid (a circle under 5 members) leave a gap.
class MemberLineChart extends StatelessWidget {
  const MemberLineChart({required this.days, super.key});

  final List<InsightDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shown = [
      for (final day in days)
        if (!day.members.isHidden) day.members.value,
    ];
    final high = shown.isEmpty ? 0 : shown.reduce(math.max);
    final low = shown.isEmpty ? 0 : shown.reduce(math.min);
    final summary = shown.isEmpty
        ? tr('No member numbers to show yet.')
        : tr('Members went from {from} to {to} over {days} days.', {
            'from': days
                .firstWhere((day) => !day.members.isHidden)
                .members
                .value,
            'to': days.lastWhere((day) => !day.members.isHidden).members.value,
            'days': days.length,
          });
    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LinePainter(
                    values: [
                      for (final day in days)
                        day.members.isHidden ? null : day.members.value,
                    ],
                    line: c.accent,
                    fill: c.accentSoft,
                    grid: c.lineSoft,
                    dot: c.accent,
                    halo: c.panel,
                  ),
                ),
              ),
              if (shown.isEmpty)
                Center(
                  child: Text(
                    tr('No member numbers to show yet.'),
                    style: TextStyle(fontSize: 13, color: c.subtle),
                  ),
                ),
              if (shown.isNotEmpty) ...[
                Positioned(left: 0, top: 0, child: _AxisLabel('$high')),
                Positioned(left: 0, bottom: 0, child: _AxisLabel('$low')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.subtle,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dot,
    required this.halo,
  });

  /// One value per day; null leaves a gap.
  final List<int?> values;
  final Color line;
  final Color fill;
  final Color grid;
  final Color dot;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 14.0;
    const bottom = 14.0;
    final height = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final shown = [for (final value in values) ?value];
    if (shown.isEmpty) {
      return;
    }
    var high = shown.reduce(math.max).toDouble();
    var low = shown.reduce(math.min).toDouble();
    if (high == low) {
      // A flat line sits in the middle.
      high += 1;
      low -= 1;
    }
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    Offset point(int i) {
      final value = values[i]!;
      final y = top + height * (1 - (value - low) / (high - low));
      return Offset(values.length <= 1 ? size.width / 2 : step * i, y);
    }

    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final area = Paint()
      ..color = fill.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    // One path per run of known days.
    var run = <int>[];
    void flush() {
      if (run.isEmpty) {
        return;
      }
      final path = Path()..moveTo(point(run.first).dx, point(run.first).dy);
      for (final i in run.skip(1)) {
        path.lineTo(point(i).dx, point(i).dy);
      }
      if (run.length > 1) {
        final areaPath = Path.from(path)
          ..lineTo(point(run.last).dx, size.height - bottom)
          ..lineTo(point(run.first).dx, size.height - bottom)
          ..close();
        canvas
          ..drawPath(areaPath, area)
          ..drawPath(path, stroke);
      } else {
        canvas.drawCircle(point(run.first), 2.5, Paint()..color = line);
      }
      run = <int>[];
    }

    for (var i = 0; i < values.length; i++) {
      if (values[i] == null) {
        flush();
      } else {
        run.add(i);
      }
    }
    flush();

    final lastIndex = values.lastIndexWhere((value) => value != null);
    final end = point(lastIndex);
    canvas
      ..drawCircle(end, 6, Paint()..color = halo)
      ..drawCircle(end, 4, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.line != line ||
      old.fill != fill ||
      old.grid != grid ||
      old.dot != dot ||
      old.halo != halo;
}

/// One bar per day. Hidden days are a short hatched stub.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({
    required this.values,
    required this.color,
    required this.summary,
    this.height = 96,
    super.key,
  });

  final List<InsightCount> values;
  final Color color;

  /// What a screen reader says for the chart.
  final String summary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final peak = values.fold<int>(0, (high, v) => math.max(high, v.drawn));
    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BarsPainter(
                    values: [for (final v in values) v.isHidden ? -1 : v.value],
                    color: color,
                    hidden: c.faint,
                    baseline: c.line,
                    gridLine: c.lineSoft,
                  ),
                ),
              ),
              if (peak > 0)
                Positioned(left: 0, top: 0, child: _AxisLabel('$peak')),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.color,
    required this.hidden,
    required this.baseline,
    required this.gridLine,
  });

  /// -1 for a hidden day.
  final List<int> values;
  final Color color;
  final Color hidden;
  final Color baseline;
  final Color gridLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final floor = size.height - 1;
    canvas.drawLine(
      Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..color = gridLine
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, floor),
      Offset(size.width, floor),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    final peak = values.fold<int>(0, math.max);
    final slot = size.width / values.length;
    final gap = slot > 6 ? 2.0 : (slot > 3 ? 1.0 : 0.5);
    final barWidth = math.max(slot - gap, 1.0);
    final fillPaint = Paint()..color = color;
    final hiddenPaint = Paint()
      ..color = hidden
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < values.length; i++) {
      final x = slot * i + gap / 2;
      final value = values[i];
      if (value < 0) {
        // Hatched stub of a fixed height: says "something, under 5".
        final rect = Rect.fromLTWH(x, floor - 5, barWidth, 5);
        canvas
          ..save()
          ..clipRect(rect);
        for (var dx = -5.0; dx < barWidth + 5; dx += 3) {
          canvas.drawLine(
            Offset(x + dx, floor),
            Offset(x + dx + 5, floor - 5),
            hiddenPaint,
          );
        }
        canvas.restore();
      } else if (value > 0 && peak > 0) {
        final barHeight = math.max((floor - 4) * value / peak, 2.0);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, floor - barHeight, barWidth, barHeight),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        );
        canvas.drawRRect(rect, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.color != color ||
      old.hidden != hidden ||
      old.baseline != baseline ||
      old.gridLine != gridLine;
}

/// Messages by weekday and hour: seven rows of 24 cells, Monday first. Cells
/// the server hid are hatched, empty cells plain.
class WeekHeatmap extends StatelessWidget {
  const WeekHeatmap({required this.heatmap, required this.summary, super.key});

  final InsightHeatmap heatmap;
  final String summary;

  static const rowHeight = 20.0;

  /// Row order of the page: Monday first (the server counts Sunday as 0).
  static const weekdayOrder = <int>[1, 2, 3, 4, 5, 6, 0];

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tokens = context.tokens;
    final labels = [
      tr('Mon'),
      tr('Tue'),
      tr('Wed'),
      tr('Thu'),
      tr('Fri'),
      tr('Sat'),
      tr('Sun'),
    ];
    final peak = heatmap.peak;
    TextStyle small() => TextStyle(fontSize: 11, color: c.subtle);
    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    for (final label in labels)
                      SizedBox(
                        width: 32,
                        height: rowHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(label, style: small()),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: SizedBox(
                    height: rowHeight * 7,
                    child: CustomPaint(
                      painter: _HeatmapPainter(
                        rows: [
                          for (final weekday in weekdayOrder)
                            weekday < heatmap.rows.length
                                ? [
                                    for (final cell in heatmap.rows[weekday])
                                      cell.isHidden ? -1 : cell.value,
                                  ]
                                : const <int>[],
                        ],
                        peak: peak,
                        palette: c,
                        outlined: tokens.highContrast,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  for (final hour in const [0, 6, 12, 18])
                    Expanded(child: Text('$hour:00', style: small())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.rows,
    required this.peak,
    required this.palette,
    required this.outlined,
  });

  /// Seven rows of 24 counts, -1 for hidden.
  final List<List<int>> rows;
  final int peak;
  final WeCordPalette palette;
  final bool outlined;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final cellWidth = (size.width - gap * 23) / 24;
    // Rows are exactly as tall as the weekday labels beside them.
    final rowStep = size.height / 7;
    final cellHeight = rowStep - gap;
    final outline = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final hatch = Paint()
      ..color = palette.faint
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var h = 0; h < 24 && h < row.length; h++) {
        final value = row[h];
        final rect = Rect.fromLTWH(
          h * (cellWidth + gap),
          r * rowStep,
          cellWidth,
          cellHeight,
        );
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        if (value < 0) {
          canvas
            ..drawRRect(rrect, Paint()..color = palette.raised)
            ..save()
            ..clipRRect(rrect);
          for (var dx = -cellHeight; dx < cellWidth; dx += 4) {
            canvas.drawLine(
              Offset(rect.left + dx, rect.bottom),
              Offset(rect.left + dx + cellHeight, rect.top),
              hatch,
            );
          }
          canvas.restore();
        } else {
          canvas.drawRRect(
            rrect,
            Paint()..color = heatColor(palette, value, peak),
          );
          if (outlined && value == 0) {
            canvas.drawRRect(rrect, outline);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.rows != rows ||
      old.peak != peak ||
      old.palette != palette ||
      old.outlined != outlined;
}
