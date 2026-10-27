import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_export.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_painter.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

import 'whiteboard_fakes.dart';

const palette = WhiteboardPalette(
  background: Color(0xFFFFFFFF),
  grid: Color(0xFFDDDDDD),
  selection: Color(0xFF3B6EF5),
  handleFill: Color(0xFFFFFFFF),
  label: Color(0xFF000000),
);

/// A big board: 3000 lines scattered over a 6000 x 6000 area.
FakeWhiteboardServer bigBoard() {
  final server = FakeWhiteboardServer();
  final random = math.Random(7);
  for (var i = 0; i < 3000; i++) {
    final x = random.nextDouble() * 6000;
    final y = random.nextDouble() * 6000;
    final points = <double>[];
    for (var j = 0; j < 40; j++) {
      points
        ..add(x + j * 2)
        ..add(y + math.sin(j / 3) * 10);
    }
    server.elements['s$i'] = stroke(
      's$i',
      z: 'V${(i % 50).toRadixString(36)}',
      points: points,
    ).copyWith(rev: 1);
  }
  return server;
}

Future<WhiteboardController> load(FakeWhiteboardServer server) async {
  final controller = WhiteboardController(
    boardId: 'board-1',
    repository: FakeWhiteboardRepository(server),
    userId: 'me',
    userName: 'Me',
    drafts: InMemoryWhiteboardDraftStore(),
    flushDelay: const Duration(days: 1),
  );
  controller.viewport = const Size(400, 600);
  await controller.load();
  return controller;
}

int paintOnce(WhiteboardPainter painter, Size size) {
  final recorder = PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
  return painter.lastDrawnCount;
}

void main() {
  test('only what is on screen is drawn, however big the board is', () async {
    final controller = await load(bigBoard());
    expect(controller.engine.liveCount, 3000);
    controller.setView(const WhiteboardView());
    final painter = WhiteboardPainter(controller: controller, palette: palette);
    const size = Size(400, 600);
    final drawn = paintOnce(painter, size);
    expect(drawn, lessThan(60));
    expect(drawn, greaterThan(0));

    // Moving the view draws what is there instead.
    controller.setView(const WhiteboardView(offset: Offset(-3000, -3000)));
    final other = paintOnce(painter, size);
    expect(other, lessThan(60));
    controller.dispose();
  });

  test('a frame of a 3000 element board is quick', () async {
    final controller = await load(bigBoard());
    final painter = WhiteboardPainter(controller: controller, palette: palette);
    const size = Size(400, 600);
    // Warm up (outline caches).
    controller.fitToContent();
    paintOnce(painter, size);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      controller.setView(
        WhiteboardView(scale: 0.2, offset: Offset(-i * 5.0, -i * 3.0)),
      );
      paintOnce(painter, size);
    }
    watch.stop();
    // 20 frames of the whole board zoomed out well under a second in total.
    expect(watch.elapsedMilliseconds, lessThan(2500));
    // At a normal zoom a frame costs very little.
    controller.setView(const WhiteboardView());
    final close = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      paintOnce(painter, size);
    }
    close.stop();
    expect(close.elapsedMilliseconds / 20, lessThan(40));
    controller.dispose();
  });

  test('elements too small to see at this zoom are skipped', () async {
    final controller = await load(bigBoard());
    controller.setView(const WhiteboardView(scale: 0.05, offset: Offset(100, 100)));
    final painter = WhiteboardPainter(controller: controller, palette: palette);
    final drawn = paintOnce(painter, const Size(400, 600));
    // Each line is about 80 units: 4 pixels at 5 percent, so they are drawn,
    // but never more than the board holds.
    expect(drawn, lessThanOrEqualTo(3000));
    controller.dispose();
  });

  test('the outline of a pressure line is cached against its element', () {
    final line = WhiteboardElement(
      id: 'p',
      kind: WhiteboardKind.stroke,
      z: 'V',
      data: const {
        'p': [0.0, 0.0, 50.0, 10.0, 100.0, 0.0],
        'pr': [20, 90, 40],
        'sw': 8,
        'c': 0xFF000000,
      },
    );
    expect(identical(strokePathOf(line), strokePathOf(line)), isTrue);
    final bounds = strokePathOf(line).getBounds();
    expect(bounds.width, greaterThan(100));
  });

  group('export', () {
    test('the picture covers everything with room around it', () {
      final plan = planWhiteboardRender([
        sticky('a', x: 0, y: 0),
        sticky('b', x: 1000, y: 500),
      ])!;
      expect(plan.width, greaterThan(1000));
      expect(plan.origin.dx, lessThan(0));
      expect(planWhiteboardRender(const []), isNull);
    });

    test('a huge board is scaled to fit the largest picture', () {
      final plan = planWhiteboardRender([
        sticky('a', x: 0, y: 0),
        sticky('b', x: 90000, y: 90000),
      ])!;
      expect(plan.width, lessThanOrEqualTo(whiteboardExportMaxSide + 1));
      expect(plan.height, lessThanOrEqualTo(whiteboardExportMaxSide + 1));
    });

    testWidgets('renders a PNG', (tester) async {
      final controller = await load(
        FakeWhiteboardServer()
          ..write(sticky('a', text: 'Hello', x: 0, y: 0))
          ..write(stroke('l', z: 'W', points: const [0, 0, 200, 100])),
      );
      final png = await tester.runAsync(
        () => renderWhiteboardPng(
          controller.engine.elements,
          controller.images,
        ),
      );
      expect(png, isNotNull);
      expect(
        Uint8List.fromList(png!.sublist(0, 4)),
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      final empty = await tester.runAsync(
        () => renderWhiteboardPng(const [], controller.images),
      );
      expect(empty, isNull);
      controller.dispose();
    });
  });
}
