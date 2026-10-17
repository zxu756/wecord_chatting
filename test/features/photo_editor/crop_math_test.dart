import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/crop_math.dart';

void main() {
  group('turning', () {
    test('a quarter turn swaps the sides', () {
      expect(rotatedSize(const Size(300, 200), 0), const Size(300, 200));
      expect(rotatedSize(const Size(300, 200), 1), const Size(200, 300));
      expect(rotatedSize(const Size(300, 200), 2), const Size(300, 200));
      expect(rotatedSize(const Size(300, 200), 3), const Size(200, 300));
    });

    test('the matrix turns the corners clockwise', () {
      const source = Size(300, 200);
      // Top-left of the picture moves to the top-right after one turn.
      expect(
        transformPoint(sourceToRotated(source, 1), Offset.zero),
        const Offset(200, 0),
      );
      // Its top-right corner goes to the bottom-right.
      expect(
        transformPoint(sourceToRotated(source, 1), const Offset(300, 0)),
        const Offset(200, 300),
      );
      expect(
        transformPoint(sourceToRotated(source, 2), Offset.zero),
        const Offset(300, 200),
      );
      expect(
        transformPoint(sourceToRotated(source, 3), Offset.zero),
        const Offset(0, 300),
      );
      expect(
        transformPoint(sourceToRotated(source, 4), const Offset(7, 9)),
        const Offset(7, 9),
      );
    });

    test('four quarter turns bring a crop back', () {
      var size = const Size(300, 200);
      var crop = const Rect.fromLTRB(20, 30, 120, 90);
      final original = crop;
      for (var i = 0; i < 4; i++) {
        crop = rotateRectClockwise(crop, size);
        size = Size(size.height, size.width);
      }
      expect(crop, original);
    });

    test('a crop turns with the same matrix as the picture', () {
      const source = Size(300, 200);
      const crop = Rect.fromLTRB(20, 30, 120, 90);
      final matrix = sourceToRotated(source, 1);
      final a = transformPoint(matrix, crop.topLeft);
      final b = transformPoint(matrix, crop.bottomRight);
      expect(rotateRectClockwise(crop, source), Rect.fromPoints(a, b));
    });
  });

  group('output size', () {
    test('keeps a small picture as it is', () {
      expect(outputSize(const Size(800, 600), 2560), const Size(800, 600));
    });

    test('scales a big one to the longest side', () {
      expect(outputSize(const Size(4000, 3000), 2000), const Size(2000, 1500));
      expect(outputSize(const Size(3000, 4000), 2000), const Size(1500, 2000));
    });

    test('never makes a side zero', () {
      final size = outputSize(const Size(10000, 1), 100);
      expect(size.width, 100);
      expect(size.height, 1);
    });
  });

  group('ratios', () {
    test('landscape and portrait', () {
      expect(CropRatio.free.aspect(), isNull);
      expect(CropRatio.square.aspect(), 1);
      expect(CropRatio.fourThree.aspect(), closeTo(4 / 3, 1e-9));
      expect(CropRatio.fourThree.aspect(portrait: true), closeTo(3 / 4, 1e-9));
      expect(CropRatio.sixteenNine.aspect(), closeTo(16 / 9, 1e-9));
    });

    test('fitAspect gives the biggest centered rectangle', () {
      const within = Rect.fromLTWH(0, 0, 400, 300);
      final wide = fitAspect(within, 16 / 9);
      expect(wide.width, 400);
      expect(wide.height, closeTo(225, 1e-9));
      expect(wide.center, within.center);
      final square = fitAspect(within, 1);
      expect(square.size, const Size(300, 300));
      final tall = fitAspect(within, 3 / 4);
      expect(tall.height, 300);
      expect(tall.width, closeTo(225, 1e-9));
    });
  });

  group('dragging the crop', () {
    const bounds = Rect.fromLTWH(0, 0, 400, 300);
    const start = Rect.fromLTRB(100, 80, 300, 220);

    test('moves, staying inside', () {
      expect(
        dragCrop(start, CropHandle.move, const Offset(20, 10), bounds),
        start.shift(const Offset(20, 10)),
      );
      final far = dragCrop(
        start,
        CropHandle.move,
        const Offset(900, 900),
        bounds,
      );
      expect(far.right, 400);
      expect(far.bottom, 300);
      expect(far.size, start.size);
    });

    test('a free corner follows the drag', () {
      final r = dragCrop(
        start,
        CropHandle.topLeft,
        const Offset(-30, 10),
        bounds,
      );
      expect(r, const Rect.fromLTRB(70, 90, 300, 220));
    });

    test('an edge moves only that edge', () {
      final r = dragCrop(start, CropHandle.right, const Offset(50, 99), bounds);
      expect(r, const Rect.fromLTRB(100, 80, 350, 220));
    });

    test('stops at the bounds and at the smallest size', () {
      final out = dragCrop(
        start,
        CropHandle.bottomRight,
        const Offset(500, 500),
        bounds,
      );
      expect(out.right, 400);
      expect(out.bottom, 300);
      final tiny = dragCrop(
        start,
        CropHandle.bottomRight,
        const Offset(-500, -500),
        bounds,
        minSize: 40,
      );
      expect(tiny.width, 40);
      expect(tiny.height, 40);
      expect(tiny.topLeft, start.topLeft);
    });

    test('a fixed ratio is kept by every handle', () {
      const aspect = 16 / 9;
      final base = fitAspect(const Rect.fromLTWH(50, 40, 300, 200), aspect);
      for (final handle in CropHandle.values) {
        if (handle == CropHandle.move) continue;
        for (final delta in const [
          Offset(-30, -20),
          Offset(25, 40),
          Offset(-200, 150),
          Offset(300, -300),
        ]) {
          final r = dragCrop(base, handle, delta, bounds, aspect: aspect);
          final why = '$handle $delta';
          expect(r.width / r.height, closeTo(aspect, 1e-6), reason: why);
          expect(r.left, greaterThanOrEqualTo(-1e-6), reason: why);
          expect(r.top, greaterThanOrEqualTo(-1e-6), reason: why);
          expect(r.right, lessThanOrEqualTo(400 + 1e-6), reason: why);
          expect(r.bottom, lessThanOrEqualTo(300 + 1e-6), reason: why);
        }
      }
    });

    test('a corner with a ratio keeps the opposite corner still', () {
      const square = Rect.fromLTRB(100, 100, 200, 200);
      final r = dragCrop(
        square,
        CropHandle.bottomRight,
        const Offset(40, 10),
        bounds,
        aspect: 1,
      );
      expect(r.topLeft, square.topLeft);
      expect(r.width, r.height);
      expect(r.width, 140);
    });

    test('finds the handle under a point', () {
      const rect = Rect.fromLTRB(100, 100, 300, 250);
      expect(cropHandleAt(rect, const Offset(102, 98)), CropHandle.topLeft);
      expect(
        cropHandleAt(rect, const Offset(298, 252)),
        CropHandle.bottomRight,
      );
      expect(cropHandleAt(rect, const Offset(200, 101)), CropHandle.top);
      expect(cropHandleAt(rect, const Offset(299, 175)), CropHandle.right);
      expect(cropHandleAt(rect, const Offset(200, 175)), CropHandle.move);
      expect(cropHandleAt(rect, const Offset(20, 20)), isNull);
    });

    test('clampRect keeps a rectangle inside', () {
      expect(
        clampRect(const Rect.fromLTWH(350, 250, 100, 100), bounds),
        const Rect.fromLTWH(300, 200, 100, 100),
      );
    });
  });

  group('view fit', () {
    const view = Size(400, 800);
    const region = Rect.fromLTWH(0, 0, 200, 200);

    test('fits and centres the region', () {
      const fit = ViewFit(view: view, region: region);
      expect(fit.scale, 2);
      expect(fit.regionInView, const Rect.fromLTWH(0, 200, 400, 400));
    });

    test('maps back and forth', () {
      const fit = ViewFit(
        view: view,
        region: Rect.fromLTWH(20, 10, 160, 120),
        zoom: 2.5,
        pan: Offset(30, -12),
      );
      for (final p in const [Offset(0, 0), Offset(50, 70), Offset(199, 133)]) {
        final back = fit.toTurned(fit.toView(p));
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
      }
      final viaMatrix = transformPoint(fit.turnedToView, const Offset(50, 70));
      final direct = fit.toView(const Offset(50, 70));
      expect(viaMatrix.dx, closeTo(direct.dx, 1e-9));
      expect(viaMatrix.dy, closeTo(direct.dy, 1e-9));
    });

    test('zooming about a point keeps that point still', () {
      const fit = ViewFit(view: view, region: region);
      const focal = Offset(300, 350);
      final turned = fit.toTurned(focal);
      final zoomed = fit.zoomedAbout(focal, 3);
      expect(zoomed.zoom, 3);
      final after = zoomed.toView(turned);
      expect(after.dx, closeTo(focal.dx, 1e-6));
      expect(after.dy, closeTo(focal.dy, 1e-6));
    });

    test('zoom stays between fit and the maximum', () {
      const fit = ViewFit(view: view, region: region);
      expect(fit.zoomedAbout(Offset.zero, 0.2).zoom, 1);
      expect(fit.zoomedAbout(Offset.zero, 100).zoom, ViewFit.maxZoom);
    });

    test('the pan cannot drag the picture away', () {
      const fit = ViewFit(view: view, region: region, zoom: 2);
      final pan = fit.clampPan(const Offset(9999, -9999));
      // A picture twice the fit width is 800 wide in a 400 wide view.
      expect(pan.dx, 200);
      final shown = ViewFit(view: view, region: region, zoom: 2, pan: pan);
      expect(shown.regionInView.left, closeTo(0, 1e-9));
      // At fit width there is nothing to pan sideways.
      final atFit = const ViewFit(
        view: view,
        region: region,
      ).clampPan(const Offset(50, 50));
      expect(atFit.dx, 0);
      expect(math.max(atFit.dy, 0), atFit.dy);
    });
  });
}
