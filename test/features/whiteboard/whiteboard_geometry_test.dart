import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';

import 'whiteboard_fakes.dart';

WhiteboardElement shape(
  String id,
  WhiteboardShape kind, {
  double x = 0,
  double y = 0,
  double w = 100,
  double h = 60,
  int? fill,
}) {
  return WhiteboardElement(
    id: id,
    kind: WhiteboardKind.shape,
    z: 'V',
    data: {
      's': kind.value,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'sw': 4,
      'c': 0xFF000000,
      'f': ?fill,
    },
  );
}

void main() {
  group('view', () {
    test('zooming keeps the point under the fingers where it is', () {
      const view = WhiteboardView(scale: 1, offset: Offset(20, 30));
      const focal = Offset(200, 150);
      final before = view.toBoard(focal);
      final zoomed = view.zoomed(2, focal);
      expect(zoomed.scale, 2);
      expect((zoomed.toBoard(focal) - before).distance, lessThan(0.001));
    });

    test('the scale stays between the limits', () {
      const view = WhiteboardView();
      expect(view.zoomed(1000, Offset.zero).scale, WhiteboardView.maxScale);
      expect(view.zoomed(0.0001, Offset.zero).scale, WhiteboardView.minScale);
    });

    test('fit shows all the content and never zooms past 100 percent', () {
      final view = WhiteboardView.fit(
        const Rect.fromLTWH(0, 0, 2000, 1000),
        const Size(400, 600),
      );
      final visible = view.visible(const Size(400, 600));
      expect(visible.contains(const Offset(0, 0)), isTrue);
      expect(visible.contains(const Offset(2000, 1000)), isTrue);
      final small = WhiteboardView.fit(
        const Rect.fromLTWH(0, 0, 10, 10),
        const Size(400, 600),
      );
      expect(small.scale, 1);
    });
  });

  group('culling', () {
    test('only elements that meet the visible part are returned', () {
      final elements = [
        sticky('near', x: 10, y: 10),
        sticky('far', x: 5000, y: 5000),
        stroke('line', points: const [0, 0, 50, 50]),
      ];
      final seen = elementsInView(elements, const Rect.fromLTWH(0, 0, 400, 600));
      expect(seen.map((e) => e.id), ['near', 'line']);
    });

    test('the union of bounds covers every element', () {
      final bounds = unionBounds([
        sticky('a', x: 0, y: 0),
        sticky('b', x: 500, y: 300),
      ])!;
      expect(bounds.left, lessThanOrEqualTo(0));
      expect(bounds.right, greaterThanOrEqualTo(660));
      expect(unionBounds(const []), isNull);
    });
  });

  group('hit testing', () {
    test('a stroke is hit near its line and not beside it', () {
      final line = stroke('l', points: const [0, 0, 100, 0], width: 4);
      expect(hitTestElement(line, const Offset(50, 3)), isTrue);
      expect(hitTestElement(line, const Offset(50, 40)), isFalse);
    });

    test('an empty shape is hit on its edge, a filled one inside', () {
      final empty = shape('e', WhiteboardShape.rect);
      final filled = shape('f', WhiteboardShape.rect, fill: 0xFFFF0000);
      expect(hitTestElement(empty, const Offset(50, 30), tolerance: 2), isFalse);
      expect(hitTestElement(empty, const Offset(50, 0), tolerance: 4), isTrue);
      expect(hitTestElement(filled, const Offset(50, 30)), isTrue);
    });

    test('a note is hit anywhere inside', () {
      final note = sticky('n', x: 100, y: 100);
      expect(hitTestElement(note, const Offset(150, 150)), isTrue);
      expect(hitTestElement(note, const Offset(20, 20)), isFalse);
    });

    test('a marquee takes a stroke only when it holds a point of it', () {
      final line = stroke('l', points: const [0, 0, 400, 0]);
      expect(
        elementInMarquee(line, const Rect.fromLTWH(100, -10, 50, 20)),
        isFalse,
      );
      expect(
        elementInMarquee(line, const Rect.fromLTWH(-10, -10, 50, 20)),
        isTrue,
      );
    });
  });

  group('strokes', () {
    test('a straight run of points shrinks to its ends', () {
      final points = [for (var i = 0; i <= 100; i++) Offset(i.toDouble(), 0)];
      final result = simplifyStroke(points, null);
      expect(result.points, [0, 0, 100, 0]);
    });

    test('a corner is kept and pressure follows the points that stay', () {
      final points = [
        for (var i = 0; i <= 50; i++) Offset(i.toDouble(), 0),
        for (var i = 1; i <= 50; i++) Offset(50, i.toDouble()),
      ];
      final pressures = [for (var i = 0; i < points.length; i++) i / 100];
      final result = simplifyStroke(points, pressures);
      expect(result.points.length, 6);
      expect(result.pressures!.length, 3);
      expect(result.pressures!.last, greaterThan(result.pressures!.first));
    });

    test('a dot becomes two equal points', () {
      final result = simplifyStroke(const [Offset(5, 5)], null);
      expect(result.points, [5, 5, 5, 5]);
    });

    test('a line over the limit is cut into pieces that share an end', () {
      final flat = [for (var i = 0; i < 5000; i++) ...[i.toDouble(), 0.0]];
      final pieces = splitStroke(flat, null, maxPoints: 2000);
      expect(pieces.length, 3);
      for (final piece in pieces) {
        expect(piece.points.length ~/ 2, lessThanOrEqualTo(2000));
      }
      expect(
        pieces[0].points.sublist(pieces[0].points.length - 2),
        pieces[1].points.sublist(0, 2),
      );
    });
  });

  group('moving and resizing', () {
    test('a stroke moves by its offset, a note by its corner', () {
      final moved = movedBy(stroke('l'), const Offset(10, 20));
      expect(moved.offsetX, 10);
      expect(moved.offsetY, 20);
      expect(moved.points, stroke('l').points);
      final note = movedBy(sticky('n', x: 5, y: 5), const Offset(1, 2));
      expect(note.x, 6);
      expect(note.y, 7);
    });

    test('nothing moves out of the board', () {
      final far = movedBy(sticky('n', x: 99990), const Offset(500000, 0));
      expect(far.x, lessThanOrEqualTo(WhiteboardLimits.maxCoordinate));
      expect(far.x, greaterThan(99000));
    });

    test('a picture keeps its proportions when a corner is dragged', () {
      final picture = WhiteboardElement(
        id: 'p',
        kind: WhiteboardKind.image,
        z: 'V',
        data: const {'x': 0, 'y': 0, 'w': 200.0, 'h': 100.0, 'path': 'b/p.png'},
      );
      final bigger = resizedBy(
        picture,
        WhiteboardHandle.bottomRight,
        const Offset(400, 400),
      );
      expect(bigger.w / bigger.h, closeTo(2, 0.01));
    });

    test('an arrow is resized by its end', () {
      final arrow = shape('a', WhiteboardShape.arrow, w: 100, h: 0);
      final longer = resizedBy(arrow, WhiteboardHandle.end, const Offset(150, 50));
      expect(longer.x, 0);
      expect(longer.w, 150);
      expect(longer.h, 50);
    });

    test('a box never shrinks below a size that can be grabbed', () {
      final note = sticky('n');
      final tiny = resizedBy(
        note,
        WhiteboardHandle.bottomRight,
        const Offset(1, 1),
      );
      expect(tiny.w, greaterThanOrEqualTo(40));
    });
  });
}
