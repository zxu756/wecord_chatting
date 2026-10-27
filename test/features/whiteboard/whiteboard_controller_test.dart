import 'dart:ui';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

import 'whiteboard_fakes.dart';

Future<(WhiteboardController, FakeWhiteboardRepository, FakeWhiteboardServer)>
open({
  FakeWhiteboardServer? server,
  WhiteboardMeta? meta,
  int? ids,
}) async {
  final world = server ?? FakeWhiteboardServer();
  final repository = FakeWhiteboardRepository(world, meta: meta);
  var counter = 0;
  final controller = WhiteboardController(
    boardId: 'board-1',
    repository: repository,
    userId: 'me',
    userName: 'Me',
    drafts: InMemoryWhiteboardDraftStore(),
    flushDelay: const Duration(days: 1),
    newId: () => 'id-${counter++}',
  );
  controller.viewport = const Size(400, 600);
  await controller.load();
  return (controller, repository, world);
}

void drawLine(WhiteboardController c, {double length = 100}) {
  c.beginStroke(const Offset(10, 10));
  for (var i = 1; i <= 10; i++) {
    c.extendStroke(Offset(10 + length * i / 10, 10 + i * 3.0));
  }
  c.endStroke();
}

void main() {
  test('loads the board and lets the person draw', () async {
    final (c, _, server) = await open();
    expect(c.loadState, WhiteboardLoadState.ready);
    expect(c.canEdit, isTrue);
    drawLine(c);
    expect(c.engine.liveCount, 1);
    final stroke = c.engine.elements.single;
    expect(stroke.kind, WhiteboardKind.stroke);
    expect(stroke.points.length, greaterThanOrEqualTo(4));
    expect(stroke.pressures, isNull);
    await c.flushNow();
    expect(server.liveCount, 1);
    c.dispose();
  });

  test('a stylus line keeps its pressure, a finger or mouse line does not', () async {
    final (c, _, _) = await open();
    c.beginStroke(
      const Offset(0, 0),
      pressure: 0.2,
      kind: PointerDeviceKind.stylus,
    );
    c.extendStroke(const Offset(50, 0), pressure: 0.9);
    c.extendStroke(const Offset(100, 40), pressure: 0.5);
    c.endStroke();
    final stroke = c.engine.elements.single;
    expect(stroke.pressures, isNotNull);
    expect(stroke.pressures!.length, stroke.points.length ~/ 2);
    expect(c.stylusSeen, isTrue);
    c.dispose();
  });

  test('a very long line is cut into elements of at most 2000 points', () async {
    final (c, _, _) = await open();
    c.beginStroke(const Offset(0, 0));
    for (var i = 1; i < 6000; i++) {
      c.extendStroke(Offset(i * 0.5, (i.isEven ? 30.0 : -30.0)));
    }
    c.endStroke();
    expect(c.engine.liveCount, greaterThan(1));
    for (final e in c.engine.elements) {
      expect(e.points.length ~/ 2, lessThanOrEqualTo(2000));
    }
    c.dispose();
  });

  test('live strokes are shown to others while drawing and ended after', () async {
    final (c, repository, _) = await open();
    c.beginStroke(const Offset(0, 0));
    c.extendStroke(const Offset(40, 40));
    expect(repository.live.sentStrokes, isNotEmpty);
    c.endStroke();
    expect(repository.live.sentStrokes.last.done, isTrue);
    c.dispose();
  });

  test('undo and redo of a line reach the server', () async {
    final (c, _, server) = await open();
    drawLine(c);
    await c.flushNow();
    c.undo();
    expect(c.engine.liveCount, 0);
    await c.flushNow();
    expect(server.liveCount, 0);
    c.redo();
    await c.flushNow();
    expect(server.liveCount, 1);
    c.dispose();
  });

  test('a shape is made by dragging, and a tap makes a default one', () async {
    final (c, _, _) = await open();
    c.setTool(WhiteboardTool.shape);
    c.beginShape(const Offset(10, 10));
    c.updateShape(const Offset(110, 60));
    c.endShape();
    var shape = c.engine.elements.single;
    expect(shape.shape, WhiteboardShape.rect);
    expect(shape.w, 100);
    expect(shape.h, 50);
    c.setShapeKind(WhiteboardShape.arrow);
    c.beginShape(const Offset(300, 300));
    c.endShape();
    shape = c.engine.elements.last;
    expect(shape.shape, WhiteboardShape.arrow);
    expect(shape.w, 140);
    c.dispose();
  });

  test('a sticky note is typed into and the typing is one undo step', () async {
    final (c, _, _) = await open();
    final note = c.addSticky(const Offset(200, 200))!;
    expect(c.editingId, note.id);
    c.setEditingText('hel');
    c.setEditingText('hello');
    c.finishEditing();
    expect(c.engine.elementById(note.id)!.text, 'hello');
    c.undo();
    expect(c.engine.elementById(note.id)!.text, '');
    c.dispose();
  });

  test('a text with no words is not kept', () async {
    final (c, _, _) = await open();
    c.addText(const Offset(50, 50));
    expect(c.engine.liveCount, 1);
    c.finishEditing();
    expect(c.engine.liveCount, 0);
    c.addText(const Offset(50, 50));
    c.setEditingText('Plan', measured: const Size(60, 30));
    c.finishEditing();
    expect(c.engine.elements.single.text, 'Plan');
    expect(c.engine.elements.single.w, 60);
    c.dispose();
  });

  test('the eraser removes what it touches as one action', () async {
    final (c, _, _) = await open();
    drawLine(c);
    c.beginStroke(const Offset(10, 100));
    c.extendStroke(const Offset(100, 100));
    c.endStroke();
    expect(c.engine.liveCount, 2);
    c.beginErase(const Offset(50, 100));
    c.eraseAt(const Offset(20, 12));
    c.endErase();
    expect(c.engine.liveCount, 0);
    c.undo();
    expect(c.engine.liveCount, 2);
    c.dispose();
  });

  test('moving the selection is one undo step and keeps the others', () async {
    final server = FakeWhiteboardServer()
      ..write(sticky('a', text: 'a', x: 10, y: 10))
      ..write(sticky('b', z: 'W', text: 'b', x: 300, y: 10));
    final (c, _, _) = await open(server: server);
    c.select(['a', 'b']);
    c.beginMove();
    c.moveBy(const Offset(5, 5));
    c.moveBy(const Offset(20, 30));
    c.endMove();
    expect(c.engine.elementById('a')!.x, 30);
    expect(c.engine.elementById('b')!.y, 40);
    c.undo();
    expect(c.engine.elementById('a')!.x, 10);
    expect(c.engine.elementById('b')!.y, 10);
    c.dispose();
  });

  test('a corner handle resizes a note', () async {
    final server = FakeWhiteboardServer()
      ..write(sticky('a', text: 'a', x: 0, y: 0));
    final (c, _, _) = await open(server: server);
    c.select(['a']);
    final handle = c.handleAt(const Offset(160, 120));
    expect(handle, WhiteboardHandle.bottomRight);
    c.beginResize(handle!);
    c.resizeTo(const Offset(260, 200));
    c.endResize();
    expect(c.engine.elementById('a')!.w, 260);
    expect(c.engine.elementById('a')!.h, 200);
    c.dispose();
  });

  test('a full board says so and takes nothing more', () async {
    final server = FakeWhiteboardServer();
    for (var i = 0; i < WhiteboardLimits.maxElements; i++) {
      server.elements['s$i'] = stroke('s$i', z: 'V${i % 9}').copyWith(rev: 1);
    }
    final (c, _, _) = await open(server: server);
    expect(c.engine.liveCount, WhiteboardLimits.maxElements);
    c.beginStroke(const Offset(0, 0));
    expect(c.ink, isNull);
    expect(c.notice, WhiteboardNotice.boardFull);
    expect(c.addSticky(const Offset(0, 0)), isNull);
    c.dispose();
  });

  test('a person who cannot edit gets a notice and no changes', () async {
    final server = FakeWhiteboardServer()..write(sticky('a'));
    final (c, _, _) = await open(
      server: server,
      meta: const WhiteboardMeta(id: 'board-1', conversationId: 'c'),
    );
    expect(c.canEdit, isFalse);
    c.beginStroke(const Offset(0, 0));
    expect(c.ink, isNull);
    expect(c.notice, WhiteboardNotice.readOnly);
    c.select(['a']);
    c.deleteSelection();
    expect(c.engine.liveCount, 1);
    expect(c.canUndo, isFalse);
    c.dispose();
  });

  test('changes by others arrive and a selected element that goes is dropped', () async {
    final server = FakeWhiteboardServer()..write(sticky('a', text: 'one'));
    final (c, _, _) = await open(server: server);
    c.select(['a']);
    await Future<void>.delayed(Duration.zero);
    server.write(server.elements['a']!.withData({'t': 'two'}));
    await Future<void>.delayed(Duration.zero);
    expect(c.engine.elementById('a')!.text, 'two');
    server.write(server.elements['a']!.copyWith(deleted: true, data: const {}));
    await Future<void>.delayed(Duration.zero);
    expect(c.engine.elementById('a'), isNull);
    expect(c.selection, isEmpty);
    c.dispose();
  });

  test('words added from the list view, and edited', () async {
    final (c, _, _) = await open();
    final note = c.addWords(sticky: true, text: 'Buy paint')!;
    expect(c.engine.elementById(note.id)!.text, 'Buy paint');
    c.replaceWords(note.id, 'Buy red paint');
    expect(c.engine.elementById(note.id)!.text, 'Buy red paint');
    c.undo();
    expect(c.engine.elementById(note.id)!.text, 'Buy paint');
    c.dispose();
  });

  test('bring to front, send to back and duplicate', () async {
    final server = FakeWhiteboardServer()
      ..write(sticky('a', z: 'V', text: 'a'))
      ..write(sticky('b', z: 'W', text: 'b'));
    final (c, _, _) = await open(server: server);
    c.select(['a']);
    c.bringToFront();
    expect(c.engine.elements.map((e) => e.id).toList().last, 'a');
    c.sendToBack();
    expect(c.engine.elements.first.id, 'a');
    c.duplicateSelection();
    expect(c.engine.liveCount, 3);
    expect(c.selection.length, 1);
    c.dispose();
  });

  test('a marquee selects what it touches', () async {
    final server = FakeWhiteboardServer()
      ..write(sticky('a', x: 10, y: 10))
      ..write(sticky('b', z: 'W', x: 900, y: 900));
    final (c, _, _) = await open(server: server);
    c.beginMarquee(const Offset(0, 0));
    c.updateMarquee(const Offset(300, 300));
    c.endMarquee();
    expect(c.selection, {'a'});
    c.dispose();
  });

  test('unsent drawing is kept as a draft when the server is away', () async {
    final server = FakeWhiteboardServer()..offline = true;
    final (c, _, _) = await open(server: server);
    drawLine(c);
    await c.flushNow();
    expect(c.engine.status, WhiteboardSyncStatus.offline);
    expect(
      (await c.drafts.load('board-1'))!.local.length,
      1,
    );
    c.dispose();
  });

  test('a deleted board is announced', () async {
    final (c, repository, _) = await open();
    repository.metas.add(
      const WhiteboardMetaChange(title: '', managersOnly: false, deleted: true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.loadState, WhiteboardLoadState.gone);
    c.dispose();
  });

  test('a board that fails to load can be tried again', () async {
    final server = FakeWhiteboardServer();
    final repository = FakeWhiteboardRepository(server)..failLoad = true;
    final c = WhiteboardController(
      boardId: 'board-1',
      repository: repository,
      userId: 'me',
      userName: 'Me',
      drafts: InMemoryWhiteboardDraftStore(),
    );
    await c.load();
    expect(c.loadState, WhiteboardLoadState.failed);
    repository.failLoad = false;
    await c.load();
    expect(c.loadState, WhiteboardLoadState.ready);
    c.dispose();
  });
}
