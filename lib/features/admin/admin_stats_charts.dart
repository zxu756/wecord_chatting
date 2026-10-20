import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// A small line of one number per day. Drawn by hand like the circle
/// Insights charts (a charting package is not worth three charts), with the
/// colors of the tokens, so light, dark and the high contrast sets all work.
/// [summary] is what a screen reader says for the chart.
class OpsLineChart extends StatelessWidget {
  const OpsLineChart({
    required this.values,
    required this.color,
    required this.fill,
    required this.summary,
    this.height = 120,
    super.key,
  });

  final List<int> values;
  final Color color;
  final Color fill;
  final String summary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final high = values.isEmpty ? 0 : values.reduce(math.max);
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
                  painter: _OpsLinePainter(
                    values: values,
                    line: color,
                    fill: fill,
                    grid: c.lineSoft,
                    halo: c.panel,
                  ),
                ),
              ),
              if (values.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.panel.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        '$high',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.subtle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpsLinePainter extends CustomPainter {
  _OpsLinePainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.grid,
    required this.halo,
  });

  final List<int> values;
  final Color line;
  final Color fill;
  final Color grid;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 14.0;
    const bottom = 4.0;
    final height = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) {
      return;
    }
    // The line starts at zero, so a quiet day looks quiet.
    final high = math.max(values.reduce(math.max), 1).toDouble();
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    Offset point(int i) {
      final y = top + height * (1 - values[i] / high);
      return Offset(values.length <= 1 ? size.width / 2 : step * i, y);
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    if (values.length > 1) {
      final area = Path.from(path)
        ..lineTo(point(values.length - 1).dx, size.height - bottom)
        ..lineTo(point(0).dx, size.height - bottom)
        ..close();
      canvas
        ..drawPath(
          area,
          Paint()
            ..color = fill.withValues(alpha: 0.7)
            ..style = PaintingStyle.fill,
        )
        ..drawPath(
          path,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
    final end = point(values.length - 1);
    canvas
      ..drawCircle(end, 6, Paint()..color = halo)
      ..drawCircle(end, 4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_OpsLinePainter old) =>
      old.values != values ||
      old.line != line ||
      old.fill != fill ||
      old.grid != grid ||
      old.halo != halo;
}
