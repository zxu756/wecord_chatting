import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:wecord/features/whiteboard/whiteboard_models.dart';

/// The maths of the whiteboard: where the view is, what a point touches and
/// how a drawn line is kept small. Nothing here knows about widgets, so it is
/// tested on its own.

/// Rounds to one decimal (what is stored; a tenth of a point is below what a
/// screen can show).
double round1(double value) => (value * 10).roundToDouble() / 10;

double clampCoordinate(double value) => value.clamp(
  -WhiteboardLimits.maxCoordinate + 1,
  WhiteboardLimits.maxCoordinate - 1,
);

/// Where the view of the board is: [scale] screen pixels per board unit, and
/// [offset] the screen position of the board's origin.
class WhiteboardView {
  const WhiteboardView({this.scale = 1, this.offset = Offset.zero});

  static const minScale = 0.05;
  static const maxScale = 8.0;

  final double scale;
  final Offset offset;

  Offset toBoard(Offset screen) => (screen - offset) / scale;
  Offset toScreen(Offset board) => board * scale + offset;

  /// The part of the board a screen of [size] shows.
  Rect visible(Size size) =>
      Rect.fromLTWH(-offset.dx / scale, -offset.dy / scale, size.width / scale, size.height / scale);

  WhiteboardView panned(Offset delta) =>
      WhiteboardView(scale: scale, offset: offset + delta);

  /// Zoomed by [factor] around the screen point [focal], which stays put.
  WhiteboardView zoomed(double factor, Offset focal) {
    final next = (scale * factor).clamp(minScale, maxScale);
    final real = next / scale;
    return WhiteboardView(
      scale: next,
      offset: focal - (focal - offset) * real,
    );
  }

