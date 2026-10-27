// The whiteboard page: drawing with the pointer, a stylus keeping fingers from
// drawing, a board you can only look at, the list view that stands in for the
// drawing, and a very small phone with huge text.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/whiteboard/whiteboard_canvas.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_page.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';
import 'package:wecord/features/whiteboard/whiteboard_toolbar.dart';

import '../../mobile/phone_test_support.dart';
import 'whiteboard_fakes.dart';

class _Setup {
  _Setup(this.controller, this.repository);

  final WhiteboardController controller;
  final FakeWhiteboardRepository repository;
}

Future<_Setup> _open(
  PhoneWorld world, {
  bool canEdit = true,
  bool managersOnly = false,
}) async {
  final server = FakeWhiteboardServer();
  final repository = FakeWhiteboardRepository(
    server,
    meta: WhiteboardMeta(
      id: 'board-1',
      conversationId: 'conv-1',
      title: 'Trip plan',
      canEdit: canEdit,
      canManage: canEdit,
      managersOnly: managersOnly,
    ),
  );
  final controller = WhiteboardController(
    boardId: 'board-1',
    repository: repository,
    userId: 'me',
    userName: 'Ada',
    drafts: InMemoryWhiteboardDraftStore(),
  );
  controller.viewport = const Size(390, 600);
  await controller.load();
  world.extraOverrides = [
    ...world.extraOverrides,
    whiteboardRepositoryProvider.overrideWithValue(repository),
    whiteboardDraftStoreProvider.overrideWithValue(
      InMemoryWhiteboardDraftStore(),
    ),
  ];
  return _Setup(controller, repository);
}

Future<void> _pump(WidgetTester tester, PhoneWorld world, _Setup setup) async {
  await pumpStandalone(
    tester,
    world,
    WhiteboardPage(
      conversationId: 'conv-1',
      boardId: 'board-1',
      title: 'Trip plan',
      controller: setup.controller,
    ),
  );
  await settle(tester);
}

/// Lets the delayed save and its retries run, then takes the page away.
Future<void> _finish(WidgetTester tester, PhoneWorld world) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox());
  await world.close(tester);
}

Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset by, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final gesture = await tester.startGesture(from, kind: kind);
  for (var i = 1; i <= 6; i++) {
    await gesture.moveBy(by / 6);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('dragging with the pen tool draws a line', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final world = PhoneWorld();
    final setup = await _open(world);
    await _pump(tester, world, setup);

    expect(setup.controller.tool, WhiteboardTool.pen);
    final center = tester.getCenter(find.byKey(WhiteboardCanvas.surfaceKey));
    await _drag(tester, center - const Offset(60, 0), const Offset(120, 40));

    final strokes = setup.controller.engine.elements
        .where((e) => e.kind == WhiteboardKind.stroke)
        .toList();
    expect(strokes, hasLength(1));
    expect(setup.controller.history.canUndo, isTrue);

    await tester.tap(find.byKey(WhiteboardPage.undoKey));
    await tester.pump();
    expect(
      setup.controller.engine.elements.where(
        (e) => e.kind == WhiteboardKind.stroke,
      ),
      isEmpty,
    );
    await _finish(tester, world);
  });

  testWidgets('once a stylus was used, fingers only move the view', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final world = PhoneWorld();
    final setup = await _open(world);
    await _pump(tester, world, setup);

    final center = tester.getCenter(find.byKey(WhiteboardCanvas.surfaceKey));
    await _drag(
      tester,
      center,
      const Offset(80, 0),
      kind: PointerDeviceKind.stylus,
    );
    expect(setup.controller.stylusSeen, isTrue);
    expect(setup.controller.engine.elements, hasLength(1));

    await _drag(tester, center, const Offset(0, 80));
    expect(
      setup.controller.engine.elements,
      hasLength(1),
      reason: 'a finger after a stylus must not draw',
    );
    await _finish(tester, world);
  });

  testWidgets('a board you cannot change has no tools and says so', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final world = PhoneWorld();
    final setup = await _open(world, canEdit: false, managersOnly: true);
    await _pump(tester, world, setup);

    expect(find.byKey(const ValueKey('whiteboard-readonly')), findsOneWidget);
    expect(
      find.byKey(WhiteboardToolbar.toolKey(WhiteboardTool.pen)),
      findsNothing,
    );
    await _finish(tester, world);
  });

  testWidgets('the list view shows what is on the board and adds a note', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final world = PhoneWorld();
    final setup = await _open(world);
    await _pump(tester, world, setup);
    setup.controller.engine.upsert(sticky('n1', text: 'Pack the tent'));
    await tester.pump();

    await tester.tap(find.byKey(WhiteboardPage.listToggleKey));
    await settle(tester);

    expect(find.textContaining('Pack the tent'), findsOneWidget);
    expect(find.text('Add a sticky note'), findsOneWidget);
    expect(find.byKey(WhiteboardCanvas.surfaceKey), findsNothing);

    await tester.tap(find.byKey(WhiteboardPage.listToggleKey));
    await settle(tester);
    expect(find.byKey(WhiteboardCanvas.surfaceKey), findsOneWidget);
    await _finish(tester, world);
  });

  testWidgets('a 360x640 phone with huge text does not overflow', (
    tester,
  ) async {
    usePhoneViewport(
      tester,
      PhoneViewport(
        name: 'tiny',
        size: smallPhone.size,
        devicePixelRatio: smallPhone.devicePixelRatio,
        topInset: smallPhone.topInset,
        bottomInset: smallPhone.bottomInset,
        textScale: 2,
      ),
    );
    final world = PhoneWorld();
    final setup = await _open(world);
    setup.controller.engine.upsert(sticky('n1', text: 'Pack the tent'));
    await _pump(tester, world, setup);
    setup.controller
      ..setTool(WhiteboardTool.select)
      ..select(['n1']);
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(WhiteboardCanvas.surfaceKey), findsOneWidget);
    await _finish(tester, world);
  });
}
