// The whiteboard (D10), for the accessibility guard (guidelines_test.dart) and
// the screenshot tools: the board with its tools (normal, large text, narrow,
// Care mode, desktop), a note selected, the shape tool with every option row
// open, a board you can only look at, an offline board, other people on the
// board, the list view that stands in for the drawing, the chat's list of
// boards (with and without boards), the versions sheet and the board's menu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_list_page.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_page.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';
import 'package:wecord/features/whiteboard/whiteboard_versions_sheet.dart';

import '../features/whiteboard/whiteboard_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _conversation = 'conv-1';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

WhiteboardElement _note(
  String id,
  String text, {
  required double x,
  required double y,
  required String z,
  int color = 0xFFFFE08A,
}) {
  return WhiteboardElement(
    id: id,
    kind: WhiteboardKind.sticky,
    z: z,
    data: {
      'x': x,
      'y': y,
      'w': 160.0,
      'h': 120.0,
      't': text,
      'c': color,
      'fs': 18.0,
    },
  );
}

/// A board with a bit of everything on it: notes, a heading, a frame, an
/// arrow, a scribble and a highlighted word.
FakeWhiteboardServer _sampleBoard() {
  final server = FakeWhiteboardServer();
  server
    ..write(
      WhiteboardElement(
        id: 'heading',
        kind: WhiteboardKind.text,
        z: 'V1',
        data: const {
          'x': -180.0,
          'y': -200.0,
          't': 'Saturday hike',
          'c': 0xFF1B1B1F,
          'fs': 30.0,
          'w': 220.0,
          'h': 40.0,
        },
      ),
    )
    ..write(
      WhiteboardElement(
        id: 'frame',
        kind: WhiteboardKind.shape,
        z: 'V2',
        data: const {
          's': 'rect',
          'x': -200.0,
          'y': -140.0,
          'w': 520.0,
          'h': 300.0,
          'sw': 3,
          'c': 0xFF3B6EF5,
        },
      ),
    )
    ..write(_note('n1', 'Pack the tent and the stove', x: -170, y: -110, z: 'V3'))
    ..write(
      _note(
        'n2',
        'Meet at the trailhead at 7',
        x: 10,
        y: -110,
        z: 'V4',
        color: 0xFFC7F0D2,
      ),
    )
    ..write(
      _note(
        'n3',
        'Who drives? Ask Bart',
        x: 160,
        y: 10,
        z: 'V5',
        color: 0xFFFFC9C9,
      ),
    )
    ..write(
      WhiteboardElement(
        id: 'arrow',
        kind: WhiteboardKind.shape,
        z: 'V6',
        data: const {
          's': 'arrow',
          'x': -20.0,
          'y': 70.0,
          'w': 170.0,
          'h': 20.0,
          'sw': 4,
          'c': 0xFFE5484D,
        },
      ),
    )
    ..write(
      WhiteboardElement(
        id: 'scribble',
        kind: WhiteboardKind.stroke,
        z: 'V7',
        data: const {
          'p': [
            -170.0, 70.0, -140.0, 40.0, -110.0, 90.0, -80.0, 40.0, -50.0, 80.0,
          ],
          'sw': 4,
          'c': 0xFF30A46C,
        },
      ),
    )
    ..write(
      WhiteboardElement(
        id: 'marker',
        kind: WhiteboardKind.stroke,
        z: 'V8',
        data: const {
          'p': [-170.0, -60.0, 0.0, -60.0],
          'sw': 14,
          'c': 0xFFE6A700,
          'hl': true,
        },
      ),
    );
  return server;
}

class _Opened {
  _Opened(this.controller, this.repository);

  final WhiteboardController controller;
  final FakeWhiteboardRepository repository;
}

