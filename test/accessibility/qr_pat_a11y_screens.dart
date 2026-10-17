// The QR code, Scan, pat-pat and Note to self screens, for the accessibility
// guard (guidelines_test.dart) and the accessibility screenshot tool.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/qr/group_qr_sheet.dart';
import 'package:wecord/features/qr/qr_camera.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/pat/pat_fakes.dart';
import '../features/qr/qr_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// Installs the QR and pat fakes; [camera] is the one a test can drive.
void _qrWorld(
  PhoneWorld world, {
  FakeQrCamera? camera,
  FakeQrRepository? repository,
}) {
  world.extraOverrides = [
    ...qrOverrides(
      repository: repository ?? FakeQrRepository(),
      exporter: FakeQrImageExporter(),
      camera: camera ?? FakeQrCamera(),
      launcher: FakeUrlLauncher(),
    ),
    ...patOverrides(FakePatRepository()..currentSuffix = "'s shoulder"),
  ];
}

Future<void> _openFromSettings(
  WidgetTester tester,
  PhoneWorld world,
  String rowKey,
) async {
  await world.open(tester, '/me');
  await tester.tap(find.byKey(ValueKey(rowKey)));
  await settle(tester);
}

/// The note to self, with a few things in it.
final _note = ConversationSummary(
  id: 'note-1',
  type: ConversationType.direct,
  unreadCount: 0,
  title: 'Note to self',
  memberCount: 1,
  isNoteToSelf: true,
  pinnedAt: minutesAgo(5000),
  lastMessageBody: 'Train tickets for Friday',
  lastMessageType: MessageType.text,
  lastMessageSenderId: 'user-1',
  lastMessageAt: minutesAgo(20),
);

Future<void> _openNote(WidgetTester tester, PhoneWorld world) async {
  _qrWorld(world);
  world.chats
    ..conversations = [...world.chats.conversations, _note]
    ..readMarkers = const []
    ..messages = [
      for (final (index, text) in [
        'Train tickets for Friday: booking ref 8KQ2LM',
        'Venue map is in the shared drive',
        'Remember to bring the charger',
      ].indexed)
        phoneMessage(
          'note-$index',
          me,
          text,
          minutesAgo: 90 - index * 30,
          conversationId: 'note-1',
        ),
    ];
  await world.open(
    tester,
    '/chats/note-1',
    extra: const ChatThreadRouteExtra(
      title: 'Note to self',
      type: ConversationType.direct,
    ),
  );
}

/// The screens, in the order of the flows.
final qrPatA11yScreens = <A11yScreen>[
  A11yScreen('my-qr-code', (tester, world) async {
    _qrWorld(world);
    await _openFromSettings(tester, world, 'settings-my-qr');
  }),
  A11yScreen('my-qr-code-reset', (tester, world) async {
    _qrWorld(world);
    await _openFromSettings(tester, world, 'settings-my-qr');
    await tester.tap(find.byKey(const ValueKey('qr-reset')));
    await settle(tester);
  }),
  A11yScreen('scanner', (tester, world) async {
    _qrWorld(world);
    await _openFromSettings(tester, world, 'settings-scan');
  }),
  A11yScreen('scanner-camera-off', (tester, world) async {
    _qrWorld(
      world,
      camera: FakeQrCamera()..failWith = QrCameraProblem.permissionDenied,
    );
    await _openFromSettings(tester, world, 'settings-scan');
  }),
  A11yScreen('scanned-link', (tester, world) async {
    final camera = FakeQrCamera();
    _qrWorld(world, camera: camera);
    await _openFromSettings(tester, world, 'settings-scan');
    camera.onCode!('https://example.com/menu');
    await settle(tester);
  }),
  A11yScreen('add-friend-qr', (tester, world) async {
    _qrWorld(world);
    await world.open(tester, '/contacts');
  }),
  A11yScreen('group-qr-code', (tester, world) async {
    _qrWorld(world);
    await world.open(tester, '/home');
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      showGroupQrSheet(
        context,
        conversationId: 'group-1',
        title: 'Weekend climbers',
        memberCount: 12,
      ),
    );
    await settle(tester);
  }),
  A11yScreen('group-qr-join', (tester, world) async {
    _qrWorld(world);
    await world.open(tester, '/g/$sampleGroupCode');
  }),
  A11yScreen('group-qr-expired', (tester, world) async {
    _qrWorld(
      world,
      repository: FakeQrRepository()
        ..preview = const GroupQrPreview(state: GroupQrState.expired),
    );
    await world.open(tester, '/g/$sampleGroupCode');
  }),
  A11yScreen('user-qr-no-longer-works', (tester, world) async {
    _qrWorld(world);
    await world.open(tester, '/u/$sampleUserCode');
  }),
  A11yScreen('pat-suffix', (tester, world) async {
    _qrWorld(world);
    await _openFromSettings(tester, world, 'pat-suffix-row');
  }),
  A11yScreen('pat-lines', (tester, world) async {
    _qrWorld(world);
    world.chats.messages = [
      ...richMessages(),
      patMessage(
        'pat-mine',
        actorId: 'user-1',
        targetId: 'user-2',
        suffix: "'s shoulder",
        age: const Duration(seconds: 30),
      ),
      patMessage(
        'pat-theirs',
        actorId: 'user-2',
        targetId: 'user-1',
        actorName: 'Bart',
        targetName: 'Ada',
        suffix: "'s shoulder",
        age: const Duration(minutes: 10),
      ),
    ];
    await world.open(
      tester,
      '/chats/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }),
  A11yScreen('note-to-self', _openNote),
  A11yScreen(
    'desktop-note-to-self',
    _openNote,
    viewport: desktopViewport,
    desktop: true,
  ),
];
