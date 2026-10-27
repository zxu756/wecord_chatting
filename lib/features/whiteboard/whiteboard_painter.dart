import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_images.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';

// -------------------------------------------------------------- caches --
//
// Elements are immutable, so what is worked out for one (its outline, its
// laid-out text) is kept against the element object itself and goes away
// with it.

final _strokePaths = Expando<Path>('whiteboard stroke path');
final _textLayouts = Expando<TextPainter>('whiteboard text layout');

/// The outline of a stroke. A stroke from a pen with pressure is a filled
/// shape whose width follows the pressure; any other is a plain line.
Path strokePathOf(WhiteboardElement element) {
  final cached = _strokePaths[element];
  if (cached != null) {
    return cached;
  }
  final pts = element.points;
  final pressures = element.pressures;
  final path = Path();
  final count = pts.length ~/ 2;
  if (count == 0) {
    return _strokePaths[element] = path;
  }
  if (pressures == null || count < 2) {
    path.moveTo(pts[0], pts[1]);
    if (count == 1) {
      path.lineTo(pts[0], pts[1]);
    } else if (count == 2) {
      path.lineTo(pts[2], pts[3]);
    } else {
      // Smooth through the middle of each pair of points.
      for (var i = 1; i < count - 1; i++) {
        final midX = (pts[i * 2] + pts[i * 2 + 2]) / 2;
        final midY = (pts[i * 2 + 1] + pts[i * 2 + 3]) / 2;
        path.quadraticBezierTo(pts[i * 2], pts[i * 2 + 1], midX, midY);
      }
      path.lineTo(pts[(count - 1) * 2], pts[(count - 1) * 2 + 1]);
    }
    return _strokePaths[element] = path;
  }
  final base = element.strokeWidth;
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < count; i++) {
    final prev = i == 0 ? 0 : i - 1;
    final next = i == count - 1 ? count - 1 : i + 1;
    var dx = pts[next * 2] - pts[prev * 2];
    var dy = pts[next * 2 + 1] - pts[prev * 2 + 1];
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) {
      dx = 1;
      dy = 0;
    } else {
      dx /= length;
      dy /= length;
    }
    final p = i < pressures.length ? pressures[i] : 0.5;
    final radius = base * (0.2 + 0.8 * p) * 0.75;
    final center = Offset(pts[i * 2], pts[i * 2 + 1]);
    left.add(center + Offset(-dy * radius, dx * radius));
    right.add(center + Offset(dy * radius, -dx * radius));
  }
  path.moveTo(left.first.dx, left.first.dy);
  for (final p in left.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in right.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  // Round ends.
  for (final i in [0, count - 1]) {
    final p = i < pressures.length ? pressures[i] : 0.5;
    path.addOval(
      Rect.fromCircle(
        center: Offset(pts[i * 2], pts[i * 2 + 1]),
        radius: base * (0.2 + 0.8 * p) * 0.75,
      ),
    );
  }
  return _strokePaths[element] = path;
}

TextPainter _layoutText(
  WhiteboardElement element, {
  required double? width,
  required Color color,
  required double fontSize,
  required String text,
  int? maxLines,
}) {
  final cached = _textLayouts[element];
  if (cached != null) {
    return cached;
  }
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, height: 1.3),
    ),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '…',
  )..layout(maxWidth: width ?? WhiteboardLimits.maxCoordinate);
  return _textLayouts[element] = painter;
}

/// The size [text] takes at [fontSize], for the box a text element keeps.
Size measureWhiteboardText(String text, double fontSize, {double? maxWidth}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text.isEmpty ? ' ' : text,
      style: TextStyle(fontSize: fontSize, height: 1.3),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? 600);
  final size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}

// ------------------------------------------------------------- drawing --

/// Paints one element at its place on the board. [images] supplies the
/// pictures; [editing] leaves the words of a note out (a text field is shown
/// over them).
void paintWhiteboardElement(
  Canvas canvas,
  WhiteboardElement element, {
  WhiteboardImageStore? images,
  bool editing = false,
  double scale = 1,
}) {
  switch (element.kind) {
    case WhiteboardKind.stroke:
      _paintStroke(canvas, element);
    case WhiteboardKind.shape:
      _paintShape(canvas, element);
    case WhiteboardKind.sticky:
      _paintSticky(canvas, element, editing: editing);
    case WhiteboardKind.text:
      _paintText(canvas, element, editing: editing);
    case WhiteboardKind.image:
      _paintImage(canvas, element, images);
  }
}