Future<_Opened> _open(
  PhoneWorld world, {
  WhiteboardMeta? meta,
  bool empty = false,
  List<WhiteboardPeer> peers = const [],
}) async {
  final server = empty ? FakeWhiteboardServer() : _sampleBoard();
  final repository = FakeWhiteboardRepository(
    server,
    meta:
        meta ??
        const WhiteboardMeta(
          id: 'board-1',
          conversationId: _conversation,
          title: 'Trip plan',
          canEdit: true,
          canManage: true,
        ),
  );
  repository.versions.addAll([
    WhiteboardVersionSummary(
      id: 'v1',
      createdAt: DateTime(2026, 10, 27, 15, 30),
      kind: 'auto',
      createdByName: 'Bart',
      elementCount: 8,
    ),
    WhiteboardVersionSummary(
      id: 'v2',
      createdAt: DateTime(2026, 10, 26, 9, 5),
      kind: 'manual',
      label: 'Before the cleanup',
      elementCount: 11,
    ),
    WhiteboardVersionSummary(
      id: 'v3',
      createdAt: DateTime(2026, 10, 25, 18, 45),
      kind: 'restore',
      elementCount: 4,
    ),
  ]);
  final controller = WhiteboardController(
    boardId: 'board-1',
    repository: repository,
    userId: 'me',
    userName: 'Ada',
    drafts: InMemoryWhiteboardDraftStore(),
  );
  controller.viewport = const Size(390, 600);
  await controller.load();
  if (peers.isNotEmpty) {
    repository.live.peersController.add(peers);
    await Future<void>.delayed(Duration.zero);
  }
  world.extraOverrides = [
    ...world.extraOverrides,
    whiteboardRepositoryProvider.overrideWithValue(repository),
    whiteboardDraftStoreProvider.overrideWithValue(
      InMemoryWhiteboardDraftStore(),
    ),
  ];
  return _Opened(controller, repository);
}

Future<void> _pump(
  WidgetTester tester,
  PhoneWorld world,
  _Opened opened,
) async {
  await pumpStandalone(
    tester,
    world,
    WhiteboardPage(
      conversationId: _conversation,
      boardId: 'board-1',
      title: 'Trip plan',
      controller: opened.controller,
    ),
  );
}

const _peers = [
  WhiteboardPeer(userId: 'u2', name: 'Bart', color: 0xFF3B6EF5),
  WhiteboardPeer(userId: 'u3', name: 'Cleo', color: 0xFFE5484D),
];

Future<void> _board(
  WidgetTester tester,
  PhoneWorld world, {
  bool care = false,
  bool withPeers = true,
}) async {
  if (care) {
    _care(world);
  }
  final opened = await _open(world, peers: withPeers ? _peers : const []);
  await _pump(tester, world, opened);
}

Future<void> _selected(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  opened.controller.select(['n1']);
  await _pump(tester, world, opened);
}

Future<void> _shapeTool(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  opened.controller.setShapeKind(WhiteboardShape.ellipse);
  await _pump(tester, world, opened);
}

Future<void> _penTool(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  opened.controller.setTool(WhiteboardTool.pen);
  await _pump(tester, world, opened);
}

Future<void> _readOnly(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(
    world,
    meta: const WhiteboardMeta(
      id: 'board-1',
      conversationId: _conversation,
      title: 'Trip plan',
      managersOnly: true,
    ),
  );
  await _pump(tester, world, opened);
}

Future<void> _offline(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  opened.repository.server.offline = true;
  opened.controller.engine.upsert(
    _note('n9', 'Drawn on the train', x: -60, y: 190, z: 'V9'),
  );
  await opened.controller.engine.flush();
  await _pump(tester, world, opened);
}

Future<void> _listView(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
}) async {
  final opened = await _open(world, empty: empty);
  await _pump(tester, world, opened);
  await tester.tap(find.byKey(WhiteboardPage.listToggleKey));
  await settle(tester);
}

Future<void> _menu(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  await _pump(tester, world, opened);
  await tester.tap(find.byKey(WhiteboardPage.menuKey));
  await settle(tester);
}

