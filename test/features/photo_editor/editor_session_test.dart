import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/crop_math.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_session.dart';

import 'editor_fakes.dart';

Future<EditorSession> _session(
  WidgetTester tester, {
  int width = 400,
  int height = 200,
  EditorDocument? initial,
}) async {
  final assets = await makeAssets(tester, width: width, height: height);
  final session = EditorSession(assets: assets, initial: initial)
    ..setViewSize(const Size(800, 800));
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('coordinates', () {
    testWidgets('the view maps to the picture and back', (tester) async {
      final s = await _session(tester);
      // 400 x 200 in an 800 x 800 view: scale 2, centred vertically.
      expect(s.fit.scale, 2);
      expect(s.viewToSource(const Offset(0, 200)), const Offset(0, 0));
      expect(s.viewToSource(const Offset(800, 600)), const Offset(400, 200));
      final back = s.sourceToViewPoint(const Offset(100, 50));
      expect(back, const Offset(200, 300));
    });

    testWidgets('they follow a turn', (tester) async {
      final s = await _session(tester);
      s.rotateClockwise();
      // Turned: 200 x 400, scale 2, centred sideways.
      expect(s.turnedSize, const Size(200, 400));
      // The picture's top-left is now the top-right of the view.
      final topLeft = s.sourceToViewPoint(Offset.zero);
      expect(topLeft.dx, closeTo(600, 1e-9));
      expect(topLeft.dy, closeTo(0, 1e-9));
      final p = s.viewToSource(topLeft);
      expect(p.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(0, 1e-9));
    });

    testWidgets('they follow a crop and zoom', (tester) async {
      final s = await _session(
        tester,
        initial: const EditorDocument(crop: Rect.fromLTWH(100, 50, 200, 100)),
      );
      // The crop fills the width: scale 4.
      expect(s.fit.scale, 4);
      expect(s.viewToSource(const Offset(400, 400)), const Offset(200, 100));
      s.zoomAbout(const Offset(400, 400), 2);
      expect(s.zoom, 2);
      final stays = s.viewToSource(const Offset(400, 400));
      expect(stays.dx, closeTo(200, 1e-6));
      expect(stays.dy, closeTo(100, 1e-6));
    });
  });

  group('drawing', () {
    testWidgets('a pen stroke is one step with the chosen color', (
      tester,
    ) async {
      final s = await _session(tester);
      s.setPenColor(0xFF2F6BF6);
      s.setPenWidth(StrokeWidth.thick);
      s.beginStroke(const Offset(100, 300));
      s.extendStroke(const Offset(200, 320));
      s.extendStroke(const Offset(300, 340));
      expect(s.activeItem, isA<PenStroke>());
      expect(s.document.items, isEmpty);
      s.endStroke();
      final stroke = s.document.items.single as PenStroke;
      expect(stroke.color, 0xFF2F6BF6);
      expect(stroke.points.length, 3);
      expect(stroke.width, StrokeWidth.thick.penFor(s.sourceSize));
      expect(stroke.points.first, const Offset(50, 50));
      expect(s.canUndo, isTrue);
      expect(s.hasChanges, isTrue);
      s.undo();
      expect(s.document.items, isEmpty);
      expect(s.hasChanges, isFalse);
    });

    testWidgets('samples closer than a screen pixel are skipped', (
      tester,
    ) async {
      final s = await _session(tester);
      s.beginStroke(const Offset(100, 300));
      s.extendStroke(const Offset(100.2, 300.2));
      s.extendStroke(const Offset(100.3, 300.1));
      s.endStroke();
      expect((s.document.items.single as PenStroke).points.length, 1);
    });

    testWidgets('a tap makes a dot', (tester) async {
      final s = await _session(tester);
      s.dot(const Offset(400, 400));
      expect((s.document.items.single as PenStroke).points.length, 1);
    });

    testWidgets('the mosaic tool draws the chosen brush', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.mosaic);
      s.setMosaicKind(MosaicKind.blur);
      s.setMosaicWidth(StrokeWidth.thin);
      s.beginStroke(const Offset(100, 300));
      s.extendStroke(const Offset(200, 300));
      s.endStroke();
      final stroke = s.document.items.single as MosaicStroke;
      expect(stroke.kind, MosaicKind.blur);
      expect(stroke.width, StrokeWidth.thin.brushFor(s.sourceSize));
    });
  });

  group('text', () {
    testWidgets('a new text goes where it was tapped', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.text);
      final draft = s.newText('', viewPoint: const Offset(400, 400));
      expect(draft.center, const Offset(200, 100));
      s.startTextEntry(draft, isNew: true);
      expect(s.editingText, draft.id);
      s.updateDraft(draft.copyWith(text: 'Hello', color: 0xFF2F6BF6));
      expect(s.document.items, isEmpty, reason: 'only a draft until Done');
      s.finishTextEntry(keep: true);
      expect(s.draftText, isNull);
      final text = s.document.items.single as TextOverlay;
      expect(text.text, 'Hello');
      expect(s.selectedTextId, text.id);
      // The color is remembered for the next text.
      expect(s.textColor, 0xFF2F6BF6);
    });

    testWidgets('empty or cancelled text adds nothing', (tester) async {
      final s = await _session(tester);
      s.startTextEntry(s.newText(''), isNew: true);
      s.finishTextEntry(keep: true);
      expect(s.document.items, isEmpty);
      s.startTextEntry(s.newText('x'), isNew: true);
      s.finishTextEntry(keep: false);
      expect(s.document.items, isEmpty);
      expect(s.canUndo, isFalse);
    });

    testWidgets('editing existing text, and emptying it removes it', (
      tester,
    ) async {
      final s = await _session(tester);
      final text = s.newText('Hello');
      s.addText(text);
      s.startTextEntry(text, isNew: false);
      s.updateDraft(text.copyWith(text: 'Bye'));
      s.finishTextEntry(keep: true);
      expect((s.document.items.single as TextOverlay).text, 'Bye');
      s.startTextEntry(s.document.textById(text.id)!, isNew: false);
      s.updateDraft(text.copyWith(text: '  '));
      s.finishTextEntry(keep: true);
      expect(s.document.items, isEmpty);
    });

    testWidgets('moving text with a finger is one step', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Move me', viewPoint: const Offset(400, 400));
      s.addText(text);
      final before = s.document;
      s.beginTextGesture(text, const Offset(400, 400));
      s.updateTextGesture(const Offset(440, 410));
      s.updateTextGesture(const Offset(500, 420));
      s.endTextGesture();
      final moved = s.document.textById(text.id)!;
      // 100 view pixels are 50 picture pixels.
      expect(moved.center.dx, closeTo(250, 1e-9));
      expect(moved.center.dy, closeTo(110, 1e-9));
      s.undo();
      expect(s.document.textById(text.id)!.center, text.center);
      expect(s.document.items.length, before.items.length);
    });

    testWidgets('two fingers resize and turn text', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Pinch', viewPoint: const Offset(400, 400));
      s.addText(text);
      s.beginTextGesture(text, const Offset(400, 400));
      s.updateTextGesture(
        const Offset(400, 400),
        scale: 2,
        rotation: math.pi / 4,
      );
      s.endTextGesture();
      final changed = s.document.textById(text.id)!;
      expect(changed.scale, 2);
      expect(changed.rotation, closeTo(math.pi / 4, 1e-9));
    });

    testWidgets('text size is kept within limits', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Limits');
      s.addText(text);
      s.beginTextGesture(text, const Offset(400, 400));
      s.updateTextGesture(const Offset(400, 400), scale: 1000);
      expect(s.document.textById(text.id)!.scale, maxTextScale);
      s.updateTextGesture(const Offset(400, 400), scale: 0.0001);
      expect(s.document.textById(text.id)!.scale, minTextScale);
      s.endTextGesture();
    });

    testWidgets('the corner handle sets size and angle', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Handle', viewPoint: const Offset(400, 400));
      s.addText(text);
      // Grab the handle 100 view pixels right of the middle, drag it to
      // 200 pixels straight down.
      s.beginTextGesture(text, const Offset(500, 400));
      s.updateTextHandle(const Offset(400, 600));
      s.endTextGesture();
      final changed = s.document.textById(text.id)!;
      expect(changed.scale, closeTo(2, 1e-9));
      expect(changed.rotation, closeTo(math.pi / 2, 1e-9));
      expect(changed.center, text.center);
    });

    testWidgets('the toolbar actions change the selected text', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Toolbar');
      s.addText(text);
      s.setTextColor(0xFFFFD60A);
      s.setTextPill(true);
      s.scaleSelectedText(2);
      s.rotateSelectedText(0.5);
      s.nudgeSelectedText(const Offset(10, -10));
      final changed = s.selectedText!;
      expect(changed.color, 0xFFFFD60A);
      expect(changed.pill, isTrue);
      expect(changed.scale, 2);
      expect(changed.rotation, 0.5);
      expect(changed.center, text.center + const Offset(10, -10));
      s.removeText(text.id);
      expect(s.selectedText, isNull);
      expect(s.document.items, isEmpty);
    });

    testWidgets('hit testing finds text under a finger', (tester) async {
      final s = await _session(tester);
      final text = s.newText('Find me', viewPoint: const Offset(400, 400));
      s.addText(text);
      expect(s.hitText(const Offset(400, 400))?.id, text.id);
      expect(s.hitText(const Offset(20, 220)), isNull);
    });

    testWidgets('the corners of a text turn with it', (tester) async {
      final s = await _session(tester);
      final text = s
          .newText('Corners', viewPoint: const Offset(400, 400))
          .copyWith(rotation: math.pi);
      s.addText(text);
      final flat = s.textCornersInView(text.copyWith(rotation: 0));
      final flipped = s.textCornersInView(text);
      expect(flipped.first.dx, closeTo(flat[2].dx, 1e-6));
      expect(flipped.first.dy, closeTo(flat[2].dy, 1e-6));
    });
  });

  group('cropping', () {
    testWidgets('dragging a corner crops, and is one step', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.crop);
      expect(s.cropRect, const Rect.fromLTWH(0, 0, 400, 200));
      final px = s.fit.scale;
      s.beginCrop(CropHandle.bottomRight);
      s.dragCropBy(Offset(-50, -25) * px);
      s.dragCropBy(Offset(-100, -50) * px);
      s.endCrop();
      // The drag counts from where it began: 100 x 50 picture pixels.
      final crop = s.document.crop!;
      expect(crop.right, closeTo(300, 1e-6));
      expect(crop.bottom, closeTo(150, 1e-6));
      expect(crop.topLeft, Offset.zero);
      s.undo();
      expect(s.document.crop, isNull);
    });

    testWidgets('a crop dragged back to the whole picture is no crop', (
      tester,
    ) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.crop);
      s.beginCrop(CropHandle.right);
      s.dragCropBy(const Offset(-100, 0));
      s.dragCropBy(const Offset(0, 0));
      s.endCrop();
      expect(s.document.crop, isNull);
      expect(s.document.isUnedited, isTrue);
      expect(s.canUndo, isFalse);
    });

    testWidgets('a fixed ratio fits the crop to it', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.crop);
      s.setRatio(CropRatio.square);
      expect(s.document.crop, const Rect.fromLTWH(100, 0, 200, 200));
      expect(s.ratio, CropRatio.square);
      // Dragging keeps the shape.
      s.beginCrop(CropHandle.bottomRight);
      s.dragCropBy(const Offset(-100, -20));
      s.endCrop();
      final crop = s.document.crop!;
      expect(crop.width, closeTo(crop.height, 1e-6));
    });

    testWidgets('choosing 4:3 twice turns it upright', (tester) async {
      final s = await _session(tester, width: 400, height: 300);
      s.selectTool(EditorTool.crop);
      s.setRatio(CropRatio.fourThree);
      expect(s.cropRect.width / s.cropRect.height, closeTo(4 / 3, 1e-6));
      s.setRatio(CropRatio.fourThree);
      expect(s.cropRect.width / s.cropRect.height, closeTo(3 / 4, 1e-6));
      s.setRatio(CropRatio.fourThree);
      expect(s.cropRect.width / s.cropRect.height, closeTo(4 / 3, 1e-6));
    });

    testWidgets('16:9 and free', (tester) async {
      final s = await _session(tester, width: 400, height: 400);
      s.selectTool(EditorTool.crop);
      s.setRatio(CropRatio.sixteenNine);
      expect(s.cropRect.width / s.cropRect.height, closeTo(16 / 9, 1e-6));
      s.setRatio(CropRatio.free);
      expect(s.ratio, CropRatio.free);
      s.beginCrop(CropHandle.right);
      s.dragCropBy(const Offset(-50, 0));
      s.endCrop();
      expect(
        s.cropRect.width / s.cropRect.height,
        isNot(closeTo(16 / 9, 1e-3)),
      );
    });

    testWidgets('rotating turns the picture and its crop', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.crop);
      final px = s.fit.scale;
      s.beginCrop(CropHandle.bottomRight);
      s.dragCropBy(Offset(-200, -100) * px);
      s.endCrop();
      Rect round(Rect r) => Rect.fromLTRB(
        r.left.roundToDouble(),
        r.top.roundToDouble(),
        r.right.roundToDouble(),
        r.bottom.roundToDouble(),
      );
      expect(round(s.document.crop!), const Rect.fromLTRB(0, 0, 200, 100));
      s.rotateClockwise();
      expect(s.document.quarterTurns, 1);
      // The top-left part of the picture is now the top-right part.
      expect(round(s.document.crop!), const Rect.fromLTRB(100, 0, 200, 200));
      for (var i = 0; i < 3; i++) {
        s.rotateClockwise();
      }
      expect(s.document.quarterTurns, 0);
      expect(round(s.document.crop!), const Rect.fromLTRB(0, 0, 200, 100));
    });

    testWidgets('reset takes back the turn and the crop, keeping marks', (
      tester,
    ) async {
      final s = await _session(tester);
      s.dot(const Offset(400, 400));
      s.rotateClockwise();
      s.selectTool(EditorTool.crop);
      s.setRatio(CropRatio.square);
      expect(s.canResetCrop, isTrue);
      s.resetCrop();
      expect(s.document.quarterTurns, 0);
      expect(s.document.crop, isNull);
      expect(s.document.items.length, 1);
      expect(s.ratio, CropRatio.free);
      expect(s.canResetCrop, isFalse);
      s.undo();
      expect(s.document.quarterTurns, 1);
    });

    testWidgets('arrow keys nudge the crop', (tester) async {
      final s = await _session(tester);
      s.selectTool(EditorTool.crop);
      s.beginCrop(CropHandle.bottomRight);
      s.dragCropBy(const Offset(-200, -100));
      s.endCrop();
      final before = s.cropRect;
      s.nudgeCrop(const Offset(10, 5));
      expect(s.cropRect, before.shift(const Offset(10, 5)));
      s.nudgeCrop(const Offset(10, 5), resize: true);
      expect(s.cropRect.width, before.width + 10);
      expect(s.cropRect.height, before.height + 5);
    });

    testWidgets('cropping shows the whole picture, other tools the crop', (
      tester,
    ) async {
      final s = await _session(
        tester,
        initial: const EditorDocument(crop: Rect.fromLTWH(100, 50, 200, 100)),
      );
      expect(s.region, const Rect.fromLTWH(100, 50, 200, 100));
      s.selectTool(EditorTool.crop);
      expect(s.region, const Rect.fromLTWH(0, 0, 400, 200));
      s.selectTool(EditorTool.draw);
      expect(s.region, const Rect.fromLTWH(100, 50, 200, 100));
    });
  });

  group('zoom', () {
    testWidgets('pinching zooms about the fingers and can pan', (tester) async {
      final s = await _session(tester);
      s.beginPinch(const Offset(400, 400));
      final under = s.viewToSource(const Offset(400, 400));
      s.updatePinch(const Offset(400, 400), 3);
      expect(s.zoom, 3);
      final still = s.viewToSource(const Offset(400, 400));
      expect(still.dx, closeTo(under.dx, 1e-6));
      s.updatePinch(const Offset(380, 400), 3);
      expect(s.viewToSource(const Offset(380, 400)).dx, closeTo(under.dx, 1e-6));
      s.resetZoom();
      expect(s.zoom, 1);
    });

    testWidgets('there is no zoom while cropping', (tester) async {
      final s = await _session(tester);
      s.zoomAbout(const Offset(400, 400), 2);
      expect(s.zoom, 2);
      s.selectTool(EditorTool.crop);
      expect(s.zoom, 1);
      s.zoomAbout(const Offset(400, 400), 2);
      expect(s.zoom, 1);
    });

    testWidgets('scrolling pans only when zoomed in', (tester) async {
      final s = await _session(tester);
      s.panBy(const Offset(50, 0));
      expect(s.fit.pan, Offset.zero);
      s.zoomAbout(const Offset(400, 400), 3);
      s.panBy(const Offset(20, 0));
      expect(s.fit.pan.dx, isNot(0));
    });
  });

  testWidgets('hasChanges is false until something is done', (tester) async {
    final s = await _session(
      tester,
      initial: const EditorDocument(quarterTurns: 1),
    );
    expect(s.hasChanges, isFalse);
    s.rotateClockwise();
    expect(s.hasChanges, isTrue);
    s.undo();
    expect(s.hasChanges, isFalse);
  });
}