void _paintStroke(Canvas canvas, WhiteboardElement element) {
  final color = Color(element.color);
  final highlighter = element.highlighter;
  canvas.save();
  canvas.translate(element.offsetX, element.offsetY);
  final path = strokePathOf(element);
  if (element.pressures != null && element.points.length >= 4) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  } else {
    final pts = element.points;
    final paint = Paint()
      ..color = highlighter ? color.withValues(alpha: 0.38) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = element.strokeWidth
      ..strokeCap = highlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (pts.length >= 4 &&
        pts.length == 4 &&
        pts[0] == pts[2] &&
        pts[1] == pts[3]) {
      // A dot.
      canvas.drawCircle(
        Offset(pts[0], pts[1]),
        element.strokeWidth / 2,
        Paint()..color = paint.color,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }
  canvas.restore();
}

Paint _linePaint(WhiteboardElement element) => Paint()
  ..color = Color(element.color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = element.strokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void _paintShape(Canvas canvas, WhiteboardElement element) {
  final line = _linePaint(element);
  final shape = element.shape;
  if (shape.isSegment) {
    final a = Offset(element.x, element.y);
    final b = Offset(element.x + element.w, element.y + element.h);
    canvas.drawLine(a, b, line);
    if (shape == WhiteboardShape.arrow && (b - a).distance > 0) {
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final head = element.strokeWidth * 3 + 6;
      for (final side in [-1.0, 1.0]) {
        final tip = b - Offset(
          math.cos(angle + side * 0.45) * head,
          math.sin(angle + side * 0.45) * head,
        );
        canvas.drawLine(b, tip, line);
      }
    }
    return;
  }
  final box = element.box;
  canvas.save();
  if (element.rotation != 0) {
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(element.rotation);
    canvas.translate(-box.center.dx, -box.center.dy);
  }
  final fill = element.fill;
  final fillPaint = fill == null
      ? null
      : (Paint()
          ..color = Color(fill).withValues(alpha: 0.22)
          ..style = PaintingStyle.fill);
  switch (shape) {
    case WhiteboardShape.rect:
      if (fillPaint != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          fillPaint,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        line,
      );
    case WhiteboardShape.ellipse:
      if (fillPaint != null) {
        canvas.drawOval(box, fillPaint);
      }
      canvas.drawOval(box, line);
    case WhiteboardShape.triangle:
    case WhiteboardShape.diamond:
      final corners = shapeCorners(shape, box);
      final path = Path()..moveTo(corners.first.dx, corners.first.dy);
      for (final c in corners.skip(1)) {
        path.lineTo(c.dx, c.dy);
      }
      path.close();
      if (fillPaint != null) {
        canvas.drawPath(path, fillPaint);
      }
      canvas.drawPath(path, line);
    case WhiteboardShape.line:
    case WhiteboardShape.arrow:
      break;
  }
  canvas.restore();
}

void _paintSticky(Canvas canvas, WhiteboardElement element, {required bool editing}) {
  final box = element.box;
  canvas.save();
  if (element.rotation != 0) {
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(element.rotation);
    canvas.translate(-box.center.dx, -box.center.dy);
  }
  final rrect = RRect.fromRectAndRadius(box, const Radius.circular(6));
  canvas.drawRRect(
    rrect.shift(const Offset(0, 2)),
    Paint()..color = const Color(0x26000000),
  );
  canvas.drawRRect(rrect, Paint()..color = Color(element.color));
  if (!editing && element.text.isNotEmpty) {
    final painter = _layoutText(
      element,
      width: math.max(10, box.width - 20),
      color: const Color(0xFF1B1B1F),
      fontSize: element.number('fs', 18),
      text: element.text,
    );
    canvas.save();
    canvas.clipRect(box.deflate(2));
    painter.paint(canvas, box.topLeft + const Offset(10, 8));
    canvas.restore();
  }
  canvas.restore();
}

void _paintText(Canvas canvas, WhiteboardElement element, {required bool editing}) {
  if (editing || element.text.isEmpty) {
    return;
  }
  final width = element.number('w', 0) > 0 ? element.w : null;
  final painter = _layoutText(
    element,
    width: width,
    color: Color(element.color),
    fontSize: element.fontSize,
    text: element.text,
  );
  canvas.save();
  if (element.rotation != 0) {
    final box = element.box;
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(element.rotation);
    canvas.translate(-box.center.dx, -box.center.dy);
  }
  painter.paint(canvas, Offset(element.x, element.y));
  canvas.restore();
}

void _paintImage(Canvas canvas, WhiteboardElement element, WhiteboardImageStore? images) {
  final box = element.box;
  final image = images?.imageFor(element.path);
  if (image == null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xFFE3E4E8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFFB9BBC6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    return;
  }
  canvas.save();
  if (element.rotation != 0) {
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(element.rotation);
    canvas.translate(-box.center.dx, -box.center.dy);
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    box,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true,
  );
  canvas.restore();
}

// -------------------------------------------------------------- painter --

/// Colors the painter needs, from the app's theme.
class WhiteboardPalette {
  const WhiteboardPalette({
    required this.background,
    required this.grid,
    required this.selection,
    required this.handleFill,
    required this.label,
  });

  final Color background;
  final Color grid;
  final Color selection;
  final Color handleFill;
  final Color label;
}

/// Draws the board: only what meets the visible part of it.
class WhiteboardPainter extends CustomPainter {
  WhiteboardPainter({
    required this.controller,
    required this.palette,
    this.showGrid = true,
  }) : super(repaint: controller);

  final WhiteboardController controller;
  final WhiteboardPalette palette;
  final bool showGrid;

  /// How many elements the last paint drew (tests read this to see that
  /// what is off screen is skipped).
  int lastDrawnCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final view = controller.view;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    if (showGrid) {
      _paintGrid(canvas, size, view);
    }
    canvas.save();
    canvas.translate(view.offset.dx, view.offset.dy);
    canvas.scale(view.scale);

    final visible = view.visible(size).inflate(8 / view.scale);
    final inView = elementsInView(controller.engine.elements, visible);
    final minSize = 0.75 / view.scale;
    var drawn = 0;
    for (final element in inView) {
      final b = element.bounds;
      // Too small to see at this zoom: skipped.
      if (b.width < minSize && b.height < minSize) {
        continue;
      }
      paintWhiteboardElement(
        canvas,
        element,
        images: controller.images,
        editing: controller.editingId == element.id,
        scale: view.scale,
      );
      drawn++;
    }
    lastDrawnCount = drawn;

    _paintDrafts(canvas);
    _paintSelection(canvas, view);
    _paintMarquee(canvas, view);
    canvas.restore();
    _paintPeers(canvas, view, size);
  }

  void _paintDrafts(Canvas canvas) {
    final ink = controller.ink;
    if (ink != null && ink.points.isNotEmpty) {
      final flat = ink.flat;
      final path = Path()..moveTo(flat[0], flat[1]);
      if (flat.length == 2) {
        path.lineTo(flat[0], flat[1]);
      }
      for (var i = 2; i + 1 < flat.length; i += 2) {
        path.lineTo(flat[i], flat[i + 1]);
      }
      final color = Color(ink.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = ink.highlighter ? color.withValues(alpha: 0.38) : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ink.width
          ..strokeCap = ink.highlighter ? StrokeCap.butt : StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
    final shape = controller.shapeDraft;
    if (shape != null) {
      paintWhiteboardElement(canvas, shape);
    }
    for (final live in controller.liveStrokes.values) {
      if (live.points.length < 2) {
        continue;
      }
      final path = Path()..moveTo(live.points[0], live.points[1]);
      for (var i = 2; i + 1 < live.points.length; i += 2) {
        path.lineTo(live.points[i], live.points[i + 1]);
      }
      final color = Color(live.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = (live.highlighter ? color.withValues(alpha: 0.38) : color)
              .withValues(alpha: live.highlighter ? 0.38 : 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = live.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _paintSelection(Canvas canvas, WhiteboardView view) {
    final selected = controller.selectedElements;
    if (selected.isEmpty) {
      return;
    }
    final line = Paint()
      ..color = palette.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / view.scale;
    for (final element in selected) {
      final box = element.kind == WhiteboardKind.stroke
          ? element.bounds
          : element.bounds.inflate(3 / view.scale);
      canvas.drawRect(box, line);
    }
    if (selected.length == 1 && controller.canEdit) {
      final handles = handlesOf(selected.first);
      final radius = 6 / view.scale;
      for (final point in handles.values) {
        canvas.drawCircle(point, radius, Paint()..color = palette.handleFill);
        canvas.drawCircle(point, radius, line);
      }
    }
  }

  void _paintMarquee(Canvas canvas, WhiteboardView view) {
    final rect = controller.marquee;
    if (rect == null) {
      return;
    }
    canvas.drawRect(
      rect,
      Paint()..color = palette.selection.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = palette.selection
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / view.scale,
    );
  }

  void _paintPeers(Canvas canvas, WhiteboardView view, Size size) {
    for (final entry in controller.pointers.entries) {
      final peer = controller.peers
          .where((p) => p.userId == entry.key)
          .firstOrNull;
      if (peer == null) {
        continue;
      }
      final at = view.toScreen(entry.value.at);
      if (!(Offset.zero & size).inflate(40).contains(at)) {
        continue;
      }
      final color = Color(peer.color);
      final cursor = Path()
        ..moveTo(at.dx, at.dy)
        ..lineTo(at.dx + 4, at.dy + 16)
        ..lineTo(at.dx + 8, at.dy + 11)
        ..lineTo(at.dx + 15, at.dy + 11)
        ..close();
      canvas.drawPath(cursor, Paint()..color = color);
      final label = TextPainter(
        text: TextSpan(
          text: peer.name,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      final rect = Rect.fromLTWH(
        at.dx + 10,
        at.dy + 16,
        label.width + 10,
        label.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = color,
      );
      label.paint(canvas, rect.topLeft + const Offset(5, 2));
      label.dispose();
    }
  }

  void _paintGrid(Canvas canvas, Size size, WhiteboardView view) {
    var spacing = 32.0 * view.scale;
    // Thin the dots out when zoomed far away so they stay a calm texture.
    while (spacing < 14) {
      spacing *= 2;
    }
    if (spacing > 400) {
      return;
    }
    final paint = Paint()
      ..color = palette.grid
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final startX = view.offset.dx % spacing;
    final startY = view.offset.dy % spacing;
    final points = <Offset>[];
    for (var x = startX; x < size.width; x += spacing) {
      for (var y = startY; y < size.height; y += spacing) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(WhiteboardPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.palette != palette ||
        oldDelegate.showGrid != showGrid;
  }
}