  /// A view that shows all of [content] inside a screen of [size], with
  /// [padding] around it and no more than 100%.
  static WhiteboardView fit(Rect content, Size size, {double padding = 48}) {
    if (content.isEmpty && content.width == 0 && content.height == 0) {
      return WhiteboardView(offset: Offset(size.width / 2, size.height / 2));
    }
    final availableW = math.max(1.0, size.width - padding * 2);
    final availableH = math.max(1.0, size.height - padding * 2);
    final scale = math
        .min(
          availableW / math.max(content.width, 1),
          availableH / math.max(content.height, 1),
        )
        .clamp(minScale, 1.0);
    return WhiteboardView(
      scale: scale,
      offset: Offset(
        size.width / 2 - content.center.dx * scale,
        size.height / 2 - content.center.dy * scale,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WhiteboardView && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

/// The elements whose box meets [area] (the part of the board on screen),
/// in drawing order. Everything else is not drawn at all.
List<WhiteboardElement> elementsInView(
  List<WhiteboardElement> ordered,
  Rect area,
) {
  final out = <WhiteboardElement>[];
  for (final element in ordered) {
    if (element.bounds.overlaps(area)) {
      out.add(element);
    }
  }
  return out;
}

/// The box around all of [elements]; null for none.
Rect? unionBounds(Iterable<WhiteboardElement> elements) {
  Rect? result;
  for (final element in elements) {
    result = result == null
        ? element.bounds
        : result.expandToInclude(element.bounds);
  }
  return result;
}

// ------------------------------------------------------------ hit testing --

double distanceToSegment(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return (p - a).distance;
  }
  final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
}

/// Whether [point] (board units) touches [element], give or take
/// [tolerance]. A filled shape, a sticky note, a text and a picture are hit
/// anywhere inside; a line, an arrow, a stroke and an unfilled shape only
/// near their line.
bool hitTestElement(
  WhiteboardElement element,
  Offset point, {
  double tolerance = 6,
}) {
  if (!element.bounds.inflate(tolerance).contains(point)) {
    return false;
  }
  switch (element.kind) {
    case WhiteboardKind.stroke:
      final pts = element.points;
      final ox = element.offsetX;
      final oy = element.offsetY;
      final reach = tolerance + element.strokeWidth / 2;
      if (pts.length < 4) {
        if (pts.length < 2) {
          return false;
        }
        return (point - Offset(pts[0] + ox, pts[1] + oy)).distance <= reach;
      }
      for (var i = 0; i + 3 < pts.length; i += 2) {
        if (distanceToSegment(
              point,
              Offset(pts[i] + ox, pts[i + 1] + oy),
              Offset(pts[i + 2] + ox, pts[i + 3] + oy),
            ) <=
            reach) {
          return true;
        }
      }
      return false;
    case WhiteboardKind.shape:
      return _hitShape(element, point, tolerance);
    case WhiteboardKind.sticky:
    case WhiteboardKind.text:
    case WhiteboardKind.image:
      final local = _unrotate(element, point);
      return element.box.inflate(tolerance).contains(local);
  }
}

Offset _unrotate(WhiteboardElement element, Offset point) {
  final angle = element.rotation;
  if (angle == 0) {
    return point;
  }
  final center = element.box.center;
  final cosine = math.cos(-angle);
  final sine = math.sin(-angle);
  final d = point - center;
  return Offset(
    center.dx + d.dx * cosine - d.dy * sine,
    center.dy + d.dx * sine + d.dy * cosine,
  );
}

bool _hitShape(WhiteboardElement element, Offset point, double tolerance) {
  final shape = element.shape;
  final reach = tolerance + element.strokeWidth / 2;
  if (shape.isSegment) {
    return distanceToSegment(
          point,
          Offset(element.x, element.y),
          Offset(element.x + element.w, element.y + element.h),
        ) <=
        reach;
  }
  final local = _unrotate(element, point);
  final box = element.box;
  final filled = element.fill != null && (element.fill! >> 24) > 0;
  switch (shape) {
    case WhiteboardShape.rect:
      if (filled) {
        return box.inflate(reach).contains(local);
      }
      return box.inflate(reach).contains(local) &&
          !box.deflate(reach).contains(local);
    case WhiteboardShape.ellipse:
      final rx = box.width / 2 + reach;
      final ry = box.height / 2 + reach;
      final dx = (local.dx - box.center.dx) / math.max(rx, 0.001);
      final dy = (local.dy - box.center.dy) / math.max(ry, 0.001);
      final outer = dx * dx + dy * dy <= 1;
      if (filled) {
        return outer;
      }
      final irx = box.width / 2 - reach;
      final iry = box.height / 2 - reach;
      if (irx <= 0 || iry <= 0) {
        return outer;
      }
      final ix = (local.dx - box.center.dx) / irx;
      final iy = (local.dy - box.center.dy) / iry;
      return outer && ix * ix + iy * iy >= 1;
    case WhiteboardShape.triangle:
    case WhiteboardShape.diamond:
      final corners = shapeCorners(shape, box);
      if (filled && _insidePolygon(local, corners)) {
        return true;
      }
      for (var i = 0; i < corners.length; i++) {
        if (distanceToSegment(local, corners[i], corners[(i + 1) % corners.length]) <=
            reach) {
          return true;
        }
      }
      return false;
    case WhiteboardShape.line:
    case WhiteboardShape.arrow:
      return false;
  }
}

/// The corners of a triangle (apex on top) or a diamond in [box].
List<Offset> shapeCorners(WhiteboardShape shape, Rect box) {
  if (shape == WhiteboardShape.triangle) {
    return [box.topCenter, box.bottomRight, box.bottomLeft];
  }
  return [box.topCenter, box.centerRight, box.bottomCenter, box.centerLeft];
}

bool _insidePolygon(Offset p, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Whether [element] is touched by the rectangle [area] (a marquee):
/// anything whose box meets it, except a stroke, which must have a point in
/// it (a long line is not picked by a box that only crosses its corner).
bool elementInMarquee(WhiteboardElement element, Rect area) {
  if (!element.bounds.overlaps(area)) {
    return false;
  }
  if (element.kind != WhiteboardKind.stroke) {
    return true;
  }
  final pts = element.points;
  final ox = element.offsetX;
  final oy = element.offsetY;
  for (var i = 0; i + 1 < pts.length; i += 2) {
    if (area.contains(Offset(pts[i] + ox, pts[i + 1] + oy))) {
      return true;
    }
  }
  return false;
}

// ----------------------------------------------------------------- strokes --

/// A drawn line kept small: points that lie within [tolerance] of the line
/// between their neighbours are dropped (Ramer-Douglas-Peucker), and what is
/// left is rounded to a tenth. [pressures] (0 to 1 per point) follow the
/// points that stay. A line with more than [maxPoints] left is thinned
/// further, never cut.
({List<double> points, List<int>? pressures}) simplifyStroke(
  List<Offset> points,
  List<double>? pressures, {
  double tolerance = 0.6,
  int maxPoints = WhiteboardLimits.maxStrokePoints,
}) {
  if (points.isEmpty) {
    return (points: const [], pressures: null);
  }
  var kept = _douglasPeucker(points, tolerance);
  var widen = tolerance;
  while (kept.length > maxPoints && widen < 200) {
    widen *= 1.6;
    kept = _douglasPeucker(points, widen);
  }
  final flat = <double>[];
  final pr = pressures == null ? null : <int>[];
  for (final index in kept) {
    flat
      ..add(round1(clampCoordinate(points[index].dx)))
      ..add(round1(clampCoordinate(points[index].dy)));
    if (pr != null) {
      final value = index < pressures!.length ? pressures[index] : 0.5;
      pr.add((value.clamp(0.0, 1.0) * 100).round());
    }
  }
  if (flat.length == 2) {
    // A dot: two points on the same spot draw a round dot.
    flat.addAll([flat[0], flat[1]]);
    pr?.add(pr.first);
  }
  return (points: flat, pressures: pr);
}

/// The indices of the points Ramer-Douglas-Peucker keeps (iterative, so a
/// long line cannot overflow the stack).
List<int> _douglasPeucker(List<Offset> points, double tolerance) {
  final n = points.length;
  if (n <= 2) {
    return [for (var i = 0; i < n; i++) i];
  }
  final keep = Uint8List(n)
    ..[0] = 1
    ..[n - 1] = 1;
  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    var farthest = -1.0;
    var index = -1;
    for (var i = first + 1; i < last; i++) {
      final d = distanceToSegment(points[i], points[first], points[last]);
      if (d > farthest) {
        farthest = d;
        index = i;
      }
    }
    if (farthest > tolerance && index > 0) {
      keep[index] = 1;
      stack
        ..add((first, index))
        ..add((index, last));
    }
  }
  return [
    for (var i = 0; i < n; i++)
      if (keep[i] == 1) i,
  ];
}

/// A long line cut into pieces of at most [maxPoints] points that share their
/// joining point, so each piece fits in one element.
List<({List<double> points, List<int>? pressures})> splitStroke(
  List<double> flat,
  List<int>? pressures, {
  int maxPoints = WhiteboardLimits.maxStrokePoints,
}) {
  final count = flat.length ~/ 2;
  if (count <= maxPoints) {
    return [(points: flat, pressures: pressures)];
  }
  final pieces = <({List<double> points, List<int>? pressures})>[];
  var start = 0;
  while (start < count - 1) {
    final end = math.min(count, start + maxPoints);
    pieces.add((
      points: flat.sublist(start * 2, end * 2),
      pressures: pressures?.sublist(start, end),
    ));
    start = end - 1;
  }
  return pieces;
}

// ------------------------------------------------------------------- moves --

/// [element] moved by [delta]. A stroke keeps its points and moves its
/// offset; the others move their corner. Kept inside the board.
WhiteboardElement movedBy(WhiteboardElement element, Offset delta) {
  if (delta == Offset.zero) {
    return element;
  }
  if (element.kind == WhiteboardKind.stroke) {
    return element.withData({
      'ox': round1(clampCoordinate(element.offsetX + delta.dx)),
      'oy': round1(clampCoordinate(element.offsetY + delta.dy)),
    });
  }
  return element.withData({
    'x': round1(clampCoordinate(element.x + delta.dx)),
    'y': round1(clampCoordinate(element.y + delta.dy)),
  });
}

/// Which end or corner of an element a handle drags.
enum WhiteboardHandle { topLeft, topRight, bottomLeft, bottomRight, start, end }

/// The handles an element offers when it is the only thing selected, with
/// their positions on the board.
Map<WhiteboardHandle, Offset> handlesOf(WhiteboardElement element) {
  if (element.kind == WhiteboardKind.stroke) {
    return const {};
  }
  if (element.kind == WhiteboardKind.shape && element.shape.isSegment) {
    return {
      WhiteboardHandle.start: Offset(element.x, element.y),
      WhiteboardHandle.end: Offset(element.x + element.w, element.y + element.h),
    };
  }
  final box = element.box;
  return {
    WhiteboardHandle.topLeft: box.topLeft,
    WhiteboardHandle.topRight: box.topRight,
    WhiteboardHandle.bottomLeft: box.bottomLeft,
    WhiteboardHandle.bottomRight: box.bottomRight,
  };
}

/// [element] with [handle] dragged to [to] (board units). A box keeps its
/// opposite corner; a picture keeps its proportions; sizes have a floor.
WhiteboardElement resizedBy(
  WhiteboardElement element,
  WhiteboardHandle handle,
  Offset to,
) {
  final target = Offset(
    round1(clampCoordinate(to.dx)),
    round1(clampCoordinate(to.dy)),
  );
  if (element.kind == WhiteboardKind.shape && element.shape.isSegment) {
    final start = Offset(element.x, element.y);
    final end = Offset(element.x + element.w, element.y + element.h);
    final a = handle == WhiteboardHandle.start ? target : start;
    final b = handle == WhiteboardHandle.end ? target : end;
    return element.withData({
      'x': a.dx,
      'y': a.dy,
      'w': round1(b.dx - a.dx),
      'h': round1(b.dy - a.dy),
    });
  }
  final box = element.box;
  final fixed = switch (handle) {
    WhiteboardHandle.topLeft => box.bottomRight,
    WhiteboardHandle.topRight => box.bottomLeft,
    WhiteboardHandle.bottomLeft => box.topRight,
    _ => box.topLeft,
  };
  final minSize = switch (element.kind) {
    WhiteboardKind.sticky => 40.0,
    WhiteboardKind.image => 16.0,
    WhiteboardKind.text => 24.0,
    _ => 4.0,
  };
  var width = math.max(minSize, (target.dx - fixed.dx).abs());
  var height = math.max(minSize, (target.dy - fixed.dy).abs());
  if (element.kind == WhiteboardKind.image && box.width > 0 && box.height > 0) {
    final ratio = box.width / box.height;
    if (width / height > ratio) {
      width = height * ratio;
    } else {
      height = width / ratio;
    }
  }
  final left = target.dx < fixed.dx ? fixed.dx - width : fixed.dx;
  final top = target.dy < fixed.dy ? fixed.dy - height : fixed.dy;
  if (element.kind == WhiteboardKind.text) {
    // A text keeps its height from its words: only the width is dragged.
    return element.withData({
      'x': round1(left),
      'y': round1(top),
      'w': round1(width),
      'h': null,
    });
  }
  return element.withData({
    'x': round1(left),
    'y': round1(top),
    'w': round1(width),
    'h': round1(height),
  });
}