Future<void> _versions(WidgetTester tester, PhoneWorld world) async {
  final opened = await _open(world);
  await _pump(tester, world, opened);
  final context = tester.element(find.byType(WhiteboardPage));
  unawaited(showWhiteboardVersions(context, opened.controller));
  await settle(tester);
}

Future<void> _boards(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
}) async {
  final repository = FakeWhiteboardRepository(FakeWhiteboardServer());
  if (!empty) {
    repository.lists.addAll([
      WhiteboardSummary(
        id: 'board-1',
        conversationId: _conversation,
        title: 'Trip plan',
        updatedByName: 'Bart',
        updatedAt: DateTime(2026, 10, 27, 15, 30),
        elementCount: 8,
        canEdit: true,
      ),
      WhiteboardSummary(
        id: 'board-2',
        conversationId: _conversation,
        title: 'Sprint retro with the whole design team and friends',
        managersOnly: true,
        updatedByName: 'Cleo',
        updatedAt: DateTime(2026, 10, 26, 11, 0),
        elementCount: 31,
      ),
      WhiteboardSummary(
        id: 'board-3',
        conversationId: _conversation,
        updatedAt: DateTime(2026, 10, 20, 8, 15),
        elementCount: 2,
        canEdit: true,
      ),
    ]);
  }
  world.extraOverrides = [
    ...world.extraOverrides,
    whiteboardRepositoryProvider.overrideWithValue(repository),
  ];
  await pumpStandalone(
    tester,
    world,
    const WhiteboardListPage(conversationId: _conversation),
  );
}

final whiteboardA11yScreens = <A11yScreen>[
  A11yScreen('whiteboard-board', _board),
  A11yScreen(
    'whiteboard-board-large-text',
    _board,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('whiteboard-board-narrow', _board, viewport: smallPhone),
  A11yScreen(
    'whiteboard-board-care-mode',
    (tester, world) => _board(tester, world, care: true),
  ),
  A11yScreen(
    'whiteboard-board-desktop',
    _board,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('whiteboard-board-pen', _penTool, viewport: smallPhone),
  A11yScreen('whiteboard-board-selected', _selected),
  A11yScreen('whiteboard-board-selected-narrow', _selected, viewport: smallPhone),
  A11yScreen(
    'whiteboard-board-selected-large-text',
    _selected,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('whiteboard-board-shapes', _shapeTool),
  A11yScreen('whiteboard-board-shapes-narrow', _shapeTool, viewport: smallPhone),
  A11yScreen('whiteboard-board-read-only', _readOnly),
  A11yScreen('whiteboard-board-read-only-narrow', _readOnly, viewport: smallPhone),
  A11yScreen('whiteboard-board-offline', _offline),
  A11yScreen('whiteboard-board-offline-narrow', _offline, viewport: smallPhone),
  A11yScreen('whiteboard-list-view', _listView),
  A11yScreen(
    'whiteboard-list-view-large-text',
    _listView,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('whiteboard-list-view-narrow', _listView, viewport: smallPhone),
  A11yScreen(
    'whiteboard-list-view-empty',
    (tester, world) => _listView(tester, world, empty: true),
  ),
  A11yScreen('whiteboard-menu-narrow', _menu, viewport: smallPhone),
  A11yScreen('whiteboard-versions', _versions),
  A11yScreen('whiteboard-versions-narrow', _versions, viewport: smallPhone),
  A11yScreen('whiteboard-boards', _boards),
  A11yScreen(
    'whiteboard-boards-large-text',
    _boards,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('whiteboard-boards-narrow', _boards, viewport: smallPhone),
  A11yScreen(
    'whiteboard-boards-empty',
    (tester, world) => _boards(tester, world, empty: true),
  ),
  A11yScreen(
    'whiteboard-boards-desktop',
    _boards,
    viewport: desktopViewport,
    desktop: true,
  ),
];
