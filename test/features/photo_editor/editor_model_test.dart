import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';

PenStroke pen(double x, {int color = 0xFFE12F35}) => PenStroke(
  points: [Offset(x, 0), Offset(x + 5, 5)],
  color: color,
  width: 4,
);

void main() {
  group('EditorDocument', () {
    test('an empty document is unedited', () {
      expect(const EditorDocument().isUnedited, isTrue);
      expect(const EditorDocument(quarterTurns: 1).isUnedited, isFalse);
      expect(
        const EditorDocument(crop: Rect.fromLTWH(0, 0, 5, 5)).isUnedited,
        isFalse,
      );
      expect(const EditorDocument().withItem(pen(1)).isUnedited, isFalse);
    });

    test('items are added in order and can be removed', () {
      final a = pen(1);
      final b = pen(2);
      final doc = const EditorDocument().withItem(a).withItem(b);
      expect(doc.items, [a, b]);
      expect(doc.withoutItem(a).items, [b]);
    });

    test('text overlays are found, replaced and removed by id', () {
      const text = TextOverlay(
        id: 7,
        text: 'Hi',
        color: 0xFFFFFFFF,
        center: Offset(10, 10),
      );
      final doc = const EditorDocument().withItem(text).withItem(pen(1));
      expect(doc.textById(7), text);
      expect(doc.textById(8), isNull);
      expect(doc.textById(null), isNull);
      final changed = doc.withReplacedText(text.copyWith(text: 'Bye'));
      expect(changed.textById(7)!.text, 'Bye');
      expect(changed.items.length, 2);
      expect(doc.withoutText(7).items.length, 1);
      expect(doc.withoutText(7).textById(7), isNull);
    });

    test('copyWith can clear the crop', () {
      const doc = EditorDocument(crop: Rect.fromLTWH(0, 0, 5, 5));
      expect(doc.copyWith(quarterTurns: 1).crop, isNotNull);
      expect(doc.copyWith(crop: null).crop, isNull);
    });
  });

  group('EditorController history', () {
    test('commit, undo and redo', () {
      final controller = EditorController();
      expect(controller.canUndo, isFalse);
      controller.commit(controller.document.withItem(pen(1)));
      controller.commit(controller.document.withItem(pen(2)));
      expect(controller.document.items.length, 2);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);

      controller.undo();
      expect(controller.document.items.length, 1);
      expect(controller.canRedo, isTrue);
      controller.undo();
      expect(controller.document.items, isEmpty);
      expect(controller.canUndo, isFalse);
      // Nothing more to undo.
      controller.undo();
      expect(controller.document.items, isEmpty);

      controller.redo();
      controller.redo();
      expect(controller.document.items.length, 2);
      expect(controller.canRedo, isFalse);
    });

    test('a new edit clears what could be redone', () {
      final controller = EditorController();
      controller.commit(controller.document.withItem(pen(1)));
      controller.undo();
      expect(controller.canRedo, isTrue);
      controller.commit(controller.document.withItem(pen(9)));
      expect(controller.canRedo, isFalse);
    });

    test('commit of the same document is not a step', () {
      final controller = EditorController();
      controller.commit(controller.document);
      expect(controller.canUndo, isFalse);
    });

    test('keeps the last hundred steps', () {
      final controller = EditorController();
      for (var i = 0; i < 130; i++) {
        controller.commit(controller.document.withItem(pen(i.toDouble())));
      }
      var undone = 0;
      while (controller.canUndo) {
        controller.undo();
        undone++;
      }
      expect(undone, EditorController.maxHistory);
      // The oldest 30 strokes cannot be undone.
      expect(controller.document.items.length, 30);
    });

    test('a drag is one step however many updates it makes', () {
      final controller = EditorController();
      controller.commit(controller.document.withItem(pen(1)));
      final before = controller.document;
      controller.beginChange();
      for (var i = 0; i < 10; i++) {
        controller.update(
          controller.document.copyWith(quarterTurns: i % 4),
        );
      }
      controller.update(controller.document.copyWith(quarterTurns: 2));
      controller.commitChange();
      expect(controller.document.quarterTurns, 2);
      controller.undo();
      expect(controller.document, same(before));
    });

    test('a drag that changes nothing is not a step', () {
      final controller = EditorController();
      controller.beginChange();
      controller.commitChange();
      expect(controller.canUndo, isFalse);
    });

    test('cancelChange puts back what the drag started with', () {
      final controller = EditorController();
      final before = controller.document;
      controller.beginChange();
      controller.update(controller.document.copyWith(quarterTurns: 3));
      controller.cancelChange();
      expect(controller.document, same(before));
      expect(controller.canUndo, isFalse);
    });

    test('reset is a step that can be undone', () {
      final controller = EditorController(
        const EditorDocument(quarterTurns: 1),
      );
      controller.commit(controller.document.withItem(pen(1)));
      controller.reset();
      expect(controller.document.isUnedited, isTrue);
      controller.undo();
      expect(controller.document.items.length, 1);
      expect(controller.document.quarterTurns, 1);
    });

    test('notifies listeners', () {
      final controller = EditorController();
      var calls = 0;
      controller.addListener(() => calls++);
      controller.commit(controller.document.withItem(pen(1)));
      controller.undo();
      controller.redo();
      expect(calls, 3);
    });
  });

  group('strokes', () {
    test('a stroke grows while drawn and joins the document at the end', () {
      final controller = EditorController();
      controller.startStroke(
        const PenStroke(points: [Offset(1, 1)], color: 0xFF000000, width: 3),
      );
      controller.extendStroke(const Offset(2, 2));
      controller.extendStroke(const Offset(3, 3));
      final active = controller.activeItem! as PenStroke;
      expect(active.points.length, 3);
      expect(controller.document.items, isEmpty);
      expect(controller.isChanged, isTrue);

      controller.endStroke();
      expect(controller.activeItem, isNull);
      expect(controller.document.items.single, active);
      expect(controller.canUndo, isTrue);
    });

    test('mosaic strokes grow the same way', () {
      final controller = EditorController();
      controller.startStroke(
        const MosaicStroke(
          points: [Offset(1, 1)],
          width: 30,
          kind: MosaicKind.blur,
        ),
      );
      controller.extendStroke(const Offset(5, 5));
      controller.endStroke();
      final stroke = controller.document.items.single as MosaicStroke;
      expect(stroke.points.length, 2);
      expect(stroke.kind, MosaicKind.blur);
    });

    test('undo drops the stroke being drawn', () {
      final controller = EditorController();
      controller.commit(controller.document.withItem(pen(1)));
      controller.startStroke(pen(2));
      controller.undo();
      expect(controller.activeItem, isNull);
      expect(controller.document.items, isEmpty);
    });

    test('extending with nothing started does nothing', () {
      final controller = EditorController();
      controller.extendStroke(const Offset(1, 1));
      controller.endStroke();
      expect(controller.document.items, isEmpty);
      expect(controller.canUndo, isFalse);
    });
  });

  group('sizes', () {
    test('line widths follow the picture', () {
      const small = Size(400, 300);
      const big = Size(4000, 3000);
      expect(StrokeWidth.thin.penFor(big), greaterThan(StrokeWidth.thin.penFor(small)));
      expect(
        StrokeWidth.thin.penFor(small),
        lessThan(StrokeWidth.medium.penFor(small)),
      );
      expect(
        StrokeWidth.medium.penFor(small),
        lessThan(StrokeWidth.thick.penFor(small)),
      );
      expect(
        StrokeWidth.thin.brushFor(small),
        lessThan(StrokeWidth.thick.brushFor(small)),
      );
      // Never thinner than a visible line.
      expect(StrokeWidth.thin.penFor(const Size(20, 20)), 2);
    });

    test('the mosaic block grows with the picture', () {
      expect(mosaicBlockSize(const Size(100, 100)), 6);
      expect(mosaicBlockSize(const Size(4000, 3000)), greaterThan(60));
      expect(mosaicBlockSize(const Size(4000, 3000)), closeTo(3000 / 48, 1));
    });

    test('text size follows the picture', () {
      expect(TextOverlayMetrics.baseFontSize(const Size(100, 100)), 14);
      expect(
        TextOverlayMetrics.baseFontSize(const Size(3000, 2000)),
        closeTo(140, 1e-9),
      );
    });
  });

  group('colors', () {
    test('eight named colors', () {
      expect(EditorPalette.colors.length, 8);
      expect(
        EditorPalette.colors.map((c) => c.argb).toSet().length,
        8,
        reason: 'distinct',
      );
      expect(
        EditorPalette.colors.map((c) => c.argb),
        contains(EditorPalette.defaultColor),
      );
    });

    test('text on a pill is black or white, whichever reads', () {
      expect(EditorPalette.onColor(0xFFFFFFFF), 0xFF17171A);
      expect(EditorPalette.onColor(0xFFFFD60A), 0xFF17171A);
      expect(EditorPalette.onColor(0xFF17171A), 0xFFFFFFFF);
      expect(EditorPalette.onColor(0xFF2F6BF6), 0xFFFFFFFF);
      expect(EditorPalette.onColor(0xFFE12F35), 0xFFFFFFFF);
    });
  });

  group('text hit testing', () {
    const box = Size(100, 40);
    const text = TextOverlay(
      id: 1,
      text: 'Hi',
      color: 0xFFFFFFFF,
      center: Offset(200, 100),
    );

    test('inside and outside the box', () {
      expect(textHitTest(text, box, const Offset(200, 100)), isTrue);
      expect(textHitTest(text, box, const Offset(249, 119)), isTrue);
      expect(textHitTest(text, box, const Offset(251, 100)), isFalse);
      expect(textHitTest(text, box, const Offset(200, 121)), isFalse);
      // A little slack for fingers.
      expect(textHitTest(text, box, const Offset(255, 100), slop: 10), isTrue);
    });

    test('follows scale', () {
      final big = text.copyWith(scale: 2);
      expect(textHitTest(big, box, const Offset(290, 100)), isTrue);
      expect(textHitTest(big, box, const Offset(310, 100)), isFalse);
      final small = text.copyWith(scale: 0.5);
      expect(textHitTest(small, box, const Offset(240, 100)), isFalse);
      expect(textHitTest(small, box, const Offset(220, 100)), isTrue);
    });

    test('follows rotation', () {
      final turned = text.copyWith(rotation: math.pi / 2);
      // A quarter turn: the 100 wide box now stands 100 tall.
      expect(textHitTest(turned, box, const Offset(200, 140)), isTrue);
      expect(textHitTest(turned, box, const Offset(240, 100)), isFalse);
      expect(textHitTest(turned, box, const Offset(215, 100)), isTrue);
    });

    test('the topmost overlay wins', () {
      final under = text.copyWith();
      final over = const TextOverlay(
        id: 2,
        text: 'Over',
        color: 0xFF000000,
        center: Offset(210, 100),
      );
      final doc = const EditorDocument().withItem(under).withItem(over);
      final hit = hitTestTexts(doc, const Offset(205, 100), (_) => box);
      expect(hit!.id, 2);
      expect(
        hitTestTexts(doc, const Offset(0, 0), (_) => box),
        isNull,
      );
      // Where only the lower one reaches.
      expect(hitTestTexts(doc, const Offset(152, 100), (_) => box)!.id, 1);
    });
  });
}
